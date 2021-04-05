package App::Prove;

use strict;
use warnings;

use TAP::Harness::Env;
use Text::ParseWords qw(shellwords);
use File::Spec;
use Getopt::Long;
use App::Prove::State;
use Carp;

use base 'TAP::Object';


our $VERSION = '3.35';


use constant IS_WIN32 => ( $^O =~ /^(MS)?Win32$/ );
use constant IS_VMS => $^O eq 'VMS';
use constant IS_UNIXY => !( IS_VMS || IS_WIN32 );

use constant STATE_FILE => IS_UNIXY ? '.prove'   : '_prove';
use constant RC_FILE    => IS_UNIXY ? '.proverc' : '_proverc';

use constant PLUGINS => 'App::Prove::Plugin';

my @ATTR;

BEGIN {
    @ATTR = qw(
      archive argv blib show_count color directives exec failures comments
      formatter harness includes modules plugins jobs lib merge parse quiet
      really_quiet recurse backwards shuffle taint_fail taint_warn timer
      verbose warnings_fail warnings_warn show_help show_man show_version
      state_class test_args state dry extensions ignore_exit rules state_manager
      normalize sources tapversion trap
    );
    __PACKAGE__->mk_methods(@ATTR);
}



sub _initialize {
    my $self = shift;
    my $args = shift || {};

    my @is_array = qw(
      argv rc_opts includes modules state plugins rules sources
    );

    # setup defaults:
    for my $key (@is_array) {
        $self->{$key} = [];
    }

    for my $attr (@ATTR) {
        if ( exists $args->{$attr} ) {

            # TODO: Some validation here
            $self->{$attr} = $args->{$attr};
        }
    }

    $self->state_class('App::Prove::State');
    return $self;
}



sub add_rc_file {
    my ( $self, $rc_file ) = @_;

    local *RC;
    open RC, "<$rc_file" or croak "Can't read $rc_file ($!)";
    while ( defined( my $line = <RC> ) ) {
        push @{ $self->{rc_opts} },
          grep { defined and not /^#/ }
          $line =~ m{ ' ([^']*) ' | " ([^"]*) " | (\#.*) | (\S+) }xg;
    }
    close RC;
}


sub process_args {
    my $self = shift;

    my @rc = RC_FILE;
    unshift @rc, glob '~/' . RC_FILE if IS_UNIXY;

    # Preprocess meta-args.
    my @args;
    while ( defined( my $arg = shift ) ) {
        if ( $arg eq '--norc' ) {
            @rc = ();
        }
        elsif ( $arg eq '--rc' ) {
            defined( my $rc = shift )
              or croak "Missing argument to --rc";
            push @rc, $rc;
        }
        elsif ( $arg =~ m{^--rc=(.+)$} ) {
            push @rc, $1;
        }
        else {
            push @args, $arg;
        }
    }

    # Everything after the arisdottle '::' gets passed as args to
    # test programs.
    if ( defined( my $stop_at = _first_pos( '::', @args ) ) ) {
        my @test_args = splice @args, $stop_at;
        shift @test_args;
        $self->{test_args} = \@test_args;
    }

    # Grab options from RC files
    $self->add_rc_file($_) for grep -f, @rc;
    unshift @args, @{ $self->{rc_opts} };

    if ( my @bad = map {"-$_"} grep {/^-(man|help)$/} @args ) {
        die "Long options should be written with two dashes: ",
          join( ', ', @bad ), "\n";
    }

    # And finally...

    {
        local @ARGV = @args;
        Getopt::Long::Configure(qw(no_ignore_case bundling pass_through));

        # Don't add coderefs to GetOptions
        GetOptions(
            'v|verbose'  => \$self->{verbose},
            'f|failures' => \$self->{failures},
            'o|comments' => \$self->{comments},
            'l|lib'      => \$self->{lib},
            'b|blib'     => \$self->{blib},
            's|shuffle'  => \$self->{shuffle},
            'color!'     => \$self->{color},
            'colour!'    => \$self->{color},
            'count!'     => \$self->{show_count},
            'c'          => \$self->{color},
            'D|dry'      => \$self->{dry},
            'ext=s@'     => sub {
                my ( $opt, $val ) = @_;

                # Workaround for Getopt::Long 2.25 handling of
                # multivalue options
                push @{ $self->{extensions} ||= [] }, $val;
            },
            'harness=s'    => \$self->{harness},
            'ignore-exit'  => \$self->{ignore_exit},
            'source=s@'    => $self->{sources},
            'formatter=s'  => \$self->{formatter},
            'r|recurse'    => \$self->{recurse},
            'reverse'      => \$self->{backwards},
            'p|parse'      => \$self->{parse},
            'q|quiet'      => \$self->{quiet},
            'Q|QUIET'      => \$self->{really_quiet},
            'e|exec=s'     => \$self->{exec},
            'm|merge'      => \$self->{merge},
            'I=s@'         => $self->{includes},
            'M=s@'         => $self->{modules},
            'P=s@'         => $self->{plugins},
            'state=s@'     => $self->{state},
            'directives'   => \$self->{directives},
            'h|help|?'     => \$self->{show_help},
            'H|man'        => \$self->{show_man},
            'V|version'    => \$self->{show_version},
            'a|archive=s'  => \$self->{archive},
            'j|jobs=i'     => \$self->{jobs},
            'timer'        => \$self->{timer},
            'T'            => \$self->{taint_fail},
            't'            => \$self->{taint_warn},
            'W'            => \$self->{warnings_fail},
            'w'            => \$self->{warnings_warn},
            'normalize'    => \$self->{normalize},
            'rules=s@'     => $self->{rules},
            'tapversion=s' => \$self->{tapversion},
            'trap'         => \$self->{trap},
        ) or croak('Unable to continue');

        # Stash the remainder of argv for later
        $self->{argv} = [@ARGV];
    }

    return;
}

