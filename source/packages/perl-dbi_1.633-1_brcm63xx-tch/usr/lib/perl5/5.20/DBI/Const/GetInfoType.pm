
package DBI::Const::GetInfoType;

use strict;

use Exporter ();

use vars qw(@ISA @EXPORT @EXPORT_OK %GetInfoType);

@ISA = qw(Exporter);
@EXPORT = qw(%GetInfoType);

my
$VERSION = "2.008697";


use DBI::Const::GetInfo::ANSI ();	# liable to change
use DBI::Const::GetInfo::ODBC ();	# liable to change

%GetInfoType =
(
  %DBI::Const::GetInfo::ANSI::InfoTypes	# liable to change
, %DBI::Const::GetInfo::ODBC::InfoTypes	# liable to change
);

1;
