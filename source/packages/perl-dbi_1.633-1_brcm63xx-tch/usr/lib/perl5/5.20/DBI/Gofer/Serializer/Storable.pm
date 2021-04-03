package DBI::Gofer::Serializer::Storable;

use strict;
use warnings;

use base qw(DBI::Gofer::Serializer::Base);



use Storable qw(nfreeze thaw);

our $VERSION = "0.015586";

use base qw(DBI::Gofer::Serializer::Base);


sub serialize {
    my $self = shift;
    local $Storable::forgive_me = 1; # for CODE refs etc
    local $Storable::canonical = 1; # for go_cache
    my $frozen = nfreeze(shift);
    return $frozen unless wantarray;
    return ($frozen, $self->{deserializer_class});
}

sub deserialize {
    my $self = shift;
    return thaw(shift);
}

1;
