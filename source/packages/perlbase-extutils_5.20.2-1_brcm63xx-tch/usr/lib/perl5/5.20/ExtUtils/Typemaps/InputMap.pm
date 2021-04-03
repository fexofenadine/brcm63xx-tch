package ExtUtils::Typemaps::InputMap;
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

  $code =~ s/(?:;+\s*|;*\s+)\z//s;

  # Move C pre-processor instructions to column 1 to be strictly ANSI
  # conformant. Some pre-processors are fussy about this.
  $code =~ s/^\s+#/#/mg;
  $code =~ s/\s*\z/\n/;

  return $code;
}


1;

