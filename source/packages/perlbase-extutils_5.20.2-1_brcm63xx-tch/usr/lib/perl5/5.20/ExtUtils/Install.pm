package ExtUtils::Install;
use strict;

use vars qw(@ISA @EXPORT $VERSION $MUST_REBOOT %Config);

use AutoSplit;
use Carp ();
use Config qw(%Config);
use Cwd qw(cwd);
use Exporter;
use ExtUtils::Packlist;
use File::Basename qw(dirname);
use File::Compare qw(compare);
use File::Copy;
use File::Find qw(find);
use File::Path;
use File::Spec;


@ISA = ('Exporter');
@EXPORT = ('install','uninstall','pm_to_blib', 'install_default');


$VERSION = '1.67';  # <-- do not forget to update the POD section just above this line!
$VERSION = eval $VERSION;


my $Is_VMS     = $^O eq 'VMS';
my $Is_MacPerl = $^O eq 'MacOS';
my $Is_Win32   = $^O eq 'MSWin32';
my $Is_cygwin  = $^O eq 'cygwin';
my $CanMoveAtBoot = ($Is_Win32 || $Is_cygwin);

my $Has_Win32API_File = ($Is_Win32 || $Is_cygwin)
    ? (eval {require Win32API::File; 1} || 0)
    : 0;


my $Inc_uninstall_warn_handler;


my $INSTALL_ROOT = $ENV{PERL_INSTALL_ROOT};

my $Curdir = File::Spec->curdir;
my $Updir  = File::Spec->updir;

sub _estr(@) {
    return join "\n",'!' x 72,@_,'!' x 72,'';
}

{my %warned;
sub _warnonce(@) {
    my $first=shift;
    my $msg=_estr "WARNING: $first",@_;
    warn $msg unless $warned{$msg}++;
}}

sub _choke(@) {
    my $first=shift;
    my $msg=_estr "ERROR: $first",@_;
    Carp::croak($msg);
}


sub _chmod($$;$) {
    my ( $mode, $item, $verbose )=@_;
    $verbose ||= 0;
    if (chmod $mode, $item) {
        printf "chmod(0%o, %s)\n",$mode, $item if $verbose > 1;
    } else {
        my $err="$!";
        _warnonce sprintf "WARNING: Failed chmod(0%o, %s): %s\n",
                  $mode, $item, $err
            if -e $item;
    }
}




sub _move_file_at_boot { #XXX OS-SPECIFIC
    my ( $file, $target, $moan  )= @_;
    Carp::confess("Panic: Can't _move_file_at_boot on this platform!")
         unless $CanMoveAtBoot;

    my $descr= ref $target
                ? "'$file' for deletion"
                : "'$file' for installation as '$target'";

    if ( ! $Has_Win32API_File ) {

        my @msg=(
            "Cannot schedule $descr at reboot.",
            "Try installing Win32API::File to allow operations on locked files",
            "to be scheduled during reboot. Or try to perform the operation by",
            "hand yourself. (You may need to close other perl processes first)"
        );
        if ( $moan ) { _warnonce(@msg) } else { _choke(@msg) }
        return 0;
    }
    my $opts= Win32API::File::MOVEFILE_DELAY_UNTIL_REBOOT();
    $opts= $opts | Win32API::File::MOVEFILE_REPLACE_EXISTING()
        unless ref $target;

    _chmod( 0666, $file );
    _chmod( 0666, $target ) unless ref $target;

    if (Win32API::File::MoveFileEx( $file, $target, $opts )) {
        $MUST_REBOOT ||= ref $target ? 0 : 1;
        return 1;
    } else {
        my @msg=(
            "MoveFileEx $descr at reboot failed: $^E",
            "You may try to perform the operation by hand yourself. ",
            "(You may need to close other perl processes first).",
        );
        if ( $moan ) { _warnonce(@msg) } else { _choke(@msg) }
    }
    return 0;
}





