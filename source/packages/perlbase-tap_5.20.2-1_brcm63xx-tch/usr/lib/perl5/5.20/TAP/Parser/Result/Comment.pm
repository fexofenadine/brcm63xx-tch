package TAP::Parser::Result::Comment;

use strict;
use warnings;

use base 'TAP::Parser::Result';


our $VERSION = '3.30';




sub comment   { shift->{comment} }
sub as_string { shift->{raw} }

1;
