package ExtUtils::Typemaps::Type;
use 5.006001;
use strict;
use warnings;
require ExtUtils::Typemaps;

our $VERSION = '3.24';



sub new {
  my $prot = shift;
  my $class = ref($prot)||$prot;
  my %args = @_;

  if (!ref($prot)) {
    if (not defined $args{xstype} or not defined $args{ctype}) {
      die("Need xstype and ctype parameters");
    }
  }

  my $self = bless(
    (ref($prot) ? {%$prot} : {proto => ''})
    => $class
  );

  $self->{xstype} = $args{xstype} if defined $args{xstype};
  $self->{ctype} = $args{ctype} if defined $args{ctype};
  $self->{tidy_ctype} = ExtUtils::Typemaps::tidy_type($self->{ctype});
  $self->{proto} = $args{'prototype'} if defined $args{'prototype'};

  return $self;
}


sub proto {
  $_[0]->{proto} = $_[1] if @_ > 1;
  return $_[0]->{proto};
}


sub xstype {
  return $_[0]->{xstype};
}


sub ctype {
  return defined($_[0]->{ctype}) ? $_[0]->{ctype} : $_[0]->{tidy_ctype};
}


sub tidy_ctype {
  return $_[0]->{tidy_ctype};
}


1;

