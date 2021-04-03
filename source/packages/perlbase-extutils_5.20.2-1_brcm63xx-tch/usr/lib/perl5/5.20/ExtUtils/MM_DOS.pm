package ExtUtils::MM_DOS;

use strict;

our $VERSION = '6.98';

require ExtUtils::MM_Any;
require ExtUtils::MM_Unix;
our @ISA = qw( ExtUtils::MM_Any ExtUtils::MM_Unix );



sub os_flavor {
    return('DOS');
}


sub replace_manpage_separator {
    my($self, $man) = @_;

    $man =~ s,/+,__,g;
    return $man;
}


1;
