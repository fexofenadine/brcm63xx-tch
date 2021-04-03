package Locale::Script;

use strict;
use warnings;
use Exporter;

our $VERSION;
$VERSION='3.30';

our (@ISA,@EXPORT);

my $backend     = 'Locale::Codes::Script';
my $backend_exp = $backend . "::EXPORT";

eval "require $backend; $backend->import(); return 1;";

{
   no strict 'refs';
   @EXPORT = @{ $backend_exp };
}

unshift (@ISA, $backend);

sub rename_script            { Locale::Codes::Script::rename_script(@_) }
sub add_script               { Locale::Codes::Script::add_script(@_) }
sub delete_script            { Locale::Codes::Script::delete_script(@_) }
sub add_script_alias         { Locale::Codes::Script::add_script_alias(@_) }
sub delete_script_alias      { Locale::Codes::Script::delete_script_alias(@_) }
sub rename_script_code       { Locale::Codes::Script::rename_script_code(@_) }
sub add_script_code_alias    { Locale::Codes::Script::add_script_code_alias(@_) }
sub delete_script_code_alias { Locale::Codes::Script::delete_script_code_alias(@_) }

1;
