package TAP::Parser::Iterator::Stream;

use strict;
use warnings;

use base 'TAP::Parser::Iterator';


our $VERSION = '3.35';



sub _initialize {
    my ( $self, $thing ) = @_;
    $self->{fh} = $thing;
    return $self;
}


sub wait { shift->exit }
sub exit { shift->{fh} ? () : 0 }

sub next_raw {
    my $self = shift;
    my $fh   = $self->{fh};

    if ( defined( my $line = <$fh> ) ) {
        chomp $line;
        return $line;
    }
    else {
        $self->_finish;
        return;
    }
}

sub _finish {
    my $self = shift;
    close delete $self->{fh};
}

1;


