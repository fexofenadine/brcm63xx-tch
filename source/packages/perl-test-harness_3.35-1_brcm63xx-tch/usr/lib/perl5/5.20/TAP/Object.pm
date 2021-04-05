package TAP::Object;

use strict;
use warnings;


our $VERSION = '3.35';


sub new {
    my $class = shift;
    my $self = bless {}, $class;
    return $self->_initialize(@_);
}


sub _initialize {
    return $_[0];
}


sub _croak {
    my $proto = shift;
    require Carp;
    Carp::croak(@_);
    return;
}


sub _confess {
    my $proto = shift;
    require Carp;
    Carp::confess(@_);
    return;
}


sub _construct {
    my ( $self, $class, @args ) = @_;

    $self->_croak("Bad module name $class")
      unless $class =~ /^ \w+ (?: :: \w+ ) *$/x;

    unless ( $class->can('new') ) {
        local $@;
        eval "require $class";
        $self->_croak("Can't load $class: $@") if $@;
    }

    return $class->new(@args);
}


sub mk_methods {
    my ( $class, @methods ) = @_;
    for my $method_name (@methods) {
        my $method = "${class}::$method_name";
        no strict 'refs';
        *$method = sub {
            my $self = shift;
            $self->{$method_name} = shift if @_;
            return $self->{$method_name};
        };
    }
}

1;

