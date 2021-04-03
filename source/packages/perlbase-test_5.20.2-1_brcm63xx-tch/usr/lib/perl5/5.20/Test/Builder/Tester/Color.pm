package Test::Builder::Tester::Color;

use strict;
our $VERSION = "1.23_002";

require Test::Builder::Tester;



sub import {
    Test::Builder::Tester::color(1);
}


1;
