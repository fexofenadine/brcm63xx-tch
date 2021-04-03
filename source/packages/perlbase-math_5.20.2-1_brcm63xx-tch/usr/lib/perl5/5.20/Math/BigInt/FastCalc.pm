package Math::BigInt::FastCalc;

use 5.006;
use strict;
use warnings;

use Math::BigInt::Calc 1.997;

use vars '$VERSION';

$VERSION = '0.31';


sub api_version () { 2; }


for my $method (qw/
    str num
    add sub mul div
    rsft lsft
    mod modpow modinv
    gcd
    pow root sqrt log_int fac nok
    digit check
    from_hex from_bin from_oct as_hex as_bin as_oct
    zeros base_len
    xor or and
    alen 1ex
    /)
    {
    no strict 'refs';
    *{'Math::BigInt::FastCalc::_' . $method} = \&{'Math::BigInt::Calc::_' . $method};
    }

require XSLoader;
XSLoader::load(__PACKAGE__, $VERSION, Math::BigInt::Calc::_base_len());


1;
__END__
