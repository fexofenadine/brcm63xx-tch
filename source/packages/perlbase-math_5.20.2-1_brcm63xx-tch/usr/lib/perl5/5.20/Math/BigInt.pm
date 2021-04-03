package Math::BigInt;




my $class = "Math::BigInt";
use 5.006002;

$VERSION = '1.9993';

@ISA = qw(Exporter);
@EXPORT_OK = qw(objectify bgcd blcm); 

use vars qw/$round_mode $accuracy $precision $div_scale $rnd_mode 
	    $upgrade $downgrade $_trap_nan $_trap_inf/;
use strict;




{ no warnings;
use overload
'='     =>      sub { $_[0]->copy(); },

'+='	=>	sub { $_[0]->badd($_[1]); },
'-='	=>	sub { $_[0]->bsub($_[1]); },
'*='	=>	sub { $_[0]->bmul($_[1]); },
'/='	=>	sub { scalar $_[0]->bdiv($_[1]); },
'%='	=>	sub { $_[0]->bmod($_[1]); },
'^='	=>	sub { $_[0]->bxor($_[1]); },
'&='	=>	sub { $_[0]->band($_[1]); },
'|='	=>	sub { $_[0]->bior($_[1]); },

'**='	=>	sub { $_[0]->bpow($_[1]); },
'<<='	=>	sub { $_[0]->blsft($_[1]); },
'>>='	=>	sub { $_[0]->brsft($_[1]); },

'..'	=>	\&_pointpoint,

'<=>'	=>	sub { my $rc = $_[2] ?
                      ref($_[0])->bcmp($_[1],$_[0]) : 
                      $_[0]->bcmp($_[1]); 
		      $rc = 1 unless defined $rc;
		      $rc <=> 0;
		},
'>='	=>	sub { my $rc = $_[2] ?
                      ref($_[0])->bcmp($_[1],$_[0]) : 
                      $_[0]->bcmp($_[1]);
		      # if there was a NaN involved, return false
		      return '' unless defined $rc;
		      $rc >= 0;
		},
'cmp'	=>	sub {
         $_[2] ? 
               "$_[1]" cmp $_[0]->bstr() :
               $_[0]->bstr() cmp "$_[1]" },

'cos'	=>	sub { $_[0]->copy->bcos(); }, 
'sin'	=>	sub { $_[0]->copy->bsin(); }, 
'atan2'	=>	sub { $_[2] ?
			ref($_[0])->new($_[1])->batan2($_[0]) :
			$_[0]->copy()->batan2($_[1]) },

#'hex'	=>	sub { print "hex"; $_[0]; }, 
#'oct'	=>	sub { print "oct"; $_[0]; }, 

'log'	=>	sub { $_[0]->copy()->blog($_[1], undef); }, 
'exp'	=>	sub { $_[0]->copy()->bexp($_[1]); }, 
'int'	=>	sub { $_[0]->copy(); }, 
'neg'	=>	sub { $_[0]->copy()->bneg(); }, 
'abs'	=>	sub { $_[0]->copy()->babs(); },
'sqrt'  =>	sub { $_[0]->copy()->bsqrt(); },
'~'	=>	sub { $_[0]->copy()->bnot(); },

'-'	=>	sub { my $c = $_[0]->copy; $_[2] ?
			$c->bneg()->badd( $_[1]) :
			$c->bsub( $_[1]) },
'+'	=>	sub { $_[0]->copy()->badd($_[1]); },
'*'	=>	sub { $_[0]->copy()->bmul($_[1]); },

'/'	=>	sub { 
   $_[2] ? ref($_[0])->new($_[1])->bdiv($_[0]) : $_[0]->copy->bdiv($_[1]);
  }, 
'%'	=>	sub { 
   $_[2] ? ref($_[0])->new($_[1])->bmod($_[0]) : $_[0]->copy->bmod($_[1]);
  }, 
'**'	=>	sub { 
   $_[2] ? ref($_[0])->new($_[1])->bpow($_[0]) : $_[0]->copy->bpow($_[1]);
  }, 
'<<'	=>	sub { 
   $_[2] ? ref($_[0])->new($_[1])->blsft($_[0]) : $_[0]->copy->blsft($_[1]);
  }, 
'>>'	=>	sub { 
   $_[2] ? ref($_[0])->new($_[1])->brsft($_[0]) : $_[0]->copy->brsft($_[1]);
  }, 
'&'	=>	sub { 
   $_[2] ? ref($_[0])->new($_[1])->band($_[0]) : $_[0]->copy->band($_[1]);
  }, 
'|'	=>	sub { 
   $_[2] ? ref($_[0])->new($_[1])->bior($_[0]) : $_[0]->copy->bior($_[1]);
  }, 
'^'	=>	sub { 
   $_[2] ? ref($_[0])->new($_[1])->bxor($_[0]) : $_[0]->copy->bxor($_[1]);
  }, 

'++'	=>	sub { $_[0]->binc() },
'--'	=>	sub { $_[0]->bdec() },

'bool'  =>	sub {
  # this kludge is needed for perl prior 5.6.0 since returning 0 here fails :-/
  # v5.6.1 dumps on this: return !$_[0]->is_zero() || undef;		    :-(
  my $t = undef;
  $t = 1 if !$_[0]->is_zero();
  $t;
  },

'""' => sub { $_[0]->bstr(); },
'0+' => sub { $_[0]->numify(); }
;
} # no warnings scope



$round_mode = 'even'; # one of 'even', 'odd', '+inf', '-inf', 'zero', 'trunc' or 'common'
$accuracy   = undef;
$precision  = undef;
$div_scale  = 40;

$upgrade = undef;			# default is no upgrade
$downgrade = undef;			# default is no downgrade


$_trap_nan = 0;				# are NaNs ok? set w/ config()
$_trap_inf = 0;				# are infs ok? set w/ config()
my $nan = 'NaN'; 			# constants for easier life

my $CALC = 'Math::BigInt::Calc';	# module to do the low level math
					# default is Calc.pm
my $IMPORT = 0;				# was import() called yet?
					# used to make require work
my %WARN;				# warn only once for low-level libs
my %CAN;				# cache for $CALC->can(...)
my %CALLBACKS;				# callbacks to notify on lib loads
my $EMU_LIB = 'Math/BigInt/CalcEmu.pm';	# emulate low-level math


$rnd_mode   = 'even';
sub TIESCALAR  { my ($class) = @_; bless \$round_mode, $class; }
sub FETCH      { return $round_mode; }
sub STORE      { $rnd_mode = $_[0]->round_mode($_[1]); }

BEGIN
  { 
  # tie to enable $rnd_mode to work transparently
  tie $rnd_mode, 'Math::BigInt'; 

  # set up some handy alias names
  *as_int = \&as_number;
  *is_pos = \&is_positive;
  *is_neg = \&is_negative;
  }


sub round_mode
  {
  no strict 'refs';
  # make Class->round_mode() work
  my $self = shift;
  my $class = ref($self) || $self || __PACKAGE__;
  if (defined $_[0])
    {
    my $m = shift;
    if ($m !~ /^(even|odd|\+inf|\-inf|zero|trunc|common)$/)
      {
      require Carp; Carp::croak ("Unknown round mode '$m'");
      }
    return ${"${class}::round_mode"} = $m;
    }
  ${"${class}::round_mode"};
  }

sub upgrade
  {
  no strict 'refs';
  # make Class->upgrade() work
  my $self = shift;
  my $class = ref($self) || $self || __PACKAGE__;
  # need to set new value?
  if (@_ > 0)
    {
    return ${"${class}::upgrade"} = $_[0];
    }
  ${"${class}::upgrade"};
  }

sub downgrade
  {
  no strict 'refs';
  # make Class->downgrade() work
  my $self = shift;
  my $class = ref($self) || $self || __PACKAGE__;
  # need to set new value?
  if (@_ > 0)
    {
    return ${"${class}::downgrade"} = $_[0];
    }
  ${"${class}::downgrade"};
  }

sub div_scale
  {
  no strict 'refs';
  # make Class->div_scale() work
  my $self = shift;
  my $class = ref($self) || $self || __PACKAGE__;
  if (defined $_[0])
    {
    if ($_[0] < 0)
      {
      require Carp; Carp::croak ('div_scale must be greater than zero');
      }
    ${"${class}::div_scale"} = $_[0];
    }
  ${"${class}::div_scale"};
  }

sub accuracy
  {
  # $x->accuracy($a);		ref($x)	$a
  # $x->accuracy();		ref($x)
  # Class->accuracy();		class
  # Class->accuracy($a);	class $a

  my $x = shift;
  my $class = ref($x) || $x || __PACKAGE__;

  no strict 'refs';
  # need to set new value?
  if (@_ > 0)
    {
    my $a = shift;
    # convert objects to scalars to avoid deep recursion. If object doesn't
    # have numify(), then hopefully it will have overloading for int() and
    # boolean test without wandering into a deep recursion path...
    $a = $a->numify() if ref($a) && $a->can('numify');

    if (defined $a)
      {
      # also croak on non-numerical
      if (!$a || $a <= 0)
        {
        require Carp;
	Carp::croak ('Argument to accuracy must be greater than zero');
        }
      if (int($a) != $a)
        {
        require Carp;
	Carp::croak ('Argument to accuracy must be an integer');
        }
      }
    if (ref($x))
      {
      # $object->accuracy() or fallback to global
      $x->bround($a) if $a;		# not for undef, 0
      $x->{_a} = $a;			# set/overwrite, even if not rounded
      delete $x->{_p};			# clear P
      $a = ${"${class}::accuracy"} unless defined $a;   # proper return value
      }
    else
      {
      ${"${class}::accuracy"} = $a;	# set global A
      ${"${class}::precision"} = undef;	# clear global P
      }
    return $a;				# shortcut
    }

  my $a;
  # $object->accuracy() or fallback to global
  $a = $x->{_a} if ref($x);
  # but don't return global undef, when $x's accuracy is 0!
  $a = ${"${class}::accuracy"} if !defined $a;
  $a;
  }

sub precision
  {
  # $x->precision($p);		ref($x)	$p
  # $x->precision();		ref($x)
  # Class->precision();		class
  # Class->precision($p);	class $p

  my $x = shift;
  my $class = ref($x) || $x || __PACKAGE__;

  no strict 'refs';
  if (@_ > 0)
    {
    my $p = shift;
    # convert objects to scalars to avoid deep recursion. If object doesn't
    # have numify(), then hopefully it will have overloading for int() and
    # boolean test without wandering into a deep recursion path...
    $p = $p->numify() if ref($p) && $p->can('numify');
    if ((defined $p) && (int($p) != $p))
      {
      require Carp; Carp::croak ('Argument to precision must be an integer');
      }
    if (ref($x))
      {
      # $object->precision() or fallback to global
      $x->bfround($p) if $p;		# not for undef, 0
      $x->{_p} = $p;			# set/overwrite, even if not rounded
      delete $x->{_a};			# clear A
      $p = ${"${class}::precision"} unless defined $p;  # proper return value
      }
    else
      {
      ${"${class}::precision"} = $p;	# set global P
      ${"${class}::accuracy"} = undef;	# clear global A
      }
    return $p;				# shortcut
    }

  my $p;
  # $object->precision() or fallback to global
  $p = $x->{_p} if ref($x);
  # but don't return global undef, when $x's precision is 0!
  $p = ${"${class}::precision"} if !defined $p;
  $p;
  }

sub config
  {
  # return (or set) configuration data as hash ref
  my $class = shift || 'Math::BigInt';

  no strict 'refs';
  if (@_ > 1 || (@_ == 1 && (ref($_[0]) eq 'HASH')))
    {
    # try to set given options as arguments from hash

    my $args = $_[0];
    if (ref($args) ne 'HASH')
      {
      $args = { @_ };
      }
    # these values can be "set"
    my $set_args = {};
    foreach my $key (
     qw/trap_inf trap_nan
        upgrade downgrade precision accuracy round_mode div_scale/
     )
      {
      $set_args->{$key} = $args->{$key} if exists $args->{$key};
      delete $args->{$key};
      }
    if (keys %$args > 0)
      {
      require Carp;
      Carp::croak ("Illegal key(s) '",
       join("','",keys %$args),"' passed to $class\->config()");
      }
    foreach my $key (keys %$set_args)
      {
      if ($key =~ /^trap_(inf|nan)\z/)
        {
        ${"${class}::_trap_$1"} = ($set_args->{"trap_$1"} ? 1 : 0);
        next;
        }
      # use a call instead of just setting the $variable to check argument
      $class->$key($set_args->{$key});
      }
    }

  # now return actual configuration

  my $cfg = {
    lib => $CALC,
    lib_version => ${"${CALC}::VERSION"},
    class => $class,
    trap_nan => ${"${class}::_trap_nan"},
    trap_inf => ${"${class}::_trap_inf"},
    version => ${"${class}::VERSION"},
    };
  foreach my $key (qw/
     upgrade downgrade precision accuracy round_mode div_scale
     /)
    {
    $cfg->{$key} = ${"${class}::$key"};
    };
  if (@_ == 1 && (ref($_[0]) ne 'HASH'))
    {
    # calls of the style config('lib') return just this value
    return $cfg->{$_[0]};
    }
  $cfg;
  }

