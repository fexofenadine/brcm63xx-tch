package Test::Harness;

use 5.006;

use strict;
use warnings;

use constant IS_WIN32 => ( $^O =~ /^(MS)?Win32$/ );
use constant IS_VMS => ( $^O eq 'VMS' );

use TAP::Harness                     ();
use TAP::Parser::Aggregator          ();
use TAP::Parser::Source              ();
use TAP::Parser::SourceHandler::Perl ();

use Text::ParseWords qw(shellwords);

use Config;
use base 'Exporter';


BEGIN {
    eval q{use Time::HiRes 'time'};
    our $has_time_hires = !$@;
}


our $VERSION = '3.35';

*verbose  = *Verbose;
*switches = *Switches;
*debug    = *Debug;

$ENV{HARNESS_ACTIVE}  = 1;
$ENV{HARNESS_VERSION} = $VERSION;

END {

    # For VMS.
    delete $ENV{HARNESS_ACTIVE};
    delete $ENV{HARNESS_VERSION};
}

our @EXPORT    = qw(&runtests);
our @EXPORT_OK = qw(&execute_tests $verbose $switches);

our $Verbose = $ENV{HARNESS_VERBOSE} || 0;
our $Debug   = $ENV{HARNESS_DEBUG}   || 0;
our $Switches = '-w';
our $Columns = $ENV{HARNESS_COLUMNS} || $ENV{COLUMNS} || 80;
$Columns--;    # Some shells have trouble with a full line of text.
our $Timer      = $ENV{HARNESS_TIMER}       || 0;
our $Color      = $ENV{HARNESS_COLOR}       || 0;
our $IgnoreExit = $ENV{HARNESS_IGNORE_EXIT} || 0;


sub _has_taint {
    my $test = shift;
    return TAP::Parser::SourceHandler::Perl->get_taint(
        TAP::Parser::Source->shebang($test) );
}

sub _aggregate {
    my ( $harness, $aggregate, @tests ) = @_;

    # Don't propagate to our children
    local $ENV{HARNESS_OPTIONS};

    _apply_extra_INC($harness);
    _aggregate_tests( $harness, $aggregate, @tests );
}

sub _apply_extra_INC {
    my $harness = shift;

    $harness->callback(
        parser_args => sub {
            my ( $args, $test ) = @_;
            push @{ $args->{switches} }, map {"-I$_"} _filtered_inc();
        }
    );
}

sub _aggregate_tests {
    my ( $harness, $aggregate, @tests ) = @_;
    $aggregate->start();
    $harness->aggregate_tests( $aggregate, @tests );
    $aggregate->stop();

}

sub runtests {
    my @tests = @_;

    # shield against -l
    local ( $\, $, );

    my $harness   = _new_harness();
    my $aggregate = TAP::Parser::Aggregator->new();

    _aggregate( $harness, $aggregate, @tests );

    $harness->formatter->summary($aggregate);

    my $total  = $aggregate->total;
    my $passed = $aggregate->passed;
    my $failed = $aggregate->failed;

    my @parsers = $aggregate->parsers;

    my $num_bad = 0;
    for my $parser (@parsers) {
        $num_bad++ if $parser->has_problems;
    }

    die(sprintf(
            "Failed %d/%d test programs. %d/%d subtests failed.\n",
            $num_bad, scalar @parsers, $failed, $total
        )
    ) if $num_bad;

    return $total && $total == $passed;
}

sub _canon {
    my @list   = sort { $a <=> $b } @_;
    my @ranges = ();
    my $count  = scalar @list;
    my $pos    = 0;

    while ( $pos < $count ) {
        my $end = $pos + 1;
        $end++ while $end < $count && $list[$end] <= $list[ $end - 1 ] + 1;
        push @ranges, ( $end == $pos + 1 )
          ? $list[$pos]
          : join( '-', $list[$pos], $list[ $end - 1 ] );
        $pos = $end;
    }

    return join( ' ', @ranges );
}

sub _new_harness {
    my $sub_args = shift || {};

    my ( @lib, @switches );
    my @opt = map { shellwords($_) } grep { defined } $Switches, $ENV{HARNESS_PERL_SWITCHES};
    while ( my $opt = shift @opt ) {
        if ( $opt =~ /^ -I (.*) $ /x ) {
            push @lib, length($1) ? $1 : shift @opt;
        }
        else {
            push @switches, $opt;
        }
    }

    # Do things the old way on VMS...
    push @lib, _filtered_inc() if IS_VMS;

    # If $Verbose isn't numeric default to 1. This helps core.
    my $verbosity = ( $Verbose ? ( $Verbose !~ /\d/ ) ? 1 : $Verbose : 0 );

    my $args = {
        timer       => $Timer,
        directives  => our $Directives,
        lib         => \@lib,
        switches    => \@switches,
        color       => $Color,
        verbosity   => $verbosity,
        ignore_exit => $IgnoreExit,
    };

    $args->{stdout} = $sub_args->{out}
      if exists $sub_args->{out};

    my $class = $ENV{HARNESS_SUBCLASS} || 'TAP::Harness';
    if ( defined( my $env_opt = $ENV{HARNESS_OPTIONS} ) ) {
        for my $opt ( split /:/, $env_opt ) {
            if ( $opt =~ /^j(\d*)$/ ) {
                $args->{jobs} = $1 || 9;
            }
            elsif ( $opt eq 'c' ) {
                $args->{color} = 1;
            }
            elsif ( $opt =~ m/^f(.*)$/ ) {
                my $fmt = $1;
                $fmt =~ s/-/::/g;
                $args->{formatter_class} = $fmt;
            }
            elsif ( $opt =~ m/^a(.*)$/ ) {
                my $archive = $1;
                $class = "TAP::Harness::Archive";
                $args->{archive} = $archive;
            }
            else {
                die "Unknown HARNESS_OPTIONS item: $opt\n";
            }
        }
    }

    return TAP::Harness->_construct( $class, $args );
}

