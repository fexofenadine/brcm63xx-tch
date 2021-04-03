package WWW::Curl;

use strict;
use warnings;
use XSLoader;

our $VERSION = '4.17';
XSLoader::load(__PACKAGE__, $VERSION);

END {
    _global_cleanup();
}

1;

__END__

