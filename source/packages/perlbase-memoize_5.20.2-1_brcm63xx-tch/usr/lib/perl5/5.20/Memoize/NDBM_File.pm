package Memoize::NDBM_File;


use NDBM_File;
@ISA = qw(NDBM_File);
$VERSION = '1.03';

$Verbose = 0;

sub AUTOLOAD {
  warn "Nonexistent function $AUTOLOAD invoked in Memoize::NDBM_File\n";
}

sub import {
  warn "Importing Memoize::NDBM_File\n" if $Verbose;
}


my %keylist;

sub _backhash {
  my $self = shift;
  my %fakehash;
  my $k; 
  for ($k = $self->FIRSTKEY(); defined $k; $k = $self->NEXTKEY($k)) {
    $fakehash{$k} = undef;
  }
  $keylist{$self} = \%fakehash;
}

sub EXISTS {
  warn "Memoize::NDBM_File EXISTS (@_)\n" if $Verbose;
  my $self = shift;
  _backhash($self)  unless exists $keylist{$self};
  my $r = exists $keylist{$self}{$_[0]};
  warn "Memoize::NDBM_File EXISTS (@_) ==> $r\n" if $Verbose;
  $r;
}

sub DEFINED {
  warn "Memoize::NDBM_File DEFINED (@_)\n" if $Verbose;
  my $self = shift;
  _backhash($self)  unless exists $keylist{$self};
  defined $keylist{$self}{$_[0]};
}

sub DESTROY {
  warn "Memoize::NDBM_File DESTROY (@_)\n" if $Verbose;
  my $self = shift;
  delete $keylist{$self};   # So much for reference counting...
  $self->SUPER::DESTROY(@_);
}


sub STORE {
  warn "Memoize::NDBM_File STORE (@_)\n" if $VERBOSE;
  my $self = shift;
  $keylist{$self}{$_[0]} = undef;
  $self->SUPER::STORE(@_);
}




1;
