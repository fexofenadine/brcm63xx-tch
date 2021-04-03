package TAP::Parser::Result;

use strict;
use warnings;

use base 'TAP::Object';

BEGIN {

    # make is_* methods
    my @attrs = qw( plan pragma test comment bailout version unknown yaml );
    no strict 'refs';
    for my $token (@attrs) {
        my $method = "is_$token";
        *$method = sub { return $token eq shift->type };
    }
}



our $VERSION = '3.35';



sub _initialize {
    my ( $self, $token ) = @_;
    if ($token) {

       # assign to a hash slice to make a shallow copy of the token.
       # I guess we could assign to the hash as (by default) there are not
       # contents, but that seems less helpful if someone wants to subclass us
        @{$self}{ keys %$token } = values %$token;
    }
    return $self;
}





sub raw { shift->{raw} }



sub type { shift->{type} }



sub as_string { shift->{raw} }



sub is_ok {1}



sub passed {
    warn 'passed() is deprecated.  Please use "is_ok()"';
    shift->is_ok;
}



sub has_directive {
    my $self = shift;
    return ( $self->has_todo || $self->has_skip );
}



sub has_todo { 'TODO' eq ( shift->{directive} || '' ) }



sub has_skip { 'SKIP' eq ( shift->{directive} || '' ) }


sub set_directive {
    my ( $self, $dir ) = @_;
    $self->{directive} = $dir;
}

1;

