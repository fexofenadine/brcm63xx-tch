package TAP::Parser::Result::Pragma;

use strict;
use warnings;

use base 'TAP::Parser::Result';


our $VERSION = '3.30';




sub pragmas {
    my @pragmas = @{ shift->{pragmas} };
    return wantarray ? @pragmas : \@pragmas;
}

1;
