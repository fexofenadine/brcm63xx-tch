package TAP::Harness;

use strict;
use warnings;
use Carp;

use File::Spec;
use File::Path;
use IO::Handle;

use base 'TAP::Base';


our $VERSION = '3.35';

$ENV{HARNESS_ACTIVE}  = 1;
$ENV{HARNESS_VERSION} = $VERSION;

END {

    # For VMS.
    delete $ENV{HARNESS_ACTIVE};
    delete $ENV{HARNESS_VERSION};
}


my %VALIDATION_FOR;
my @FORMATTER_ARGS;

sub _error {
    my $self = shift;
    return $self->{error} unless @_;
    $self->{error} = shift;
}

BEGIN {

    @FORMATTER_ARGS = qw(
      directives verbosity timer failures comments errors stdout color
      show_count normalize
    );

    %VALIDATION_FOR = (
        lib => sub {
            my ( $self, $libs ) = @_;
            $libs = [$libs] unless 'ARRAY' eq ref $libs;

            return [ map {"-I$_"} @$libs ];
        },
        switches          => sub { shift; shift },
        exec              => sub { shift; shift },
        merge             => sub { shift; shift },
        aggregator_class  => sub { shift; shift },
        formatter_class   => sub { shift; shift },
        multiplexer_class => sub { shift; shift },
        parser_class      => sub { shift; shift },
        scheduler_class   => sub { shift; shift },
        formatter         => sub { shift; shift },
        jobs              => sub { shift; shift },
        test_args         => sub { shift; shift },
        ignore_exit       => sub { shift; shift },
        rules             => sub { shift; shift },
        rulesfile         => sub { shift; shift },
        sources           => sub { shift; shift },
        version           => sub { shift; shift },
        trap              => sub { shift; shift },
    );

    for my $method ( sort keys %VALIDATION_FOR ) {
        no strict 'refs';
        if ( $method eq 'lib' || $method eq 'switches' ) {
            *{$method} = sub {
                my $self = shift;
                unless (@_) {
                    $self->{$method} ||= [];
                    return wantarray
                      ? @{ $self->{$method} }
                      : $self->{$method};
                }
                $self->_croak("Too many arguments to method '$method'")
                  if @_ > 1;
                my $args = shift;
                $args = [$args] unless ref $args;
                $self->{$method} = $args;
                return $self;
            };
        }
        else {
            *{$method} = sub {
                my $self = shift;
                return $self->{$method} unless @_;
                $self->{$method} = shift;
            };
        }
    }

    for my $method (@FORMATTER_ARGS) {
        no strict 'refs';
        *{$method} = sub {
            my $self = shift;
            return $self->formatter->$method(@_);
        };
    }
}




{
    my @legal_callback = qw(
      parser_args
      made_parser
      before_runtests
      after_runtests
      after_test
    );

    my %default_class = (
        aggregator_class  => 'TAP::Parser::Aggregator',
        formatter_class   => 'TAP::Formatter::Console',
        multiplexer_class => 'TAP::Parser::Multiplexer',
        parser_class      => 'TAP::Parser',
        scheduler_class   => 'TAP::Parser::Scheduler',
    );

    sub _initialize {
        my ( $self, $arg_for ) = @_;
        $arg_for ||= {};

        $self->SUPER::_initialize( $arg_for, \@legal_callback );
        my %arg_for = %$arg_for;    # force a shallow copy

        for my $name ( sort keys %VALIDATION_FOR ) {
            my $property = delete $arg_for{$name};
            if ( defined $property ) {
                my $validate = $VALIDATION_FOR{$name};

                my $value = $self->$validate($property);
                if ( $self->_error ) {
                    $self->_croak;
                }
                $self->$name($value);
            }
        }

        $self->jobs(1) unless defined $self->jobs;

        if ( ! defined $self->rules ) {
            $self->_maybe_load_rulesfile;
        }

        local $default_class{formatter_class} = 'TAP::Formatter::File'
          unless -t ( $arg_for{stdout} || \*STDOUT ) && !$ENV{HARNESS_NOTTY};

        while ( my ( $attr, $class ) = each %default_class ) {
            $self->$attr( $self->$attr() || $class );
        }

        unless ( $self->formatter ) {

            # This is a little bodge to preserve legacy behaviour. It's
            # pretty horrible that we know which args are destined for
            # the formatter.
            my %formatter_args = ( jobs => $self->jobs );
            for my $name (@FORMATTER_ARGS) {
                if ( defined( my $property = delete $arg_for{$name} ) ) {
                    $formatter_args{$name} = $property;
                }
            }

            $self->formatter(
                $self->_construct( $self->formatter_class, \%formatter_args )
            );
        }

        if ( my @props = sort keys %arg_for ) {
            $self->_croak("Unknown arguments to TAP::Harness::new (@props)");
        }

        return $self;
    }

    sub _maybe_load_rulesfile {
        my ($self) = @_;

        my ($rulesfile) =   defined $self->rulesfile ? $self->rulesfile :
                            defined($ENV{HARNESS_RULESFILE}) ? $ENV{HARNESS_RULESFILE} :
                            grep { -r } qw(./testrules.yml t/testrules.yml);

        if ( defined $rulesfile && -r $rulesfile ) {
            if ( ! eval { require CPAN::Meta::YAML; 1} ) {
               warn "CPAN::Meta::YAML required to process $rulesfile" ;
               return;
            }
            my $layer = $] lt "5.008" ? "" : ":encoding(UTF-8)";
            open my $fh, "<$layer", $rulesfile
                or die "Couldn't open $rulesfile: $!";
            my $yaml_text = do { local $/; <$fh> };
            my $yaml = CPAN::Meta::YAML->read_string($yaml_text)
                or die CPAN::Meta::YAML->errstr;
            $self->rules( $yaml->[0] );
        }
        return;
    }
}