sub _first_pos {
    my $want = shift;
    for ( 0 .. $#_ ) {
        return $_ if $_[$_] eq $want;
    }
    return;
}

sub _help {
    my ( $self, $verbosity ) = @_;

    eval('use Pod::Usage 1.12 ()');
    if ( my $err = $@ ) {
        die 'Please install Pod::Usage for the --help option '
          . '(or try `perldoc prove`.)'
          . "\n ($@)";
    }

    Pod::Usage::pod2usage( { -verbose => $verbosity } );

    return;
}

sub _color_default {
    my $self = shift;

    return -t STDOUT && !$ENV{HARNESS_NOTTY} && !IS_WIN32;
}

sub _get_args {
    my $self = shift;

    my %args;

    $args{trap} = 1 if $self->trap;

    if ( defined $self->color ? $self->color : $self->_color_default ) {
        $args{color} = 1;
    }
    if ( !defined $self->show_count ) {
        $args{show_count} = 1;
    }
    else {
        $args{show_count} = $self->show_count;
    }

    if ( $self->archive ) {
        $self->require_harness( archive => 'TAP::Harness::Archive' );
        $args{archive} = $self->archive;
    }

    if ( my $jobs = $self->jobs ) {
        $args{jobs} = $jobs;
    }

    if ( my $harness_opt = $self->harness ) {
        $self->require_harness( harness => $harness_opt );
    }

    if ( my $formatter = $self->formatter ) {
        $args{formatter_class} = $formatter;
    }

    for my $handler ( @{ $self->sources } ) {
        my ( $name, $config ) = $self->_parse_source($handler);
        $args{sources}->{$name} = $config;
    }

    if ( $self->ignore_exit ) {
        $args{ignore_exit} = 1;
    }

    if ( $self->taint_fail && $self->taint_warn ) {
        die '-t and -T are mutually exclusive';
    }

    if ( $self->warnings_fail && $self->warnings_warn ) {
        die '-w and -W are mutually exclusive';
    }

    for my $a (qw( lib switches )) {
        my $method = "_get_$a";
        my $val    = $self->$method();
        $args{$a} = $val if defined $val;
    }

    # Handle verbose, quiet, really_quiet flags
    my %verb_map = ( verbose => 1, quiet => -1, really_quiet => -2, );

    my @verb_adj = grep {$_} map { $self->$_() ? $verb_map{$_} : 0 }
      keys %verb_map;

    die "Only one of verbose, quiet or really_quiet should be specified\n"
      if @verb_adj > 1;

    $args{verbosity} = shift @verb_adj || 0;

    for my $a (qw( merge failures comments timer directives normalize )) {
        $args{$a} = 1 if $self->$a();
    }

    $args{errors} = 1 if $self->parse;

    # defined but zero-length exec runs test files as binaries
    $args{exec} = [ split( /\s+/, $self->exec ) ]
      if ( defined( $self->exec ) );

    $args{version} = $self->tapversion if defined( $self->tapversion );

    if ( defined( my $test_args = $self->test_args ) ) {
        $args{test_args} = $test_args;
    }

    if ( @{ $self->rules } ) {
        my @rules;
        for ( @{ $self->rules } ) {
            if (/^par=(.*)/) {
                push @rules, $1;
            }
            elsif (/^seq=(.*)/) {
                push @rules, { seq => $1 };
            }
        }
        $args{rules} = { par => [@rules] };
    }
    $args{harness_class} = $self->{harness_class} if $self->{harness_class};

    return \%args;
}

sub _find_module {
    my ( $self, $class, @search ) = @_;

    croak "Bad module name $class"
      unless $class =~ /^ \w+ (?: :: \w+ ) *$/x;

    for my $pfx (@search) {
        my $name = join( '::', $pfx, $class );
        eval "require $name";
        return $name unless $@;
    }

    eval "require $class";
    return $class unless $@;
    return;
}

sub _load_extension {
    my ( $self, $name, @search ) = @_;

    my @args = ();
    if ( $name =~ /^(.*?)=(.*)/ ) {
        $name = $1;
        @args = split( /,/, $2 );
    }

    if ( my $class = $self->_find_module( $name, @search ) ) {
        $class->import(@args);
        if ( $class->can('load') ) {
            $class->load( { app_prove => $self, args => [@args] } );
        }
    }
    else {
        croak "Can't load module $name";
    }
}

