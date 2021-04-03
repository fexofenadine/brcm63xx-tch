package DBI::Gofer::Serializer::DataDumper;

use strict;
use warnings;

our $VERSION = "0.009950";



use Data::Dumper;

use base qw(DBI::Gofer::Serializer::Base);


sub serialize {
    my $self = shift;
    local $Data::Dumper::Indent    = 1;
    local $Data::Dumper::Terse     = 1;
    local $Data::Dumper::Useqq     = 0; # enabling this disables xs
    local $Data::Dumper::Sortkeys  = 1;
    local $Data::Dumper::Quotekeys = 0;
    local $Data::Dumper::Deparse   = 0;
    local $Data::Dumper::Purity    = 0;
    my $frozen = Data::Dumper::Dumper(shift);
    return $frozen unless wantarray;
    return ($frozen, $self->{deserializer_class});
}

1;