sub runtests {
    my ( $self, @tests ) = @_;

    my $aggregate = $self->_construct( $self->aggregator_class );

    $self->_make_callback( 'before_runtests', $aggregate );
    $aggregate->start;
    my $finish = sub {
        my $interrupted = shift;
        $aggregate->stop;
        $self->summary( $aggregate, $interrupted );
        $self->_make_callback( 'after_runtests', $aggregate );
    };
    my $run = sub {
        $self->aggregate_tests( $aggregate, @tests );
        $finish->();
    };

    if ( $self->trap ) {
        local $SIG{INT} = sub {
            print "\n";
            $finish->(1);
            exit;
        };
        $run->();
    }
    else {
        $run->();
    }

    return $aggregate;
}


sub summary {
    my ( $self, @args ) = @_;
    $self->formatter->summary(@args);
}

sub _after_test {
    my ( $self, $aggregate, $job, $parser ) = @_;

    $self->_make_callback( 'after_test', $job->as_array_ref, $parser );
    $aggregate->add( $job->description, $parser );
}

sub _bailout {
    my ( $self, $result ) = @_;
    my $explanation = $result->explanation;
    die "FAILED--Further testing stopped"
      . ( $explanation ? ": $explanation\n" : ".\n" );
}

sub _aggregate_parallel {
    my ( $self, $aggregate, $scheduler ) = @_;

    my $jobs = $self->jobs;
    my $mux  = $self->_construct( $self->multiplexer_class );

    RESULT: {

        # Keep multiplexer topped up
        FILL:
        while ( $mux->parsers < $jobs ) {
            my $job = $scheduler->get_job;

            # If we hit a spinner stop filling and start running.
            last FILL if !defined $job || $job->is_spinner;

            my ( $parser, $session ) = $self->make_parser($job);
            $mux->add( $parser, [ $session, $job ] );
        }

        if ( my ( $parser, $stash, $result ) = $mux->next ) {
            my ( $session, $job ) = @$stash;
            if ( defined $result ) {
                $session->result($result);
                $self->_bailout($result) if $result->is_bailout;
            }
            else {

                # End of parser. Automatically removed from the mux.
                $self->finish_parser( $parser, $session );
                $self->_after_test( $aggregate, $job, $parser );
                $job->finish;
            }
            redo RESULT;
        }
    }

    return;
}

sub _aggregate_single {
    my ( $self, $aggregate, $scheduler ) = @_;

    JOB:
    while ( my $job = $scheduler->get_job ) {
        next JOB if $job->is_spinner;

        my ( $parser, $session ) = $self->make_parser($job);

        while ( defined( my $result = $parser->next ) ) {
            $session->result($result);
            if ( $result->is_bailout ) {

                # Keep reading until input is exhausted in the hope
                # of allowing any pending diagnostics to show up.
                1 while $parser->next;
                $self->_bailout($result);
            }
        }

        $self->finish_parser( $parser, $session );
        $self->_after_test( $aggregate, $job, $parser );
        $job->finish;
    }

    return;
}


