package ExtUtils::testlib;

use strict;
use warnings;

our $VERSION = '6.98';

use Cwd;
use File::Spec;

my $cwd;
BEGIN {
    ($cwd) = getcwd() =~ /(.*)/;
}
use lib map { File::Spec->rel2abs($_, $cwd) } qw(blib/arch blib/lib);
1;
__END__