sub _load_extensions {
    my ( $self, $ext, @search ) = @_;
    $self->_load_extension( $_, @search ) for @$ext;
}

sub _parse_source {
    my ( $self, $handler ) = @_;

    # Load any options.
    ( my $opt_name = lc $handler ) =~ s/::/-/g;
    local @ARGV = @{ $self->{argv} };
    my %config;
    Getopt::Long::GetOptions(
        "$opt_name-option=s%" => sub {
            my ( $name, $k, $v ) = @_;
            if ( $v =~ /(?<!\\)=/ ) {

                # It's a hash option.
                croak "Option $name must be consistently used as a hash"
                  if exists $config{$k} && ref $config{$k} ne 'HASH';
                $config{$k} ||= {};
                my ( $hk, $hv ) = split /(?<!\\)=/, $v, 2;
                $config{$k}{$hk} = $hv;
            }
            else {
                $v =~ s/\\=/=/g;
                if ( exists $config{$k} ) {
                    $config{$k} = [ $config{$k} ]
                      unless ref $config{$k} eq 'ARRAY';
                    push @{ $config{$k} } => $v;
                }
                else {
                    $config{$k} = $v;
                }
            }
        }
    );
    $self->{argv} = \@ARGV;
    return ( $handler, \%config );
}


sub run {
    my $self = shift;

    unless ( $self->state_manager ) {
        $self->state_manager(
            $self->state_class->new( { store => STATE_FILE } ) );
    }

    if ( $self->show_help ) {
        $self->_help(1);
    }
    elsif ( $self->show_man ) {
        $self->_help(2);
    }
    elsif ( $self->show_version ) {
        $self->print_version;
    }
    elsif ( $self->dry ) {
        print "$_\n" for $self->_get_tests;
    }
    else {

        $self->_load_extensions( $self->modules );
        $self->_load_extensions( $self->plugins, PLUGINS );

        local $ENV{TEST_VERBOSE} = 1 if $self->verbose;

        return $self->_runtests( $self->_get_args, $self->_get_tests );
    }

    return 1;
}

sub _get_tests {
    my $self = shift;

    my $state = $self->state_manager;
    my $ext   = $self->extensions;
    $state->extensions($ext) if defined $ext;
    if ( defined( my $state_switch = $self->state ) ) {
        $state->apply_switch(@$state_switch);
    }

    my @tests = $state->get_tests( $self->recurse, @{ $self->argv } );

    $self->_shuffle(@tests) if $self->shuffle;
    @tests = reverse @tests if $self->backwards;

    return @tests;
}

sub _runtests {
    my ( $self, $args, @tests ) = @_;
    my $harness = TAP::Harness::Env->create($args);

    my $state = $self->state_manager;

    $harness->callback(
        after_test => sub {
            $state->observe_test(@_);
        }
    );

    $harness->callback(
        after_runtests => sub {
            $state->commit(@_);
        }
    );

    my $aggregator = $harness->runtests(@tests);

    return !$aggregator->has_errors;
}

sub _get_switches {
    my $self = shift;
    my @switches;

    # notes that -T or -t must be at the front of the switches!
    if ( $self->taint_fail ) {
        push @switches, '-T';
    }
    elsif ( $self->taint_warn ) {
        push @switches, '-t';
    }
    if ( $self->warnings_fail ) {
        push @switches, '-W';
    }
    elsif ( $self->warnings_warn ) {
        push @switches, '-w';
    }

    return @switches ? \@switches : ();
}

sub _get_lib {
    my $self = shift;
    my @libs;
    if ( $self->lib ) {
        push @libs, 'lib';
    }
    if ( $self->blib ) {
        push @libs, 'blib/lib', 'blib/arch';
    }
    if ( @{ $self->includes } ) {
        push @libs, @{ $self->includes };
    }

    #24926
    @libs = map { File::Spec->rel2abs($_) } @libs;

    # Huh?
    return @libs ? \@libs : ();
}

sub _shuffle {
    my $self = shift;

    # Fisher-Yates shuffle
    my $i = @_;
    while ($i) {
        my $j = rand $i--;
        @_[ $i, $j ] = @_[ $j, $i ];
    }
    return;
}


sub require_harness {
    my ( $self, $for, $class ) = @_;

    my ($class_name) = $class =~ /^(\w+(?:::\w+)*)/;

    # Emulate Perl's -MModule=arg1,arg2 behaviour
    $class =~ s!^(\w+(?:::\w+)*)=(.*)$!$1 split(/,/,q{$2})!;

    eval("use $class;");
    die "$class_name is required to use the --$for feature: $@" if $@;

    $self->{harness_class} = $class_name;

    return;
}


sub print_version {
    my $self = shift;
    require TAP::Harness;
    printf(
        "TAP::Harness v%s and Perl v%vd\n",
        $TAP::Harness::VERSION, $^V
    );

    return;
}

1;


__END__

