package Encode::CN;
BEGIN {
    if ( ord("A") == 193 ) {
        die "Encode::CN not supported on EBCDIC\n";
    }
}
use strict;
use warnings;
use Encode;
our $VERSION = do { my @r = ( q$Revision: 2.3 $ =~ /\d+/g ); sprintf "%d." . "%02d" x $#r, @r };
use XSLoader;
XSLoader::load( __PACKAGE__, $VERSION );


use Encode::CN::HZ;


1;
__END__
