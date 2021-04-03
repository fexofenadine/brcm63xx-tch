package TAP::Parser::Result::Bailout;

use strict;
use warnings;

use base 'TAP::Parser::Result';


our $VERSION = '3.35';




sub explanation { shift->{bailout} }
sub as_string   { shift->{bailout} }

1;
