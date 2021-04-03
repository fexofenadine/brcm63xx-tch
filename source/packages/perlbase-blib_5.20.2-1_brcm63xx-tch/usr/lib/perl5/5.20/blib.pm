package blib;


use Cwd;
use File::Spec;

use vars qw($VERSION $Verbose);
$VERSION = '1.06';
$Verbose = 0;

sub import
{
 my $package = shift;
 my $dir;
 if ($^O eq "MSWin32" && -f "Win32.xs") {
     # We don't use getcwd() on Windows because it will internally
     # call Win32::GetCwd(), which will get the Win32 module loaded.
     # That means that it would not be possible to run `make test`
     # for the Win32 module because blib.pm would always load the
     # installed version before @INC gets updated with the blib path.
     chomp($dir = `cd`);
 }
 else {
     $dir = getcwd;
 }
 if ($^O eq 'VMS') { ($dir = VMS::Filespec::unixify($dir)) =~ s-/\z--; }
 if (@_)
  {
   $dir = shift;
   $dir =~ s/blib\z//;
   $dir =~ s,/+\z,,;
   $dir = File::Spec->curdir unless ($dir);
   die "$dir is not a directory\n" unless (-d $dir);
  }

 # detaint: if the user asked for blib, s/he presumably knew
 # what s/he wanted
 $dir = $1 if $dir =~ /^(.*)$/;

 my $i = 5;
 my($blib, $blib_lib, $blib_arch);
 while ($i--)
  {
   $blib = File::Spec->catdir($dir, "blib");
   $blib_lib = File::Spec->catdir($blib, "lib");
   $blib_arch = File::Spec->catdir($blib, "arch");

   if (-d $blib && -d $blib_arch && -d $blib_lib)
    {
     unshift(@INC,$blib_arch,$blib_lib);
     warn "Using $blib\n" if $Verbose;
     return;
    }
   $dir = File::Spec->catdir($dir, File::Spec->updir);
  }
 die "Cannot find blib even in $dir\n";
}

1;
