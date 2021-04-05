package Thread::Semaphore;

use strict;
use warnings;

our $VERSION = '2.12';
$VERSION = eval $VERSION;

use threads::shared;
use Scalar::Util 1.10 qw(looks_like_number);

my ($validate_arg);

sub new {
    my $class = shift;

    my $val :shared = 1;
    if (@_) {
        $val = shift;
        if (! defined($val) ||
            ! looks_like_number($val) ||
            (int($val) != $val))
        {
            require Carp;
            $val = 'undef' if (! defined($val));
            Carp::croak("Semaphore initializer is not an integer: $val");
        }
    }

    return bless(\$val, $class);
}

sub down {
    my $sema = shift;
    my $dec = @_ ? $validate_arg->(shift) : 1;

    lock($$sema);
    cond_wait($$sema) until ($$sema >= $dec);
    $$sema -= $dec;
}

sub down_nb {
    my $sema = shift;
    my $dec = @_ ? $validate_arg->(shift) : 1;

    lock($$sema);
    my $ok = ($$sema >= $dec);
    $$sema -= $dec if $ok;
    return $ok;
}

sub down_force {
    my $sema = shift;
    my $dec = @_ ? $validate_arg->(shift) : 1;

    lock($$sema);
    $$sema -= $dec;
}

sub up {
    my $sema = shift;
    my $inc = @_ ? $validate_arg->(shift) : 1;

    lock($$sema);
    ($$sema += $inc) > 0 and cond_broadcast($$sema);
}


$validate_arg = sub {
    my $arg = shift;

    if (! defined($arg) ||
        ! looks_like_number($arg) ||
        (int($arg) != $arg) ||
        ($arg < 1))
    {
        require Carp;
        my ($method) = (caller(1))[3];
        $method =~ s/Thread::Semaphore:://;
        $arg = 'undef' if (! defined($arg));
        Carp::croak("Argument to semaphore method '$method' is not a positive integer: $arg");
    }

    return $arg;
};

1;

