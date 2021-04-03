package autodie::skip;
use strict;
use warnings;

our $VERSION = '2.23'; # VERSION


if ($] < 5.010) {
    # Older Perls don't have a native ->DOES.  Let's provide a cheap
    # imitation here.

    *DOES = sub { return shift->isa(@_); };
}

1;

__END__

