package PerlIO::encoding;

use strict;
our $VERSION = '0.18';
our $DEBUG = 0;
$DEBUG and warn __PACKAGE__, " called by ", join(", ", caller), "\n";


require XSLoader;
XSLoader::load();

our $fallback =
    Encode::PERLQQ()|Encode::WARN_ON_ERR()|Encode::STOP_AT_PARTIAL();

1;
__END__