sub _scale_a
  { 
  # select accuracy parameter based on precedence,
  # used by bround() and bfround(), may return undef for scale (means no op)
  my ($x,$scale,$mode) = @_;

  $scale = $x->{_a} unless defined $scale;

  no strict 'refs';
  my $class = ref($x);

  $scale = ${ $class . '::accuracy' } unless defined $scale;
  $mode = ${ $class . '::round_mode' } unless defined $mode;

  if (defined $scale)
    {
    $scale = $scale->can('numify') ? $scale->numify() : "$scale" if ref($scale);
    $scale = int($scale);
    }

  ($scale,$mode);
  }

sub _scale_p
  { 
  # select precision parameter based on precedence,
  # used by bround() and bfround(), may return undef for scale (means no op)
  my ($x,$scale,$mode) = @_;
  
  $scale = $x->{_p} unless defined $scale;

  no strict 'refs';
  my $class = ref($x);

  $scale = ${ $class . '::precision' } unless defined $scale;
  $mode = ${ $class . '::round_mode' } unless defined $mode;

  if (defined $scale)
    {
    $scale = $scale->can('numify') ? $scale->numify() : "$scale" if ref($scale);
    $scale = int($scale);
    }

  ($scale,$mode);
  }


sub copy
  {
  # if two arguments, the first one is the class to "swallow" subclasses
  if (@_ > 1)
    {
    my  $self = bless {
	sign => $_[1]->{sign}, 
	value => $CALC->_copy($_[1]->{value}),
    }, $_[0] if @_ > 1;

    $self->{_a} = $_[1]->{_a} if defined $_[1]->{_a};
    $self->{_p} = $_[1]->{_p} if defined $_[1]->{_p};
    return $self;
    }

  my $self = bless {
	sign => $_[0]->{sign}, 
	value => $CALC->_copy($_[0]->{value}),
	}, ref($_[0]);

  $self->{_a} = $_[0]->{_a} if defined $_[0]->{_a};
  $self->{_p} = $_[0]->{_p} if defined $_[0]->{_p};
  $self;
  }

