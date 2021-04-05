package Config::Extensions;
use strict;
use vars qw(%Extensions $VERSION @ISA @EXPORT_OK);
use Config;
require Exporter;

$VERSION = '0.01';
@ISA = 'Exporter';
@EXPORT_OK = '%Extensions';

foreach my $type (qw(static dynamic nonxs)) {
    foreach (split /\s+/, $Config{$type . '_ext'}) {
	s!/!::!g;
	$Extensions{$_} = $type;
    }
}

1;
__END__
