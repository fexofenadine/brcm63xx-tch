package ExtUtils::MY;

use strict;
require ExtUtils::MM;

our $VERSION = '6.98';
our @ISA = qw(ExtUtils::MM);

{
    package MY;
    our @ISA = qw(ExtUtils::MY);
}

sub DESTROY {}