sub new 
  {
  # create a new BigInt object from a string or another BigInt object. 
  # see hash keys documented at top

  # the argument could be an object, so avoid ||, && etc on it, this would
  # cause costly overloaded code to be called. The only allowed ops are
  # ref() and defined.

  my ($class,$wanted,$a,$p,$r) = @_;
 
  # avoid numify-calls by not using || on $wanted!
  return $class->bzero($a,$p) if !defined $wanted;	# default to 0
  return $class->copy($wanted,$a,$p,$r)
   if ref($wanted) && $wanted->isa($class);		# MBI or subclass

  $class->import() if $IMPORT == 0;		# make require work
  
  my $self = bless {}, $class;

  # shortcut for "normal" numbers
  if ((!ref $wanted) && ($wanted =~ /^([+-]?)[1-9][0-9]*\z/))
    {
    $self->{sign} = $1 || '+';

    if ($wanted =~ /^[+-]/)
     {
      # remove sign without touching wanted to make it work with constants
      my $t = $wanted; $t =~ s/^[+-]//;
      $self->{value} = $CALC->_new($t);
      }
    else
      {
      $self->{value} = $CALC->_new($wanted);
      }
    no strict 'refs';
    if ( (defined $a) || (defined $p) 
        || (defined ${"${class}::precision"})
        || (defined ${"${class}::accuracy"}) 
       )
      {
      $self->round($a,$p,$r) unless (@_ == 4 && !defined $a && !defined $p);
      }
    return $self;
    }

  # handle '+inf', '-inf' first
  if ($wanted =~ /^[+-]?inf\z/)
    {
    $self->{sign} = $wanted;		# set a default sign for bstr()
    return $self->binf($wanted);
    }
  # split str in m mantissa, e exponent, i integer, f fraction, v value, s sign
  my ($mis,$miv,$mfv,$es,$ev) = _split($wanted);
  if (!ref $mis)
    {
    if ($_trap_nan)
      {
      require Carp; Carp::croak("$wanted is not a number in $class");
      }
    $self->{value} = $CALC->_zero();
    $self->{sign} = $nan;
    return $self;
    }
  if (!ref $miv)
    {
    # _from_hex or _from_bin
    $self->{value} = $mis->{value};
    $self->{sign} = $mis->{sign};
    return $self;	# throw away $mis
    }
  # make integer from mantissa by adjusting exp, then convert to bigint
  $self->{sign} = $$mis;			# store sign
  $self->{value} = $CALC->_zero();		# for all the NaN cases
  my $e = int("$$es$$ev");			# exponent (avoid recursion)
  if ($e > 0)
    {
    my $diff = $e - CORE::length($$mfv);
    if ($diff < 0)				# Not integer
      {
      if ($_trap_nan)
        {
        require Carp; Carp::croak("$wanted not an integer in $class");
        }
      #print "NOI 1\n";
      return $upgrade->new($wanted,$a,$p,$r) if defined $upgrade;
      $self->{sign} = $nan;
      }
    else					# diff >= 0
      {
      # adjust fraction and add it to value
      #print "diff > 0 $$miv\n";
      $$miv = $$miv . ($$mfv . '0' x $diff);
      }
    }
  else
    {
    if ($$mfv ne '')				# e <= 0
      {
      # fraction and negative/zero E => NOI
      if ($_trap_nan)
        {
        require Carp; Carp::croak("$wanted not an integer in $class");
        }
      #print "NOI 2 \$\$mfv '$$mfv'\n";
      return $upgrade->new($wanted,$a,$p,$r) if defined $upgrade;
      $self->{sign} = $nan;
      }
    elsif ($e < 0)
      {
      # xE-y, and empty mfv
      #print "xE-y\n";
      $e = abs($e);
      if ($$miv !~ s/0{$e}$//)		# can strip so many zero's?
        {
        if ($_trap_nan)
          {
          require Carp; Carp::croak("$wanted not an integer in $class");
          }
        #print "NOI 3\n";
        return $upgrade->new($wanted,$a,$p,$r) if defined $upgrade;
        $self->{sign} = $nan;
        }
      }
    }
  $self->{sign} = '+' if $$miv eq '0';			# normalize -0 => +0
  $self->{value} = $CALC->_new($$miv) if $self->{sign} =~ /^[+-]$/;
  # if any of the globals is set, use them to round and store them inside $self
  # do not round for new($x,undef,undef) since that is used by MBF to signal
  # no rounding
  $self->round($a,$p,$r) unless @_ == 4 && !defined $a && !defined $p;
  $self;
  }

sub bnan
  {
  # create a bigint 'NaN', if given a BigInt, set it to 'NaN'
  my $self = shift;
  $self = $class if !defined $self;
  if (!ref($self))
    {
    my $c = $self; $self = {}; bless $self, $c;
    }
  no strict 'refs';
  if (${"${class}::_trap_nan"})
    {
    require Carp;
    Carp::croak ("Tried to set $self to NaN in $class\::bnan()");
    }
  $self->import() if $IMPORT == 0;		# make require work
  return if $self->modify('bnan');
  if ($self->can('_bnan'))
    {
    # use subclass to initialize
    $self->_bnan();
    }
  else
    {
    # otherwise do our own thing
    $self->{value} = $CALC->_zero();
    }
  $self->{sign} = $nan;
  delete $self->{_a}; delete $self->{_p};	# rounding NaN is silly
  $self;
  }

sub binf
  {
  # create a bigint '+-inf', if given a BigInt, set it to '+-inf'
  # the sign is either '+', or if given, used from there
  my $self = shift;
  my $sign = shift; $sign = '+' if !defined $sign || $sign !~ /^-(inf)?$/;
  $self = $class if !defined $self;
  if (!ref($self))
    {
    my $c = $self; $self = {}; bless $self, $c;
    }
  no strict 'refs';
  if (${"${class}::_trap_inf"})
    {
    require Carp;
    Carp::croak ("Tried to set $self to +-inf in $class\::binf()");
    }
  $self->import() if $IMPORT == 0;		# make require work
  return if $self->modify('binf');
  if ($self->can('_binf'))
    {
    # use subclass to initialize
    $self->_binf();
    }
  else
    {
    # otherwise do our own thing
    $self->{value} = $CALC->_zero();
    }
  $sign = $sign . 'inf' if $sign !~ /inf$/;	# - => -inf
  $self->{sign} = $sign;
  ($self->{_a},$self->{_p}) = @_;		# take over requested rounding
  $self;
  }

sub bzero
  {
  # create a bigint '+0', if given a BigInt, set it to 0
  my $self = shift;
  $self = __PACKAGE__ if !defined $self;
 
  if (!ref($self))
    {
    my $c = $self; $self = {}; bless $self, $c;
    }
  $self->import() if $IMPORT == 0;		# make require work
  return if $self->modify('bzero');
  
  if ($self->can('_bzero'))
    {
    # use subclass to initialize
    $self->_bzero();
    }
  else
    {
    # otherwise do our own thing
    $self->{value} = $CALC->_zero();
    }
  $self->{sign} = '+';
  if (@_ > 0)
    {
    if (@_ > 3)
      {
      # call like: $x->bzero($a,$p,$r,$y);
      ($self,$self->{_a},$self->{_p}) = $self->_find_round_parameters(@_);
      }
    else
      {
      $self->{_a} = $_[0]
       if ( (!defined $self->{_a}) || (defined $_[0] && $_[0] > $self->{_a}));
      $self->{_p} = $_[1]
       if ( (!defined $self->{_p}) || (defined $_[1] && $_[1] > $self->{_p}));
      }
    }
  $self;
  }

sub bone
  {
  # create a bigint '+1' (or -1 if given sign '-'),
  # if given a BigInt, set it to +1 or -1, respectively
  my $self = shift;
  my $sign = shift; $sign = '+' if !defined $sign || $sign ne '-';
  $self = $class if !defined $self;

  if (!ref($self))
    {
    my $c = $self; $self = {}; bless $self, $c;
    }
  $self->import() if $IMPORT == 0;		# make require work
  return if $self->modify('bone');

  if ($self->can('_bone'))
    {
    # use subclass to initialize
    $self->_bone();
    }
  else
    {
    # otherwise do our own thing
    $self->{value} = $CALC->_one();
    }
  $self->{sign} = $sign;
  if (@_ > 0)
    {
    if (@_ > 3)
      {
      # call like: $x->bone($sign,$a,$p,$r,$y);
      ($self,$self->{_a},$self->{_p}) = $self->_find_round_parameters(@_);
      }
    else
      {
      # call like: $x->bone($sign,$a,$p,$r);
      $self->{_a} = $_[0]
       if ( (!defined $self->{_a}) || (defined $_[0] && $_[0] > $self->{_a}));
      $self->{_p} = $_[1]
       if ( (!defined $self->{_p}) || (defined $_[1] && $_[1] > $self->{_p}));
      }
    }
  $self;
  }


sub bsstr
  {
  # (ref to BFLOAT or num_str ) return num_str
  # Convert number from internal format to scientific string format.
  # internal format is always normalized (no leading zeros, "-0E0" => "+0E0")
  my ($self,$x) = ref($_[0]) ? (undef,$_[0]) : objectify(1,@_); 

  if ($x->{sign} !~ /^[+-]$/)
    {
    return $x->{sign} unless $x->{sign} eq '+inf';	# -inf, NaN
    return 'inf';					# +inf
    }
  my ($m,$e) = $x->parts();
  #$m->bstr() . 'e+' . $e->bstr(); 	# e can only be positive in BigInt
  # 'e+' because E can only be positive in BigInt
  $m->bstr() . 'e+' . $CALC->_str($e->{value}); 
  }

sub bstr 
  {
  # make a string from bigint object
  my ($self,$x) = ref($_[0]) ? (undef,$_[0]) : objectify(1,@_); 

  if ($x->{sign} !~ /^[+-]$/)
    {
    return $x->{sign} unless $x->{sign} eq '+inf';	# -inf, NaN
    return 'inf';					# +inf
    }
  my $es = ''; $es = $x->{sign} if $x->{sign} eq '-';
  $es.$CALC->_str($x->{value});
  }

sub numify 
  {
  # Make a "normal" scalar from a BigInt object
  my $x = shift; $x = $class->new($x) unless ref $x;

  return $x->bstr() if $x->{sign} !~ /^[+-]$/;
  my $num = $CALC->_num($x->{value});
  return -$num if $x->{sign} eq '-';
  $num;
  }


sub sign
  {
  # return the sign of the number: +/-/-inf/+inf/NaN
  my ($self,$x) = ref($_[0]) ? (undef,$_[0]) : objectify(1,@_); 
  
  $x->{sign};
  }

sub _find_round_parameters
  {
  # After any operation or when calling round(), the result is rounded by
  # regarding the A & P from arguments, local parameters, or globals.

  # !!!!!!! If you change this, remember to change round(), too! !!!!!!!!!!

  # This procedure finds the round parameters, but it is for speed reasons
  # duplicated in round. Otherwise, it is tested by the testsuite and used
  # by fdiv().
 
  # returns ($self) or ($self,$a,$p,$r) - sets $self to NaN of both A and P
  # were requested/defined (locally or globally or both)
  
  my ($self,$a,$p,$r,@args) = @_;
  # $a accuracy, if given by caller
  # $p precision, if given by caller
  # $r round_mode, if given by caller
  # @args all 'other' arguments (0 for unary, 1 for binary ops)

  my $c = ref($self);				# find out class of argument(s)
  no strict 'refs';

  # convert to normal scalar for speed and correctness in inner parts
  $a = $a->can('numify') ? $a->numify() : "$a" if defined $a && ref($a);
  $p = $p->can('numify') ? $p->numify() : "$p" if defined $p && ref($p);

  # now pick $a or $p, but only if we have got "arguments"
  if (!defined $a)
    {
    foreach ($self,@args)
      {
      # take the defined one, or if both defined, the one that is smaller
      $a = $_->{_a} if (defined $_->{_a}) && (!defined $a || $_->{_a} < $a);
      }
    }
  if (!defined $p)
    {
    # even if $a is defined, take $p, to signal error for both defined
    foreach ($self,@args)
      {
      # take the defined one, or if both defined, the one that is bigger
      # -2 > -3, and 3 > 2
      $p = $_->{_p} if (defined $_->{_p}) && (!defined $p || $_->{_p} > $p);
      }
    }
  # if still none defined, use globals (#2)
  $a = ${"$c\::accuracy"} unless defined $a;
  $p = ${"$c\::precision"} unless defined $p;

  # A == 0 is useless, so undef it to signal no rounding
  $a = undef if defined $a && $a == 0;
 
  # no rounding today? 
  return ($self) unless defined $a || defined $p;		# early out

  # set A and set P is an fatal error
  return ($self->bnan()) if defined $a && defined $p;		# error

  $r = ${"$c\::round_mode"} unless defined $r;
  if ($r !~ /^(even|odd|\+inf|\-inf|zero|trunc|common)$/)
    {
    require Carp; Carp::croak ("Unknown round mode '$r'");
    }

  $a = int($a) if defined $a;
  $p = int($p) if defined $p;

  ($self,$a,$p,$r);
  }

sub round
  {
  # Round $self according to given parameters, or given second argument's
  # parameters or global defaults 

  # for speed reasons, _find_round_parameters is embedded here:

  my ($self,$a,$p,$r,@args) = @_;
  # $a accuracy, if given by caller
  # $p precision, if given by caller
  # $r round_mode, if given by caller
  # @args all 'other' arguments (0 for unary, 1 for binary ops)

  my $c = ref($self);				# find out class of argument(s)
  no strict 'refs';

  # now pick $a or $p, but only if we have got "arguments"
  if (!defined $a)
    {
    foreach ($self,@args)
      {
      # take the defined one, or if both defined, the one that is smaller
      $a = $_->{_a} if (defined $_->{_a}) && (!defined $a || $_->{_a} < $a);
      }
    }
  if (!defined $p)
    {
    # even if $a is defined, take $p, to signal error for both defined
    foreach ($self,@args)
      {
      # take the defined one, or if both defined, the one that is bigger
      # -2 > -3, and 3 > 2
      $p = $_->{_p} if (defined $_->{_p}) && (!defined $p || $_->{_p} > $p);
      }
    }
  # if still none defined, use globals (#2)
  $a = ${"$c\::accuracy"} unless defined $a;
  $p = ${"$c\::precision"} unless defined $p;
 
  # A == 0 is useless, so undef it to signal no rounding
  $a = undef if defined $a && $a == 0;
  
  # no rounding today? 
  return $self unless defined $a || defined $p;		# early out

  # set A and set P is an fatal error
  return $self->bnan() if defined $a && defined $p;

  $r = ${"$c\::round_mode"} unless defined $r;
  if ($r !~ /^(even|odd|\+inf|\-inf|zero|trunc|common)$/)
    {
    require Carp; Carp::croak ("Unknown round mode '$r'");
    }

  # now round, by calling either fround or ffround:
  if (defined $a)
    {
    $self->bround(int($a),$r) if !defined $self->{_a} || $self->{_a} >= $a;
    }
  else # both can't be undefined due to early out
    {
    $self->bfround(int($p),$r) if !defined $self->{_p} || $self->{_p} <= $p;
    }
  # bround() or bfround() already called bnorm() if nec.
  $self;
  }

sub bnorm
  { 
  # (numstr or BINT) return BINT
  # Normalize number -- no-op here
  my ($self,$x) = ref($_[0]) ? (undef,$_[0]) : objectify(1,@_);
  $x;
  }

sub babs 
  {
  # (BINT or num_str) return BINT
  # make number absolute, or return absolute BINT from string
  my ($self,$x) = ref($_[0]) ? (undef,$_[0]) : objectify(1,@_);

  return $x if $x->modify('babs');
  # post-normalized abs for internal use (does nothing for NaN)
  $x->{sign} =~ s/^-/+/;
  $x;
  }

sub bsgn {
    # Signum function.

    my $self = shift;

    return $self if $self->modify('bsgn');

    return $self -> bone("+") if $self -> is_pos();
    return $self -> bone("-") if $self -> is_neg();
    return $self;               # zero or NaN
}

sub bneg 
  { 
  # (BINT or num_str) return BINT
  # negate number or make a negated number from string
  my ($self,$x) = ref($_[0]) ? (undef,$_[0]) : objectify(1,@_);
  
  return $x if $x->modify('bneg');

  # for +0 do not negate (to have always normalized +0). Does nothing for 'NaN'
  $x->{sign} =~ tr/+-/-+/ unless ($x->{sign} eq '+' && $CALC->_is_zero($x->{value}));
  $x;
  }

sub bcmp 
  {
  # Compares 2 values.  Returns one of undef, <0, =0, >0. (suitable for sort)
  # (BINT or num_str, BINT or num_str) return cond_code
  
  # set up parameters
  my ($self,$x,$y) = (ref($_[0]),@_);

  # objectify is costly, so avoid it 
  if ((!ref($_[0])) || (ref($_[0]) ne ref($_[1])))
    {
    ($self,$x,$y) = objectify(2,@_);
    }

  return $upgrade->bcmp($x,$y) if defined $upgrade &&
    ((!$x->isa($self)) || (!$y->isa($self)));

  if (($x->{sign} !~ /^[+-]$/) || ($y->{sign} !~ /^[+-]$/))
    {
    # handle +-inf and NaN
    return undef if (($x->{sign} eq $nan) || ($y->{sign} eq $nan));
    return 0 if $x->{sign} eq $y->{sign} && $x->{sign} =~ /^[+-]inf$/;
    return +1 if $x->{sign} eq '+inf';
    return -1 if $x->{sign} eq '-inf';
    return -1 if $y->{sign} eq '+inf';
    return +1;
    }
  # check sign for speed first
  return 1 if $x->{sign} eq '+' && $y->{sign} eq '-';	# does also 0 <=> -y
  return -1 if $x->{sign} eq '-' && $y->{sign} eq '+';  # does also -x <=> 0 

  # have same sign, so compare absolute values. Don't make tests for zero here
  # because it's actually slower than testing in Calc (especially w/ Pari et al)

  # post-normalized compare for internal use (honors signs)
  if ($x->{sign} eq '+') 
    {
    # $x and $y both > 0
    return $CALC->_acmp($x->{value},$y->{value});
    }

  # $x && $y both < 0
  $CALC->_acmp($y->{value},$x->{value});	# swapped acmp (lib returns 0,1,-1)
  }

sub bacmp 
  {
  # Compares 2 values, ignoring their signs. 
  # Returns one of undef, <0, =0, >0. (suitable for sort)
  # (BINT, BINT) return cond_code
  
  # set up parameters
  my ($self,$x,$y) = (ref($_[0]),@_);
  # objectify is costly, so avoid it 
  if ((!ref($_[0])) || (ref($_[0]) ne ref($_[1])))
    {
    ($self,$x,$y) = objectify(2,@_);
    }

  return $upgrade->bacmp($x,$y) if defined $upgrade &&
    ((!$x->isa($self)) || (!$y->isa($self)));

  if (($x->{sign} !~ /^[+-]$/) || ($y->{sign} !~ /^[+-]$/))
    {
    # handle +-inf and NaN
    return undef if (($x->{sign} eq $nan) || ($y->{sign} eq $nan));
    return 0 if $x->{sign} =~ /^[+-]inf$/ && $y->{sign} =~ /^[+-]inf$/;
    return 1 if $x->{sign} =~ /^[+-]inf$/ && $y->{sign} !~ /^[+-]inf$/;
    return -1;
    }
  $CALC->_acmp($x->{value},$y->{value});	# lib does only 0,1,-1
  }

sub badd 
  {
  # add second arg (BINT or string) to first (BINT) (modifies first)
  # return result as BINT

  # set up parameters
  my ($self,$x,$y,@r) = (ref($_[0]),@_);
  # objectify is costly, so avoid it 
  if ((!ref($_[0])) || (ref($_[0]) ne ref($_[1])))
    {
    ($self,$x,$y,@r) = objectify(2,@_);
    }

  return $x if $x->modify('badd');
  return $upgrade->badd($upgrade->new($x),$upgrade->new($y),@r) if defined $upgrade &&
    ((!$x->isa($self)) || (!$y->isa($self)));

  $r[3] = $y;				# no push!
  # inf and NaN handling
  if (($x->{sign} !~ /^[+-]$/) || ($y->{sign} !~ /^[+-]$/))
    {
    # NaN first
    return $x->bnan() if (($x->{sign} eq $nan) || ($y->{sign} eq $nan));
    # inf handling
    if (($x->{sign} =~ /^[+-]inf$/) && ($y->{sign} =~ /^[+-]inf$/))
      {
      # +inf++inf or -inf+-inf => same, rest is NaN
      return $x if $x->{sign} eq $y->{sign};
      return $x->bnan();
      }
    # +-inf + something => +inf
    # something +-inf => +-inf
    $x->{sign} = $y->{sign}, return $x if $y->{sign} =~ /^[+-]inf$/;
    return $x;
    }
    
  my ($sx, $sy) = ( $x->{sign}, $y->{sign} ); 		# get signs

  if ($sx eq $sy)  
    {
    $x->{value} = $CALC->_add($x->{value},$y->{value});	# same sign, abs add
    }
  else 
    {
    my $a = $CALC->_acmp ($y->{value},$x->{value});	# absolute compare
    if ($a > 0)                           
      {
      $x->{value} = $CALC->_sub($y->{value},$x->{value},1); # abs sub w/ swap
      $x->{sign} = $sy;
      } 
    elsif ($a == 0)
      {
      # speedup, if equal, set result to 0
      $x->{value} = $CALC->_zero();
      $x->{sign} = '+';
      }
    else # a < 0
      {
      $x->{value} = $CALC->_sub($x->{value}, $y->{value}); # abs sub
      }
    }
  $x->round(@r);
  }

sub bsub 
  {
  # (BINT or num_str, BINT or num_str) return BINT
  # subtract second arg from first, modify first
  
  # set up parameters
  my ($self,$x,$y,@r) = (ref($_[0]),@_);

  # objectify is costly, so avoid it
  if ((!ref($_[0])) || (ref($_[0]) ne ref($_[1])))
    {
    ($self,$x,$y,@r) = objectify(2,@_);
    }

  return $x if $x->modify('bsub');

  return $upgrade->new($x)->bsub($upgrade->new($y),@r) if defined $upgrade &&
   ((!$x->isa($self)) || (!$y->isa($self)));

  return $x->round(@r) if $y->is_zero();

  # To correctly handle the lone special case $x->bsub($x), we note the sign
  # of $x, then flip the sign from $y, and if the sign of $x did change, too,
  # then we caught the special case:
  my $xsign = $x->{sign};
  $y->{sign} =~ tr/+\-/-+/; 	# does nothing for NaN
  if ($xsign ne $x->{sign})
    {
    # special case of $x->bsub($x) results in 0
    return $x->bzero(@r) if $xsign =~ /^[+-]$/;
    return $x->bnan();          # NaN, -inf, +inf
    }
  $x->badd($y,@r); 		# badd does not leave internal zeros
  $y->{sign} =~ tr/+\-/-+/; 	# refix $y (does nothing for NaN)
  $x;				# already rounded by badd() or no round nec.
  }

sub binc
  {
  # increment arg by one
  my ($self,$x,$a,$p,$r) = ref($_[0]) ? (ref($_[0]),@_) : objectify(1,@_);
  return $x if $x->modify('binc');

  if ($x->{sign} eq '+')
    {
    $x->{value} = $CALC->_inc($x->{value});
    return $x->round($a,$p,$r);
    }
  elsif ($x->{sign} eq '-')
    {
    $x->{value} = $CALC->_dec($x->{value});
    $x->{sign} = '+' if $CALC->_is_zero($x->{value}); # -1 +1 => -0 => +0
    return $x->round($a,$p,$r);
    }
  # inf, nan handling etc
  $x->badd($self->bone(),$a,$p,$r);		# badd does round
  }

sub bdec
  {
  # decrement arg by one
  my ($self,$x,@r) = ref($_[0]) ? (ref($_[0]),@_) : objectify(1,@_);
  return $x if $x->modify('bdec');
  
  if ($x->{sign} eq '-')
    {
    # x already < 0
    $x->{value} = $CALC->_inc($x->{value});
    } 
  else
    {
    return $x->badd($self->bone('-'),@r) unless $x->{sign} eq '+'; 	# inf or NaN
    # >= 0
    if ($CALC->_is_zero($x->{value}))
      {
      # == 0
      $x->{value} = $CALC->_one(); $x->{sign} = '-';		# 0 => -1
      }
    else
      {
      # > 0
      $x->{value} = $CALC->_dec($x->{value});
      }
    }
  $x->round(@r);
  }

sub blog
  {
  # calculate $x = $a ** $base + $b and return $a (e.g. the log() to base
  # $base of $x)

  # set up parameters
  my ($self,$x,$base,@r) = (undef,@_);
  # objectify is costly, so avoid it
  if ((!ref($_[0])) || (ref($_[0]) ne ref($_[1])))
    {
    ($self,$x,$base,@r) = objectify(2,@_);
    }

  return $x if $x->modify('blog');

  $base = $self->new($base) if defined $base && !ref $base;

  # inf, -inf, NaN, <0 => NaN
  return $x->bnan()
   if $x->{sign} ne '+' || (defined $base && $base->{sign} ne '+');

  return $upgrade->blog($upgrade->new($x),$base,@r) if 
    defined $upgrade;

  # fix for bug #24969:
  # the default base is e (Euler's number) which is not an integer
  if (!defined $base)
    {
    require Math::BigFloat;
    my $u = Math::BigFloat->blog(Math::BigFloat->new($x))->as_int();
    # modify $x in place
    $x->{value} = $u->{value};
    $x->{sign} = $u->{sign};
    return $x;
    }
  
  my ($rc,$exact) = $CALC->_log_int($x->{value},$base->{value});
  return $x->bnan() unless defined $rc;		# not possible to take log?
  $x->{value} = $rc;
  $x->round(@r);
  }

sub bnok
  {
  # Calculate n over k (binomial coefficient or "choose" function) as integer.
  # set up parameters
  my ($self,$x,$y,@r) = (ref($_[0]),@_);

  # objectify is costly, so avoid it
  if ((!ref($_[0])) || (ref($_[0]) ne ref($_[1])))
    {
    ($self,$x,$y,@r) = objectify(2,@_);
    }

  return $x if $x->modify('bnok');
  return $x->bnan() if $x->{sign} eq 'NaN' || $y->{sign} eq 'NaN';
  return $x->binf() if $x->{sign} eq '+inf';

  # k > n or k < 0 => 0
  my $cmp = $x->bacmp($y);
  return $x->bzero() if $cmp < 0 || $y->{sign} =~ /^-/;
  # k == n => 1
  return $x->bone(@r) if $cmp == 0;

  if ($CALC->can('_nok'))
    {
    $x->{value} = $CALC->_nok($x->{value},$y->{value});
    }
  else
    {
    # ( 7 )       7!       1*2*3*4 * 5*6*7   5 * 6 * 7       6   7
    # ( - ) = --------- =  --------------- = --------- = 5 * - * -
    # ( 3 )   (7-3)! 3!    1*2*3*4 * 1*2*3   1 * 2 * 3       2   3

    if (!$y->is_zero())
      {
      my $z = $x - $y;
      $z->binc();
      my $r = $z->copy(); $z->binc();
      my $d = $self->new(2);
      while ($z->bacmp($x) <= 0)		# f <= x ?
        {
        $r->bmul($z); $r->bdiv($d);
        $z->binc(); $d->binc();
        }
      $x->{value} = $r->{value}; $x->{sign} = '+';
      }
    else { $x->bone(); }
    }
  $x->round(@r);
  }

sub bexp
  {
  # Calculate e ** $x (Euler's number to the power of X), truncated to
  # an integer value.
  my ($self,$x,@r) = ref($_[0]) ? (ref($_[0]),@_) : objectify(1,@_);
  return $x if $x->modify('bexp');

  # inf, -inf, NaN, <0 => NaN
  return $x->bnan() if $x->{sign} eq 'NaN';
  return $x->bone() if $x->is_zero();
  return $x if $x->{sign} eq '+inf';
  return $x->bzero() if $x->{sign} eq '-inf';

  my $u;
  {
    # run through Math::BigFloat unless told otherwise
    require Math::BigFloat unless defined $upgrade;
    local $upgrade = 'Math::BigFloat' unless defined $upgrade;
    # calculate result, truncate it to integer
    $u = $upgrade->bexp($upgrade->new($x),@r);
  }

  if (!defined $upgrade)
    {
    $u = $u->as_int();
    # modify $x in place
    $x->{value} = $u->{value};
    $x->round(@r);
    }
  else { $x = $u; }
  }

sub blcm
  {
  # (BINT or num_str, BINT or num_str) return BINT
  # does not modify arguments, but returns new object
  # Lowest Common Multiple

  my $y = shift; my ($x);
  if (ref($y))
    {
    $x = $y->copy();
    }
  else
    {
    $x = $class->new($y);
    }
  my $self = ref($x);
  while (@_) 
    {
    my $y = shift; $y = $self->new($y) if !ref ($y);
    $x = __lcm($x,$y);
    } 
  $x;
  }

sub bgcd 
  { 
  # (BINT or num_str, BINT or num_str) return BINT
  # does not modify arguments, but returns new object
  # GCD -- Euclid's algorithm, variant C (Knuth Vol 3, pg 341 ff)

  my $y = shift;
  $y = $class->new($y) if !ref($y);
  my $self = ref($y);
  my $x = $y->copy()->babs();			# keep arguments
  return $x->bnan() if $x->{sign} !~ /^[+-]$/;	# x NaN?

  while (@_)
    {
    $y = shift; $y = $self->new($y) if !ref($y);
    return $x->bnan() if $y->{sign} !~ /^[+-]$/;	# y NaN?
    $x->{value} = $CALC->_gcd($x->{value},$y->{value});
    last if $CALC->_is_one($x->{value});
    }
  $x;
  }

sub bnot 
  {
  # (num_str or BINT) return BINT
  # represent ~x as twos-complement number
  # we don't need $self, so undef instead of ref($_[0]) make it slightly faster
  my ($self,$x,$a,$p,$r) = ref($_[0]) ? (undef,@_) : objectify(1,@_);
 
  return $x if $x->modify('bnot');
  $x->binc()->bneg();			# binc already does round
  }


sub is_zero
  {
  # return true if arg (BINT or num_str) is zero (array '+', '0')
  my ($self,$x) = ref($_[0]) ? (undef,$_[0]) : objectify(1,@_);
  
  return 0 if $x->{sign} !~ /^\+$/;			# -, NaN & +-inf aren't
  $CALC->_is_zero($x->{value});
  }

sub is_nan
  {
  # return true if arg (BINT or num_str) is NaN
  my ($self,$x) = ref($_[0]) ? (undef,$_[0]) : objectify(1,@_);

  $x->{sign} eq $nan ? 1 : 0;
  }

sub is_inf
  {
  # return true if arg (BINT or num_str) is +-inf
  my ($self,$x,$sign) = ref($_[0]) ? (undef,@_) : objectify(1,@_);

  if (defined $sign)
    {
    $sign = '[+-]inf' if $sign eq '';	# +- doesn't matter, only that's inf
    $sign = "[$1]inf" if $sign =~ /^([+-])(inf)?$/;	# extract '+' or '-'
    return $x->{sign} =~ /^$sign$/ ? 1 : 0;
    }
  $x->{sign} =~ /^[+-]inf$/ ? 1 : 0;		# only +-inf is infinity
  }

sub is_one
  {
  # return true if arg (BINT or num_str) is +1, or -1 if sign is given
  my ($self,$x,$sign) = ref($_[0]) ? (undef,@_) : objectify(1,@_);
    
  $sign = '+' if !defined $sign || $sign ne '-';
 
  return 0 if $x->{sign} ne $sign; 	# -1 != +1, NaN, +-inf aren't either
  $CALC->_is_one($x->{value});
  }

sub is_odd
  {
  # return true when arg (BINT or num_str) is odd, false for even
  my ($self,$x) = ref($_[0]) ? (undef,$_[0]) : objectify(1,@_);

  return 0 if $x->{sign} !~ /^[+-]$/;			# NaN & +-inf aren't
  $CALC->_is_odd($x->{value});
  }

sub is_even
  {
  # return true when arg (BINT or num_str) is even, false for odd
  my ($self,$x) = ref($_[0]) ? (undef,$_[0]) : objectify(1,@_);

  return 0 if $x->{sign} !~ /^[+-]$/;			# NaN & +-inf aren't
  $CALC->_is_even($x->{value});
  }

sub is_positive
  {
  # return true when arg (BINT or num_str) is positive (> 0)
  my ($self,$x) = ref($_[0]) ? (undef,$_[0]) : objectify(1,@_);

  return 1 if $x->{sign} eq '+inf';			# +inf is positive

  # 0+ is neither positive nor negative
  ($x->{sign} eq '+' && !$x->is_zero()) ? 1 : 0;
  }

sub is_negative
  {
  # return true when arg (BINT or num_str) is negative (< 0)
  my ($self,$x) = ref($_[0]) ? (undef,$_[0]) : objectify(1,@_);
  
  $x->{sign} =~ /^-/ ? 1 : 0; 		# -inf is negative, but NaN is not
  }

sub is_int
  {
  # return true when arg (BINT or num_str) is an integer
  # always true for BigInt, but different for BigFloats
  my ($self,$x) = ref($_[0]) ? (undef,$_[0]) : objectify(1,@_);
  
  $x->{sign} =~ /^[+-]$/ ? 1 : 0;		# inf/-inf/NaN aren't
  }


sub bmul 
  { 
  # multiply the first number by the second number
  # (BINT or num_str, BINT or num_str) return BINT

  # set up parameters
  my ($self,$x,$y,@r) = (ref($_[0]),@_);
  # objectify is costly, so avoid it
  if ((!ref($_[0])) || (ref($_[0]) ne ref($_[1])))
    {
    ($self,$x,$y,@r) = objectify(2,@_);
    }

  return $x if $x->modify('bmul');

  return $x->bnan() if (($x->{sign} eq $nan) || ($y->{sign} eq $nan));

  # inf handling
  if (($x->{sign} =~ /^[+-]inf$/) || ($y->{sign} =~ /^[+-]inf$/))
    {
    return $x->bnan() if $x->is_zero() || $y->is_zero();
    # result will always be +-inf:
    # +inf * +/+inf => +inf, -inf * -/-inf => +inf
    # +inf * -/-inf => -inf, -inf * +/+inf => -inf
    return $x->binf() if ($x->{sign} =~ /^\+/ && $y->{sign} =~ /^\+/); 
    return $x->binf() if ($x->{sign} =~ /^-/ && $y->{sign} =~ /^-/); 
    return $x->binf('-');
    }

  return $upgrade->bmul($x,$upgrade->new($y),@r)
   if defined $upgrade && !$y->isa($self);
  
  $r[3] = $y;				# no push here

  $x->{sign} = $x->{sign} eq $y->{sign} ? '+' : '-'; # +1 * +1 or -1 * -1 => +

  $x->{value} = $CALC->_mul($x->{value},$y->{value});	# do actual math
  $x->{sign} = '+' if $CALC->_is_zero($x->{value}); 	# no -0

  $x->round(@r);
  }

sub bmuladd
  { 
  # multiply two numbers and then add the third to the result
  # (BINT or num_str, BINT or num_str, BINT or num_str) return BINT

  # set up parameters
  my ($self,$x,$y,$z,@r) = objectify(3,@_);

  return $x if $x->modify('bmuladd');

  return $x->bnan() if  ($x->{sign} eq $nan) ||
			($y->{sign} eq $nan) ||
			($z->{sign} eq $nan);

  # inf handling of x and y
  if (($x->{sign} =~ /^[+-]inf$/) || ($y->{sign} =~ /^[+-]inf$/))
    {
    return $x->bnan() if $x->is_zero() || $y->is_zero();
    # result will always be +-inf:
    # +inf * +/+inf => +inf, -inf * -/-inf => +inf
    # +inf * -/-inf => -inf, -inf * +/+inf => -inf
    return $x->binf() if ($x->{sign} =~ /^\+/ && $y->{sign} =~ /^\+/); 
    return $x->binf() if ($x->{sign} =~ /^-/ && $y->{sign} =~ /^-/); 
    return $x->binf('-');
    }
  # inf handling x*y and z
  if (($z->{sign} =~ /^[+-]inf$/))
    {
    # something +-inf => +-inf
    $x->{sign} = $z->{sign}, return $x if $z->{sign} =~ /^[+-]inf$/;
    }

  return $upgrade->bmuladd($x,$upgrade->new($y),$upgrade->new($z),@r)
   if defined $upgrade && (!$y->isa($self) || !$z->isa($self) || !$x->isa($self));
 
  # TODO: what if $y and $z have A or P set?
  $r[3] = $z;				# no push here

  $x->{sign} = $x->{sign} eq $y->{sign} ? '+' : '-'; # +1 * +1 or -1 * -1 => +

  $x->{value} = $CALC->_mul($x->{value},$y->{value});	# do actual math
  $x->{sign} = '+' if $CALC->_is_zero($x->{value}); 	# no -0

  my ($sx, $sz) = ( $x->{sign}, $z->{sign} ); 		# get signs

  if ($sx eq $sz)  
    {
    $x->{value} = $CALC->_add($x->{value},$z->{value});	# same sign, abs add
    }
  else 
    {
    my $a = $CALC->_acmp ($z->{value},$x->{value});	# absolute compare
    if ($a > 0)                           
      {
      $x->{value} = $CALC->_sub($z->{value},$x->{value},1); # abs sub w/ swap
      $x->{sign} = $sz;
      } 
    elsif ($a == 0)
      {
      # speedup, if equal, set result to 0
      $x->{value} = $CALC->_zero();
      $x->{sign} = '+';
      }
    else # a < 0
      {
      $x->{value} = $CALC->_sub($x->{value}, $z->{value}); # abs sub
      }
    }
  $x->round(@r);
  }

sub _div_inf
  {
  # helper function that handles +-inf cases for bdiv()/bmod() to reuse code
  my ($self,$x,$y) = @_;

  # NaN if x == NaN or y == NaN or x==y==0
  return wantarray ? ($x->bnan(),$self->bnan()) : $x->bnan()
   if (($x->is_nan() || $y->is_nan())   ||
       ($x->is_zero() && $y->is_zero()));
 
  # +-inf / +-inf == NaN, remainder also NaN
  if (($x->{sign} =~ /^[+-]inf$/) && ($y->{sign} =~ /^[+-]inf$/))
    {
    return wantarray ? ($x->bnan(),$self->bnan()) : $x->bnan();
    }
  # x / +-inf => 0, remainder x (works even if x == 0)
  if ($y->{sign} =~ /^[+-]inf$/)
    {
    my $t = $x->copy();		# bzero clobbers up $x
    return wantarray ? ($x->bzero(),$t) : $x->bzero()
    }
  
  # 5 / 0 => +inf, -6 / 0 => -inf
  # +inf / 0 = inf, inf,  and -inf / 0 => -inf, -inf 
  # exception:   -8 / 0 has remainder -8, not 8
  # exception: -inf / 0 has remainder -inf, not inf
  if ($y->is_zero())
    {
    # +-inf / 0 => special case for -inf
    return wantarray ?  ($x,$x->copy()) : $x if $x->is_inf();
    if (!$x->is_zero() && !$x->is_inf())
      {
      my $t = $x->copy();		# binf clobbers up $x
      return wantarray ?
       ($x->binf($x->{sign}),$t) : $x->binf($x->{sign})
      }
    }
  
  # last case: +-inf / ordinary number
  my $sign = '+inf';
  $sign = '-inf' if substr($x->{sign},0,1) ne $y->{sign};
  $x->{sign} = $sign;
  return wantarray ? ($x,$self->bzero()) : $x;
  }

sub bdiv 
  {
  # (dividend: BINT or num_str, divisor: BINT or num_str) return 
  # (BINT,BINT) (quo,rem) or BINT (only rem)
  
  # set up parameters
  my ($self,$x,$y,@r) = (ref($_[0]),@_);
  # objectify is costly, so avoid it 
  if ((!ref($_[0])) || (ref($_[0]) ne ref($_[1])))
    {
    ($self,$x,$y,@r) = objectify(2,@_);
    } 

  return $x if $x->modify('bdiv');

  return $self->_div_inf($x,$y)
   if (($x->{sign} !~ /^[+-]$/) || ($y->{sign} !~ /^[+-]$/) || $y->is_zero());

  return $upgrade->bdiv($upgrade->new($x),$upgrade->new($y),@r)
   if defined $upgrade;
   
  $r[3] = $y;					# no push!

  # calc new sign and in case $y == +/- 1, return $x
  my $xsign = $x->{sign};				# keep
  $x->{sign} = ($x->{sign} ne $y->{sign} ? '-' : '+'); 

  if (wantarray)
    {
    my $rem = $self->bzero(); 
    ($x->{value},$rem->{value}) = $CALC->_div($x->{value},$y->{value});
    $x->{sign} = '+' if $CALC->_is_zero($x->{value});
    $rem->{_a} = $x->{_a};
    $rem->{_p} = $x->{_p};
    $x->round(@r);
    if (! $CALC->_is_zero($rem->{value}))
      {
      $rem->{sign} = $y->{sign};
      $rem = $y->copy()->bsub($rem) if $xsign ne $y->{sign}; # one of them '-'
      }
    else
      {
      $rem->{sign} = '+';			# do not leave -0
      }
    $rem->round(@r);
    return ($x,$rem);
    }

  $x->{value} = $CALC->_div($x->{value},$y->{value});
  $x->{sign} = '+' if $CALC->_is_zero($x->{value});

  $x->round(@r);
  }


sub bmod 
  {
  # modulus (or remainder)
  # (BINT or num_str, BINT or num_str) return BINT
  
  # set up parameters
  my ($self,$x,$y,@r) = (ref($_[0]),@_);
  # objectify is costly, so avoid it
  if ((!ref($_[0])) || (ref($_[0]) ne ref($_[1])))
    {
    ($self,$x,$y,@r) = objectify(2,@_);
    }

  return $x if $x->modify('bmod');
  $r[3] = $y;					# no push!
  if (($x->{sign} !~ /^[+-]$/) || ($y->{sign} !~ /^[+-]$/) || $y->is_zero())
    {
    my ($d,$r) = $self->_div_inf($x,$y);
    $x->{sign} = $r->{sign};
    $x->{value} = $r->{value};
    return $x->round(@r);
    }

  # calc new sign and in case $y == +/- 1, return $x
  $x->{value} = $CALC->_mod($x->{value},$y->{value});
  if (!$CALC->_is_zero($x->{value}))
    {
    $x->{value} = $CALC->_sub($y->{value},$x->{value},1) 	# $y-$x
      if ($x->{sign} ne $y->{sign});
    $x->{sign} = $y->{sign};
    }
   else
    {
    $x->{sign} = '+';				# do not leave -0
    }
  $x->round(@r);
  }

sub bmodinv
  {
  # Return modular multiplicative inverse: z is the modular inverse of x (mod
  # y) if and only if x*z (mod y) = 1 (mod y). If the modulus y is larger than
  # one, x and z are relative primes (i.e., their greatest common divisor is
  # one).
  #
  # If no modular multiplicative inverse exists, NaN is returned.

  # set up parameters
  my ($self,$x,$y,@r) = (undef,@_);
  # objectify is costly, so avoid it
  if ((!ref($_[0])) || (ref($_[0]) ne ref($_[1])))
    {
    ($self,$x,$y,@r) = objectify(2,@_);
    }

  return $x if $x->modify('bmodinv');

  # Return NaN if one or both arguments is +inf, -inf, or nan.

  return $x->bnan() if ($y->{sign} !~ /^[+-]$/ ||
                        $x->{sign} !~ /^[+-]$/);

  # Return NaN if $y is zero; 1 % 0 makes no sense.

  return $x->bnan() if $y->is_zero();

  # Return 0 in the trivial case. $x % 1 or $x % -1 is zero for all finite
  # integers $x.

  return $x->bzero() if ($y->is_one() ||
                         $y->is_one('-'));

  # Return NaN if $x = 0, or $x modulo $y is zero. The only valid case when
  # $x = 0 is when $y = 1 or $y = -1, but that was covered above.
  #
  # Note that computing $x modulo $y here affects the value we'll feed to
  # $CALC->_modinv() below when $x and $y have opposite signs. E.g., if $x =
  # 5 and $y = 7, those two values are fed to _modinv(), but if $x = -5 and
  # $y = 7, the values fed to _modinv() are $x = 2 (= -5 % 7) and $y = 7.
  # The value if $x is affected only when $x and $y have opposite signs.

  $x->bmod($y);
  return $x->bnan() if $x->is_zero();

  # Compute the modular multiplicative inverse of the absolute values. We'll
  # correct for the signs of $x and $y later. Return NaN if no GCD is found.

  ($x->{value}, $x->{sign}) = $CALC->_modinv($x->{value}, $y->{value});
  return $x->bnan() if !defined $x->{value};

  # Library inconsistency workaround: _modinv() in Math::BigInt::GMP versions
  # <= 1.32 return undef rather than a "+" for the sign.

  $x->{sign} = '+' unless defined $x->{sign};

  # When one or both arguments are negative, we have the following
  # relations.  If x and y are positive:
  #
  #   modinv(-x, -y) = -modinv(x, y)
  #   modinv(-x,  y) = y - modinv(x, y)  = -modinv(x, y) (mod y)
  #   modinv( x, -y) = modinv(x, y) - y  =  modinv(x, y) (mod -y)

  # We must swap the sign of the result if the original $x is negative.
  # However, we must compensate for ignoring the signs when computing the
  # inverse modulo. The net effect is that we must swap the sign of the
  # result if $y is negative.

  $x -> bneg() if $y->{sign} eq '-';

  # Compute $x modulo $y again after correcting the sign.

  $x -> bmod($y) if $x->{sign} ne $y->{sign};

  return $x;
  }

sub bmodpow
  {
  # Modular exponentiation. Raises a very large number to a very large exponent
  # in a given very large modulus quickly, thanks to binary exponentiation.
  # Supports negative exponents.
  my ($self,$num,$exp,$mod,@r) = objectify(3,@_);

  return $num if $num->modify('bmodpow');

  # When the exponent 'e' is negative, use the following relation, which is
  # based on finding the multiplicative inverse 'd' of 'b' modulo 'm':
  #
  #    b^(-e) (mod m) = d^e (mod m) where b*d = 1 (mod m)

  $num->bmodinv($mod) if ($exp->{sign} eq '-');

  # Check for valid input. All operands must be finite, and the modulus must be
  # non-zero.

  return $num->bnan() if ($num->{sign} =~ /NaN|inf/ ||  # NaN, -inf, +inf
                          $exp->{sign} =~ /NaN|inf/ ||  # NaN, -inf, +inf
                          $mod->{sign} =~ /NaN|inf/ ||  # NaN, -inf, +inf
                          $mod->is_zero());

  # Compute 'a (mod m)', ignoring the signs on 'a' and 'm'. If the resulting
  # value is zero, the output is also zero, regardless of the signs on 'a' and
  # 'm'.

  my $value = $CALC->_modpow($num->{value}, $exp->{value}, $mod->{value});
  my $sign  = '+';

  # If the resulting value is non-zero, we have four special cases, depending
  # on the signs on 'a' and 'm'.

  unless ($CALC->_is_zero($value)) {

      # There is a negative sign on 'a' (= $num**$exp) only if the number we
      # are exponentiating ($num) is negative and the exponent ($exp) is odd.

      if ($num->{sign} eq '-' && $exp->is_odd()) {

          # When both the number 'a' and the modulus 'm' have a negative sign,
          # use this relation:
          #
          #    -a (mod -m) = -(a (mod m))

          if ($mod->{sign} eq '-') {
              $sign = '-';
          }

          # When only the number 'a' has a negative sign, use this relation:
          #
          #    -a (mod m) = m - (a (mod m))

          else {
              # Use copy of $mod since _sub() modifies the first argument.
              my $mod = $CALC->_copy($mod->{value});
              $value = $CALC->_sub($mod, $value);
              $sign  = '+';
          }

      } else {

          # When only the modulus 'm' has a negative sign, use this relation:
          #
          #    a (mod -m) = (a (mod m)) - m
          #               = -(m - (a (mod m)))

          if ($mod->{sign} eq '-') {
              # Use copy of $mod since _sub() modifies the first argument.
              my $mod = $CALC->_copy($mod->{value});
              $value = $CALC->_sub($mod, $value);
              $sign  = '-';
          }

          # When neither the number 'a' nor the modulus 'm' have a negative
          # sign, directly return the already computed value.
          #
          #    (a (mod m))

      }

  }

  $num->{value} = $value;
  $num->{sign}  = $sign;

  return $num;
  }


sub bfac
  {
  # (BINT or num_str, BINT or num_str) return BINT
  # compute factorial number from $x, modify $x in place
  my ($self,$x,@r) = ref($_[0]) ? (undef,@_) : objectify(1,@_);

  return $x if $x->modify('bfac') || $x->{sign} eq '+inf';	# inf => inf
  return $x->bnan() if $x->{sign} ne '+';			# NaN, <0 etc => NaN

  $x->{value} = $CALC->_fac($x->{value});
  $x->round(@r);
  }
 
sub bpow 
  {
  # (BINT or num_str, BINT or num_str) return BINT
  # compute power of two numbers -- stolen from Knuth Vol 2 pg 233
  # modifies first argument

  # set up parameters
  my ($self,$x,$y,@r) = (ref($_[0]),@_);
  # objectify is costly, so avoid it
  if ((!ref($_[0])) || (ref($_[0]) ne ref($_[1])))
    {
    ($self,$x,$y,@r) = objectify(2,@_);
    }

  return $x if $x->modify('bpow');

  return $x->bnan() if $x->{sign} eq $nan || $y->{sign} eq $nan;

  # inf handling
  if (($x->{sign} =~ /^[+-]inf$/) || ($y->{sign} =~ /^[+-]inf$/))
    {
    if (($x->{sign} =~ /^[+-]inf$/) && ($y->{sign} =~ /^[+-]inf$/))
      {
      # +-inf ** +-inf
      return $x->bnan();
      }
    # +-inf ** Y
    if ($x->{sign} =~ /^[+-]inf/)
      {
      # +inf ** 0 => NaN
      return $x->bnan() if $y->is_zero();
      # -inf ** -1 => 1/inf => 0
      return $x->bzero() if $y->is_one('-') && $x->is_negative();

      # +inf ** Y => inf
      return $x if $x->{sign} eq '+inf';

      # -inf ** Y => -inf if Y is odd
      return $x if $y->is_odd();
      return $x->babs();
      }
    # X ** +-inf

    # 1 ** +inf => 1
    return $x if $x->is_one();
    
    # 0 ** inf => 0
    return $x if $x->is_zero() && $y->{sign} =~ /^[+]/;

    # 0 ** -inf => inf
    return $x->binf() if $x->is_zero();

    # -1 ** -inf => NaN
    return $x->bnan() if $x->is_one('-') && $y->{sign} =~ /^[-]/;

    # -X ** -inf => 0
    return $x->bzero() if $x->{sign} eq '-' && $y->{sign} =~ /^[-]/;

    # -1 ** inf => NaN
    return $x->bnan() if $x->{sign} eq '-';

    # X ** inf => inf
    return $x->binf() if $y->{sign} =~ /^[+]/;
    # X ** -inf => 0
    return $x->bzero();
    }

  return $upgrade->bpow($upgrade->new($x),$y,@r)
   if defined $upgrade && (!$y->isa($self) || $y->{sign} eq '-');

  $r[3] = $y;					# no push!

  # cases 0 ** Y, X ** 0, X ** 1, 1 ** Y are handled by Calc or Emu

  my $new_sign = '+';
  $new_sign = $y->is_odd() ? '-' : '+' if ($x->{sign} ne '+'); 

  # 0 ** -7 => ( 1 / (0 ** 7)) => 1 / 0 => +inf 
  return $x->binf() 
    if $y->{sign} eq '-' && $x->{sign} eq '+' && $CALC->_is_zero($x->{value});
  # 1 ** -y => 1 / (1 ** |y|)
  # so do test for negative $y after above's clause
  return $x->bnan() if $y->{sign} eq '-' && !$CALC->_is_one($x->{value});

  $x->{value} = $CALC->_pow($x->{value},$y->{value});
  $x->{sign} = $new_sign;
  $x->{sign} = '+' if $CALC->_is_zero($y->{value});
  $x->round(@r);
  }

sub blsft 
  {
  # (BINT or num_str, BINT or num_str) return BINT
  # compute x << y, base n, y >= 0
 
  # set up parameters
  my ($self,$x,$y,$n,@r) = (ref($_[0]),@_);
  # objectify is costly, so avoid it
  if ((!ref($_[0])) || (ref($_[0]) ne ref($_[1])))
    {
    ($self,$x,$y,$n,@r) = objectify(2,@_);
    }

  return $x if $x->modify('blsft');
  return $x->bnan() if ($x->{sign} !~ /^[+-]$/ || $y->{sign} !~ /^[+-]$/);
  return $x->round(@r) if $y->is_zero();

  $n = 2 if !defined $n; return $x->bnan() if $n <= 0 || $y->{sign} eq '-';

  $x->{value} = $CALC->_lsft($x->{value},$y->{value},$n);
  $x->round(@r);
  }

sub brsft 
  {
  # (BINT or num_str, BINT or num_str) return BINT
  # compute x >> y, base n, y >= 0
  
  # set up parameters
  my ($self,$x,$y,$n,@r) = (ref($_[0]),@_);
  # objectify is costly, so avoid it
  if ((!ref($_[0])) || (ref($_[0]) ne ref($_[1])))
    {
    ($self,$x,$y,$n,@r) = objectify(2,@_);
    }

  return $x if $x->modify('brsft');
  return $x->bnan() if ($x->{sign} !~ /^[+-]$/ || $y->{sign} !~ /^[+-]$/);
  return $x->round(@r) if $y->is_zero();
  return $x->bzero(@r) if $x->is_zero();		# 0 => 0

  $n = 2 if !defined $n; return $x->bnan() if $n <= 0 || $y->{sign} eq '-';

   # this only works for negative numbers when shifting in base 2
  if (($x->{sign} eq '-') && ($n == 2))
    {
    return $x->round(@r) if $x->is_one('-');	# -1 => -1
    if (!$y->is_one())
      {
      # although this is O(N*N) in calc (as_bin!) it is O(N) in Pari et al
      # but perhaps there is a better emulation for two's complement shift...
      # if $y != 1, we must simulate it by doing:
      # convert to bin, flip all bits, shift, and be done
      $x->binc();			# -3 => -2
      my $bin = $x->as_bin();
      $bin =~ s/^-0b//;			# strip '-0b' prefix
      $bin =~ tr/10/01/;		# flip bits
      # now shift
      if ($y >= CORE::length($bin))
        {
	$bin = '0'; 			# shifting to far right creates -1
					# 0, because later increment makes 
					# that 1, attached '-' makes it '-1'
					# because -1 >> x == -1 !
        } 
      else
	{
	$bin =~ s/.{$y}$//;		# cut off at the right side
        $bin = '1' . $bin;		# extend left side by one dummy '1'
        $bin =~ tr/10/01/;		# flip bits back
	}
      my $res = $self->new('0b'.$bin);	# add prefix and convert back
      $res->binc();			# remember to increment
      $x->{value} = $res->{value};	# take over value
      return $x->round(@r);		# we are done now, magic, isn't?
      }
    # x < 0, n == 2, y == 1
    $x->bdec();				# n == 2, but $y == 1: this fixes it
    }

  $x->{value} = $CALC->_rsft($x->{value},$y->{value},$n);
  $x->round(@r);
  }

sub band 
  {
  #(BINT or num_str, BINT or num_str) return BINT
  # compute x & y
 
  # set up parameters
  my ($self,$x,$y,@r) = (ref($_[0]),@_);
  # objectify is costly, so avoid it
  if ((!ref($_[0])) || (ref($_[0]) ne ref($_[1])))
    {
    ($self,$x,$y,@r) = objectify(2,@_);
    }
  
  return $x if $x->modify('band');

  $r[3] = $y;				# no push!

  return $x->bnan() if ($x->{sign} !~ /^[+-]$/ || $y->{sign} !~ /^[+-]$/);

  my $sx = $x->{sign} eq '+' ? 1 : -1;
  my $sy = $y->{sign} eq '+' ? 1 : -1;
  
  if ($sx == 1 && $sy == 1)
    {
    $x->{value} = $CALC->_and($x->{value},$y->{value});
    return $x->round(@r);
    }
  
  if ($CAN{signed_and})
    {
    $x->{value} = $CALC->_signed_and($x->{value},$y->{value},$sx,$sy);
    return $x->round(@r);
    }
 
  require $EMU_LIB;
  __emu_band($self,$x,$y,$sx,$sy,@r);
  }

sub bior 
  {
  #(BINT or num_str, BINT or num_str) return BINT
  # compute x | y
  
  # set up parameters
  my ($self,$x,$y,@r) = (ref($_[0]),@_);
  # objectify is costly, so avoid it
  if ((!ref($_[0])) || (ref($_[0]) ne ref($_[1])))
    {
    ($self,$x,$y,@r) = objectify(2,@_);
    }

  return $x if $x->modify('bior');
  $r[3] = $y;				# no push!

  return $x->bnan() if ($x->{sign} !~ /^[+-]$/ || $y->{sign} !~ /^[+-]$/);

  my $sx = $x->{sign} eq '+' ? 1 : -1;
  my $sy = $y->{sign} eq '+' ? 1 : -1;

  # the sign of X follows the sign of X, e.g. sign of Y irrelevant for bior()
  
  # don't use lib for negative values
  if ($sx == 1 && $sy == 1)
    {
    $x->{value} = $CALC->_or($x->{value},$y->{value});
    return $x->round(@r);
    }

  # if lib can do negative values, let it handle this
  if ($CAN{signed_or})
    {
    $x->{value} = $CALC->_signed_or($x->{value},$y->{value},$sx,$sy);
    return $x->round(@r);
    }

  require $EMU_LIB;
  __emu_bior($self,$x,$y,$sx,$sy,@r);
  }

sub bxor 
  {
  #(BINT or num_str, BINT or num_str) return BINT
  # compute x ^ y
  
  # set up parameters
  my ($self,$x,$y,@r) = (ref($_[0]),@_);
  # objectify is costly, so avoid it
  if ((!ref($_[0])) || (ref($_[0]) ne ref($_[1])))
    {
    ($self,$x,$y,@r) = objectify(2,@_);
    }

  return $x if $x->modify('bxor');
  $r[3] = $y;				# no push!

  return $x->bnan() if ($x->{sign} !~ /^[+-]$/ || $y->{sign} !~ /^[+-]$/);
  
  my $sx = $x->{sign} eq '+' ? 1 : -1;
  my $sy = $y->{sign} eq '+' ? 1 : -1;

  # don't use lib for negative values
  if ($sx == 1 && $sy == 1)
    {
    $x->{value} = $CALC->_xor($x->{value},$y->{value});
    return $x->round(@r);
    }
  
  # if lib can do negative values, let it handle this
  if ($CAN{signed_xor})
    {
    $x->{value} = $CALC->_signed_xor($x->{value},$y->{value},$sx,$sy);
    return $x->round(@r);
    }

  require $EMU_LIB;
  __emu_bxor($self,$x,$y,$sx,$sy,@r);
  }

sub length
  {
  my ($self,$x) = ref($_[0]) ? (undef,$_[0]) : objectify(1,@_);

  my $e = $CALC->_len($x->{value}); 
  wantarray ? ($e,0) : $e;
  }

sub digit
  {
  # return the nth decimal digit, negative values count backward, 0 is right
  my ($self,$x,$n) = ref($_[0]) ? (undef,@_) : objectify(1,@_);

  $n = $n->numify() if ref($n);
  $CALC->_digit($x->{value},$n||0);
  }

sub _trailing_zeros
  {
  # return the amount of trailing zeros in $x (as scalar)
  my $x = shift;
  $x = $class->new($x) unless ref $x;

  return 0 if $x->{sign} !~ /^[+-]$/;	# NaN, inf, -inf etc

  $CALC->_zeros($x->{value});		# must handle odd values, 0 etc
  }

sub bsqrt
  {
  # calculate square root of $x
  my ($self,$x,@r) = ref($_[0]) ? (undef,@_) : objectify(1,@_);

  return $x if $x->modify('bsqrt');

  return $x->bnan() if $x->{sign} !~ /^\+/;	# -x or -inf or NaN => NaN
  return $x if $x->{sign} eq '+inf';		# sqrt(+inf) == inf

  return $upgrade->bsqrt($x,@r) if defined $upgrade;

  $x->{value} = $CALC->_sqrt($x->{value});
  $x->round(@r);
  }

sub broot
  {
  # calculate $y'th root of $x
 
  # set up parameters
  my ($self,$x,$y,@r) = (ref($_[0]),@_);

  $y = $self->new(2) unless defined $y;

  # objectify is costly, so avoid it
  if ((!ref($x)) || (ref($x) ne ref($y)))
    {
    ($self,$x,$y,@r) = objectify(2,$self || $class,@_);
    }

  return $x if $x->modify('broot');

  # NaN handling: $x ** 1/0, x or y NaN, or y inf/-inf or y == 0
  return $x->bnan() if $x->{sign} !~ /^\+/ || $y->is_zero() ||
         $y->{sign} !~ /^\+$/;

  return $x->round(@r)
    if $x->is_zero() || $x->is_one() || $x->is_inf() || $y->is_one();

  return $upgrade->new($x)->broot($upgrade->new($y),@r) if defined $upgrade;

  $x->{value} = $CALC->_root($x->{value},$y->{value});
  $x->round(@r);
  }

sub exponent
  {
  # return a copy of the exponent (here always 0, NaN or 1 for $m == 0)
  my ($self,$x) = ref($_[0]) ? (ref($_[0]),$_[0]) : objectify(1,@_);
 
  if ($x->{sign} !~ /^[+-]$/)
    {
    my $s = $x->{sign}; $s =~ s/^[+-]//;  # NaN, -inf,+inf => NaN or inf
    return $self->new($s);
    }
  return $self->bone() if $x->is_zero();

  # 12300 => 2 trailing zeros => exponent is 2
  $self->new( $CALC->_zeros($x->{value}) );
  }

sub mantissa
  {
  # return the mantissa (compatible to Math::BigFloat, e.g. reduced)
  my ($self,$x) = ref($_[0]) ? (ref($_[0]),$_[0]) : objectify(1,@_);

  if ($x->{sign} !~ /^[+-]$/)
    {
    # for NaN, +inf, -inf: keep the sign
    return $self->new($x->{sign});
    }
  my $m = $x->copy(); delete $m->{_p}; delete $m->{_a};

  # that's a bit inefficient:
  my $zeros = $CALC->_zeros($m->{value});
  $m->brsft($zeros,10) if $zeros != 0;
  $m;
  }

sub parts
  {
  # return a copy of both the exponent and the mantissa
  my ($self,$x) = ref($_[0]) ? (undef,$_[0]) : objectify(1,@_);

  ($x->mantissa(),$x->exponent());
  }
   

sub bfround
  {
  # precision: round to the $Nth digit left (+$n) or right (-$n) from the '.'
  # $n == 0 || $n == 1 => round to integer
  my $x = shift; my $self = ref($x) || $x; $x = $self->new($x) unless ref $x;

  my ($scale,$mode) = $x->_scale_p(@_);

  return $x if !defined $scale || $x->modify('bfround');	# no-op

  # no-op for BigInts if $n <= 0
  $x->bround( $x->length()-$scale, $mode) if $scale > 0;

  delete $x->{_a};	# delete to save memory
  $x->{_p} = $scale;	# store new _p
  $x;
  }

sub _scan_for_nonzero
  {
  # internal, used by bround() to scan for non-zeros after a '5'
  my ($x,$pad,$xs,$len) = @_;
 
  return 0 if $len == 1;		# "5" is trailed by invisible zeros
  my $follow = $pad - 1;
  return 0 if $follow > $len || $follow < 1;

  # use the string form to check whether only '0's follow or not
  substr ($xs,-$follow) =~ /[^0]/ ? 1 : 0;
  }

sub fround
  {
  # Exists to make life easier for switch between MBF and MBI (should we
  # autoload fxxx() like MBF does for bxxx()?)
  my $x = shift; $x = $class->new($x) unless ref $x;
  $x->bround(@_);
  }

sub bround
  {
  # accuracy: +$n preserve $n digits from left,
  #           -$n preserve $n digits from right (f.i. for 0.1234 style in MBF)
  # no-op for $n == 0
  # and overwrite the rest with 0's, return normalized number
  # do not return $x->bnorm(), but $x

  my $x = shift; $x = $class->new($x) unless ref $x;
  my ($scale,$mode) = $x->_scale_a(@_);
  return $x if !defined $scale || $x->modify('bround');	# no-op
  
  if ($x->is_zero() || $scale == 0)
    {
    $x->{_a} = $scale if !defined $x->{_a} || $x->{_a} > $scale; # 3 > 2
    return $x;
    }
  return $x if $x->{sign} !~ /^[+-]$/;		# inf, NaN

  # we have fewer digits than we want to scale to
  my $len = $x->length();
  # convert $scale to a scalar in case it is an object (put's a limit on the
  # number length, but this would already limited by memory constraints), makes
  # it faster
  $scale = $scale->numify() if ref ($scale);

  # scale < 0, but > -len (not >=!)
  if (($scale < 0 && $scale < -$len-1) || ($scale >= $len))
    {
    $x->{_a} = $scale if !defined $x->{_a} || $x->{_a} > $scale; # 3 > 2
    return $x; 
    }
   
  # count of 0's to pad, from left (+) or right (-): 9 - +6 => 3, or |-6| => 6
  my ($pad,$digit_round,$digit_after);
  $pad = $len - $scale;
  $pad = abs($scale-1) if $scale < 0;

  # do not use digit(), it is very costly for binary => decimal
  # getting the entire string is also costly, but we need to do it only once
  my $xs = $CALC->_str($x->{value});
  my $pl = -$pad-1;

  # pad:   123: 0 => -1, at 1 => -2, at 2 => -3, at 3 => -4
  # pad+1: 123: 0 => 0,  at 1 => -1, at 2 => -2, at 3 => -3
  $digit_round = '0'; $digit_round = substr($xs,$pl,1) if $pad <= $len;
  $pl++; $pl ++ if $pad >= $len;
  $digit_after = '0'; $digit_after = substr($xs,$pl,1) if $pad > 0;

  # in case of 01234 we round down, for 6789 up, and only in case 5 we look
  # closer at the remaining digits of the original $x, remember decision
  my $round_up = 1;					# default round up
  $round_up -- if
    ($mode eq 'trunc')				||	# trunc by round down
    ($digit_after =~ /[01234]/)			|| 	# round down anyway,
							# 6789 => round up
    ($digit_after eq '5')			&&	# not 5000...0000
    ($x->_scan_for_nonzero($pad,$xs,$len) == 0)		&&
    (
     ($mode eq 'even') && ($digit_round =~ /[24680]/) ||
     ($mode eq 'odd')  && ($digit_round =~ /[13579]/) ||
     ($mode eq '+inf') && ($x->{sign} eq '-')   ||
     ($mode eq '-inf') && ($x->{sign} eq '+')   ||
     ($mode eq 'zero')		# round down if zero, sign adjusted below
    );
  my $put_back = 0;					# not yet modified
	
  if (($pad > 0) && ($pad <= $len))
    {
    substr($xs,-$pad,$pad) = '0' x $pad;		# replace with '00...'
    $put_back = 1;					# need to put back
    }
  elsif ($pad > $len)
    {
    $x->bzero();					# round to '0'
    }

  if ($round_up)					# what gave test above?
    {
    $put_back = 1;					# need to put back
    $pad = $len, $xs = '0' x $pad if $scale < 0;	# tlr: whack 0.51=>1.0	

    # we modify directly the string variant instead of creating a number and
    # adding it, since that is faster (we already have the string)
    my $c = 0; $pad ++;				# for $pad == $len case
    while ($pad <= $len)
      {
      $c = substr($xs,-$pad,1) + 1; $c = '0' if $c eq '10';
      substr($xs,-$pad,1) = $c; $pad++;
      last if $c != 0;				# no overflow => early out
      }
    $xs = '1'.$xs if $c == 0;

    }
  $x->{value} = $CALC->_new($xs) if $put_back == 1;	# put back, if needed

  $x->{_a} = $scale if $scale >= 0;
  if ($scale < 0)
    {
    $x->{_a} = $len+$scale;
    $x->{_a} = 0 if $scale < -$len;
    }
  $x;
  }

sub bfloor
  {
  # round towards minus infinity; no-op since it's already integer
  my ($self,$x,@r) = ref($_[0]) ? (undef,@_) : objectify(1,@_);

  $x->round(@r);
  }

sub bceil
  {
  # round towards plus infinity; no-op since it's already int
  my ($self,$x,@r) = ref($_[0]) ? (undef,@_) : objectify(1,@_);

  $x->round(@r);
  }

sub bint {
    # round towards zero; no-op since it's already integer
    my ($self,$x,@r) = ref($_[0]) ? (undef,@_) : objectify(1,@_);

    $x->round(@r);
}

sub as_number
  {
  # An object might be asked to return itself as bigint on certain overloaded
  # operations. This does exactly this, so that sub classes can simple inherit
  # it or override with their own integer conversion routine.
  $_[0]->copy();
  }

sub as_hex
  {
  # return as hex string, with prefixed 0x
  my $x = shift; $x = $class->new($x) if !ref($x);

  return $x->bstr() if $x->{sign} !~ /^[+-]$/;	# inf, nan etc

  my $s = '';
  $s = $x->{sign} if $x->{sign} eq '-';
  $s . $CALC->_as_hex($x->{value});
  }

sub as_bin
  {
  # return as binary string, with prefixed 0b
  my $x = shift; $x = $class->new($x) if !ref($x);

  return $x->bstr() if $x->{sign} !~ /^[+-]$/;	# inf, nan etc

  my $s = ''; $s = $x->{sign} if $x->{sign} eq '-';
  return $s . $CALC->_as_bin($x->{value});
  }

sub as_oct
  {
  # return as octal string, with prefixed 0
  my $x = shift; $x = $class->new($x) if !ref($x);

  return $x->bstr() if $x->{sign} !~ /^[+-]$/;	# inf, nan etc

  my $s = ''; $s = $x->{sign} if $x->{sign} eq '-';
  return $s . $CALC->_as_oct($x->{value});
  }


sub objectify {
    # Convert strings and "foreign objects" to the objects we want.

    # The first argument, $count, is the number of following arguments that
    # objectify() looks at and converts to objects. The first is a classname.
    # If the given count is 0, all arguments will be used.

    # After the count is read, objectify obtains the name of the class to which
    # the following arguments are converted. If the second argument is a
    # reference, use the reference type as the class name. Otherwise, if it is
    # a string that looks like a class name, use that. Otherwise, use $class.

    # Caller:                        Gives us:
    #
    # $x->badd(1);                => ref x, scalar y
    # Class->badd(1,2);           => classname x (scalar), scalar x, scalar y
    # Class->badd(Class->(1),2);  => classname x (scalar), ref x, scalar y
    # Math::BigInt::badd(1,2);    => scalar x, scalar y

    # A shortcut for the common case $x->unary_op():

    return (ref($_[1]), $_[1]) if (@_ == 2) && ($_[0]||0 == 1) && ref($_[1]);

    # Check the context.

    unless (wantarray) {
        require Carp;
        Carp::croak ("${class}::objectify() needs list context");
    }

    # Get the number of arguments to objectify.

    my $count = shift;
    $count ||= @_;

    # Initialize the output array.

    my @a = @_;

    # If the first argument is a reference, use that reference type as our
    # class name. Otherwise, if the first argument looks like a class name,
    # then use that as our class name. Otherwise, use the default class name.

    {
        if (ref($a[0])) {               # reference?
            unshift @a, ref($a[0]);
            last;
        }
        if ($a[0] =~ /^[A-Z].*::/) {    # string with class name?
            last;
        }
        unshift @a, $class;             # default class name
    }

    no strict 'refs';

    # What we upgrade to, if anything.

    my $up = ${"$a[0]::upgrade"};

    # Disable downgrading, because Math::BigFloat -> foo('1.0','2.0') needs
    # floats.

    my $down;
    if (defined ${"$a[0]::downgrade"}) {
        $down = ${"$a[0]::downgrade"};
        ${"$a[0]::downgrade"} = undef;
    }

    for my $i (1 .. $count) {
        my $ref = ref $a[$i];

        # If it is an object of the right class, all is fine.

        if ($ref eq $a[0]) {
            next;
        }

        # Don't do anything with undefs.

        unless (defined($a[$i])) {
            next;
        }

        # Perl scalars are fed to the appropriate constructor.

        unless ($ref) {
            $a[$i] = $a[0] -> new($a[$i]);
            next;
        }

        # Upgrading is OK, so skip further tests if the argument is upgraded.

        if (defined $up && $ref eq $up) {
            next;
        }

        # If we want a Math::BigInt, see if the object can become one.
        # Support the old misnomer as_number().

        if ($a[0] eq 'Math::BigInt') {
            if ($a[$i] -> can('as_int')) {
                $a[$i] = $a[$i] -> as_int();
                next;
            }
            if ($a[$i] -> can('as_number')) {
                $a[$i] = $a[$i] -> as_number();
                next;
            }
        }

        # If we want a Math::BigFloat, see if the object can become one.

        if ($a[0] eq 'Math::BigFloat') {
            if ($a[$i] -> can('as_float')) {
                $a[$i] = $a[$i] -> as_float();
                next;
            }
        }

        # Last resort.

        $a[$i] = $a[0] -> new($a[$i]);
    }

    # Reset the downgrading.

    ${"$a[0]::downgrade"} = $down;

    return @a;
}

sub _register_callback
  {
  my ($class,$callback) = @_;

  if (ref($callback) ne 'CODE')
    { 
    require Carp;
    Carp::croak ("$callback is not a coderef");
    }
  $CALLBACKS{$class} = $callback;
  }

sub import 
  {
  my $self = shift;

  $IMPORT++;				# remember we did import()
  my @a; my $l = scalar @_;
  my $warn_or_die = 0;			# 0 - no warn, 1 - warn, 2 - die
  for ( my $i = 0; $i < $l ; $i++ )
    {
    if ($_[$i] eq ':constant')
      {
      # this causes overlord er load to step in
      overload::constant 
	integer => sub { $self->new(shift) },
      	binary => sub { $self->new(shift) };
      }
    elsif ($_[$i] eq 'upgrade')
      {
      # this causes upgrading
      $upgrade = $_[$i+1];		# or undef to disable
      $i++;
      }
    elsif ($_[$i] =~ /^(lib|try|only)\z/)
      {
      # this causes a different low lib to take care...
      $CALC = $_[$i+1] || '';
      # lib => 1 (warn on fallback), try => 0 (no warn), only => 2 (die on fallback)
      $warn_or_die = 1 if $_[$i] eq 'lib';
      $warn_or_die = 2 if $_[$i] eq 'only';
      $i++;
      }
    else
      {
      push @a, $_[$i];
      }
    }
  # any non :constant stuff is handled by our parent, Exporter
  if (@a > 0)
    {
    require Exporter;
 
    $self->SUPER::import(@a);			# need it for subclasses
    $self->export_to_level(1,$self,@a);		# need it for MBF
    }

  # try to load core math lib
  my @c = split /\s*,\s*/,$CALC;
  foreach (@c)
    {
    $_ =~ tr/a-zA-Z0-9://cd;			# limit to sane characters
    }
  push @c, \'Calc'				# if all fail, try these
    if $warn_or_die < 2;			# but not for "only"
  $CALC = '';					# signal error
  foreach my $l (@c)
    {
    # fallback libraries are "marked" as \'string', extract string if nec.
    my $lib = $l; $lib = $$l if ref($l);

    next if ($lib || '') eq '';
    $lib = 'Math::BigInt::'.$lib if $lib !~ /^Math::BigInt/i;
    $lib =~ s/\.pm$//;
    if ($] < 5.006)
      {
      # Perl < 5.6.0 dies with "out of memory!" when eval("") and ':constant' is
      # used in the same script, or eval("") inside import().
      my @parts = split /::/, $lib;             # Math::BigInt => Math BigInt
      my $file = pop @parts; $file .= '.pm';    # BigInt => BigInt.pm
      require File::Spec;
      $file = File::Spec->catfile (@parts, $file);
      eval { require "$file"; $lib->import( @c ); }
      }
    else
      {
      eval "use $lib qw/@c/;";
      }
    if ($@ eq '')
      {
      my $ok = 1;
      # loaded it ok, see if the api_version() is high enough
      if ($lib->can('api_version') && $lib->api_version() >= 1.0)
	{
	$ok = 0;
	# api_version matches, check if it really provides anything we need
        for my $method (qw/
		one two ten
		str num
		add mul div sub dec inc
		acmp len digit is_one is_zero is_even is_odd
		is_two is_ten
		zeros new copy check
		from_hex from_oct from_bin as_hex as_bin as_oct
		rsft lsft xor and or
		mod sqrt root fac pow modinv modpow log_int gcd
	 /)
          {
	  if (!$lib->can("_$method"))
	    {
	    if (($WARN{$lib}||0) < 2)
	      {
	      require Carp;
	      Carp::carp ("$lib is missing method '_$method'");
	      $WARN{$lib} = 1;		# still warn about the lib
	      }
            $ok++; last; 
	    }
          }
	}
      if ($ok == 0)
	{
	$CALC = $lib;
	if ($warn_or_die > 0 && ref($l))
	  {
	  require Carp;
	  my $msg = "Math::BigInt: couldn't load specified math lib(s), fallback to $lib";
          Carp::carp ($msg) if $warn_or_die == 1;
          Carp::croak ($msg) if $warn_or_die == 2;
	  }
        last;			# found a usable one, break
	}
      else
	{
	if (($WARN{$lib}||0) < 2)
	  {
	  my $ver = eval "\$$lib\::VERSION" || 'unknown';
	  require Carp;
	  Carp::carp ("Cannot load outdated $lib v$ver, please upgrade");
	  $WARN{$lib} = 2;		# never warn again
	  }
        }
      }
    }
  if ($CALC eq '')
    {
    require Carp;
    if ($warn_or_die == 2)
      {
      Carp::croak ("Couldn't load specified math lib(s) and fallback disallowed");
      }
    else
      {
      Carp::croak ("Couldn't load any math lib(s), not even fallback to Calc.pm");
      }
    }

  # notify callbacks
  foreach my $class (keys %CALLBACKS)
    {
    &{$CALLBACKS{$class}}($CALC);
    }

  # Fill $CAN with the results of $CALC->can(...) for emulating lower math lib
  # functions

  %CAN = ();
  for my $method (qw/ signed_and signed_or signed_xor /)
    {
    $CAN{$method} = $CALC->can("_$method") ? 1 : 0;
    }

  # import done
  }

