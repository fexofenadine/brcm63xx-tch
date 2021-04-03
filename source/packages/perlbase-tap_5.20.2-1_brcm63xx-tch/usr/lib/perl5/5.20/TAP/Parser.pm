package TAP::Parser;

use strict;
use warnings;

use TAP::Parser::Grammar                   ();
use TAP::Parser::Result                    ();
use TAP::Parser::ResultFactory             ();
use TAP::Parser::Source                    ();
use TAP::Parser::Iterator                  ();
use TAP::Parser::IteratorFactory           ();
use TAP::Parser::SourceHandler::Executable ();
use TAP::Parser::SourceHandler::Perl       ();
use TAP::Parser::SourceHandler::File       ();
use TAP::Parser::SourceHandler::RawTAP     ();
use TAP::Parser::SourceHandler::Handle     ();

use Carp qw( confess );

use base 'TAP::Base';


our $VERSION = '3.30';

my $DEFAULT_TAP_VERSION = 12;
my $MAX_TAP_VERSION     = 13;

$ENV{TAP_VERSION} = $MAX_TAP_VERSION;

END {

    # For VMS.
    delete $ENV{TAP_VERSION};
}

BEGIN {    # making accessors
    __PACKAGE__->mk_methods(
        qw(
          _iterator
          _spool
          exec
          exit
          is_good_plan
          plan
          tests_planned
          tests_run
          wait
          version
          in_todo
          start_time
          end_time
          skip_all
          grammar_class
          result_factory_class
          iterator_factory_class
          )
    );

    sub _stream {    # deprecated
        my $self = shift;
        $self->_iterator(@_);
    }
}    # done making accessors



sub _default_grammar_class          {'TAP::Parser::Grammar'}
sub _default_result_factory_class   {'TAP::Parser::ResultFactory'}
sub _default_iterator_factory_class {'TAP::Parser::IteratorFactory'}



sub next {
    my $self = shift;
    return ( $self->{_iter} ||= $self->_iter )->();
}



sub run {
    my $self = shift;
    while ( defined( my $result = $self->next ) ) {

        # do nothing
    }
}



sub make_iterator_factory { shift->iterator_factory_class->new(@_); }
sub make_grammar          { shift->grammar_class->new(@_); }
sub make_result           { shift->result_factory_class->make_result(@_); }

{

    # of the following, anything beginning with an underscore is strictly
    # internal and should not be exposed.
    my %initialize = (
        version       => $DEFAULT_TAP_VERSION,
        plan          => '',                    # the test plan (e.g., 1..3)
        tests_run     => 0,                     # actual current test numbers
        skipped       => [],                    #
        todo          => [],                    #
        passed        => [],                    #
        failed        => [],                    #
        actual_failed => [],                    # how many tests really failed
        actual_passed => [],                    # how many tests really passed
        todo_passed  => [],    # tests which unexpectedly succeed
        parse_errors => [],    # perfect TAP should have none
    );

    # We seem to have this list hanging around all over the place. We could
    # probably get it from somewhere else to avoid the repetition.
    my @legal_callback = qw(
      test
      version
      plan
      comment
      bailout
      unknown
      yaml
      ALL
      ELSE
      EOF
    );

    my @class_overrides = qw(
      grammar_class
      result_factory_class
      iterator_factory_class
    );

    sub _initialize {
        my ( $self, $arg_for ) = @_;

        # everything here is basically designed to convert any TAP source to a
        # TAP::Parser::Iterator.

        # Shallow copy
        my %args = %{ $arg_for || {} };

        $self->SUPER::_initialize( \%args, \@legal_callback );

        # get any class overrides out first:
        for my $key (@class_overrides) {
            my $default_method = "_default_$key";
            my $val = delete $args{$key} || $self->$default_method();
            $self->$key($val);
        }

        my $iterator = delete $args{iterator};
        $iterator ||= delete $args{stream};    # deprecated
        my $tap         = delete $args{tap};
        my $version     = delete $args{version};
        my $raw_source  = delete $args{source};
        my $sources     = delete $args{sources};
        my $exec        = delete $args{exec};
        my $merge       = delete $args{merge};
        my $spool       = delete $args{spool};
        my $switches    = delete $args{switches};
        my $ignore_exit = delete $args{ignore_exit};
        my $test_args   = delete $args{test_args} || [];

        if ( 1 < grep {defined} $iterator, $tap, $raw_source, $exec ) {
            $self->_croak(
                "You may only choose one of 'exec', 'tap', 'source' or 'iterator'"
            );
        }

        if ( my @excess = sort keys %args ) {
            $self->_croak("Unknown options: @excess");
        }

        # convert $tap & $exec to $raw_source equiv.
        my $type   = '';
        my $source = TAP::Parser::Source->new;
        if ($tap) {
            $type = 'raw TAP';
            $source->raw( \$tap );
        }
        elsif ($exec) {
            $type = 'exec ' . $exec->[0];
            $source->raw( { exec => $exec } );
        }
        elsif ($raw_source) {
            $type = 'source ' . ref($raw_source) || $raw_source;
            $source->raw( ref($raw_source) ? $raw_source : \$raw_source );
        }
        elsif ($iterator) {
            $type = 'iterator ' . ref($iterator);
        }

        if ( $source->raw ) {
            my $src_factory = $self->make_iterator_factory($sources);
            $source->merge($merge)->switches($switches)
              ->test_args($test_args);
            $iterator = $src_factory->make_iterator($source);
        }

        unless ($iterator) {
            $self->_croak(
                "PANIC: could not determine iterator for input $type");
        }

        while ( my ( $k, $v ) = each %initialize ) {
            $self->{$k} = 'ARRAY' eq ref $v ? [] : $v;
        }

        $self->version($version) if $version;
        $self->_iterator($iterator);
        $self->_spool($spool);
        $self->ignore_exit($ignore_exit);

        return $self;
    }
}


