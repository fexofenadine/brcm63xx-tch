package File::Spec::Functions;

use File::Spec;
use strict;

use vars qw(@ISA @EXPORT @EXPORT_OK %EXPORT_TAGS $VERSION);

$VERSION = '3.48_01';
$VERSION =~ tr/_//;

require Exporter;

@ISA = qw(Exporter);

@EXPORT = qw(
	canonpath
	catdir
	catfile
	curdir
	rootdir
	updir
	no_upwards
	file_name_is_absolute
	path
);

@EXPORT_OK = qw(
	devnull
	tmpdir
	splitpath
	splitdir
	catpath
	abs2rel
	rel2abs
	case_tolerant
);

%EXPORT_TAGS = ( ALL => [ @EXPORT_OK, @EXPORT ] );

require File::Spec::Unix;
my %udeps = (
    canonpath => [],
    catdir => [qw(canonpath)],
    catfile => [qw(canonpath catdir)],
    case_tolerant => [],
    curdir => [],
    devnull => [],
    rootdir => [],
    updir => [],
);

foreach my $meth (@EXPORT, @EXPORT_OK) {
    my $sub = File::Spec->can($meth);
    no strict 'refs';
    if (exists($udeps{$meth}) && $sub == File::Spec::Unix->can($meth) &&
	    !(grep {
		File::Spec->can($_) != File::Spec::Unix->can($_)
	    } @{$udeps{$meth}}) &&
	    defined(&{"File::Spec::Unix::_fn_$meth"})) {
	*{$meth} = \&{"File::Spec::Unix::_fn_$meth"};
    } else {
	*{$meth} = sub {&$sub('File::Spec', @_)};
    }
}


1;
__END__