sub _unlink_or_rename { #XXX OS-SPECIFIC
    my ( $file, $tryhard, $installing )= @_;

    # this chmod was originally unconditional. However, its not needed on
    # POSIXy systems since permission to unlink a file is specified by the
    # directory rather than the file; and in fact it screwed up hard- and
    # symlinked files. Keep it for other platforms in case its still
    # needed there.
    if ($^O =~ /^(dos|os2|MSWin32|VMS)$/) {
        _chmod( 0666, $file );
    }
    my $unlink_count = 0;
    while (unlink $file) { $unlink_count++; }
    return $file if $unlink_count > 0;
    my $error="$!";

    _choke("Cannot unlink '$file': $!")
          unless $CanMoveAtBoot && $tryhard;

    my $tmp= "AAA";
    ++$tmp while -e "$file.$tmp";
    $tmp= "$file.$tmp";

    warn "WARNING: Unable to unlink '$file': $error\n",
         "Going to try to rename it to '$tmp'.\n";

    if ( rename $file, $tmp ) {
        warn "Rename successful. Scheduling '$tmp'\nfor deletion at reboot.\n";
        # when $installing we can set $moan to true.
        # IOW, if we cant delete the renamed file at reboot its
        # not the end of the world. The other cases are more serious
        # and need to be fatal.
        _move_file_at_boot( $tmp, [], $installing );
        return $file;
    } elsif ( $installing ) {
        _warnonce("Rename failed: $!. Scheduling '$tmp'\nfor".
             " installation as '$file' at reboot.\n");
        _move_file_at_boot( $tmp, $file );
        return $tmp;
    } else {
        _choke("Rename failed:$!", "Cannot proceed.");
    }

}