sub passed {
    return @{ $_[0]->{passed} }
      if ref $_[0]->{passed};
    return wantarray ? 1 .. $_[0]->{passed} : $_[0]->{passed};
}


sub failed { @{ shift->{failed} } }


sub actual_passed {
    return @{ $_[0]->{actual_passed} }
      if ref $_[0]->{actual_passed};
    return wantarray ? 1 .. $_[0]->{actual_passed} : $_[0]->{actual_passed};
}
*actual_ok = \&actual_passed;


sub actual_failed { @{ shift->{actual_failed} } }



sub todo { @{ shift->{todo} } }


sub todo_passed { @{ shift->{todo_passed} } }



sub todo_failed {
    warn
      '"todo_failed" is deprecated.  Please use "todo_passed".  See the docs.';
    goto &todo_passed;
}


sub skipped { @{ shift->{skipped} } }


sub pragma {
    my ( $self, $pragma ) = splice @_, 0, 2;

    return $self->{pragma}->{$pragma} unless @_;

    if ( my $state = shift ) {
        $self->{pragma}->{$pragma} = 1;
    }
    else {
        delete $self->{pragma}->{$pragma};
    }

    return;
}


sub pragmas { sort keys %{ shift->{pragma} || {} } }


sub good_plan {
    warn 'good_plan() is deprecated.  Please use "is_good_plan()"';
    goto &is_good_plan;
}



sub has_problems {
    my $self = shift;
    return
         $self->failed
      || $self->parse_errors
      || ( !$self->ignore_exit && ( $self->wait || $self->exit ) );
}


sub ignore_exit { shift->pragma( 'ignore_exit', @_ ) }


sub parse_errors { @{ shift->{parse_errors} } }

sub _add_error {
    my ( $self, $error ) = @_;
    push @{ $self->{parse_errors} } => $error;
    return $self;
}

