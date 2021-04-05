

package GDBM_File;

use strict;
use warnings;
our($VERSION, @ISA, @EXPORT);

require Carp;
require Tie::Hash;
require Exporter;
require XSLoader;
@ISA = qw(Tie::Hash Exporter);
@EXPORT = qw(
	GDBM_CACHESIZE
	GDBM_CENTFREE
	GDBM_COALESCEBLKS
	GDBM_FAST
	GDBM_FASTMODE
	GDBM_INSERT
	GDBM_NEWDB
	GDBM_NOLOCK
	GDBM_OPENMASK
	GDBM_READER
	GDBM_REPLACE
	GDBM_SYNC
	GDBM_SYNCMODE
	GDBM_WRCREAT
	GDBM_WRITER
);

$VERSION = '1.15';

XSLoader::load();

1;
