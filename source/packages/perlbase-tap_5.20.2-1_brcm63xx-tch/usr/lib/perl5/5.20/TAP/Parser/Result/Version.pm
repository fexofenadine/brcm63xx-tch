package TAP::Parser::Result::Version;

use strict;
use warnings;

use base 'TAP::Parser::Result';


our $VERSION = '3.30';




sub version { shift->{version} }

1;
