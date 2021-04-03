package CPAN::Nox;
use strict;
use vars qw($VERSION @EXPORT);

BEGIN{
  $CPAN::Suppress_readline=1 unless defined $CPAN::term;
}

use Exporter ();
@CPAN::ISA = ('Exporter');
use CPAN;

$VERSION = "5.5001";
$CPAN::META->has_inst('Digest::MD5','no');
$CPAN::META->has_inst('LWP','no');
$CPAN::META->has_inst('Compress::Zlib','no');
@EXPORT = @CPAN::EXPORT;

*AUTOLOAD = \&CPAN::AUTOLOAD;

1;

__END__


