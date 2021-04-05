package bigint;
use 5.006;

$VERSION = '0.36';
use Exporter;
@ISA		= qw( Exporter );
@EXPORT_OK	= qw( PI e bpi bexp hex oct );
@EXPORT		= qw( inf NaN );

use strict;
use overload;



my @faked = qw/round_mode accuracy precision div_scale/;
use vars qw/$VERSION $AUTOLOAD $_lite/;		# _lite for testsuite

sub AUTOLOAD
  {
  my $name = $AUTOLOAD;

  $name =~ s/.*:://;    # split package
  no strict 'refs';
  foreach my $n (@faked)
    {
    if ($n eq $name)
      {
      *{"bigint::$name"} = sub 
        {
        my $self = shift;
        no strict 'refs';
        if (defined $_[0])
          {
          return Math::BigInt->$name($_[0]);
          }
        return Math::BigInt->$name();
        };
      return &$name;
      }
    }
 
  # delayed load of Carp and avoid recursion
  require Carp;
  Carp::croak ("Can't call bigint\-\>$name, not a valid method");
  }

sub upgrade
  {
  $Math::BigInt::upgrade;
  }

sub _binary_constant
  {
  # this takes a binary/hexadecimal/octal constant string and returns it
  # as string suitable for new. Basically it converts octal to decimal, and
  # passes every thing else unmodified back.
  my $string = shift;

  return Math::BigInt->new($string) if $string =~ /^0[bx]/;

  # so it must be an octal constant
  Math::BigInt->from_oct($string);
  }

sub _float_constant
  {
  # this takes a floating point constant string and returns it truncated to
  # integer. For instance, '4.5' => '4', '1.234e2' => '123' etc
  my $float = shift;

  # some simple cases first
  return $float if ($float =~ /^[+-]?[0-9]+$/);		# '+123','-1','0' etc
  return $float 
    if ($float =~ /^[+-]?[0-9]+\.?[eE]\+?[0-9]+$/);	# 123e2, 123.e+2
  return '0' if ($float =~ /^[+-]?[0]*\.[0-9]+$/);	# .2, 0.2, -.1
  if ($float =~ /^[+-]?[0-9]+\.[0-9]*$/)		# 1., 1.23, -1.2 etc
    {
    $float =~ s/\..*//;
    return $float;
    }
  my ($mis,$miv,$mfv,$es,$ev) = Math::BigInt::_split($float);
  return $float if !defined $mis; 	# doesn't look like a number to me
  my $ec = int($$ev);
  my $sign = $$mis; $sign = '' if $sign eq '+';
  if ($$es eq '-')
    {
    # ignore fraction part entirely
    if ($ec >= length($$miv))			# 123.23E-4
      {
      return '0';
      }
    return $sign . substr ($$miv,0,length($$miv)-$ec);	# 1234.45E-2 = 12
    }
  # xE+y
  if ($ec >= length($$mfv))
    {
    $ec -= length($$mfv);			
    return $sign.$$miv.$$mfv if $ec == 0;	# 123.45E+2 => 12345
    return $sign.$$miv.$$mfv.'E'.$ec; 		# 123.45e+3 => 12345e1
    }
  $mfv = substr($$mfv,0,$ec);
  $sign.$$miv.$mfv; 				# 123.45e+1 => 1234
  }

sub unimport
  {
  $^H{bigint} = undef;					# no longer in effect
  overload::remove_constant('binary','','float','','integer');
  }

sub in_effect
  {
  my $level = shift || 0;
  my $hinthash = (caller($level))[10];
  $hinthash->{bigint};
  }


use constant LEXICAL => $] > 5.009004;

{
    my $proto = LEXICAL ? '_' : ';$';
    eval '
sub hex(' . $proto . ')' . <<'.';
  {
  my $i = @_ ? $_[0] : $_;
  $i = '0x'.$i unless $i =~ /^0x/;
  Math::BigInt->new($i);
  }
.
    eval '
sub oct(' . $proto . ')' . <<'.';
  {
  my $i = @_ ? $_[0] : $_;
  # oct() should never fall back to decimal
  return Math::BigInt->from_oct($i) if $i =~ s/^(?=0[0-9]|[1-9])/0/;
  Math::BigInt->new($i);
  }
.
}


my ($prev_oct, $prev_hex, $overridden);

if (LEXICAL) { eval <<'.' }
sub _hex(_)
  {
  my $hh = (caller 0)[10];
  return $prev_hex ? &$prev_hex($_[0]) : CORE::hex($_[0])
    unless $$hh{bigint}||$$hh{bignum}||$$hh{bigrat};
  my $i = $_[0];
  $i = '0x'.$i unless $i =~ /^0x/;
  Math::BigInt->new($i);
  }

