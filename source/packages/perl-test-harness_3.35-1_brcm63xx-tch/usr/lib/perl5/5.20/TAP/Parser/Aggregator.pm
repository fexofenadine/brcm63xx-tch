package TAP::Parser::Aggregator;

use strict;
use warnings;
use Benchmark;

use base 'TAP::Object';


our $VERSION = '3.35';



my %SUMMARY_METHOD_FOR;

BEGIN {    # install summary methods
    %SUMMARY_METHOD_FOR = map { $_ => $_ } qw(
      failed
      parse_errors
      passed
      skipped
      todo
      todo_passed
      total
      wait
      exit
    );
    $SUMMARY_METHOD_FOR{total}   = 'tests_run';
    $SUMMARY_METHOD_FOR{planned} = 'tests_planned';

    for my $method ( keys %SUMMARY_METHOD_FOR ) {
        next if 'total' eq $method;
        no strict 'refs';
        *$method = sub {
            my $self = shift;
            return wantarray
              ? @{ $self->{"descriptions_for_$method"} }
              : $self->{$method};
        };
    }
}    # end install summary methods

sub _initialize {
    my ($self) = @_;
    $self->{parser_for}  = {};
    $self->{parse_order} = [];
    for my $summary ( keys %SUMMARY_METHOD_FOR ) {
        $self->{$summary} = 0;
        next if 'total' eq $summary;
        $self->{"descriptions_for_$summary"} = [];
    }
    return $self;
}



sub add {
    my ( $self, $description, $parser ) = @_;
    if ( exists $self->{parser_for}{$description} ) {
        $self->_croak( "You already have a parser for ($description)."
              . " Perhaps you have run the same test twice." );
    }
    push @{ $self->{parse_order} } => $description;
    $self->{parser_for}{$description} = $parser;

    while ( my ( $summary, $method ) = each %SUMMARY_METHOD_FOR ) {

        # Slightly nasty. Instead we should maybe have 'cooked' accessors
        # for results that may be masked by the parser.
        next
          if ( $method eq 'exit' || $method eq 'wait' )
          && $parser->ignore_exit;

        if ( my $count = $parser->$method() ) {
            $self->{$summary} += $count;
            push @{ $self->{"descriptions_for_$summary"} } => $description;
        }
    }

    return $self;
}



sub parsers {
    my $self = shift;
    return $self->_get_parsers(@_) if @_;
    my $descriptions = $self->{parse_order};
    my @parsers      = @{ $self->{parser_for} }{@$descriptions};

    # Note:  Because of the way context works, we must assign the parsers to
    # the @parsers array or else this method does not work as documented.
    return @parsers;
}

sub _get_parsers {
    my ( $self, @descriptions ) = @_;
    my @parsers;
    for my $description (@descriptions) {
        $self->_croak("A parser for ($description) could not be found")
          unless exists $self->{parser_for}{$description};
        push @parsers => $self->{parser_for}{$description};
    }
    return wantarray ? @parsers : \@parsers;
}


sub descriptions { @{ shift->{parse_order} || [] } }


sub start {
    my $self = shift;
    $self->{start_time} = Benchmark->new;
}


sub stop {
    my $self = shift;
    $self->{end_time} = Benchmark->new;
}


sub elapsed {
    my $self = shift;

    require Carp;
    Carp::croak
      q{Can't call elapsed without first calling start and then stop}
      unless defined $self->{start_time} && defined $self->{end_time};
    return timediff( $self->{end_time}, $self->{start_time} );
}


sub elapsed_timestr {
    my $self = shift;

    my $elapsed = $self->elapsed;

    return timestr($elapsed);
}


sub all_passed {
    my $self = shift;
    return
         $self->total
      && $self->total == $self->passed
      && !$self->has_errors;
}


sub get_status {
    my $self = shift;

    my $total  = $self->total;
    my $passed = $self->passed;

    return
        ( $self->has_errors || $total != $passed ) ? 'FAIL'
      : $total ? 'PASS'
      :          'NOTESTS';
}





sub total { shift->{total} }



sub has_problems {
    my $self = shift;
    return $self->todo_passed
      || $self->has_errors;
}



sub has_errors {
    my $self = shift;
    return
         $self->failed
      || $self->parse_errors
      || $self->exit
      || $self->wait;
}



sub todo_failed {
    warn
      '"todo_failed" is deprecated.  Please use "todo_passed".  See the docs.';
    goto &todo_passed;
}


1;
