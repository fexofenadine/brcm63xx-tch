package ExtUtils::MM_Darwin;

use strict;

BEGIN {
    require ExtUtils::MM_Unix;
    our @ISA = qw( ExtUtils::MM_Unix );
}

our $VERSION = '6.98';



sub init_dist {
    my $self = shift;

    # Thank you, Apple, for breaking tar and then breaking the work around.
    # 10.4 wants COPY_EXTENDED_ATTRIBUTES_DISABLE while 10.5 wants
    # COPYFILE_DISABLE.  I'm not going to push my luck and instead just
    # set both.
    $self->{TAR} ||=
        'COPY_EXTENDED_ATTRIBUTES_DISABLE=1 COPYFILE_DISABLE=1 tar';

    $self->SUPER::init_dist(@_);
}

1;
