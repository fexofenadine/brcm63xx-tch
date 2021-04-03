package App::Prove::State::Result;

use strict;
use warnings;
use Carp 'croak';

use App::Prove::State::Result::Test;

use constant STATE_VERSION => 1;


our $VERSION = '3.35';



sub new {
    my ( $class, $arg_for ) = @_;
    $arg_for ||= {};
    my %instance_data = %$arg_for;    # shallow copy
    $instance_data{version} = $class->state_version;
    my $tests = delete $instance_data{tests} || {};
    my $self = bless \%instance_data => $class;
    $self->_initialize($tests);
    return $self;
}

sub _initialize {
    my ( $self, $tests ) = @_;
    my %tests;
    while ( my ( $name, $test ) = each %$tests ) {
        $tests{$name} = $self->test_class->new(
            {   %$test,
                name => $name
            }
        );
    }
    $self->tests( \%tests );
    return $self;
}


sub state_version {STATE_VERSION}


sub test_class {
    return 'App::Prove::State::Result::Test';
}

my %methods = (
    generation    => { method => 'generation',    default => 0 },
    last_run_time => { method => 'last_run_time', default => undef },
);

while ( my ( $key, $description ) = each %methods ) {
    my $default = $description->{default};
    no strict 'refs';
    *{ $description->{method} } = sub {
        my $self = shift;
        if (@_) {
            $self->{$key} = shift;
            return $self;
        }
        return $self->{$key} || $default;
    };
}


sub tests {
    my $self = shift;
    if (@_) {
        $self->{tests} = shift;
        return $self;
    }
    my %tests = %{ $self->{tests} };
    my @tests = sort { $a->sequence <=> $b->sequence } values %tests;
    return wantarray ? @tests : \@tests;
}


sub test {
    my ( $self, $name ) = @_;
    croak("test() requires a test name") unless defined $name;

    my $tests = $self->{tests} ||= {};
    if ( my $test = $tests->{$name} ) {
        return $test;
    }
    else {
        my $test = $self->test_class->new( { name => $name } );
        $self->{tests}->{$name} = $test;
        return $test;
    }
}


sub test_names {
    my $self = shift;
    return map { $_->name } $self->tests;
}


sub remove {
    my ( $self, $name ) = @_;
    delete $self->{tests}->{$name};
    return $self;
}


sub num_tests { keys %{ shift->{tests} } }


sub raw {
    my $self = shift;
    my %raw  = %$self;

    my %tests;
    for my $test ( $self->tests ) {
        $tests{ $test->name } = $test->raw;
    }
    $raw{tests} = \%tests;
    return \%raw;
}

1;
