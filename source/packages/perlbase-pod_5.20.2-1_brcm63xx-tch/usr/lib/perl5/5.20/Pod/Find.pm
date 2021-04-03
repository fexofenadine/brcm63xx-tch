
package Pod::Find;
use strict;

use vars qw($VERSION);
$VERSION = '1.62';   ## Current version of this package
require  5.005;   ## requires this Perl version or later
use Carp;

BEGIN {
   if ($] < 5.006) {
      require Symbol;
      import Symbol;
   }
}



use Exporter;
use File::Spec;
use File::Find;
use Cwd qw(abs_path cwd);

use vars qw(@ISA @EXPORT_OK $VERSION);
@ISA = qw(Exporter);
@EXPORT_OK = qw(&pod_find &simplify_name &pod_where &contains_pod);

my $SIMPLIFY_RX;


sub pod_find
{
    my %opts;
    if(ref $_[0]) {
        %opts = %{shift()};
    }

    $opts{-verbose} ||= 0;
    $opts{-perl}    ||= 0;

    my (@search) = @_;

    if($opts{-script}) {
        require Config;
        push(@search, $Config::Config{scriptdir})
            if -d $Config::Config{scriptdir};
        $opts{-perl} = 1;
    }

    if($opts{-inc}) {
        if ($^O eq 'MacOS') {
            # tolerate '.', './some_dir' and '(../)+some_dir' on Mac OS
            my @new_INC = @INC;
            for (@new_INC) {
                if ( $_ eq '.' ) {
                    $_ = ':';
                } elsif ( $_ =~ s{^((?:\.\./)+)}{':' x (length($1)/3)}e ) {
                    $_ = ':'. $_;
                } else {
                    $_ =~ s{^\./}{:};
                }
            }
            push(@search, grep($_ ne File::Spec->curdir, @new_INC));
        } else {
            my %seen;
            my $curdir = File::Spec->curdir;
	    foreach(@INC) {
                next if $_ eq $curdir;
		my $path = abs_path($_);
                push(@search, $path) unless $seen{$path}++;
            }
        }

        $opts{-perl} = 1;
    }

    if($opts{-perl}) {
        require Config;
        # this code simplifies the POD name for Perl modules:
        # * remove "site_perl"
        # * remove e.g. "i586-linux" (from 'archname')
        # * remove e.g. 5.00503
        # * remove pod/ if followed by *.pod (e.g. in pod/perlfunc.pod)

        # Mac OS:
        # * remove ":?site_perl:"
        # * remove :?pod: if followed by *.pod (e.g. in :pod:perlfunc.pod)

        if ($^O eq 'MacOS') {
            $SIMPLIFY_RX =
              qq!^(?i:\:?site_perl\:|\:?pod\:(?=.*?\\.pod\\z))*!;
        } else {
            $SIMPLIFY_RX =
              qq!^(?i:site(_perl)?/|\Q$Config::Config{archname}\E/|\\d+\\.\\d+([_.]?\\d+)?/|pod/(?=.*?\\.pod\\z))*!;
        }
    }

    my %dirs_visited;
    my %pods;
    my %names;
    my $pwd = cwd();

    foreach my $try (@search) {
        unless(File::Spec->file_name_is_absolute($try)) {
            # make path absolute
            $try = File::Spec->catfile($pwd,$try);
        }
        # simplify path
        # on VMS canonpath will vmsify:[the.path], but File::Find::find
        # wants /unixy/paths
        if ($^O eq 'VMS') {
            $try = VMS::Filespec::unixify($try);
        }
        else {
            $try = File::Spec->canonpath($try);
        }
        my $name;
        if(-f $try) {
            if($name = _check_and_extract_name($try, $opts{-verbose})) {
                _check_for_duplicates($try, $name, \%names, \%pods);
            }
            next;
        }
        my $root_rx = $^O eq 'MacOS' ? qq!^\Q$try\E! : qq!^\Q$try\E/!;
        $root_rx=~ s|//$|/|;  # remove trailing double slash
        File::Find::find( sub {
            my $item = $File::Find::name;
            if(-d) {
                if($item =~ m{/(?:RCS|CVS|SCCS|\.svn)$}) {
                    $File::Find::prune = 1;
                    return;
                }
                elsif($dirs_visited{$item}) {
                    warn "Directory '$item' already seen, skipping.\n"
                        if($opts{-verbose});
                    $File::Find::prune = 1;
                    return;
                }
                else {
                    $dirs_visited{$item} = 1;
                }
                if($opts{-perl} && /^(\d+\.[\d_]+)\z/s && eval "$1" != $]) {
                    $File::Find::prune = 1;
                    warn "Perl $] version mismatch on $_, skipping.\n"
                        if($opts{-verbose});
                }
                return;
            }
            if($name = _check_and_extract_name($item, $opts{-verbose}, $root_rx)) {
                _check_for_duplicates($item, $name, \%names, \%pods);
            }
        }, $try); # end of File::Find::find
    }
    chdir $pwd;
    return %pods;
}

sub _check_for_duplicates {
    my ($file, $name, $names_ref, $pods_ref) = @_;
    if($$names_ref{$name}) {
        warn "Duplicate POD found (shadowing?): $name ($file)\n";
        warn '    Already seen in ',
            join(' ', grep($$pods_ref{$_} eq $name, keys %$pods_ref)),"\n";
    }
    else {
        $$names_ref{$name} = 1;
    }
    return $$pods_ref{$file} = $name;
}

