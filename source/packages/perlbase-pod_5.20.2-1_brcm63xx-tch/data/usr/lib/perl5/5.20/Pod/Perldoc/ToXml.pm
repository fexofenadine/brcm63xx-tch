package Pod::Perldoc::ToXml;
use strict;
use warnings;
use vars qw($VERSION);

use parent qw( Pod::Simple::XMLOutStream );

use vars qw($VERSION);
$VERSION = '3.23';

sub is_pageable        { 0 }
sub write_with_binmode { 0 }
sub output_extension   { 'xml' }

1;
__END__


