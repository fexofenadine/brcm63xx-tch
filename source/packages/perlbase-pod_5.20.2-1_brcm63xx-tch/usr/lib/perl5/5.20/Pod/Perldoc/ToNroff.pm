package Pod::Perldoc::ToNroff;
use strict;
use warnings;
use parent qw(Pod::Perldoc::BaseTo);

use vars qw($VERSION);
$VERSION = '3.23';


sub is_pageable        { 1 }  # well, if you ask for it...
sub write_with_binmode { 0 }
sub output_extension   { 'man' }

use Pod::Man ();

sub center          { shift->_perldoc_elem('center'         , @_) }
sub date            { shift->_perldoc_elem('date'           , @_) }
sub fixed           { shift->_perldoc_elem('fixed'          , @_) }
sub fixedbold       { shift->_perldoc_elem('fixedbold'      , @_) }
sub fixeditalic     { shift->_perldoc_elem('fixeditalic'    , @_) }
sub fixedbolditalic { shift->_perldoc_elem('fixedbolditalic', @_) }
sub quotes          { shift->_perldoc_elem('quotes'         , @_) }
sub release         { shift->_perldoc_elem('release'        , @_) }
sub section         { shift->_perldoc_elem('section'        , @_) }

sub new { return bless {}, ref($_[0]) || $_[0] }

sub parse_from_file {
  my $self = shift;
  my $file = $_[0];

  my @options =
    map {; $_, $self->{$_} }
      grep !m/^_/s,
        keys %$self
  ;

  defined(&Pod::Perldoc::DEBUG)
   and Pod::Perldoc::DEBUG()
   and print "About to call new Pod::Man ",
    $Pod::Man::VERSION ? "(v$Pod::Man::VERSION) " : '',
    "with options: ",
    @options ? "[@options]" : "(nil)", "\n";
  ;

  Pod::Man->new(@options)->parse_from_file(@_);
}

1;
__END__


