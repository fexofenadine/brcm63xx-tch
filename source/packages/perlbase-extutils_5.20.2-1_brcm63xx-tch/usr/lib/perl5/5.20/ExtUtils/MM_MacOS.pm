package ExtUtils::MM_MacOS;

use strict;

our $VERSION = '6.98';

sub new {
    die <<'UNSUPPORTED';
MacOS Classic (MacPerl) is no longer supported by MakeMaker.
Please use Module::Build instead.
UNSUPPORTED
}


1;
