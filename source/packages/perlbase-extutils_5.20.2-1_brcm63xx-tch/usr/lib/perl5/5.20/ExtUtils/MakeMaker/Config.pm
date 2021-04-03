package ExtUtils::MakeMaker::Config;

use strict;

our $VERSION = '6.98';

use Config ();

our %Config = %Config::Config;

sub import {
    my $caller = caller;

    no strict 'refs';   ## no critic
    *{$caller.'::Config'} = \%Config;
}

1;


