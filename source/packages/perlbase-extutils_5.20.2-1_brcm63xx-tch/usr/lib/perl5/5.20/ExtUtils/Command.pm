package ExtUtils::Command;

use 5.00503;
use strict;
use Carp;
use File::Copy;
use File::Compare;
use File::Basename;
use File::Path qw(rmtree);
require Exporter;
use vars qw(@ISA @EXPORT @EXPORT_OK $VERSION);
@ISA       = qw(Exporter);
@EXPORT    = qw(cp rm_f rm_rf mv cat eqtime mkpath touch test_f test_d chmod
                dos2unix);
$VERSION = '1.18';

my $Is_VMS   = $^O eq 'VMS';
my $Is_VMS_mode = $Is_VMS;
my $Is_VMS_noefs = $Is_VMS;
my $Is_Win32 = $^O eq 'MSWin32';

if( $Is_VMS ) {
    my $vms_unix_rpt;
    my $vms_efs;
    my $vms_case;

    if (eval { local $SIG{__DIE__}; require VMS::Feature; }) {
        $vms_unix_rpt = VMS::Feature::current("filename_unix_report");
        $vms_efs = VMS::Feature::current("efs_charset");
        $vms_case = VMS::Feature::current("efs_case_preserve");
    } else {
        my $unix_rpt = $ENV{'DECC$FILENAME_UNIX_REPORT'} || '';
        my $efs_charset = $ENV{'DECC$EFS_CHARSET'} || '';
        my $efs_case = $ENV{'DECC$EFS_CASE_PRESERVE'} || '';
        $vms_unix_rpt = $unix_rpt =~ /^[ET1]/i;
        $vms_efs = $efs_charset =~ /^[ET1]/i;
        $vms_case = $efs_case =~ /^[ET1]/i;
    }
    $Is_VMS_mode = 0 if $vms_unix_rpt;
    $Is_VMS_noefs = 0 if ($vms_efs);
}



my $wild_regex = $Is_VMS ? '*%' : '*?';
sub expand_wildcards
{
 @ARGV = map(/[$wild_regex]/o ? glob($_) : $_,@ARGV);
}



sub cat ()
{
 expand_wildcards();
 print while (<>);
}


sub eqtime
{
 my ($src,$dst) = @ARGV;
 local @ARGV = ($dst);  touch();  # in case $dst doesn't exist
 utime((stat($src))[8,9],$dst);
}


sub rm_rf
{
 expand_wildcards();
 rmtree([grep -e $_,@ARGV],0,0);
}


sub rm_f {
    expand_wildcards();

    foreach my $file (@ARGV) {
        next unless -f $file;

        next if _unlink($file);

        chmod(0777, $file);

        next if _unlink($file);

        carp "Cannot delete $file: $!";
    }
}

sub _unlink {
    my $files_unlinked = 0;
    foreach my $file (@_) {
        my $delete_count = 0;
        $delete_count++ while unlink $file;
        $files_unlinked++ if $delete_count;
    }
    return $files_unlinked;
}



sub touch {
    my $t    = time;
    expand_wildcards();
    foreach my $file (@ARGV) {
        open(FILE,">>$file") || die "Cannot write $file:$!";
        close(FILE);
        utime($t,$t,$file);
    }
}


sub mv {
    expand_wildcards();
    my @src = @ARGV;
    my $dst = pop @src;

    croak("Too many arguments") if (@src > 1 && ! -d $dst);

    my $nok = 0;
    foreach my $src (@src) {
        $nok ||= !move($src,$dst);
    }
    return !$nok;
}


sub cp {
    expand_wildcards();
    my @src = @ARGV;
    my $dst = pop @src;

    croak("Too many arguments") if (@src > 1 && ! -d $dst);

    my $nok = 0;
    foreach my $src (@src) {
        $nok ||= !copy($src,$dst);

        # Win32 does not update the mod time of a copied file, just the
        # created time which make does not look at.
        utime(time, time, $dst) if $Is_Win32;
    }
    return $nok;
}


sub chmod {
    local @ARGV = @ARGV;
    my $mode = shift(@ARGV);
    expand_wildcards();

    if( $Is_VMS_mode && $Is_VMS_noefs) {
        foreach my $idx (0..$#ARGV) {
            my $path = $ARGV[$idx];
            next unless -d $path;

            # chmod 0777, [.foo.bar] doesn't work on VMS, you have to do
            # chmod 0777, [.foo]bar.dir
            my @dirs = File::Spec->splitdir( $path );
            $dirs[-1] .= '.dir';
            $path = File::Spec->catfile(@dirs);

            $ARGV[$idx] = $path;
        }
    }

    chmod(oct $mode,@ARGV) || die "Cannot chmod ".join(' ',$mode,@ARGV).":$!";
}


sub mkpath
{
 expand_wildcards();
 File::Path::mkpath([@ARGV],0,0777);
}


sub test_f
{
 exit(-f $ARGV[0] ? 0 : 1);
}


sub test_d
{
 exit(-d $ARGV[0] ? 0 : 1);
}


sub dos2unix {
    require File::Find;
    File::Find::find(sub {
        return if -d;
        return unless -w _;
        return unless -r _;
        return if -B _;

        local $\;

	my $orig = $_;
	my $temp = '.dos2unix_tmp';
	open ORIG, $_ or do { warn "dos2unix can't open $_: $!"; return };
	open TEMP, ">$temp" or
	    do { warn "dos2unix can't create .dos2unix_tmp: $!"; return };
        while (my $line = <ORIG>) {
            $line =~ s/\015\012/\012/g;
            print TEMP $line;
        }
	close ORIG;
	close TEMP;
	rename $temp, $orig;

    }, @ARGV);
}

