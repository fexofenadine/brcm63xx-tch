
package URI::ldap;

use strict;
use warnings;

our $VERSION = "1.67";

use parent qw(URI::_ldap URI::_server);

sub default_port { 389 }

sub _nonldap_canonical {
    my $self = shift;
    $self->URI::_server::canonical(@_);
}

1;

__END__