sub _check_and_extract_name {
    my ($file, $verbose, $root_rx) = @_;

    # check extension or executable flag
    # this involves testing the .bat extension on Win32!
    unless(-f $file && -T $file && ($file =~ /\.(pod|pm|plx?)\z/i || -x $file )) {
      return;
    }

    return unless contains_pod($file,$verbose);

    # strip non-significant path components
    # TODO what happens on e.g. Win32?
    my $name = $file;
    if(defined $root_rx) {
        $name =~ s/$root_rx//is;
        $name =~ s/$SIMPLIFY_RX//is if(defined $SIMPLIFY_RX);
    }
    else {
        if ($^O eq 'MacOS') {
            $name =~ s/^.*://s;
        } else {
            $name =~ s{^.*/}{}s;
        }
    }
    _simplify($name);
    $name =~ s{/+}{::}g;
    if ($^O eq 'MacOS') {
        $name =~ s{:+}{::}g; # : -> ::
    } else {
        $name =~ s{/+}{::}g; # / -> ::
    }
    return $name;
}


sub simplify_name {
    my ($str) = @_;
    # remove all path components
    if ($^O eq 'MacOS') {
        $str =~ s/^.*://s;
    } else {
        $str =~ s{^.*/}{}s;
    }
    _simplify($str);
    return $str;
}

sub _simplify {
    # strip Perl's own extensions
    $_[0] =~ s/\.(pod|pm|plx?)\z//i;
    # strip meaningless extensions on Win32 and OS/2
    $_[0] =~ s/\.(bat|exe|cmd)\z//i if($^O =~ /mswin|os2/i);
    # strip meaningless extensions on VMS
    $_[0] =~ s/\.(com)\z//i if($^O eq 'VMS');
}



sub pod_where {

  # default options
  my %options = (
         '-inc' => 0,
         '-verbose' => 0,
         '-dirs' => [ File::Spec->curdir ],
        );

  # Check for an options hash as first argument
  if (defined $_[0] && ref($_[0]) eq 'HASH') {
    my $opt = shift;

    # Merge default options with supplied options
    %options = (%options, %$opt);
  }

  # Check usage
  carp 'Usage: pod_where({options}, $pod)' unless (scalar(@_));

  # Read argument
  my $pod = shift;

  # Split on :: and then join the name together using File::Spec
  my @parts = split (/::/, $pod);

  # Get full directory list
  my @search_dirs = @{ $options{'-dirs'} };

  if ($options{'-inc'}) {

    require Config;

    # Add @INC
    if ($^O eq 'MacOS' && $options{'-inc'}) {
        # tolerate '.', './some_dir' and '(../)+some_dir' on Mac OS
        my @new_INC = @INC;
        for (@new_INC) {
            if ( $_ eq '.' ) {
                $_ = ':';
            } elsif ( $_ =~ s{^((?:\.\./)+)}{':' x (length($1)/3)}e ) {
                $_ = ':'. $_;
            } else {
                $_ =~ s{^\./}{:};
            }
        }
        push (@search_dirs, @new_INC);
    } elsif ($options{'-inc'}) {
        push (@search_dirs, @INC);
    }

    # Add location of pod documentation for perl man pages (eg perlfunc)
    # This is a pod directory in the private install tree
    #my $perlpoddir = File::Spec->catdir($Config::Config{'installprivlib'},
    #					'pod');
    #push (@search_dirs, $perlpoddir)
    #  if -d $perlpoddir;

    # Add location of binaries such as pod2text
    push (@search_dirs, $Config::Config{'scriptdir'})
      if -d $Config::Config{'scriptdir'};
  }

  warn 'Search path is: '.join(' ', @search_dirs)."\n"
        if $options{'-verbose'};

  # Loop over directories
  Dir: foreach my $dir ( @search_dirs ) {

    # Don't bother if can't find the directory
    if (-d $dir) {
      warn "Looking in directory $dir\n"
        if $options{'-verbose'};

      # Now concatenate this directory with the pod we are searching for
      my $fullname = File::Spec->catfile($dir, @parts);
      $fullname = VMS::Filespec::unixify($fullname) if $^O eq 'VMS';
      warn "Filename is now $fullname\n"
        if $options{'-verbose'};

      # Loop over possible extensions
      foreach my $ext ('', '.pod', '.pm', '.pl') {
        my $fullext = $fullname . $ext;
        if (-f $fullext &&
         contains_pod($fullext, $options{'-verbose'}) ) {
          warn "FOUND: $fullext\n" if $options{'-verbose'};
          return $fullext;
        }
      }
    } else {
      warn "Directory $dir does not exist\n"
        if $options{'-verbose'};
      next Dir;
    }
    # for some strange reason the path on MacOS/darwin/cygwin is
    # 'pods' not 'pod'
    # this could be the case also for other systems that
    # have a case-tolerant file system, but File::Spec
    # does not recognize 'darwin' yet. And cygwin also has "pods",
    # but is not case tolerant. Oh well...
    if((File::Spec->case_tolerant || $^O =~ /macos|darwin|cygwin/i)
     && -d File::Spec->catdir($dir,'pods')) {
      $dir = File::Spec->catdir($dir,'pods');
      redo Dir;
    }
    if(-d File::Spec->catdir($dir,'pod')) {
      $dir = File::Spec->catdir($dir,'pod');
      redo Dir;
    }
  }
  # No match;
  return;
}


sub contains_pod {
  my $file = shift;
  my $verbose = 0;
  $verbose = shift if @_;

  # check for one line of POD
  my $podfh;
  if ($] < 5.006) {
    $podfh = gensym();
  }

  unless(open($podfh,"<$file")) {
    warn "Error: $file is unreadable: $!\n";
    return;
  }
  
  local $/ = undef;
  my $pod = <$podfh>;
  close($podfh) || die "Error closing $file: $!\n";
  unless($pod =~ /^=(head\d|pod|over|item|cut)\b/m) {
    warn "No POD in $file, skipping.\n"
      if($verbose);
    return 0;
  }

  return 1;
}


1;