sub _get_install_skip {
    my ( $skip, $verbose )= @_;
    if ($ENV{EU_INSTALL_IGNORE_SKIP}) {
        print "EU_INSTALL_IGNORE_SKIP is set, ignore skipfile settings\n"
            if $verbose>2;
        return [];
    }
    if ( ! defined $skip ) {
        print "Looking for install skip list\n"
            if $verbose>2;
        for my $file ( 'INSTALL.SKIP', $ENV{EU_INSTALL_SITE_SKIPFILE} ) {
            next unless $file;
            print "\tChecking for $file\n"
                if $verbose>2;
            if (-e $file) {
                $skip= $file;
                last;
            }
        }
    }
    if ($skip && !ref $skip) {
        print "Reading skip patterns from '$skip'.\n"
            if $verbose;
        if (open my $fh,$skip ) {
            my @patterns;
            while (<$fh>) {
                chomp;
                next if /^\s*(?:#|$)/;
                print "\tSkip pattern: $_\n" if $verbose>3;
                push @patterns, $_;
            }
            $skip= \@patterns;
        } else {
            warn "Can't read skip file:'$skip':$!\n";
            $skip=[];
        }
    } elsif ( UNIVERSAL::isa($skip,'ARRAY') ) {
        print "Using array for skip list\n"
            if $verbose>2;
    } elsif ($verbose) {
        print "No skip list found.\n"
            if $verbose>1;
        $skip= [];
    }
    warn "Got @{[0+@$skip]} skip patterns.\n"
        if $verbose>3;
    return $skip
}


{
    my  $has_posix;
    sub _have_write_access {
        my $dir=shift;
        unless (defined $has_posix) {
            $has_posix= (!$Is_cygwin && !$Is_Win32
             && eval 'local $^W; require POSIX; 1') || 0;
        }
        if ($has_posix) {
            return POSIX::access($dir, POSIX::W_OK());
        } else {
            return -w $dir;
        }
    }
}



sub _can_write_dir {
    my $dir=shift;
    return
        unless defined $dir and length $dir;

    my ($vol, $dirs, $file) = File::Spec->splitpath($dir,1);
    my @dirs = File::Spec->splitdir($dirs);
    unshift @dirs, File::Spec->curdir
        unless File::Spec->file_name_is_absolute($dir);

    my $path='';
    my @make;
    while (@dirs) {
        if ($Is_VMS) {
            $dir = File::Spec->catdir($vol,@dirs);
        }
        else {
            $dir = File::Spec->catdir(@dirs);
            $dir = File::Spec->catpath($vol,$dir,'')
                    if defined $vol and length $vol;
        }
        next if ( $dir eq $path );
        if ( ! -e $dir ) {
            unshift @make,$dir;
            next;
        }
        if ( _have_write_access($dir) ) {
            return 1,$dir,@make
        } else {
            return 0,$dir,@make
        }
    } continue {
        pop @dirs;
    }
    return 0;
}


sub _mkpath {
    my ($dir,$show,$mode,$verbose,$dry_run)=@_;
    if ( $verbose && $verbose > 1 && ! -d $dir) {
        $show= 1;
        printf "mkpath(%s,%d,%#o)\n", $dir, $show, $mode;
    }
    if (!$dry_run) {
        if ( ! eval { File::Path::mkpath($dir,$show,$mode); 1 } ) {
            _choke("Can't create '$dir'","$@");
        }

    }
    my ($can,$root,@make)=_can_write_dir($dir);
    if (!$can) {
        my @msg=(
            "Can't create '$dir'",
            $root ? "Do not have write permissions on '$root'"
                  : "Unknown Error"
        );
        if ($dry_run) {
            _warnonce @msg;
        } else {
            _choke @msg;
        }
    } elsif ($show and $dry_run) {
        print "$_\n" for @make;
    }

}



sub _copy {
    my ( $from, $to, $verbose, $dry_run)=@_;
    if ($verbose && $verbose>1) {
        printf "copy(%s,%s)\n", $from, $to;
    }
    if (!$dry_run) {
        File::Copy::copy($from,$to)
            or Carp::croak( _estr "ERROR: Cannot copy '$from' to '$to': $!" );
    }
}


sub _chdir {
    my ($dir)= @_;
    my $ret;
    if (defined wantarray) {
        $ret= cwd;
    }
    chdir $dir
        or _choke("Couldn't chdir to '$dir': $!");
    return $ret;
}


sub install { #XXX OS-SPECIFIC
    my($from_to,$verbose,$dry_run,$uninstall_shadows,$skip,$always_copy,$result) = @_;
    if (@_==1 and eval { 1+@$from_to }) {
        my %opts        = @$from_to;
        $from_to        = $opts{from_to}
                            or Carp::confess("from_to is a mandatory parameter");
        $verbose        = $opts{verbose};
        $dry_run        = $opts{dry_run};
        $uninstall_shadows  = $opts{uninstall_shadows};
        $skip           = $opts{skip};
        $always_copy    = $opts{always_copy};
        $result         = $opts{result};
    }

    $result ||= {};
    $verbose ||= 0;
    $dry_run  ||= 0;

    $skip= _get_install_skip($skip,$verbose);
    $always_copy =  $ENV{EU_INSTALL_ALWAYS_COPY}
                 || $ENV{EU_ALWAYS_COPY}
                 || 0
        unless defined $always_copy;

    my(%from_to) = %$from_to;
    my(%pack, $dir, %warned);
    my($packlist) = ExtUtils::Packlist->new();

    local(*DIR);
    for (qw/read write/) {
        $pack{$_}=$from_to{$_};
        delete $from_to{$_};
    }
    my $tmpfile = install_rooted_file($pack{"read"});
    $packlist->read($tmpfile) if (-f $tmpfile);
    my $cwd = cwd();
    my @found_files;
    my %check_dirs;

    MOD_INSTALL: foreach my $source (sort keys %from_to) {
        #copy the tree to the target directory without altering
        #timestamp and permission and remember for the .packlist
        #file. The packlist file contains the absolute paths of the
        #install locations. AFS users may call this a bug. We'll have
        #to reconsider how to add the means to satisfy AFS users also.

        #October 1997: we want to install .pm files into archlib if
        #there are any files in arch. So we depend on having ./blib/arch
        #hardcoded here.

        my $targetroot = install_rooted_dir($from_to{$source});

        my $blib_lib  = File::Spec->catdir('blib', 'lib');
        my $blib_arch = File::Spec->catdir('blib', 'arch');
        if ($source eq $blib_lib and
            exists $from_to{$blib_arch} and
            directory_not_empty($blib_arch)
        ){
            $targetroot = install_rooted_dir($from_to{$blib_arch});
            print "Files found in $blib_arch: installing files in $blib_lib into architecture dependent library tree\n";
        }

        next unless -d $source;
        _chdir($source);
        # 5.5.3's File::Find missing no_chdir option
        # XXX OS-SPECIFIC
        # File::Find seems to always be Unixy except on MacPerl :(
        my $current_directory= $Is_MacPerl ? $Curdir : '.';
        find(sub {
            my ($mode,$size,$atime,$mtime) = (stat)[2,7,8,9];

            return if !-f _;
            my $origfile = $_;

            return if $origfile eq ".exists";
            my $targetdir  = File::Spec->catdir($targetroot, $File::Find::dir);
            my $targetfile = File::Spec->catfile($targetdir, $origfile);
            my $sourcedir  = File::Spec->catdir($source, $File::Find::dir);
            my $sourcefile = File::Spec->catfile($sourcedir, $origfile);

            for my $pat (@$skip) {
                if ( $sourcefile=~/$pat/ ) {
                    print "Skipping $targetfile (filtered)\n"
                        if $verbose>1;
                    $result->{install_filtered}{$sourcefile} = $pat;
                    return;
                }
            }
            # we have to do this for back compat with old File::Finds
            # and because the target is relative
            my $save_cwd = _chdir($cwd);
            my $diff = 0;
            # XXX: I wonder how useful this logic is actually -- demerphq
            if ( $always_copy or !-f $targetfile or -s $targetfile != $size) {
                $diff++;
            } else {
                # we might not need to copy this file
                $diff = compare($sourcefile, $targetfile);
            }
            $check_dirs{$targetdir}++
                unless -w $targetfile;

            push @found_files,
                [ $diff, $File::Find::dir, $origfile,
                  $mode, $size, $atime, $mtime,
                  $targetdir, $targetfile, $sourcedir, $sourcefile,

                ];
            #restore the original directory we were in when File::Find
            #called us so that it doesn't get horribly confused.
            _chdir($save_cwd);
        }, $current_directory );
        _chdir($cwd);
    }
    foreach my $targetdir (sort keys %check_dirs) {
        _mkpath( $targetdir, 0, 0755, $verbose, $dry_run );
    }
    foreach my $found (@found_files) {
        my ($diff, $ffd, $origfile, $mode, $size, $atime, $mtime,
            $targetdir, $targetfile, $sourcedir, $sourcefile)= @$found;

        my $realtarget= $targetfile;
        if ($diff) {
            eval {
                if (-f $targetfile) {
                    print "_unlink_or_rename($targetfile)\n" if $verbose>1;
                    $targetfile= _unlink_or_rename( $targetfile, 'tryhard', 'install' )
                        unless $dry_run;
                } elsif ( ! -d $targetdir ) {
                    _mkpath( $targetdir, 0, 0755, $verbose, $dry_run );
                }
                print "Installing $targetfile\n";

                _copy( $sourcefile, $targetfile, $verbose, $dry_run, );


                #XXX OS-SPECIFIC
                print "utime($atime,$mtime,$targetfile)\n" if $verbose>1;
                utime($atime,$mtime + $Is_VMS,$targetfile) unless $dry_run>1;


                $mode = 0444 | ( $mode & 0111 ? 0111 : 0 );
                $mode = $mode | 0222
                    if $realtarget ne $targetfile;
                _chmod( $mode, $targetfile, $verbose );
                $result->{install}{$targetfile} = $sourcefile;
                1
            } or do {
                $result->{install_fail}{$targetfile} = $sourcefile;
                die $@;
            };
        } else {
            $result->{install_unchanged}{$targetfile} = $sourcefile;
            print "Skipping $targetfile (unchanged)\n" if $verbose;
        }

        if ( $uninstall_shadows ) {
            inc_uninstall($sourcefile,$ffd, $verbose,
                          $dry_run,
                          $realtarget ne $targetfile ? $realtarget : "",
                          $result);
        }

        # Record the full pathname.
        $packlist->{$targetfile}++;
    }

    if ($pack{'write'}) {
        $dir = install_rooted_dir(dirname($pack{'write'}));
        _mkpath( $dir, 0, 0755, $verbose, $dry_run );
        print "Writing $pack{'write'}\n" if $verbose;
        $packlist->write(install_rooted_file($pack{'write'})) unless $dry_run;
    }

    _do_cleanup($verbose);
    return $result;
}


sub _do_cleanup {
    my ($verbose) = @_;
    if ($MUST_REBOOT) {
        die _estr "Operation not completed! ",
            "You must reboot to complete the installation.",
            "Sorry.";
    } elsif (defined $MUST_REBOOT & $verbose) {
        warn _estr "Installation will be completed at the next reboot.\n",
             "However it is not necessary to reboot immediately.\n";
    }
}



sub install_rooted_file {
    if (defined $INSTALL_ROOT) {
        File::Spec->catfile($INSTALL_ROOT, $_[0]);
    } else {
        $_[0];
    }
}


sub install_rooted_dir {
    if (defined $INSTALL_ROOT) {
        File::Spec->catdir($INSTALL_ROOT, $_[0]);
    } else {
        $_[0];
    }
}



sub forceunlink {
    my ( $file, $tryhard )= @_; #XXX OS-SPECIFIC
    _unlink_or_rename( $file, $tryhard, not("installing") );
}


sub directory_not_empty ($) {
  my($dir) = @_;
  my $files = 0;
  find(sub {
           return if $_ eq ".exists";
           if (-f) {
             $File::Find::prune++;
             $files = 1;
           }
       }, $dir);
  return $files;
}


sub install_default {
  @_ < 2 or Carp::croak("install_default should be called with 0 or 1 argument");
  my $FULLEXT = @_ ? shift : $ARGV[0];
  defined $FULLEXT or die "Do not know to where to write install log";
  my $INST_LIB = File::Spec->catdir($Curdir,"blib","lib");
  my $INST_ARCHLIB = File::Spec->catdir($Curdir,"blib","arch");
  my $INST_BIN = File::Spec->catdir($Curdir,'blib','bin');
  my $INST_SCRIPT = File::Spec->catdir($Curdir,'blib','script');
  my $INST_MAN1DIR = File::Spec->catdir($Curdir,'blib','man1');
  my $INST_MAN3DIR = File::Spec->catdir($Curdir,'blib','man3');

  my @INST_HTML;
  if($Config{installhtmldir}) {
      my $INST_HTMLDIR = File::Spec->catdir($Curdir,'blib','html');
      @INST_HTML = ($INST_HTMLDIR => $Config{installhtmldir});
  }

  install({
           read => "$Config{sitearchexp}/auto/$FULLEXT/.packlist",
           write => "$Config{installsitearch}/auto/$FULLEXT/.packlist",
           $INST_LIB => (directory_not_empty($INST_ARCHLIB)) ?
                         $Config{installsitearch} :
                         $Config{installsitelib},
           $INST_ARCHLIB => $Config{installsitearch},
           $INST_BIN => $Config{installbin} ,
           $INST_SCRIPT => $Config{installscript},
           $INST_MAN1DIR => $Config{installman1dir},
           $INST_MAN3DIR => $Config{installman3dir},
       @INST_HTML,
          },1,0,0);
}



sub uninstall {
    my($fil,$verbose,$dry_run) = @_;
    $verbose ||= 0;
    $dry_run  ||= 0;

    die _estr "ERROR: no packlist file found: '$fil'"
        unless -f $fil;
    # my $my_req = $self->catfile(qw(auto ExtUtils Install forceunlink.al));
    # require $my_req; # Hairy, but for the first
    my ($packlist) = ExtUtils::Packlist->new($fil);
    foreach (sort(keys(%$packlist))) {
        chomp;
        print "unlink $_\n" if $verbose;
        forceunlink($_,'tryhard') unless $dry_run;
    }
    print "unlink $fil\n" if $verbose;
    forceunlink($fil, 'tryhard') unless $dry_run;
    _do_cleanup($verbose);
}


sub inc_uninstall {
    my($filepath,$libdir,$verbose,$dry_run,$ignore,$results) = @_;
    my($dir);
    $ignore||="";
    my $file = (File::Spec->splitpath($filepath))[2];
    my %seen_dir = ();

    my @PERL_ENV_LIB = split $Config{path_sep}, defined $ENV{'PERL5LIB'}
      ? $ENV{'PERL5LIB'} : $ENV{'PERLLIB'} || '';

    my @dirs=( @PERL_ENV_LIB,
               @INC,
               @Config{qw(archlibexp
                          privlibexp
                          sitearchexp
                          sitelibexp)});

    #warn join "\n","---",@dirs,"---";
    my $seen_ours;
    foreach $dir ( @dirs ) {
        my $canonpath = $Is_VMS ? $dir : File::Spec->canonpath($dir);
        next if $canonpath eq $Curdir;
        next if $seen_dir{$canonpath}++;
        my $targetfile = File::Spec->catfile($canonpath,$libdir,$file);
        next unless -f $targetfile;

        # The reason why we compare file's contents is, that we cannot
        # know, which is the file we just installed (AFS). So we leave
        # an identical file in place
        my $diff = 0;
        if ( -f $targetfile && -s _ == -s $filepath) {
            # We have a good chance, we can skip this one
            $diff = compare($filepath,$targetfile);
        } else {
            $diff++;
        }
        print "#$file and $targetfile differ\n" if $diff && $verbose > 1;

        if (!$diff or $targetfile eq $ignore) {
            $seen_ours = 1;
            next;
        }
        if ($dry_run) {
            $results->{uninstall}{$targetfile} = $filepath;
            if ($verbose) {
                $Inc_uninstall_warn_handler ||= ExtUtils::Install::Warn->new();
                $libdir =~ s|^\./||s ; # That's just cosmetics, no need to port. It looks prettier.
                $Inc_uninstall_warn_handler->add(
                                     File::Spec->catfile($libdir, $file),
                                     $targetfile
                                    );
            }
            # if not verbose, we just say nothing
        } else {
            print "Unlinking $targetfile (shadowing?)\n" if $verbose;
            eval {
                die "Fake die for testing"
                    if $ExtUtils::Install::Testing and
                       ucase(File::Spec->canonpath($ExtUtils::Install::Testing)) eq ucase($targetfile);
                forceunlink($targetfile,'tryhard');
                $results->{uninstall}{$targetfile} = $filepath;
                1;
            } or do {
                $results->{fail_uninstall}{$targetfile} = $filepath;
                if ($seen_ours) {
                    warn "Failed to remove probably harmless shadow file '$targetfile'\n";
                } else {
                    die "$@\n";
                }
            };
        }
    }
}


sub run_filter {
    my ($cmd, $src, $dest) = @_;
    local(*CMD, *SRC);
    open(CMD, "|$cmd >$dest") || die "Cannot fork: $!";
    open(SRC, $src)           || die "Cannot open $src: $!";
    my $buf;
    my $sz = 1024;
    while (my $len = sysread(SRC, $buf, $sz)) {
        syswrite(CMD, $buf, $len);
    }
    close SRC;
    close CMD or die "Filter command '$cmd' failed for $src";
}


sub pm_to_blib {
    my($fromto,$autodir,$pm_filter) = @_;

    _mkpath($autodir,0,0755);
    while(my($from, $to) = each %$fromto) {
        if( -f $to && -s $from == -s $to && -M $to < -M $from ) {
            print "Skip $to (unchanged)\n";
            next;
        }

        # When a pm_filter is defined, we need to pre-process the source first
        # to determine whether it has changed or not.  Therefore, only perform
        # the comparison check when there's no filter to be ran.
        #    -- RAM, 03/01/2001

        my $need_filtering = defined $pm_filter && length $pm_filter &&
                             $from =~ /\.pm$/;

        if (!$need_filtering && 0 == compare($from,$to)) {
            print "Skip $to (unchanged)\n";
            next;
        }
        if (-f $to){
            # we wont try hard here. its too likely to mess things up.
            forceunlink($to);
        } else {
            _mkpath(dirname($to),0,0755);
        }
        if ($need_filtering) {
            run_filter($pm_filter, $from, $to);
            print "$pm_filter <$from >$to\n";
        } else {
            _copy( $from, $to );
            print "cp $from $to\n";
        }
        my($mode,$atime,$mtime) = (stat $from)[2,8,9];
        utime($atime,$mtime+$Is_VMS,$to);
        _chmod(0444 | ( $mode & 0111 ? 0111 : 0 ),$to);
        next unless $from =~ /\.pm$/;
        _autosplit($to,$autodir);
    }
}



sub _autosplit { #XXX OS-SPECIFIC
    my $retval = autosplit(@_);
    close *AutoSplit::IN if defined *AutoSplit::IN{IO};

    return $retval;
}


package ExtUtils::Install::Warn;

sub new { bless {}, shift }

sub add {
    my($self,$file,$targetfile) = @_;
    push @{$self->{$file}}, $targetfile;
}

sub DESTROY {
    unless(defined $INSTALL_ROOT) {
        my $self = shift;
        my($file,$i,$plural);
        foreach $file (sort keys %$self) {
            $plural = @{$self->{$file}} > 1 ? "s" : "";
            print "## Differing version$plural of $file found. You might like to\n";
            for (0..$#{$self->{$file}}) {
                print "rm ", $self->{$file}[$_], "\n";
                $i++;
            }
        }
        $plural = $i>1 ? "all those files" : "this file";
        my $inst = (_invokant() eq 'ExtUtils::MakeMaker')
                 ? ( $Config::Config{make} || 'make' ).' install'
                     . ( $Is_VMS ? '/MACRO="UNINST"=1' : ' UNINST=1' )
                 : './Build install uninst=1';
        print "## Running '$inst' will unlink $plural for you.\n";
    }
}


sub _invokant {
    my @stack;
    my $frame = 0;
    while (my $file = (caller($frame++))[1]) {
        push @stack, (File::Spec->splitpath($file))[2];
    }

    my $builder;
    my $top = pop @stack;
    if ($top =~ /^Build/i || exists($INC{'Module/Build.pm'})) {
        $builder = 'Module::Build';
    } else {
        $builder = 'ExtUtils::MakeMaker';
    }
    return $builder;
}


1;