sub aggregate_tests {
    my ( $self, $aggregate, @tests ) = @_;

    my $jobs      = $self->jobs;
    my $scheduler = $self->make_scheduler(@tests);

    # #12458
    local $ENV{HARNESS_IS_VERBOSE} = 1
      if $self->formatter->verbosity > 0;

    # Formatter gets only names.
    $self->formatter->prepare( map { $_->description } $scheduler->get_all );

    if ( $self->jobs > 1 ) {
        $self->_aggregate_parallel( $aggregate, $scheduler );
    }
    else {
        $self->_aggregate_single( $aggregate, $scheduler );
    }

    return;
}

sub _add_descriptions {
    my $self = shift;

    # Turn unwrapped scalars into anonymous arrays and copy the name as
    # the description for tests that have only a name.
    return map { @$_ == 1 ? [ $_->[0], $_->[0] ] : $_ }
      map { 'ARRAY' eq ref $_ ? $_ : [$_] } @_;
}


sub make_scheduler {
    my ( $self, @tests ) = @_;
    return $self->_construct(
        $self->scheduler_class,
        tests => [ $self->_add_descriptions(@tests) ],
        rules => $self->rules
    );
}



sub _get_parser_args {
    my ( $self, $job ) = @_;
    my $test_prog = $job->filename;
    my %args      = ();

    $args{sources} = $self->sources if $self->sources;

    my @switches;
    @switches = $self->lib if $self->lib;
    push @switches => $self->switches if $self->switches;
    $args{switches}    = \@switches;
    $args{spool}       = $self->_open_spool($test_prog);
    $args{merge}       = $self->merge;
    $args{ignore_exit} = $self->ignore_exit;
    $args{version}     = $self->version if $self->version;

    if ( my $exec = $self->exec ) {
        $args{exec}
          = ref $exec eq 'CODE'
          ? $exec->( $self, $test_prog )
          : [ @$exec, $test_prog ];
        if ( not defined $args{exec} ) {
            $args{source} = $test_prog;
        }
        elsif ( ( ref( $args{exec} ) || "" ) ne "ARRAY" ) {
            $args{source} = delete $args{exec};
        }
    }
    else {
        $args{source} = $test_prog;
    }

    if ( defined( my $test_args = $self->test_args ) ) {

        if ( ref($test_args) eq 'HASH' ) {

            # different args for each test
            if ( exists( $test_args->{ $job->description } ) ) {
                $test_args = $test_args->{ $job->description };
            }
            else {
                $self->_croak( "TAP::Harness Can't find test_args for "
                      . $job->description );
            }
        }

        $args{test_args} = $test_args;
    }

    return \%args;
}


sub make_parser {
    my ( $self, $job ) = @_;

    my $args = $self->_get_parser_args($job);
    $self->_make_callback( 'parser_args', $args, $job->as_array_ref );
    my $parser = $self->_construct( $self->parser_class, $args );

    $self->_make_callback( 'made_parser', $parser, $job->as_array_ref );
    my $session = $self->formatter->open_test( $job->description, $parser );

    return ( $parser, $session );
}


sub finish_parser {
    my ( $self, $parser, $session ) = @_;

    $session->close_test;
    $self->_close_spool($parser);

    return $parser;
}

sub _open_spool {
    my $self = shift;
    my $test = shift;

    if ( my $spool_dir = $ENV{PERL_TEST_HARNESS_DUMP_TAP} ) {

        my $spool = File::Spec->catfile( $spool_dir, $test );

        # Make the directory
        my ( $vol, $dir, undef ) = File::Spec->splitpath($spool);
        my $path = File::Spec->catpath( $vol, $dir, '' );
        eval { mkpath($path) };
        $self->_croak($@) if $@;

        my $spool_handle = IO::Handle->new;
        open( $spool_handle, ">$spool" )
          or $self->_croak(" Can't write $spool ( $! ) ");

        return $spool_handle;
    }

    return;
}

sub _close_spool {
    my $self = shift;
    my ($parser) = @_;

    if ( my $spool_handle = $parser->delete_spool ) {
        close($spool_handle)
          or $self->_croak(" Error closing TAP spool file( $! ) \n ");
    }

    return;
}

sub _croak {
    my ( $self, $message ) = @_;
    unless ($message) {
        $message = $self->_error;
    }
    $self->SUPER::_croak($message);

    return;
}

1;

__END__




