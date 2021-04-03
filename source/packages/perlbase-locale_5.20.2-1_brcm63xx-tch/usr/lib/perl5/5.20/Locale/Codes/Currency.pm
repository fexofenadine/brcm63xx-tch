package Locale::Codes::Currency;

use strict;
require 5.006;
use warnings;

require Exporter;
use Carp;
use Locale::Codes;
use Locale::Codes::Constants;
use Locale::Codes::Currency_Codes;
use Locale::Codes::Currency_Retired;


our($VERSION,@ISA,@EXPORT,@EXPORT_OK);

$VERSION='3.30';
@ISA       = qw(Exporter);
@EXPORT    = qw(code2currency
                currency2code
                all_currency_codes
                all_currency_names
                currency_code2code
                LOCALE_CURR_ALPHA
                LOCALE_CURR_NUMERIC
               );

sub code2currency {
   return Locale::Codes::_code2name('currency',@_);
}

sub currency2code {
   return Locale::Codes::_name2code('currency',@_);
}

sub currency_code2code {
   return Locale::Codes::_code2code('currency',@_);
}

sub all_currency_codes {
   return Locale::Codes::_all_codes('currency',@_);
}

sub all_currency_names {
   return Locale::Codes::_all_names('currency',@_);
}

sub rename_currency {
   return Locale::Codes::_rename('currency',@_);
}

sub add_currency {
   return Locale::Codes::_add_code('currency',@_);
}

sub delete_currency {
   return Locale::Codes::_delete_code('currency',@_);
}

sub add_currency_alias {
   return Locale::Codes::_add_alias('currency',@_);
}

sub delete_currency_alias {
   return Locale::Codes::_delete_alias('currency',@_);
}

sub rename_currency_code {
   return Locale::Codes::_rename_code('currency',@_);
}

sub add_currency_code_alias {
   return Locale::Codes::_add_code_alias('currency',@_);
}

sub delete_currency_code_alias {
   return Locale::Codes::_delete_code_alias('currency',@_);
}

1;
