package Locale::Codes::LangFam;

use strict;
require 5.006;
use warnings;

require Exporter;
use Carp;
use Locale::Codes;
use Locale::Codes::Constants;
use Locale::Codes::LangFam_Codes;
use Locale::Codes::LangFam_Retired;


our($VERSION,@ISA,@EXPORT,@EXPORT_OK);

$VERSION='3.30';
@ISA       = qw(Exporter);
@EXPORT    = qw(code2langfam
                langfam2code
                all_langfam_codes
                all_langfam_names
                langfam_code2code
                LOCALE_LANGFAM_ALPHA
               );

sub code2langfam {
   return Locale::Codes::_code2name('langfam',@_);
}

sub langfam2code {
   return Locale::Codes::_name2code('langfam',@_);
}

sub langfam_code2code {
   return Locale::Codes::_code2code('langfam',@_);
}

sub all_langfam_codes {
   return Locale::Codes::_all_codes('langfam',@_);
}

sub all_langfam_names {
   return Locale::Codes::_all_names('langfam',@_);
}

sub rename_langfam {
   return Locale::Codes::_rename('langfam',@_);
}

sub add_langfam {
   return Locale::Codes::_add_code('langfam',@_);
}

sub delete_langfam {
   return Locale::Codes::_delete_code('langfam',@_);
}

sub add_langfam_alias {
   return Locale::Codes::_add_alias('langfam',@_);
}

sub delete_langfam_alias {
   return Locale::Codes::_delete_alias('langfam',@_);
}

sub rename_langfam_code {
   return Locale::Codes::_rename_code('langfam',@_);
}

sub add_langfam_code_alias {
   return Locale::Codes::_add_code_alias('langfam',@_);
}

sub delete_langfam_code_alias {
   return Locale::Codes::_delete_code_alias('langfam',@_);
}

1;
