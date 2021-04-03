package ExtUtils::ParseXS::Eval;
use strict;
use warnings;

our $VERSION = '3.24';


sub eval_output_typemap_code {
  my ($_pxs, $_code, $_other) = @_;

  my ($Package, $ALIAS, $func_name, $Full_func_name, $pname)
    = @{$_pxs}{qw(Package ALIAS func_name Full_func_name pname)};

  my ($var, $type, $ntype, $subtype, $arg)
    = @{$_other}{qw(var type ntype subtype arg)};

  my $rv = eval $_code;
  warn $@ if $@;
  return $rv;
}


sub eval_input_typemap_code {
  my ($_pxs, $_code, $_other) = @_;

  my ($Package, $ALIAS, $func_name, $Full_func_name, $pname)
    = @{$_pxs}{qw(Package ALIAS func_name Full_func_name pname)};

  my ($var, $type, $num, $init, $printed_name, $arg, $ntype, $argoff, $subtype)
    = @{$_other}{qw(var type num init printed_name arg ntype argoff subtype)};

  my $rv = eval $_code;
  warn $@ if $@;
  return $rv;
}


1;