sub _oct(_)
  {
  my $hh = (caller 0)[10];
  return $prev_oct ? &$prev_oct($_[0]) : CORE::oct($_[0])
    unless $$hh{bigint}||$$hh{bignum}||$$hh{bigrat};
  my $i = $_[0];
  # oct() should never fall back to decimal
  return Math::BigInt->from_oct($i) if $i =~ s/^(?=0[0-9]|[1-9])/0/;
  Math::BigInt->new($i);
  }
.

sub _override
  {
  return if $overridden;
  $prev_oct = *CORE::GLOBAL::oct{CODE};
  $prev_hex = *CORE::GLOBAL::hex{CODE};
  no warnings 'redefine';
  *CORE::GLOBAL::oct = \&_oct;
  *CORE::GLOBAL::hex = \&_hex;
  $overridden++;
  }

sub import 
  {
  my $self = shift;

  $^H{bigint} = 1;					# we are in effect

  # for newer Perls always override hex() and oct() with a lexical version:
  if (LEXICAL)
    {
    _override();
    }
  # some defaults
  my $lib = ''; my $lib_kind = 'try';

  my @import = ( ':constant' );				# drive it w/ constant
  my @a = @_; my $l = scalar @_; my $j = 0;
  my ($ver,$trace);					# version? trace?
  my ($a,$p);						# accuracy, precision
  for ( my $i = 0; $i < $l ; $i++,$j++ )
    {
    if ($_[$i] =~ /^(l|lib|try|only)$/)
      {
      # this causes a different low lib to take care...
      $lib_kind = $1; $lib_kind = 'lib' if $lib_kind eq 'l';
      $lib = $_[$i+1] || '';
      my $s = 2; $s = 1 if @a-$j < 2;	# avoid "can not modify non-existent..."
      splice @a, $j, $s; $j -= $s; $i++;
      }
    elsif ($_[$i] =~ /^(a|accuracy)$/)
      {
      $a = $_[$i+1];
      my $s = 2; $s = 1 if @a-$j < 2;	# avoid "can not modify non-existent..."
      splice @a, $j, $s; $j -= $s; $i++;
      }
    elsif ($_[$i] =~ /^(p|precision)$/)
      {
      $p = $_[$i+1];
      my $s = 2; $s = 1 if @a-$j < 2;	# avoid "can not modify non-existent..."
      splice @a, $j, $s; $j -= $s; $i++;
      }
    elsif ($_[$i] =~ /^(v|version)$/)
      {
      $ver = 1;
      splice @a, $j, 1; $j --;
      }
    elsif ($_[$i] =~ /^(t|trace)$/)
      {
      $trace = 1;
      splice @a, $j, 1; $j --;
      }
    elsif ($_[$i] !~ /^(PI|e|bpi|bexp|hex|oct)\z/)
      {
      die ("unknown option $_[$i]");
      }
    }
  my $class;
  $_lite = 0;					# using M::BI::L ?
  if ($trace)
    {
    require Math::BigInt::Trace; $class = 'Math::BigInt::Trace';
    }
  else
    {
    # see if we can find Math::BigInt::Lite
    if (!defined $a && !defined $p)		# rounding won't work to well
      {
      eval 'require Math::BigInt::Lite;';
      if ($@ eq '')
        {
        @import = ( );				# :constant in Lite, not MBI
        Math::BigInt::Lite->import( ':constant' );
        $_lite= 1;				# signal okay
        }
      }
    require Math::BigInt if $_lite == 0;	# not already loaded?
    $class = 'Math::BigInt';			# regardless of MBIL or not
    }
  push @import, $lib_kind => $lib if $lib ne '';
  # Math::BigInt::Trace or plain Math::BigInt
  $class->import(@import);

  bigint->accuracy($a) if defined $a;
  bigint->precision($p) if defined $p;
  if ($ver)
    {
    print "bigint\t\t\t v$VERSION\n";
    print "Math::BigInt::Lite\t v$Math::BigInt::Lite::VERSION\n" if $_lite;
    print "Math::BigInt\t\t v$Math::BigInt::VERSION";
    my $config = Math::BigInt->config();
    print " lib => $config->{lib} v$config->{lib_version}\n";
    exit;
    }
  # we take care of floating point constants, since BigFloat isn't available
  # and BigInt doesn't like them:
  overload::constant float => sub { Math::BigInt->new( _float_constant(shift) ); };
  # Take care of octal/hexadecimal constants
  overload::constant binary => sub { _binary_constant(shift) };

  # if another big* was already loaded:
  my ($package) = caller();

  no strict 'refs';
  if (!defined *{"${package}::inf"})
    {
    $self->export_to_level(1,$self,@a);           # export inf and NaN, e and PI
    }
  }

sub inf () { Math::BigInt::binf(); }
sub NaN () { Math::BigInt::bnan(); }

sub PI () { Math::BigInt->new(3); }
sub e () { Math::BigInt->new(2); }
sub bpi ($) { Math::BigInt->new(3); }
sub bexp ($$) { my $x = Math::BigInt->new($_[0]); $x->bexp($_[1]); }

1;

__END__

