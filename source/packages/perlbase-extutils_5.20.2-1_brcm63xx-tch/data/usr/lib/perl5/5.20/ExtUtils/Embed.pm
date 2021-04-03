package ExtUtils::Embed;
require Exporter;
use Config;
require File::Spec;

use vars qw(@ISA @EXPORT $VERSION
	    @Extensions $Verbose $lib_ext
	    $opt_o $opt_s 
	    );
use strict;

$VERSION = '1.32';

@ISA = qw(Exporter);
@EXPORT = qw(&xsinit &ldopts 
	     &ccopts &ccflags &ccdlflags &perl_inc
	     &xsi_header &xsi_protos &xsi_body);

$Verbose = 0;
$lib_ext = $Config{lib_ext} || '.a';

sub is_cmd { $0 eq '-e' }

sub my_return {
    my $val = shift;
    if(is_cmd) {
	print $val;
    }
    else {
	return $val;
    }
}

sub xsinit { 
    my($file, $std, $mods) = @_;
    my($fh,@mods,%seen);
    $file ||= "perlxsi.c";
    my $xsinit_proto = "pTHX";

    if (@_) {
       @mods = @$mods if $mods;
    }
    else {
       require Getopt::Std;
       Getopt::Std::getopts('o:s:');
       $file = $opt_o if defined $opt_o;
       $std  = $opt_s  if defined $opt_s;
       @mods = @ARGV;
    }
    $std = 1 unless scalar @mods;

    if ($file eq "STDOUT") {
	$fh = \*STDOUT;
    }
    else {
        open $fh, '>', $file
            or die "Can't open '$file': $!";
    }

    push(@mods, static_ext()) if defined $std;
    @mods = grep(!$seen{$_}++, @mods);

    print $fh &xsi_header();
    print $fh "\nEXTERN_C void xs_init ($xsinit_proto);\n\n";
    print $fh &xsi_protos(@mods);

    print $fh "\nEXTERN_C void\nxs_init($xsinit_proto)\n{\n";
    print $fh &xsi_body(@mods);
    print $fh "}\n";

}

sub xsi_header {
    return <<EOF;
EOF
}    

sub xsi_protos {
    my @exts = @_;
    my %seen;
    my $retval = '';
    foreach my $cname (canon('__', @exts)) {
        my $ccode = "EXTERN_C void boot_${cname} (pTHX_ CV* cv);\n";
        $retval .= $ccode
            unless $seen{$ccode}++;
    }
    return $retval;
}

sub xsi_body {
    my @exts = @_;
    my %seen;
    my $retval;
    $retval .= "    static const char file[] = __FILE__;\n"
        if @exts;
    $retval .= <<'EOT';
    dXSUB_SYS;
    PERL_UNUSED_CONTEXT;
EOT
    $retval .= "\n"
        if @exts;

    foreach my $pname (canon('/', @exts)) {
        next
            if $seen{$pname}++;
        (my $mname = $pname) =~ s!/!::!g;
        (my $cname = $pname) =~ s!/!__!g;
        my $fname;
        if ($pname eq 'DynaLoader'){
            # Must NOT install 'DynaLoader::boot_DynaLoader' as 'bootstrap'!
            # boot_DynaLoader is called directly in DynaLoader.pm
            $retval .= "    /* DynaLoader is a special case */\n";
            $fname = "${mname}::boot_DynaLoader";
        } else {
            $fname = "${mname}::bootstrap";
        }
        $retval .= "    newXS(\"$fname\", boot_${cname}, file);\n"
    }
    return $retval;
}

sub static_ext {
    @Extensions = ('DynaLoader', sort $Config{static_ext} =~ /(\S+)/g)
        unless @Extensions;
    @Extensions;
}

sub _escape {
    my $arg = shift;
    return $$arg if $^O eq 'VMS'; # parens legal in qualifier lists
    $$arg =~ s/([\(\)])/\\$1/g;
}

sub _ldflags {
    my $ldflags = $Config{ldflags};
    _escape(\$ldflags);
    return $ldflags;
}

sub _ccflags {
    my $ccflags = $Config{ccflags};
    _escape(\$ccflags);
    return $ccflags;
}

sub _ccdlflags {
    my $ccdlflags = $Config{ccdlflags};
    _escape(\$ccdlflags);
    return $ccdlflags;
}