sub _make_state_table {
    my $self = shift;
    my %states;
    my %planned_todo = ();

    # These transitions are defaults for all states
    my %state_globals = (
        comment => {},
        bailout => {},
        yaml    => {},
        version => {
            act => sub {
                $self->_add_error(
                    'If TAP version is present it must be the first line of output'
                );
            },
        },
        unknown => {
            act => sub {
                my $unk = shift;
                if ( $self->pragma('strict') ) {
                    $self->_add_error(
                        'Unknown TAP token: "' . $unk->raw . '"' );
                }
            },
        },
        pragma => {
            act => sub {
                my ($pragma) = @_;
                for my $pr ( $pragma->pragmas ) {
                    if ( $pr =~ /^ ([-+])(\w+) $/x ) {
                        $self->pragma( $2, $1 eq '+' );
                    }
                }
            },
        },
    );

    # Provides default elements for transitions
    my %state_defaults = (
        plan => {
            act => sub {
                my ($plan) = @_;
                $self->tests_planned( $plan->tests_planned );
                $self->plan( $plan->plan );
                if ( $plan->has_skip ) {
                    $self->skip_all( $plan->explanation
                          || '(no reason given)' );
                }

                $planned_todo{$_}++ for @{ $plan->todo_list };
            },
        },
        test => {
            act => sub {
                my ($test) = @_;

                my ( $number, $tests_run )
                  = ( $test->number, ++$self->{tests_run} );

                # Fake TODO state
                if ( defined $number && delete $planned_todo{$number} ) {
                    $test->set_directive('TODO');
                }

                my $has_todo = $test->has_todo;

                $self->in_todo($has_todo);
                if ( defined( my $tests_planned = $self->tests_planned ) ) {
                    if ( $tests_run > $tests_planned ) {
                        $test->is_unplanned(1);
                    }
                }

                if ( defined $number ) {
                    if ( $number != $tests_run ) {
                        my $count = $tests_run;
                        $self->_add_error( "Tests out of sequence.  Found "
                              . "($number) but expected ($count)" );
                    }
                }
                else {
                    $test->_number( $number = $tests_run );
                }

                push @{ $self->{todo} } => $number if $has_todo;
                push @{ $self->{todo_passed} } => $number
                  if $test->todo_passed;
                push @{ $self->{skipped} } => $number
                  if $test->has_skip;

                push @{ $self->{ $test->is_ok ? 'passed' : 'failed' } } =>
                  $number;
                push @{
                    $self->{
                        $test->is_actual_ok
                        ? 'actual_passed'
                        : 'actual_failed'
                      }
                  } => $number;
            },
        },
        yaml => { act => sub { }, },
    );

    # Each state contains a hash the keys of which match a token type. For
    # each token
    # type there may be:
    #   act      A coderef to run
    #   goto     The new state to move to. Stay in this state if
    #            missing
    #   continue Goto the new state and run the new state for the
    #            current token
    %states = (
        INIT => {
            version => {
                act => sub {
                    my ($version) = @_;
                    my $ver_num = $version->version;
                    if ( $ver_num <= $DEFAULT_TAP_VERSION ) {
                        my $ver_min = $DEFAULT_TAP_VERSION + 1;
                        $self->_add_error(
                                "Explicit TAP version must be at least "
                              . "$ver_min. Got version $ver_num" );
                        $ver_num = $DEFAULT_TAP_VERSION;
                    }
                    if ( $ver_num > $MAX_TAP_VERSION ) {
                        $self->_add_error(
                                "TAP specified version $ver_num but "
                              . "we don't know about versions later "
                              . "than $MAX_TAP_VERSION" );
                        $ver_num = $MAX_TAP_VERSION;
                    }
                    $self->version($ver_num);
                    $self->_grammar->set_version($ver_num);
                },
                goto => 'PLAN'
            },
            plan => { goto => 'PLANNED' },
            test => { goto => 'UNPLANNED' },
        },
        PLAN => {
            plan => { goto => 'PLANNED' },
            test => { goto => 'UNPLANNED' },
        },
        PLANNED => {
            test => { goto => 'PLANNED_AFTER_TEST' },
            plan => {
                act => sub {
                    my ($version) = @_;
                    $self->_add_error(
                        'More than one plan found in TAP output');
                },
            },
        },
        PLANNED_AFTER_TEST => {
            test => { goto => 'PLANNED_AFTER_TEST' },
            plan => { act  => sub { }, continue => 'PLANNED' },
            yaml => { goto => 'PLANNED' },
        },
        GOT_PLAN => {
            test => {
                act => sub {
                    my ($plan) = @_;
                    my $line = $self->plan;
                    $self->_add_error(
                            "Plan ($line) must be at the beginning "
                          . "or end of the TAP output" );
                    $self->is_good_plan(0);
                },
                continue => 'PLANNED'
            },
            plan => { continue => 'PLANNED' },
        },
        UNPLANNED => {
            test => { goto => 'UNPLANNED_AFTER_TEST' },
            plan => { goto => 'GOT_PLAN' },
        },
        UNPLANNED_AFTER_TEST => {
            test => { act  => sub { }, continue => 'UNPLANNED' },
            plan => { act  => sub { }, continue => 'UNPLANNED' },
            yaml => { goto => 'UNPLANNED' },
        },
    );

    # Apply globals and defaults to state table
    for my $name ( keys %states ) {

        # Merge with globals
        my $st = { %state_globals, %{ $states{$name} } };

        # Add defaults
        for my $next ( sort keys %{$st} ) {
            if ( my $default = $state_defaults{$next} ) {
                for my $def ( sort keys %{$default} ) {
                    $st->{$next}->{$def} ||= $default->{$def};
                }
            }
        }

        # Stuff back in table
        $states{$name} = $st;
    }

    return \%states;
}


