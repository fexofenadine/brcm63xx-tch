package bignum;
use 5.006;

$VERSION = '0.37';
use Exporter;
@ISA 		= qw( bigint );
@EXPORT_OK	= qw( PI e bexp bpi hex oct ); 
@EXPORT 	= qw( inf NaN ); 

use strict;
use overload;
use bigint ();


BEGIN 
  {
  *inf = \&bigint::inf;
  *NaN = \&bigint::NaN;
  *hex = \&bigint::hex;
  *oct = \&bigint::oct;
  }


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
      *{"bignum::$name"} = sub 
        {
        my $self = shift;
        no strict 'refs';
        if (defined $_[0])
          {
          Math::BigInt->$name($_[0]);
          return Math::BigFloat->$name($_[0]);
          }
        return Math::BigInt->$name();
        };
      return &$name;
      }
    }
 
  # delayed load of Carp and avoid recursion
  require Carp;
  Carp::croak ("Can't call bignum\-\>$name, not a valid method");
  }

sub unimport
  {
  $^H{bignum} = undef;					# no longer in effect
  overload::remove_constant('binary','','float','','integer');
  }

sub in_effect
  {
  my $level = shift || 0;
  my $hinthash = (caller($level))[10];
  $hinthash->{bignum};
  }


sub import 
  {
  my $self = shift;

  $^H{bignum} = 1;					# we are in effect

  # for newer Perls override hex() and oct() with a lexical version:
  if ($] > 5.009004)
    {
    bigint::_override();
    }

  # some defaults
  my $lib = ''; my $lib_kind = 'try';
  my $upgrade = 'Math::BigFloat';
  my $downgrade = 'Math::BigInt';

  my @import = ( ':constant' );				# drive it w/ constant
  my @a = @_; my $l = scalar @_; my $j = 0;
  my ($ver,$trace);					# version? trace?
  my ($a,$p);						# accuracy, precision
  for ( my $i = 0; $i < $l ; $i++,$j++ )
    {
    if ($_[$i] eq 'upgrade')
      {
      # this causes upgrading
      $upgrade = $_[$i+1];		# or undef to disable
      my $s = 2; $s = 1 if @a-$j < 2;	# avoid "can not modify non-existent..."
      splice @a, $j, $s; $j -= $s; $i++;
      }
    elsif ($_[$i] eq 'downgrade')
      {
      # this causes downgrading
      $downgrade = $_[$i+1];		# or undef to disable
      my $s = 2; $s = 1 if @a-$j < 2;	# avoid "can not modify non-existent..."
      splice @a, $j, $s; $j -= $s; $i++;
      }
    elsif ($_[$i] =~ /^(l|lib|try|only)$/)
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
    elsif ($_[$i] !~ /^(PI|e|bexp|bpi|hex|oct)\z/)
      {
      die ("unknown option $_[$i]");
      }
    }
  my $class;
  $_lite = 0;					# using M::BI::L ?
  if ($trace)
    {
    require Math::BigInt::Trace; $class = 'Math::BigInt::Trace';
    $upgrade = 'Math::BigFloat::Trace';	
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
  $class->import(@import, upgrade => $upgrade);

  if ($trace)
    {
    require Math::BigFloat::Trace; $class = 'Math::BigFloat::Trace';
    $downgrade = 'Math::BigInt::Trace';	
    }
  else
    {
    require Math::BigFloat; $class = 'Math::BigFloat';
    }
  $class->import(':constant','downgrade',$downgrade);

  bignum->accuracy($a) if defined $a;
  bignum->precision($p) if defined $p;
  if ($ver)
    {
    print "bignum\t\t\t v$VERSION\n";
    print "Math::BigInt::Lite\t v$Math::BigInt::Lite::VERSION\n" if $_lite;
    print "Math::BigInt\t\t v$Math::BigInt::VERSION";
    my $config = Math::BigInt->config();
    print " lib => $config->{lib} v$config->{lib_version}\n";
    print "Math::BigFloat\t\t v$Math::BigFloat::VERSION\n";
    exit;
    }

  # Take care of octal/hexadecimal constants
  overload::constant binary => sub { bigint::_binary_constant(shift) };

  # if another big* was already loaded:
  my ($package) = caller();

  no strict 'refs';
  if (!defined *{"${package}::inf"})
    {
    $self->export_to_level(1,$self,@a);           # export inf and NaN
    }
  }

sub PI () { Math::BigFloat->new('3.141592653589793238462643383279502884197'); }
sub e () { Math::BigFloat->new('2.718281828459045235360287471352662497757'); }
sub bpi ($) { Math::BigFloat::bpi(@_); }
sub bexp ($$) { my $x = Math::BigFloat->new($_[0]); $x->bexp($_[1]); }

1;

__END__

