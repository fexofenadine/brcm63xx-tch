package Test::Simple;

use 5.006;

use strict;

our $VERSION = '1.001002';
$VERSION = eval $VERSION;    ## no critic (BuiltinFunctions::ProhibitStringyEval)

use Test::Builder::Module 0.99;
our @ISA    = qw(Test::Builder::Module);
our @EXPORT = qw(ok);

my $CLASS = __PACKAGE__;


sub ok ($;$) {    ## no critic (Subroutines::ProhibitSubroutinePrototypes)
    return $CLASS->builder->ok(@_);
}


1;
