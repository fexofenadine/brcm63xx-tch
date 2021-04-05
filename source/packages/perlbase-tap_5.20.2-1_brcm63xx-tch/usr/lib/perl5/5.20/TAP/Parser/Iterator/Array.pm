package TAP::Parser::Iterator::Array;

use strict;
use warnings;

use base 'TAP::Parser::Iterator';


our $VERSION = '3.30';



sub _initialize {
    my ( $self, $thing ) = @_;
    chomp @$thing;
    $self->{idx}   = 0;
    $self->{array} = $thing;
    $self->{exit}  = undef;
    return $self;
}

sub wait { shift->exit }

sub exit {
    my $self = shift;
    return 0 if $self->{idx} >= @{ $self->{array} };
    return;
}

sub next_raw {
    my $self = shift;
    return $self->{array}->[ $self->{idx}++ ];
}

1;


