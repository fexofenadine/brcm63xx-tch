package Locale::Language;

use strict;
use warnings;
use Exporter;

our $VERSION;
$VERSION='3.30';

our (@ISA,@EXPORT);

my $backend     = 'Locale::Codes::Language';
my $backend_exp = $backend . "::EXPORT";

eval "require $backend; $backend->import(); return 1;";

{
   no strict 'refs';
   @EXPORT = @{ $backend_exp };
}

unshift (@ISA, $backend);

sub rename_language            { Locale::Codes::Language::rename_language(@_) }
sub add_language               { Locale::Codes::Language::add_language(@_) }
sub delete_language            { Locale::Codes::Language::delete_language(@_) }
sub add_language_alias         { Locale::Codes::Language::add_language_alias(@_) }
sub delete_language_alias      { Locale::Codes::Language::delete_language_alias(@_) }
sub rename_language_code       { Locale::Codes::Language::rename_language_code(@_) }
sub add_language_code_alias    { Locale::Codes::Language::add_language_code_alias(@_) }
sub delete_language_code_alias { Locale::Codes::Language::delete_language_code_alias(@_) }

1;
