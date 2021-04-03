package ExtUtils::MM_UWIN;

use strict;
our $VERSION = '6.98';

require ExtUtils::MM_Unix;
our @ISA = qw(ExtUtils::MM_Unix);



sub os_flavor {
    return('Unix', 'U/WIN');
}



sub replace_manpage_separator {
    my($self, $man) = @_;

    $man =~ s,/+,.,g;
    return $man;
}


1;
