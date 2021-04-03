package ExtUtils::Typemaps::OutputMap;
use 5.006001;
use strict;
use warnings;
our $VERSION = '3.24';



sub new {
  my $prot = shift;
  my $class = ref($prot)||$prot;
  my %args = @_;

  if (!ref($prot)) {
    if (not defined $args{xstype} or not defined $args{code}) {
      die("Need xstype and code parameters");
    }
  }

  my $self = bless(
    (ref($prot) ? {%$prot} : {})
    => $class
  );

  $self->{xstype} = $args{xstype} if defined $args{xstype};
  $self->{code} = $args{code} if defined $args{code};
  $self->{code} =~ s/^(?=\S)/\t/mg;

  return $self;
}


sub code {
  $_[0]->{code} = $_[1] if @_ > 1;
  return $_[0]->{code};
}


sub xstype {
  return $_[0]->{xstype};
}


sub cleaned_code {
  my $self = shift;
  my $code = $self->code;

  # Move C pre-processor instructions to column 1 to be strictly ANSI
  # conformant. Some pre-processors are fussy about this.
  $code =~ s/^\s+#/#/mg;
  $code =~ s/\s*\z/\n/;

  return $code;
}


sub targetable {
  my $self = shift;
  return $self->{targetable} if exists $self->{targetable};

  our $bal; # ()-balanced
  $bal = qr[
    (?:
      (?>[^()]+)
      |
      \( (??{ $bal }) \)
    )*
  ]x;
  my $bal_no_comma = qr[
    (?:
      (?>[^(),]+)
      |
      \( (??{ $bal }) \)
    )+
  ]x;

  # matches variations on (SV*)
  my $sv_cast = qr[
    (?:
      \( \s* SV \s* \* \s* \) \s*
    )?
  ]x;

  my $size = qr[ # Third arg (to setpvn)
    , \s* (??{ $bal })
  ]xo;

  my $code = $self->code;

  # We can still bootstrap compile 're', because in code re.pm is
  # available to miniperl, and does not attempt to load the XS code.
  use re 'eval';

  my ($type, $with_size, $arg, $sarg) =
    ($code =~
      m[^
        \s+
        sv_set([iunp])v(n)?    # Type, is_setpvn
        \s*
        \( \s*
          $sv_cast \$arg \s* , \s*
          ( $bal_no_comma )    # Set from
          ( $size )?           # Possible sizeof set-from
        \s* \) \s* ; \s* $
      ]xo
  );

  my $rv = undef;
  if ($type) {
    $rv = {
      type      => $type,
      with_size => $with_size,
      what      => $arg,
      what_size => $sarg,
    };
  }
  $self->{targetable} = $rv;
  return $rv;
}


1;

