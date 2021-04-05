package ExtUtils::ParseXS::Constants;
use strict;
use warnings;
use Symbol;

our $VERSION = '3.24';


our @InitFileCode;

our $PrototypeRegexp = "[" . quotemeta('\$%&*@;[]_') . "]";
our @XSKeywords      = qw( 
  REQUIRE BOOT CASE PREINIT INPUT INIT CODE PPCODE
  OUTPUT CLEANUP ALIAS ATTRS PROTOTYPES PROTOTYPE
  VERSIONCHECK INCLUDE INCLUDE_COMMAND SCOPE INTERFACE
  INTERFACE_MACRO C_ARGS POSTCALL OVERLOAD FALLBACK
  EXPORT_XSUB_SYMBOLS
);

our $XSKeywordsAlternation = join('|', @XSKeywords);

1;
