package Hash::Util::FieldHash;

use 5.009004;
use strict;
use warnings;
use Scalar::Util qw( reftype);

our $VERSION = '1.15';

require Exporter;
our @ISA = qw(Exporter);
our %EXPORT_TAGS = (
    'all' => [ qw(
        fieldhash
        fieldhashes
        idhash
        idhashes
        id
        id_2obj
        register
    )],
);
our @EXPORT_OK = ( @{ $EXPORT_TAGS{'all'} } );

{
    require XSLoader;
    my %ob_reg; # private object registry
    sub _ob_reg { \ %ob_reg }
    XSLoader::load();
}

sub fieldhash (\%) {
    for ( shift ) {
        return unless ref() && reftype( $_) eq 'HASH';
        return $_ if Hash::Util::FieldHash::_fieldhash( $_, 0);
        return $_ if Hash::Util::FieldHash::_fieldhash( $_, 2) == 2;
        return;
    }
}

sub idhash (\%) {
    for ( shift ) {
        return unless ref() && reftype( $_) eq 'HASH';
        return $_ if Hash::Util::FieldHash::_fieldhash( $_, 0);
        return $_ if Hash::Util::FieldHash::_fieldhash( $_, 1) == 1;
        return;
    }
}

sub fieldhashes { map &fieldhash( $_), @_ }
sub idhashes { map &idhash( $_), @_ }

1;
__END__

