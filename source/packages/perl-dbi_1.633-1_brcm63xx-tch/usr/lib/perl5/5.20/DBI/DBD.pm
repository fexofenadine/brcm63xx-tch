package DBI::DBD;

use vars qw($VERSION);	# set $VERSION early so we don't confuse PAUSE/CPAN etc

$VERSION = "12.015129";



use Exporter ();
use Config qw(%Config);
use Carp;
use Cwd;
use File::Spec;
use strict;
use vars qw(
    @ISA @EXPORT
    $is_dbi
);

BEGIN {
    if ($^O eq 'VMS') {
	require vmsish;
	import  vmsish;
	require VMS::Filespec;
	import  VMS::Filespec;
    }
    else {
	*vmsify  = sub { return $_[0] };
	*unixify = sub { return $_[0] };
    }
}

@ISA = qw(Exporter);

@EXPORT = qw(
    dbd_dbi_dir
    dbd_dbi_arch_dir
    dbd_edit_mm_attribs
    dbd_postamble
);

BEGIN {
    $is_dbi = (-r 'DBI.pm' && -r 'DBI.xs' && -r 'DBIXS.h');
    require DBI unless $is_dbi;
}

my $done_inst_checks;

sub _inst_checks {
    return if $done_inst_checks++;
    my $cwd = cwd();
    if ($cwd =~ /\Q$Config{path_sep}/) {
	warn "*** Warning: Path separator characters (`$Config{path_sep}') ",
	    "in the current directory path ($cwd) may cause problems\a\n\n";
        sleep 2;
    }
    if ($cwd =~ /\s/) {
	warn "*** Warning: whitespace characters ",
	    "in the current directory path ($cwd) may cause problems\a\n\n";
        sleep 2;
    }
    if (   $^O eq 'MSWin32'
	&& $Config{cc} eq 'cl'
	&& !(exists $ENV{'LIB'} && exists $ENV{'INCLUDE'}))
    {
	die <<EOT;
*** You're using Microsoft Visual C++ compiler or similar but
    the LIB and INCLUDE environment variables are not both set.

    You need to run the VCVARS32.BAT batch file that was supplied
    with the compiler before you can use it.

    A copy of vcvars32.bat can typically be found in the following
    directories under your Visual Studio install directory:
        Visual C++ 6.0:     vc98\\bin
        Visual Studio .NET: vc7\\bin

    Find it, run it, then retry this.

    If you think this error is not correct then just set the LIB and
    INCLUDE environment variables to some value to disable the check.
EOT
    }
}

