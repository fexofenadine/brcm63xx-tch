package TAP::Formatter::File::Session;

use strict;
use warnings;
use base 'TAP::Formatter::Session';


our $VERSION = '3.35';



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
        my $time_report = $self->time_report($formatter, $parser);
        $formatter->_output( $pretty
              . ( $self->{results} ? "\n" . $self->{results} : "" )
              . $self->_make_ok_line($time_report) );
    }
}

1;
