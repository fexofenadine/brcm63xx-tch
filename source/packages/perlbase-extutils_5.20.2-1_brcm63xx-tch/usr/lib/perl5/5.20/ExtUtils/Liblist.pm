package ExtUtils::Liblist;

use strict;

our $VERSION = '6.98';

use File::Spec;
require ExtUtils::Liblist::Kid;
our @ISA = qw(ExtUtils::Liblist::Kid File::Spec);

sub ext {
    goto &ExtUtils::Liblist::Kid::ext;
}

sub lsdir {
  shift;
  my $rex = qr/$_[1]/;
  opendir DIR, $_[0];
  my @out = grep /$rex/, readdir DIR;
  closedir DIR;
  return @out;
}

__END__