sub get_select_handles { shift->_iterator->get_select_handles }

sub _grammar {
    my $self = shift;
    return $self->{_grammar} = shift if @_;

    return $self->{_grammar} ||= $self->make_grammar(
        {   iterator => $self->_iterator,
            parser   => $self,
            version  => $self->version
        }
    );
}

sub _iter {
    my $self        = shift;
    my $iterator    = $self->_iterator;
    my $grammar     = $self->_grammar;
    my $spool       = $self->_spool;
    my $state       = 'INIT';
    my $state_table = $self->_make_state_table;

    $self->start_time( $self->get_time );

    # Make next_state closure
    my $next_state = sub {
        my $token = shift;
        my $type  = $token->type;
        TRANS: {
            my $state_spec = $state_table->{$state}
              or die "Illegal state: $state";

            if ( my $next = $state_spec->{$type} ) {
                if ( my $act = $next->{act} ) {
                    $act->($token);
                }
                if ( my $cont = $next->{continue} ) {
                    $state = $cont;
                    redo TRANS;
                }
                elsif ( my $goto = $next->{goto} ) {
                    $state = $goto;
                }
            }
            else {
                confess("Unhandled token type: $type\n");
            }
        }
        return $token;
    };

    # Handle end of stream - which means either pop a block or finish
    my $end_handler = sub {
        $self->exit( $iterator->exit );
        $self->wait( $iterator->wait );
        $self->_finish;
        return;
    };

    # Finally make the closure that we return. For performance reasons
    # there are two versions of the returned function: one that handles
    # callbacks and one that does not.
    if ( $self->_has_callbacks ) {
        return sub {
            my $result = eval { $grammar->tokenize };
            $self->_add_error($@) if $@;

            if ( defined $result ) {
                $result = $next_state->($result);

                if ( my $code = $self->_callback_for( $result->type ) ) {
                    $_->($result) for @{$code};
                }
                else {
                    $self->_make_callback( 'ELSE', $result );
                }

                $self->_make_callback( 'ALL', $result );

                # Echo TAP to spool file
                print {$spool} $result->raw, "\n" if $spool;
            }
            else {
                $result = $end_handler->();
                $self->_make_callback( 'EOF', $self )
                  unless defined $result;
            }

            return $result;
        };
    }    # _has_callbacks
    else {
        return sub {
            my $result = eval { $grammar->tokenize };
            $self->_add_error($@) if $@;

            if ( defined $result ) {
                $result = $next_state->($result);

                # Echo TAP to spool file
                print {$spool} $result->raw, "\n" if $spool;
            }
            else {
                $result = $end_handler->();
            }

            return $result;
        };
    }    # no callbacks
}

sub _finish {
    my $self = shift;

    $self->end_time( $self->get_time );

    # Avoid leaks
    $self->_iterator(undef);
    $self->_grammar(undef);

    # If we just delete the iter we won't get a fault if it's recreated.
    # Instead we set it to a sub that returns an infinite
    # stream of undef. This segfaults on 5.5.4, presumably because
    # we're still executing the closure that gets replaced and it hasn't
    # been protected with a refcount.
    $self->{_iter} = sub {return}
      if $] >= 5.006;

    # sanity checks
    if ( !$self->plan ) {
        $self->_add_error('No plan found in TAP output');
    }
    else {
        $self->is_good_plan(1) unless defined $self->is_good_plan;
    }
    if ( $self->tests_run != ( $self->tests_planned || 0 ) ) {
        $self->is_good_plan(0);
        if ( defined( my $planned = $self->tests_planned ) ) {
            my $ran = $self->tests_run;
            $self->_add_error(
                "Bad plan.  You planned $planned tests but ran $ran.");
        }
    }
    if ( $self->tests_run != ( $self->passed + $self->failed ) ) {

        # this should never happen
        my $actual = $self->tests_run;
        my $passed = $self->passed;
        my $failed = $self->failed;
        $self->_croak( "Panic: planned test count ($actual) did not equal "
              . "sum of passed ($passed) and failed ($failed) tests!" );
    }

    $self->is_good_plan(0) unless defined $self->is_good_plan;

    unless ( $self->parse_errors ) {
        # Optimise storage where possible
        if ( $self->tests_run == @{$self->{passed}} ) {
            $self->{passed} = $self->tests_run;
        }
        if ( $self->tests_run == @{$self->{actual_passed}} ) {
            $self->{actual_passed} = $self->tests_run;
        }
    }

    return $self;
}


sub delete_spool {
    my $self = shift;

    return delete $self->{_spool};
}



1;
