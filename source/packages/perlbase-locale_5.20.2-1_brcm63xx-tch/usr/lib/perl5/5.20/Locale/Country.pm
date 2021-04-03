package Locale::Country;

use strict;
use warnings;
use Exporter;

our $VERSION;
$VERSION='3.30';

our (@ISA,@EXPORT);

my $backend     = 'Locale::Codes::Country';
my $backend_exp = $backend . "::EXPORT";

eval "require $backend; $backend->import(); return 1;";

{
   no strict 'refs';
   @EXPORT = @{ $backend_exp };
}

unshift (@ISA, $backend);

sub alias_code                { Locale::Codes::Country::alias_code(@_) }

sub rename_country            { Locale::Codes::Country::rename_country(@_) }
sub add_country               { Locale::Codes::Country::add_country(@_) }
sub delete_country            { Locale::Codes::Country::delete_country(@_) }
sub add_country_alias         { Locale::Codes::Country::add_country_alias(@_) }
sub delete_country_alias      { Locale::Codes::Country::delete_country_alias(@_) }
sub rename_country_code       { Locale::Codes::Country::rename_country_code(@_) }
sub add_country_code_alias    { Locale::Codes::Country::add_country_code_alias(@_) }
sub delete_country_code_alias { Locale::Codes::Country::delete_country_code_alias(@_) }

1;
