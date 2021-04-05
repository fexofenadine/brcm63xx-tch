package Locale::Codes::Script;

use strict;
require 5.006;
use warnings;

require Exporter;
use Carp;
use Locale::Codes;
use Locale::Codes::Constants;
use Locale::Codes::Script_Codes;
use Locale::Codes::Script_Retired;


our($VERSION,@ISA,@EXPORT,@EXPORT_OK);

$VERSION='3.30';
@ISA       = qw(Exporter);
@EXPORT    = qw(code2script
                script2code
                all_script_codes
                all_script_names
                script_code2code
                LOCALE_SCRIPT_ALPHA
                LOCALE_SCRIPT_NUMERIC
               );

sub code2script {
   return Locale::Codes::_code2name('script',@_);
}

sub script2code {
   return Locale::Codes::_name2code('script',@_);
}

sub script_code2code {
   return Locale::Codes::_code2code('script',@_);
}

sub all_script_codes {
   return Locale::Codes::_all_codes('script',@_);
}

sub all_script_names {
   return Locale::Codes::_all_names('script',@_);
}

sub rename_script {
   return Locale::Codes::_rename('script',@_);
}

sub add_script {
   return Locale::Codes::_add_code('script',@_);
}

sub delete_script {
   return Locale::Codes::_delete_code('script',@_);
}

sub add_script_alias {
   return Locale::Codes::_add_alias('script',@_);
}

sub delete_script_alias {
   return Locale::Codes::_delete_alias('script',@_);
}

sub rename_script_code {
   return Locale::Codes::_rename_code('script',@_);
}

sub add_script_code_alias {
   return Locale::Codes::_add_code_alias('script',@_);
}

sub delete_script_code_alias {
   return Locale::Codes::_delete_code_alias('script',@_);
}

1;
