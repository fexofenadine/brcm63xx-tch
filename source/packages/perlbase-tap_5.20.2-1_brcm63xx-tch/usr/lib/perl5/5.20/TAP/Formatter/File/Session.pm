package TAP::Formatter::File::Session;

use strict;
use warnings;
use base 'TAP::Formatter::Session';


our $VERSION = '3.30';



sub result {
    my $self   = shift;
    my $result = shift;

    my $parser    = $self->parser;
    my $formatter = $self->formatter;

    if ( $result->is_bailout ) {
        $formatter->_failure_output(
                "Bailout called.  Further testing stopped:  "
              . $result->explanation
              . "\n" );
        return;
    }

    if (!$formatter->quiet
        && (   $formatter->verbose
            || ( $result->is_test && $formatter->failures && !$result->is_ok )
            || ( $formatter->comments   && $result->is_comment )
            || ( $result->has_directive && $formatter->directives ) )
      )
    {
        $self->{results} .= $self->_format_for_output($result) . "\n";
    }
}


sub close_test {
    my $self = shift;

    # Avoid circular references
    $self->parser(undef);

    my $parser    = $self->parser;
    my $formatter = $self->formatter;
    my $pretty    = $formatter->_format_name( $self->name );

    return if $formatter->really_quiet;
    if ( my $skip_all = $parser->skip_all ) {
        $formatter->_output( $pretty . "skipped: $skip_all\n" );
    }
    elsif ( $parser->has_problems ) {
        $formatter->_output(
            $pretty . ( $self->{results} ? "\n" . $self->{results} : "\n" ) );
        $self->_output_test_failure($parser);
    }
    else {
        my $time_report = '';
        if ( $formatter->timer ) {
            my $start_time = $parser->start_time;
            my $end_time   = $parser->end_time;
            if ( defined $start_time and defined $end_time ) {
                my $elapsed = $end_time - $start_time;
                $time_report
                  = $self->time_is_hires
                  ? sprintf( ' %8d ms', $elapsed * 1000 )
                  : sprintf( ' %8s s', $elapsed || '<1' );
            }
        }

        $formatter->_output( $pretty
              . ( $self->{results} ? "\n" . $self->{results} : "" )
              . $self->_make_ok_line($time_report) );
    }
}

1;
