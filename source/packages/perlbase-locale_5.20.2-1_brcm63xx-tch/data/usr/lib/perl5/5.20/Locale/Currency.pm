package Locale::Currency;

use strict;
use warnings;
use Exporter;

our $VERSION;
$VERSION='3.30';

our (@ISA,@EXPORT);

my $backend     = 'Locale::Codes::Currency';
my $backend_exp = $backend . "::EXPORT";

eval "require $backend; $backend->import(); return 1;";

{
   no strict 'refs';
   @EXPORT = @{ $backend_exp };
}

unshift (@ISA, $backend);

sub rename_currency            { Locale::Codes::Currency::rename_currency(@_) }
sub add_currency               { Locale::Codes::Currency::add_currency(@_) }
sub delete_currency            { Locale::Codes::Currency::delete_currency(@_) }
sub add_currency_alias         { Locale::Codes::Currency::add_currency_alias(@_) }
sub delete_currency_alias      { Locale::Codes::Currency::delete_currency_alias(@_) }
sub rename_currency_code       { Locale::Codes::Currency::rename_currency_code(@_) }
sub add_currency_code_alias    { Locale::Codes::Currency::add_currency_code_alias(@_) }
sub delete_currency_code_alias { Locale::Codes::Currency::delete_currency_code_alias(@_) }

1;