sub _filtered_inc {
    my @inc = grep { !ref } @INC;    #28567

    if (IS_VMS) {

        # VMS has a 255-byte limit on the length of %ENV entries, so
        # toss the ones that involve perl_root, the install location
        @inc = grep !/perl_root/i, @inc;

    }
    elsif (IS_WIN32) {

        # Lose any trailing backslashes in the Win32 paths
        s/[\\\/]+$// for @inc;
    }

    my @default_inc = _default_inc();

    my @new_inc;
    my %seen;
    for my $dir (@inc) {
        next if $seen{$dir}++;

        if ( $dir eq ( $default_inc[0] || '' ) ) {
            shift @default_inc;
        }
        else {
            push @new_inc, $dir;
        }

        shift @default_inc while @default_inc and $seen{ $default_inc[0] };
    }

    return @new_inc;
}

{

    # Cache this to avoid repeatedly shelling out to Perl.
    my @inc;

    sub _default_inc {
        return @inc if @inc;

        local $ENV{PERL5LIB};
        local $ENV{PERLLIB};

        my $perl = $ENV{HARNESS_PERL} || $^X;

        # Avoid using -l for the benefit of Perl 6
        chomp( @inc = `"$perl" -e "print join qq[\\n], \@INC, q[]"` );
        return @inc;
    }
}

sub _check_sequence {
    my @list = @_;
    my $prev;
    while ( my $next = shift @list ) {
        return if defined $prev && $next <= $prev;
        $prev = $next;
    }

    return 1;
}

sub execute_tests {
    my %args = @_;

    my $harness   = _new_harness( \%args );
    my $aggregate = TAP::Parser::Aggregator->new();

    my %tot = (
        bonus       => 0,
        max         => 0,
        ok          => 0,
        bad         => 0,
        good        => 0,
        files       => 0,
        tests       => 0,
        sub_skipped => 0,
        todo        => 0,
        skipped     => 0,
        bench       => undef,
    );

    # Install a callback so we get to see any plans the
    # harness executes.
    $harness->callback(
        made_parser => sub {
            my $parser = shift;
            $parser->callback(
                plan => sub {
                    my $plan = shift;
                    if ( $plan->directive eq 'SKIP' ) {
                        $tot{skipped}++;
                    }
                }
            );
        }
    );

    _aggregate( $harness, $aggregate, @{ $args{tests} } );

    $tot{bench} = $aggregate->elapsed;
    my @tests = $aggregate->descriptions;

    # TODO: Work out the circumstances under which the files
    # and tests totals can differ.
    $tot{files} = $tot{tests} = scalar @tests;

    my %failedtests = ();
    my %todo_passed = ();

    for my $test (@tests) {
        my ($parser) = $aggregate->parsers($test);

        my @failed = $parser->failed;

        my $wstat         = $parser->wait;
        my $estat         = $parser->exit;
        my $planned       = $parser->tests_planned;
        my @errors        = $parser->parse_errors;
        my $passed        = $parser->passed;
        my $actual_passed = $parser->actual_passed;

        my $ok_seq = _check_sequence( $parser->actual_passed );

        # Duplicate exit, wait status semantics of old version
        $estat ||= '' unless $wstat;
        $wstat ||= '';

        $tot{max} += ( $planned || 0 );
        $tot{bonus} += $parser->todo_passed;
        $tot{ok} += $passed > $actual_passed ? $passed : $actual_passed;
        $tot{sub_skipped} += $parser->skipped;
        $tot{todo}        += $parser->todo;

        if ( @failed || $estat || @errors ) {
            $tot{bad}++;

            my $huh_planned = $planned ? undef : '??';
            my $huh_errors  = $ok_seq  ? undef : '??';

            $failedtests{$test} = {
                'canon' => $huh_planned
                  || $huh_errors
                  || _canon(@failed)
                  || '??',
                'estat'  => $estat,
                'failed' => $huh_planned
                  || $huh_errors
                  || scalar @failed,
                'max' => $huh_planned || $planned,
                'name'  => $test,
                'wstat' => $wstat
            };
        }
        else {
            $tot{good}++;
        }

        my @todo = $parser->todo_passed;
        if (@todo) {
            $todo_passed{$test} = {
                'canon'  => _canon(@todo),
                'estat'  => $estat,
                'failed' => scalar @todo,
                'max'    => scalar $parser->todo,
                'name'   => $test,
                'wstat'  => $wstat
            };
        }
    }

    return ( \%tot, \%failedtests, \%todo_passed );
}


1;
__END__

