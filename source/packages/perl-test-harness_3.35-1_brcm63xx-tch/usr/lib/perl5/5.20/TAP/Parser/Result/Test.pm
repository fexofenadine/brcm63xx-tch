package TAP::Parser::Result::Test;

use strict;
use warnings;

use base 'TAP::Parser::Result';


our $VERSION = '3.35';




sub ok { shift->{ok} }



sub number { shift->{test_num} }

sub _number {
    my ( $self, $number ) = @_;
    $self->{test_num} = $number;
}



sub description { shift->{description} }



sub directive { shift->{directive} }



sub explanation { shift->{explanation} }



sub is_ok {
    my $self = shift;

    return if $self->is_unplanned;

    # TODO directives reverse the sense of a test.
    return $self->has_todo ? 1 : $self->ok !~ /not/;
}



sub is_actual_ok {
    my $self = shift;
    return $self->{ok} !~ /not/;
}



sub actual_passed {
    warn 'actual_passed() is deprecated.  Please use "is_actual_ok()"';
    goto &is_actual_ok;
}



sub todo_passed {
    my $self = shift;
    return $self->has_todo && $self->is_actual_ok;
}



sub todo_failed {
    warn 'todo_failed() is deprecated.  Please use "todo_passed()"';
    goto &todo_passed;
}



sub as_string {
    my $self   = shift;
    my $string = $self->ok . " " . $self->number;
    if ( my $description = $self->description ) {
        $string .= " $description";
    }
    if ( my $directive = $self->directive ) {
        my $explanation = $self->explanation;
        $string .= " # $directive $explanation";
    }
    return $string;
}



sub is_unplanned {
    my $self = shift;
    return ( $self->{unplanned} || '' ) unless @_;
    $self->{unplanned} = !!shift;
    return $self;
}

1;