sub from_hex {
    # Create a bigint from a hexadecimal string.

    my ($self, $str) = @_;

    if ($str =~ s/
                     ^
                     ( [+-]? )
                     (0?x)?
                     (
                         [0-9a-fA-F]*
                         ( _ [0-9a-fA-F]+ )*
                     )
                     $
                 //x)
    {
        # Get a "clean" version of the string, i.e., non-emtpy and with no
        # underscores or invalid characters.

        my $sign = $1;
        my $chrs = $3;
        $chrs =~ tr/_//d;
        $chrs = '0' unless CORE::length $chrs;

        # Initialize output.

        my $x = Math::BigInt->bzero();

        # The library method requires a prefix.

        $x->{value} = $CALC->_from_hex('0x' . $chrs);

        # Place the sign.

        if ($sign eq '-' && ! $CALC->_is_zero($x->{value})) {
            $x->{sign} = '-';
        }

        return $x;
    }

    # CORE::hex() parses as much as it can, and ignores any trailing garbage.
    # For backwards compatibility, we return NaN.

    return $self->bnan();
}

sub from_oct {
    # Create a bigint from an octal string.

    my ($self, $str) = @_;

    if ($str =~ s/
                     ^
                     ( [+-]? )
                     (
                         [0-7]*
                         ( _ [0-7]+ )*
                     )
                     $
                 //x)
    {
        # Get a "clean" version of the string, i.e., non-emtpy and with no
        # underscores or invalid characters.

        my $sign = $1;
        my $chrs = $2;
        $chrs =~ tr/_//d;
        $chrs = '0' unless CORE::length $chrs;

        # Initialize output.

        my $x = Math::BigInt->bzero();

        # The library method requires a prefix.

        $x->{value} = $CALC->_from_oct('0' . $chrs);

        # Place the sign.

        if ($sign eq '-' && ! $CALC->_is_zero($x->{value})) {
            $x->{sign} = '-';
        }

        return $x;
    }

    # CORE::oct() parses as much as it can, and ignores any trailing garbage.
    # For backwards compatibility, we return NaN.

    return $self->bnan();
}

sub from_bin {
    # Create a bigint from a binary string.

    my ($self, $str) = @_;

    if ($str =~ s/
                     ^
                     ( [+-]? )
                     (0?b)?
                     (
                         [01]*
                         ( _ [01]+ )*
                     )
                     $
                 //x)
    {
        # Get a "clean" version of the string, i.e., non-emtpy and with no
        # underscores or invalid characters.

        my $sign = $1;
        my $chrs = $3;
        $chrs =~ tr/_//d;
        $chrs = '0' unless CORE::length $chrs;

        # Initialize output.

        my $x = Math::BigInt->bzero();

        # The library method requires a prefix.

        $x->{value} = $CALC->_from_bin('0b' . $chrs);

        # Place the sign.

        if ($sign eq '-' && ! $CALC->_is_zero($x->{value})) {
            $x->{sign} = '-';
        }

        return $x;
    }

    # For consistency with from_hex() and from_oct(), we return NaN when the
    # input is invalid.

    return $self->bnan();
}

sub _split
  {
  # input: num_str; output: undef for invalid or
  # (\$mantissa_sign,\$mantissa_value,\$mantissa_fraction,\$exp_sign,\$exp_value)
  # Internal, take apart a string and return the pieces.
  # Strip leading/trailing whitespace, leading zeros, underscore and reject
  # invalid input.
  my $x = shift;

  # strip white space at front, also extraneous leading zeros
  $x =~ s/^\s*([-]?)0*([0-9])/$1$2/g;   # will not strip '  .2'
  $x =~ s/^\s+//;                       # but this will
  $x =~ s/\s+$//g;                      # strip white space at end

  # shortcut, if nothing to split, return early
  if ($x =~ /^[+-]?[0-9]+\z/)
    {
    $x =~ s/^([+-])0*([0-9])/$2/; my $sign = $1 || '+';
    return (\$sign, \$x, \'', \'', \0);
    }

  # invalid starting char?
  return if $x !~ /^[+-]?(\.?[0-9]|0b[0-1]|0x[0-9a-fA-F])/;

  return Math::BigInt->from_hex($x) if $x =~ /^[+-]?0x/;        # hex string
  return Math::BigInt->from_bin($x) if $x =~ /^[+-]?0b/;        # binary string

  # strip underscores between digits
  $x =~ s/([0-9])_([0-9])/$1$2/g;
  $x =~ s/([0-9])_([0-9])/$1$2/g;		# do twice for 1_2_3

  # some possible inputs: 
  # 2.1234 # 0.12        # 1 	      # 1E1 # 2.134E1 # 434E-10 # 1.02009E-2 
  # .2 	   # 1_2_3.4_5_6 # 1.4E1_2_3  # 1e3 # +.2     # 0e999	

  my ($m,$e,$last) = split /[Ee]/,$x;
  return if defined $last;		# last defined => 1e2E3 or others
  $e = '0' if !defined $e || $e eq "";

  # sign,value for exponent,mantint,mantfrac
  my ($es,$ev,$mis,$miv,$mfv);
  # valid exponent?
  if ($e =~ /^([+-]?)0*([0-9]+)$/)	# strip leading zeros
    {
    $es = $1; $ev = $2;
    # valid mantissa?
    return if $m eq '.' || $m eq '';
    my ($mi,$mf,$lastf) = split /\./,$m;
    return if defined $lastf;		# lastf defined => 1.2.3 or others
    $mi = '0' if !defined $mi;
    $mi .= '0' if $mi =~ /^[\-\+]?$/;
    $mf = '0' if !defined $mf || $mf eq '';
    if ($mi =~ /^([+-]?)0*([0-9]+)$/)		# strip leading zeros
      {
      $mis = $1||'+'; $miv = $2;
      return unless ($mf =~ /^([0-9]*?)0*$/);	# strip trailing zeros
      $mfv = $1;
      # handle the 0e999 case here
      $ev = 0 if $miv eq '0' && $mfv eq '';
      return (\$mis,\$miv,\$mfv,\$es,\$ev);
      }
    }
  return; # NaN, not a number
  }


sub __lcm 
  { 
  # (BINT or num_str, BINT or num_str) return BINT
  # does modify first argument
  # LCM
 
  my ($x,$ty) = @_;
  return $x->bnan() if ($x->{sign} eq $nan) || ($ty->{sign} eq $nan);
  my $method = ref($x) . '::bgcd';
  no strict 'refs';
  $x * $ty / &$method($x,$ty);
  }


sub bpi
  {
  # Calculate PI to N digits. Unless upgrading is in effect, returns the
  # result truncated to an integer, that is, always returns '3'.
  my ($self,$n) = @_;
  if (@_ == 1)
    {
    # called like Math::BigInt::bpi(10);
    $n = $self; $self = $class;
    }
  $self = ref($self) if ref($self);

  return $upgrade->new($n) if defined $upgrade;

  # hard-wired to "3"
  $self->new(3);
  }

sub bcos
  {
  # Calculate cosinus(x) to N digits. Unless upgrading is in effect, returns the
  # result truncated to an integer.
  my ($self,$x,@r) = ref($_[0]) ? (undef,@_) : objectify(1,@_);

  return $x if $x->modify('bcos');

  return $x->bnan() if $x->{sign} !~ /^[+-]\z/;	# -inf +inf or NaN => NaN

  return $upgrade->new($x)->bcos(@r) if defined $upgrade;

  require Math::BigFloat;
  # calculate the result and truncate it to integer
  my $t = Math::BigFloat->new($x)->bcos(@r)->as_int();

  $x->bone() if $t->is_one();
  $x->bzero() if $t->is_zero();
  $x->round(@r);
  }

sub bsin
  {
  # Calculate sinus(x) to N digits. Unless upgrading is in effect, returns the
  # result truncated to an integer.
  my ($self,$x,@r) = ref($_[0]) ? (undef,@_) : objectify(1,@_);

  return $x if $x->modify('bsin');

  return $x->bnan() if $x->{sign} !~ /^[+-]\z/;	# -inf +inf or NaN => NaN

  return $upgrade->new($x)->bsin(@r) if defined $upgrade;

  require Math::BigFloat;
  # calculate the result and truncate it to integer
  my $t = Math::BigFloat->new($x)->bsin(@r)->as_int();

  $x->bone() if $t->is_one();
  $x->bzero() if $t->is_zero();
  $x->round(@r);
  }

sub batan2
  { 
  # calculate arcus tangens of ($y/$x)
 
  # set up parameters
  my ($self,$y,$x,@r) = (ref($_[0]),@_);
  # objectify is costly, so avoid it
  if ((!ref($_[0])) || (ref($_[0]) ne ref($_[1])))
    {
    ($self,$y,$x,@r) = objectify(2,@_);
    }

  return $y if $y->modify('batan2');

  return $y->bnan() if ($y->{sign} eq $nan) || ($x->{sign} eq $nan);

  # Y    X
  # != 0 -inf result is +- pi
  if ($x->is_inf() || $y->is_inf())
    {
    # upgrade to BigFloat etc.
    return $upgrade->new($y)->batan2($upgrade->new($x),@r) if defined $upgrade;
    if ($y->is_inf())
      {
      if ($x->{sign} eq '-inf')
        {
        # calculate 3 pi/4 => 2.3.. => 2
        $y->bone( substr($y->{sign},0,1) );
        $y->bmul($self->new(2));
        }
      elsif ($x->{sign} eq '+inf')
        {
        # calculate pi/4 => 0.7 => 0
        $y->bzero();
        }
      else
        {
        # calculate pi/2 => 1.5 => 1
        $y->bone( substr($y->{sign},0,1) );
        }
      }
    else
      {
      if ($x->{sign} eq '+inf')
        {
        # calculate pi/4 => 0.7 => 0
        $y->bzero();
        }
      else
        {
        # PI => 3.1415.. => 3
        $y->bone( substr($y->{sign},0,1) );
        $y->bmul($self->new(3));
        }
      }
    return $y;
    }

  return $upgrade->new($y)->batan2($upgrade->new($x),@r) if defined $upgrade;

  require Math::BigFloat;
  my $r = Math::BigFloat->new($y)->batan2(Math::BigFloat->new($x),@r)->as_int();

  $x->{value} = $r->{value};
  $x->{sign} = $r->{sign};

  $x;
  }

sub batan
  {
  # Calculate arcus tangens of x to N digits. Unless upgrading is in effect, returns the
  # result truncated to an integer.
  my ($self,$x,@r) = ref($_[0]) ? (undef,@_) : objectify(1,@_);

  return $x if $x->modify('batan');

  return $x->bnan() if $x->{sign} !~ /^[+-]\z/;	# -inf +inf or NaN => NaN

  return $upgrade->new($x)->batan(@r) if defined $upgrade;

  # calculate the result and truncate it to integer
  my $t = Math::BigFloat->new($x)->batan(@r);

  $x->{value} = $CALC->_new( $x->as_int()->bstr() );
  $x->round(@r);
  }


sub modify () { 0; }

1;
__END__

