package DBI::Util::CacheMemory;


use strict;
use warnings;


our $VERSION = "0.010315";

my %cache;

sub new {
    my ($class, %options ) = @_;
    my $namespace = $options{namespace} ||= 'Default';
    #$options{_cache} = \%cache; # can be handy for debugging/dumping
    my $self =  bless \%options => $class;
    $cache{ $namespace } ||= {}; # init - ensure it exists
    return $self;
}

sub set {
    my ($self, $key, $value) = @_;
    $cache{ $self->{namespace} }->{$key} = $value;
}

sub get {
    my ($self, $key) = @_;
    return $cache{ $self->{namespace} }->{$key};
}

sub exists {
    my ($self, $key) = @_;
    return exists $cache{ $self->{namespace} }->{$key};
}

sub remove {
    my ($self, $key) = @_;
    return delete $cache{ $self->{namespace} }->{$key};
}

sub purge {
    return shift->clear;
}

sub clear {
    $cache{ shift->{namespace} } = {};
}

sub count {
    return scalar keys %{ $cache{ shift->{namespace} } };
}

sub size {
    my $c = $cache{ shift->{namespace} };
    my $size = 0;
    while ( my ($k,$v) = each %$c ) {
        $size += length($k) + length($v);
    }
    return $size;
}

1;
