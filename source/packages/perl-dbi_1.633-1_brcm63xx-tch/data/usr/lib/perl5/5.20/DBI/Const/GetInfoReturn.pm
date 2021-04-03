
package DBI::Const::GetInfoReturn;

use strict;

use Exporter ();

use vars qw(@ISA @EXPORT @EXPORT_OK %GetInfoReturnTypes %GetInfoReturnValues);

@ISA = qw(Exporter);
@EXPORT = qw(%GetInfoReturnTypes %GetInfoReturnValues);

my
$VERSION = "2.008697";


use DBI::Const::GetInfoType;

use DBI::Const::GetInfo::ANSI ();
use DBI::Const::GetInfo::ODBC ();

%GetInfoReturnTypes =
(
  %DBI::Const::GetInfo::ANSI::ReturnTypes
, %DBI::Const::GetInfo::ODBC::ReturnTypes
);

%GetInfoReturnValues = ();
{
  my $A = \%DBI::Const::GetInfo::ANSI::ReturnValues;
  my $O = \%DBI::Const::GetInfo::ODBC::ReturnValues;
  while ( my ($k, $v) = each %$A ) {
    my %h = ( exists $O->{$k} ) ? ( %$v, %{$O->{$k}} ) : %$v;
    $GetInfoReturnValues{$k} = \%h;
  }
  while ( my ($k, $v) = each %$O ) {
    next if exists $A->{$k};
    my %h = %$v;
    $GetInfoReturnValues{$k} = \%h;
  }
}


sub Format {
  my $InfoType = shift;
  my $Value    = shift;

  return '' unless defined $Value;

  my $ReturnType = $GetInfoReturnTypes{$InfoType};

  return sprintf '0x%08X', $Value if $ReturnType eq 'SQLUINTEGER bitmask';
  return sprintf '0x%08X', $Value if $ReturnType eq 'SQLINTEGER bitmask';
  return $Value;
}


sub Explain {
  my $InfoType = shift;
  my $Value    = shift;

  return '' unless defined $Value;
  return '' unless exists $GetInfoReturnValues{$InfoType};

  $Value = int $Value;
  my $ReturnType = $GetInfoReturnTypes{$InfoType};
  my %h = reverse %{$GetInfoReturnValues{$InfoType}};

  if ( $ReturnType eq 'SQLUINTEGER bitmask'|| $ReturnType eq 'SQLINTEGER bitmask') {
    my @a = ();
    for my $k ( sort { $a <=> $b } keys %h ) {
      push @a, $h{$k} if $Value & $k;
    }
    return wantarray ? @a : join(' ', @a );
  }
  else {
    return $h{$Value} ||'?';
  }
}

1;
