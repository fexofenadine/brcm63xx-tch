package ExtUtils::MM_VOS;

use strict;
our $VERSION = '6.98';

require ExtUtils::MM_Unix;
our @ISA = qw(ExtUtils::MM_Unix);



sub extra_clean_files {
    return qw(*.kp);
}




1;