sub ldopts {
    require ExtUtils::MakeMaker;
    require ExtUtils::Liblist;
    my($std,$mods,$link_args,$path) = @_;
    my(@mods,@link_args,@argv);
    my($dllib,$config_libs,@potential_libs,@path);
    local($") = ' ' unless $" eq ' ';
    if (scalar @_) {
       @link_args = @$link_args if $link_args;
       @mods = @$mods if $mods;
    }
    else {
       @argv = @ARGV;
       #hmm
       while($_ = shift @argv) {
	   /^-std$/  && do { $std = 1; next; };
	   /^--$/    && do { @link_args = @argv; last; };
	   /^-I(.*)/ && do { $path = $1 || shift @argv; next; };
	   push(@mods, $_); 
       }
    }
    $std = 1 unless scalar @link_args;
    my $sep = $Config{path_sep} || ':';
    @path = $path ? split(/\Q$sep/, $path) : @INC;

    push(@potential_libs, @link_args)    if scalar @link_args;
    # makemaker includes std libs on windows by default
    if ($^O ne 'MSWin32' and defined($std)) {
	push(@potential_libs, $Config{perllibs});
    }

    push(@mods, static_ext()) if $std;

    my($mod,@ns,$root,$sub,$extra,$archive,@archives);
    print STDERR "Searching (@path) for archives\n" if $Verbose;
    foreach $mod (@mods) {
	@ns = split(/::|\/|\\/, $mod);
	$sub = $ns[-1];
	$root = File::Spec->catdir(@ns);
	
	print STDERR "searching for '$sub${lib_ext}'\n" if $Verbose;
	foreach (@path) {
	    next unless -e ($archive = File::Spec->catdir($_,"auto",$root,"$sub$lib_ext"));
	    push @archives, $archive;
	    if(-e ($extra = File::Spec->catdir($_,"auto",$root,"extralibs.ld"))) {
		local(*FH); 
		if(open(FH, $extra)) {
		    my($libs) = <FH>; chomp $libs;
		    push @potential_libs, split /\s+/, $libs;
		}
		else {  
		    warn "Couldn't open '$extra'"; 
		}
	    }
	    last;
	}
    }
    #print STDERR "\@potential_libs = @potential_libs\n";

    my $libperl;
    if ($^O eq 'MSWin32') {
	$libperl = $Config{libperl};
    }
    elsif ($^O eq 'os390' && $Config{usedl}) {
	# Nothing for OS/390 (z/OS) dynamic.
    } else {
	$libperl = (grep(/^-l\w*perl\w*$/, @link_args))[0]
	    || ($Config{libperl} =~ /^lib(\w+)(\Q$lib_ext\E|\.\Q$Config{dlext}\E)$/
		? "-l$1" : '')
		|| "-lperl";
    }

    my $lpath = File::Spec->catdir($Config{archlibexp}, 'CORE');
    $lpath = qq["$lpath"] if $^O eq 'MSWin32';
    my($extralibs, $bsloadlibs, $ldloadlibs, $ld_run_path) =
	MM->ext(join ' ', "-L$lpath", $libperl, @potential_libs);

    my $ld_or_bs = $bsloadlibs || $ldloadlibs;
    print STDERR "bs: $bsloadlibs ** ld: $ldloadlibs" if $Verbose;
    my $ccdlflags = _ccdlflags();
    my $ldflags   = _ldflags();
    my $linkage = "$ccdlflags $ldflags @archives $ld_or_bs";
    print STDERR "ldopts: '$linkage'\n" if $Verbose;

    return $linkage if scalar @_;
    my_return("$linkage\n");
}

sub ccflags {
    my $ccflags = _ccflags();
    my_return(" $ccflags ");
}

sub ccdlflags {
    my $ccdlflags = _ccdlflags();
    my_return(" $ccdlflags ");
}

sub perl_inc {
    my $dir = File::Spec->catdir($Config{archlibexp}, 'CORE');
    $dir = qq["$dir"] if $^O eq 'MSWin32';
    my_return(" -I$dir ");
}

sub ccopts {
   ccflags . perl_inc;
}

sub canon {
    my($as, @ext) = @_;
    foreach(@ext) {
        # might be X::Y or lib/auto/X/Y/Y.a
        next
            if s!::!/!g;
        s!^(?:lib|ext|dist|cpan)/(?:auto/)?!!;
        s!/\w+\.\w+$!!;
    }
    if ($as ne '/') {
        s!/!$as!g
            foreach @ext;
    }
    @ext;
}

__END__

