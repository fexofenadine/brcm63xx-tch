package Pod::Perldoc::ToANSI;
use strict;
use warnings;
use parent qw(Pod::Perldoc::BaseTo);

use vars qw($VERSION);
$VERSION = '3.23';

sub is_pageable        { 1 }
sub write_with_binmode { 0 }
sub output_extension   { 'txt' }

use Pod::Text::Color ();

sub alt       { shift->_perldoc_elem('alt'     , @_) }
sub indent    { shift->_perldoc_elem('indent'  , @_) }
sub loose     { shift->_perldoc_elem('loose'   , @_) }
sub quotes    { shift->_perldoc_elem('quotes'  , @_) }
sub sentence  { shift->_perldoc_elem('sentence', @_) }
sub width     { shift->_perldoc_elem('width'   , @_) }

sub new { return bless {}, ref($_[0]) || $_[0] }

sub parse_from_file {
  my $self = shift;

  my @options =
    map {; $_, $self->{$_} }
      grep !m/^_/s,
        keys %$self
  ;

  defined(&Pod::Perldoc::DEBUG)
   and Pod::Perldoc::DEBUG()
   and print "About to call new Pod::Text::Color ",
    $Pod::Text::VERSION ? "(v$Pod::Text::VERSION) " : '',
    "with options: ",
    @options ? "[@options]" : "(nil)", "\n";
  ;

  Pod::Text::Color->new(@options)->parse_from_file(@_);
}

1;