sub dbd_edit_mm_attribs {
    # this both edits the attribs in-place and returns the flattened attribs
    my $mm_attr = shift;
    my $dbd_attr = shift || {};
    croak "dbd_edit_mm_attribs( \%makemaker [, \%other ]): too many parameters"
	if @_;
    _inst_checks();

    # what can be done
    my %test_variants = (
	p => {	name => "DBI::PurePerl",
		match => qr/^\d/,
		add => [ '$ENV{DBI_PUREPERL} = 2',
			 'END { delete $ENV{DBI_PUREPERL}; }' ],
	},
	g => {	name => "DBD::Gofer",
		match => qr/^\d/,
		add => [ q{$ENV{DBI_AUTOPROXY} = 'dbi:Gofer:transport=null;policy=pedantic'},
			 q|END { delete $ENV{DBI_AUTOPROXY}; }| ],
	},
	n => {	name => "DBI::SQL::Nano",
		match => qr/^(?:48dbi_dbd_sqlengine|49dbd_file|5\ddbm_\w+|85gofer)\.t$/,
		add => [ q{$ENV{DBI_SQL_NANO} = 1},
			 q|END { delete $ENV{DBI_SQL_NANO}; }| ],
	},
    #   mx => {	name => "DBD::Multiplex",
    #           add => [ q{local $ENV{DBI_AUTOPROXY} = 'dbi:Multiplex:';} ],
    #   }
    #   px => {	name => "DBD::Proxy",
    #		need mechanism for starting/stopping the proxy server
    #		add => [ q{local $ENV{DBI_AUTOPROXY} = 'dbi:Proxy:XXX';} ],
    #   }
    );

    # decide what needs doing
    $dbd_attr->{create_pp_tests} or delete $test_variants{p};
    $dbd_attr->{create_nano_tests} or delete $test_variants{n};
    $dbd_attr->{create_gap_tests} or delete $test_variants{g};

    # expand for all combinations
    my @all_keys = my @tv_keys = sort keys %test_variants;
    while( @tv_keys ) {
	my $cur_key = shift @tv_keys;
	last if( 1 < length $cur_key );
	my @new_keys;
	foreach my $remain (@tv_keys) {
	    push @new_keys, $cur_key . $remain unless $remain =~ /$cur_key/;
	}
	push @tv_keys, @new_keys;
	push @all_keys, @new_keys;
    }

    my %uniq_keys;
    foreach my $key (@all_keys) {
	@tv_keys = sort split //, $key;
	my $ordered = join( '', @tv_keys );
	$uniq_keys{$ordered} = 1;
    }
    @all_keys = sort { length $a <=> length $b or $a cmp $b } keys %uniq_keys;

    # do whatever needs doing
    if( keys %test_variants ) {
	# XXX need to convert this to work within the generated Makefile
	# so 'make' creates them and 'make clean' deletes them
	opendir DIR, 't' or die "Can't read 't' directory: $!";
	my @tests = grep { /\.t$/ } readdir DIR;
	closedir DIR;

        foreach my $test_combo (@all_keys) {
	    @tv_keys = split //, $test_combo;
	    my @test_names = map { $test_variants{$_}->{name} } @tv_keys;
            printf "Creating test wrappers for " . join( " + ", @test_names ) . ":\n";
	    my @test_matches = map { $test_variants{$_}->{match} } @tv_keys;
	    my @test_adds;
	    foreach my $test_add ( map { $test_variants{$_}->{add} } @tv_keys) {
		push @test_adds, @$test_add;
	    }
	    my $v_type = $test_combo;
	    $v_type = 'x' . $v_type if length( $v_type ) > 1;

	TEST:
            foreach my $test (sort @tests) {
		foreach my $match (@test_matches) {
		    next TEST if $test !~ $match;
		}
                my $usethr = ($test =~ /(\d+|\b)thr/ && $] >= 5.008 && $Config{useithreads});
                my $v_test = "t/zv${v_type}_$test";
                my $v_perl = ($test =~ /taint/) ? "perl -wT" : "perl -w";
		printf "%s %s\n", $v_test, ($usethr) ? "(use threads)" : "";
		open PPT, ">$v_test" or warn "Can't create $v_test: $!";
		print PPT "#!$v_perl\n";
		print PPT "use threads;\n" if $usethr;
		print PPT "$_;\n" foreach @test_adds;
		print PPT "require './t/$test'; # or warn \$!;\n";
		close PPT or warn "Error writing $v_test: $!";
	    }
	}
    }
    return %$mm_attr;
}

sub dbd_dbi_dir {
    _inst_checks();
    return '.' if $is_dbi;
    my $dbidir = $INC{'DBI.pm'} || die "DBI.pm not in %INC!";
    $dbidir =~ s:/DBI\.pm$::;
    return $dbidir;
}

sub dbd_dbi_arch_dir {
    _inst_checks();
    return '$(INST_ARCHAUTODIR)' if $is_dbi;
    my $dbidir = dbd_dbi_dir();
    my %seen;
    my @try = grep { not $seen{$_}++ } map { vmsify( unixify($_) . "/auto/DBI/" ) } @INC;
    my @xst = grep { -f vmsify( unixify($_) . "/Driver.xst" ) } @try;
    Carp::croak("Unable to locate Driver.xst in @try") unless @xst;
    Carp::carp( "Multiple copies of Driver.xst found in: @xst") if @xst > 1;
    print "Using DBI $DBI::VERSION (for perl $] on $Config{archname}) installed in $xst[0]\n";
    return File::Spec->canonpath($xst[0]);
}

sub dbd_postamble {
    my $self = shift;
    _inst_checks();
    my $dbi_instarch_dir = ($is_dbi) ? "." : dbd_dbi_arch_dir();
    my $dbi_driver_xst= File::Spec->catfile($dbi_instarch_dir, 'Driver.xst');
    my $xstf_h = File::Spec->catfile($dbi_instarch_dir, 'Driver_xst.h');

    # we must be careful of quotes, especially for Win32 here.
    return '
DBI_INSTARCH_DIR='.$dbi_instarch_dir.'
DBI_DRIVER_XST='.$dbi_driver_xst.'

$(BASEEXT).c: $(BASEEXT).xsi

$(BASEEXT)$(OBJ_EXT): $(BASEEXT).xsi

$(BASEEXT).xsi: $(DBI_DRIVER_XST) '.$xstf_h.'
	$(PERL) -p -e "s/~DRIVER~/$(BASEEXT)/g" $(DBI_DRIVER_XST) > $(BASEEXT).xsi

';
}

package DBDI; # just to reserve it via PAUSE for the future

1;

__END__

