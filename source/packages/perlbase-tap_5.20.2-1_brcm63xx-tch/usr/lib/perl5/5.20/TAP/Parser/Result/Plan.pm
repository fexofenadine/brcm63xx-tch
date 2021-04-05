package TAP::Parser::Result::Plan;

use strict;
use warnings;

use base 'TAP::Parser::Result';


our $VERSION = '3.30';




sub plan { '1..' . shift->{tests_planned} }



sub tests_planned { shift->{tests_planned} }



sub directive { shift->{directive} }



sub explanation { shift->{explanation} }


sub todo_list { shift->{todo_list} }

1;
