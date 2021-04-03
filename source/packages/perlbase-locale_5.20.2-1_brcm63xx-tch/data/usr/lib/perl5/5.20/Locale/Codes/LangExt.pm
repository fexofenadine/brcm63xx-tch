package Locale::Codes::LangExt;

use strict;
require 5.006;
use warnings;

require Exporter;
use Carp;
use Locale::Codes;
use Locale::Codes::Constants;
use Locale::Codes::LangExt_Codes;
use Locale::Codes::LangExt_Retired;


our($VERSION,@ISA,@EXPORT,@EXPORT_OK);

$VERSION='3.30';
@ISA       = qw(Exporter);
@EXPORT    = qw(code2langext
                langext2code
                all_langext_codes
                all_langext_names
                langext_code2code
                LOCALE_LANGEXT_ALPHA
               );

sub code2langext {
   return Locale::Codes::_code2name('langext',@_);
}

sub langext2code {
   return Locale::Codes::_name2code('langext',@_);
}

sub langext_code2code {
   return Locale::Codes::_code2code('langext',@_);
}

sub all_langext_codes {
   return Locale::Codes::_all_codes('langext',@_);
}

sub all_langext_names {
   return Locale::Codes::_all_names('langext',@_);
}

sub rename_langext {
   return Locale::Codes::_rename('langext',@_);
}

sub add_langext {
   return Locale::Codes::_add_code('langext',@_);
}

sub delete_langext {
   return Locale::Codes::_delete_code('langext',@_);
}

sub add_langext_alias {
   return Locale::Codes::_add_alias('langext',@_);
}

sub delete_langext_alias {
   return Locale::Codes::_delete_alias('langext',@_);
}

sub rename_langext_code {
   return Locale::Codes::_rename_code('langext',@_);
}

sub add_langext_code_alias {
   return Locale::Codes::_add_code_alias('langext',@_);
}

sub delete_langext_code_alias {
   return Locale::Codes::_delete_code_alias('langext',@_);
}

1;
