
require 5.005;
package Pod::Simple::Search;
use strict;

use vars qw($VERSION $MAX_VERSION_WITHIN $SLEEPY);
$VERSION = '3.28';   ## Current version of this package

BEGIN { *DEBUG = sub () {0} unless defined &DEBUG; }   # set DEBUG level
use Carp ();

$SLEEPY = 1 if !defined $SLEEPY and $^O =~ /mswin|mac/i;
  # flag to occasionally sleep for $SLEEPY - 1 seconds.

$MAX_VERSION_WITHIN ||= 60;


use File::Spec ();
use File::Basename qw( basename );
use Config ();
use Cwd qw( cwd );

__PACKAGE__->_accessorize(  # Make my dumb accessor methods
 'callback', 'progress', 'dir_prefix', 'inc', 'laborious', 'limit_glob',
 'limit_re', 'shadows', 'verbose', 'name2path', 'path2name', 'recurse',
);

sub new {
  my $class = shift;
  my $self = bless {}, ref($class) || $class;
  $self->init;
  return $self;
}

sub init {
  my $self = shift;
  $self->inc(1);
  $self->recurse(1);
  $self->verbose(DEBUG);
  return $self;
}


sub survey {
  my($self, @search_dirs) = @_;
  $self = $self->new unless ref $self; # tolerate being a class method

  $self->_expand_inc( \@search_dirs );


  $self->{'_scan_count'} = 0;
  $self->{'_dirs_visited'} = {};
  $self->path2name( {} );
  $self->name2path( {} );
  $self->limit_re( $self->_limit_glob_to_limit_re ) if $self->{'limit_glob'};
  my $cwd = cwd();
  my $verbose  = $self->verbose;
  local $_; # don't clobber the caller's $_ !

  foreach my $try (@search_dirs) {
    unless( File::Spec->file_name_is_absolute($try) ) {
      # make path absolute
      $try = File::Spec->catfile( $cwd ,$try);
    }
    # simplify path
    $try =  File::Spec->canonpath($try);

    my $start_in;
    my $modname_prefix;
    if($self->{'dir_prefix'}) {
      $start_in = File::Spec->catdir(
        $try,
        grep length($_), split '[\\/:]+', $self->{'dir_prefix'}
      );
      $modname_prefix = [grep length($_), split m{[:/\\]}, $self->{'dir_prefix'}];
      $verbose and print "Appending \"$self->{'dir_prefix'}\" to $try, ",
        "giving $start_in (= @$modname_prefix)\n";
    } else {
      $start_in = $try;
    }

    if( $self->{'_dirs_visited'}{$start_in} ) {
      $verbose and print "Directory '$start_in' already seen, skipping.\n";
      next;
    } else {
      $self->{'_dirs_visited'}{$start_in} = 1;
    }
  
    unless(-e $start_in) {
      $verbose and print "Skipping non-existent $start_in\n";
      next;
    }

    my $closure = $self->_make_search_callback;
    
    if(-d $start_in) {
      # Normal case:
      $verbose and print "Beginning excursion under $start_in\n";
      $self->_recurse_dir( $start_in, $closure, $modname_prefix );
      $verbose and print "Back from excursion under $start_in\n\n";
        
    } elsif(-f _) {
      # A excursion consisting of just one file!
      $_ = basename($start_in);
      $verbose and print "Pondering $start_in ($_)\n";
      $closure->($start_in, $_, 0, []);
        
    } else {
      $verbose and print "Skipping mysterious $start_in\n";
    }
  }
  $self->progress and $self->progress->done(
   "Noted $$self{'_scan_count'} Pod files total");

  return unless defined wantarray; # void
  return $self->name2path unless wantarray; # scalar
  return $self->name2path, $self->path2name; # list
}


sub _make_search_callback {
  my $self = $_[0];

  # Put the options in variables, for easy access
  my( $laborious, $verbose, $shadows, $limit_re, $callback, $progress,
      $path2name, $name2path, $recurse) =
    map scalar($self->$_()),
     qw(laborious verbose shadows limit_re callback progress
        path2name name2path recurse);

  my($file, $shortname, $isdir, $modname_bits);
  return sub {
    ($file, $shortname, $isdir, $modname_bits) = @_;

    if($isdir) { # this never gets called on the startdir itself, just subdirs

      unless( $recurse ) {
        $verbose and print "Not recursing into '$file' as per requested.\n";
        return 'PRUNE';
      }

      if( $self->{'_dirs_visited'}{$file} ) {
        $verbose and print "Directory '$file' already seen, skipping.\n";
        return 'PRUNE';
      }

      print "Looking in dir $file\n" if $verbose;

      unless ($laborious) { # $laborious overrides pruning
        if( m/^(\d+\.[\d_]{3,})\z/s
             and do { my $x = $1; $x =~ tr/_//d; $x != $] }
           ) {
          $verbose and print "Perl $] version mismatch on $_, skipping.\n";
          return 'PRUNE';
        }

        if( m/^([A-Za-z][a-zA-Z0-9_]*)\z/s ) {
          $verbose and print "$_ is a well-named module subdir.  Looking....\n";
        } else {
          $verbose and print "$_ is a fishy directory name.  Skipping.\n";
          return 'PRUNE';
        }
      } # end unless $laborious

      $self->{'_dirs_visited'}{$file} = 1;
      return; # (not pruning);
    }

      
    # Make sure it's a file even worth even considering
    if($laborious) {
      unless(
        m/\.(pod|pm|plx?)\z/i || -x _ and -T _
         # Note that the cheapest operation (the RE) is run first.
      ) {
        $verbose > 1 and print " Brushing off uninteresting $file\n";
        return;
      }
    } else {
      unless( m/^[-_a-zA-Z0-9]+\.(?:pod|pm|plx?)\z/is ) {
        $verbose > 1 and print " Brushing off oddly-named $file\n";
        return;
      }
    }

    $verbose and print "Considering item $file\n";
    my $name = $self->_path2modname( $file, $shortname, $modname_bits );
    $verbose > 0.01 and print " Nominating $file as $name\n";
        
    if($limit_re and $name !~ m/$limit_re/i) {
      $verbose and print "Shunning $name as not matching $limit_re\n";
      return;
    }

    if( !$shadows and $name2path->{$name} ) {
      $verbose and print "Not worth considering $file ",
        "-- already saw $name as ",
        join(' ', grep($path2name->{$_} eq $name, keys %$path2name)), "\n";
      return;
    }
        
    # Put off until as late as possible the expense of
    #  actually reading the file:
    if( m/\.pod\z/is ) {
      # just assume it has pod, okay?
    } else {
      $progress and $progress->reach($self->{'_scan_count'}, "Scanning $file");
      return unless $self->contains_pod( $file );
    }
    ++ $self->{'_scan_count'};

    # Or finally take note of it:
    if( $name2path->{$name} ) {
      $verbose and print
       "Duplicate POD found (shadowing?): $name ($file)\n",
       "    Already seen in ",
       join(' ', grep($path2name->{$_} eq $name, keys %$path2name)), "\n";
    } else {
      $name2path->{$name} = $file; # Noting just the first occurrence
    }
    $verbose and print "  Noting $name = $file\n";
    if( $callback ) {
      local $_ = $_; # insulate from changes, just in case
      $callback->($file, $name);
    }
    $path2name->{$file} = $name;
    return;
  }
}


sub _path2modname {
  my($self, $file, $shortname, $modname_bits) = @_;

  # this code simplifies the POD name for Perl modules:
  # * remove "site_perl"
  # * remove e.g. "i586-linux" (from 'archname')
  # * remove e.g. 5.00503
  # * remove pod/ if followed by perl*.pod (e.g. in pod/perlfunc.pod)
  # * dig into the file for case-preserved name if not already mixed case

  my @m = @$modname_bits;
  my $x;
  my $verbose = $self->verbose;

  # Shaving off leading naughty-bits
  while(@m
    and defined($x = lc( $m[0] ))
    and(  $x eq 'site_perl'
       or($x eq 'pod' and @m == 1 and $shortname =~ m{^perl.*\.pod$}s )
       or $x =~ m{\\d+\\.z\\d+([_.]?\\d+)?}  # if looks like a vernum
       or $x eq lc( $Config::Config{'archname'} )
  )) { shift @m }

  my $name = join '::', @m, $shortname;
  $self->_simplify_base($name);

  # On VMS, case-preserved document names can't be constructed from
  # filenames, so try to extract them from the "=head1 NAME" tag in the
  # file instead.
  if ($^O eq 'VMS' && ($name eq lc($name) || $name eq uc($name))) {
      open PODFILE, "<$file" or die "_path2modname: Can't open $file: $!";
      my $in_pod = 0;
      my $in_name = 0;
      my $line;
      while ($line = <PODFILE>) {
        chomp $line;
        $in_pod = 1 if ($line =~ m/^=\w/);
        $in_pod = 0 if ($line =~ m/^=cut/);
        next unless $in_pod;         # skip non-pod text
        next if ($line =~ m/^\s*\z/);           # and blank lines
        next if ($in_pod && ($line =~ m/^X</)); # and commands
        if ($in_name) {
          if ($line =~ m/(\w+::)?(\w+)/) {
            # substitute case-preserved version of name
            my $podname = $2;
            my $prefix = $1 || '';
            $verbose and print "Attempting case restore of '$name' from '$prefix$podname'\n";
            unless ($name =~ s/$prefix$podname/$prefix$podname/i) {
              $verbose and print "Attempting case restore of '$name' from '$podname'\n";
              $name =~ s/$podname/$podname/i;
            }
            last;
          }
        }
        $in_name = 1 if ($line =~ m/^=head1 NAME/);
    }
    close PODFILE;
  }

  return $name;
}


sub _recurse_dir {
  my($self, $startdir, $callback, $modname_bits) = @_;

  my $maxdepth = $self->{'fs_recursion_maxdepth'} || 10;
  my $verbose = $self->verbose;

  my $here_string = File::Spec->curdir;
  my $up_string   = File::Spec->updir;
  $modname_bits ||= [];

  my $recursor;
  $recursor = sub {
    my($dir_long, $dir_bare) = @_;
    if( @$modname_bits >= 10 ) {
      $verbose and print "Too deep! [@$modname_bits]\n";
      return;
    }

    unless(-d $dir_long) {
      $verbose > 2 and print "But it's not a dir! $dir_long\n";
      return;
    }
    unless( opendir(INDIR, $dir_long) ) {
      $verbose > 2 and print "Can't opendir $dir_long : $!\n";
      closedir(INDIR);
      return
    }
    my @items = sort readdir(INDIR);
    closedir(INDIR);

    push @$modname_bits, $dir_bare unless $dir_bare eq '';

    my $i_full;
    foreach my $i (@items) {
      next if $i eq $here_string or $i eq $up_string or $i eq '';
      $i_full = File::Spec->catfile( $dir_long, $i );

      if(!-r $i_full) {
        $verbose and print "Skipping unreadable $i_full\n";
       
      } elsif(-f $i_full) {
        $_ = $i;
        $callback->(          $i_full, $i, 0, $modname_bits );

      } elsif(-d _) {
        $i =~ s/\.DIR\z//i if $^O eq 'VMS';
        $_ = $i;
        my $rv = $callback->( $i_full, $i, 1, $modname_bits ) || '';

        if($rv eq 'PRUNE') {
          $verbose > 1 and print "OK, pruning";
        } else {
          # Otherwise, recurse into it
          $recursor->( File::Spec->catdir($dir_long, $i) , $i);
        }
      } else {
        $verbose > 1 and print "Skipping oddity $i_full\n";
      }
    }
    pop @$modname_bits;
    return;
  };;

  local $_;
  $recursor->($startdir, '');

  undef $recursor;  # allow it to be GC'd

  return;  
}



sub run {
  # A function, useful in one-liners

  my $self = __PACKAGE__->new;
  $self->limit_glob($ARGV[0]) if @ARGV;
  $self->callback( sub {
    my($file, $name) = @_;
    my $version = '';
     
    # Yes, I know we won't catch the version in like a File/Thing.pm
    #  if we see File/Thing.pod first.  That's just the way the
    #  cookie crumbles.  -- SMB
     
    if($file =~ m/\.pod$/i) {
      # Don't bother looking for $VERSION in .pod files
      DEBUG and print "Not looking for \$VERSION in .pod $file\n";
    } elsif( !open(INPOD, $file) ) {
      DEBUG and print "Couldn't open $file: $!\n";
      close(INPOD);
    } else {
      # Sane case: file is readable
      my $lines = 0;
      while(<INPOD>) {
        last if $lines++ > $MAX_VERSION_WITHIN; # some degree of sanity
        if( s/^\s*\$VERSION\s*=\s*//s and m/\d/ ) {
          DEBUG and print "Found version line (#$lines): $_";
          s/\s*\#.*//s;
          s/\;\s*$//s;
          s/\s+$//s;
          s/\t+/ /s; # nix tabs
          # Optimize the most common cases:
          $_ = "v$1"
            if m{^v?["']?([0-9_]+(\.[0-9_]+)*)["']?$}s
             # like in $VERSION = "3.14159";
             or m{\$Revision:\s*([0-9_]+(?:\.[0-9_]+)*)\s*\$}s
             # like in sprintf("%d.%02d", q$Revision: 4.13 $ =~ /(\d+)\.(\d+)/);
          ;
           
          # Like in sprintf("%d.%s", map {s/_//g; $_} q$Name: release-0_55-public $ =~ /-(\d+)_([\d_]+)/)
          $_ = sprintf("v%d.%s",
            map {s/_//g; $_}
              $1 =~ m/-(\d+)_([\d_]+)/) # snare just the numeric part
           if m{\$Name:\s*([^\$]+)\$}s 
          ;
          $version = $_;
          DEBUG and print "Noting $version as version\n";
          last;
        }
      }
      close(INPOD);
    }
    print "$name\t$version\t$file\n";
    return;
    # End of callback!
  });

  $self->survey;
}


sub simplify_name {
  my($self, $str) = @_;
    
  # Remove all path components
  #                             XXX Why not just use basename()? -- SMB

  if ($^O eq 'MacOS') { $str =~ s{^.*:+}{}s }
  else                { $str =~ s{^.*/+}{}s }
  
  $self->_simplify_base($str);
  return $str;
}


sub _simplify_base {   # Internal method only

  # strip Perl's own extensions
  $_[1] =~ s/\.(pod|pm|plx?)\z//i;

  # strip meaningless extensions on Win32 and OS/2
  $_[1] =~ s/\.(bat|exe|cmd)\z//i if $^O =~ /mswin|os2/i;

  # strip meaningless extensions on VMS
  $_[1] =~ s/\.(com)\z//i if $^O eq 'VMS';

  return;
}


sub _expand_inc {
  my($self, $search_dirs) = @_;
  
  return unless $self->{'inc'};

  if ($^O eq 'MacOS') {
    push @$search_dirs,
      grep $_ ne File::Spec->curdir, $self->_mac_whammy(@INC);
  # Any other OSs need custom handling here?
  } else {
    push @$search_dirs, grep $_ ne File::Spec->curdir,  @INC;
  }

  $self->{'laborious'} = 0;   # Since inc said to use INC
  return;
}


sub _mac_whammy { # Tolerate '.', './some_dir' and '(../)+some_dir' on Mac OS
  my @them;
  (undef,@them) = @_;
  for $_ (@them) {
    if ( $_ eq '.' ) {
      $_ = ':';
    } elsif ( $_ =~ s|^((?:\.\./)+)|':' x (length($1)/3)|e ) {
      $_ = ':'. $_;
    } else {
      $_ =~ s|^\./|:|;
    }
  }
  return @them;
}


sub _limit_glob_to_limit_re {
  my $self = $_[0];
  my $limit_glob = $self->{'limit_glob'} || return;

  my $limit_re = '^' . quotemeta($limit_glob) . '$';
  $limit_re =~ s/\\\?/./g;    # glob "?" => "."
  $limit_re =~ s/\\\*/.*?/g;  # glob "*" => ".*?"
  $limit_re =~ s/\.\*\?\$$//s; # final glob "*" => ".*?$" => ""

  $self->{'verbose'} and print "Turning limit_glob $limit_glob into re $limit_re\n";

  # A common optimization:
  if(!exists($self->{'dir_prefix'})
    and $limit_glob =~ m/^(?:\w+\:\:)+/s  # like "File::*" or "File::Thing*"
    # Optimize for sane and common cases (but not things like "*::File")
  ) {
    $self->{'dir_prefix'} = join "::", $limit_glob =~ m/^(?:\w+::)+/sg;
    $self->{'verbose'} and print " and setting dir_prefix to $self->{'dir_prefix'}\n";
  }

  return $limit_re;
}



sub find {
  my($self, $pod, @search_dirs) = @_;
  $self = $self->new unless ref $self; # tolerate being a class method

  # Check usage
  Carp::carp 'Usage: \$self->find($podname, ...)'
   unless defined $pod and length $pod;

  my $verbose = $self->verbose;

  # Split on :: and then join the name together using File::Spec
  my @parts = split /::/, $pod;
  $verbose and print "Chomping {$pod} => {@parts}\n";

  #@search_dirs = File::Spec->curdir unless @search_dirs;
  
  if( $self->inc ) {
    if( $^O eq 'MacOS' ) {
      push @search_dirs, $self->_mac_whammy(@INC);
    } else {
      push @search_dirs,                    @INC;
    }

    # Add location of pod documentation for perl man pages (eg perlfunc)
    # This is a pod directory in the private install tree
    #my $perlpoddir = File::Spec->catdir($Config::Config{'installprivlib'},
    #					'pod');
    #push (@search_dirs, $perlpoddir)
    #  if -d $perlpoddir;

    # Add location of binaries such as pod2text:
    push @search_dirs, $Config::Config{'scriptdir'};
     # and if that's undef or q{} or nonexistent, we just ignore it later
  }

  my %seen_dir;
 Dir:
  foreach my $dir ( @search_dirs ) {
    next unless defined $dir and length $dir;
    next if $seen_dir{$dir};
    $seen_dir{$dir} = 1;
    unless(-d $dir) {
      print "Directory $dir does not exist\n" if $verbose;
      next Dir;
    }

    print "Looking in directory $dir\n" if $verbose;
    my $fullname = File::Spec->catfile( $dir, @parts );
    print "Filename is now $fullname\n" if $verbose;

    foreach my $ext ('', '.pod', '.pm', '.pl') {   # possible extensions
      my $fullext = $fullname . $ext;
      if( -f $fullext  and  $self->contains_pod( $fullext ) ){
        print "FOUND: $fullext\n" if $verbose;
        return $fullext;
      }
    }
    my $subdir = File::Spec->catdir($dir,'pod');
    if(-d $subdir) {  # slip in the ./pod dir too
      $verbose and print "Noticing $subdir and stopping there...\n";
      $dir = $subdir;
      redo Dir;
    }
  }

  return undef;
}


sub contains_pod {
  my($self, $file) = @_;
  my $verbose = $self->{'verbose'};

  # check for one line of POD
  $verbose > 1 and print " Scanning $file for pod...\n";
  unless( open(MAYBEPOD,"<$file") ) {
    print "Error: $file is unreadable: $!\n";
    return undef;
  }

  sleep($SLEEPY - 1) if $SLEEPY;
   # avoid totally hogging the processor on OSs with poor process control
  
  local $_;
  while( <MAYBEPOD> ) {
    if(m/^=(head\d|pod|over|item)\b/s) {
      close(MAYBEPOD) || die "Bizarre error closing $file: $!\nAborting";
      chomp;
      $verbose > 1 and print "  Found some pod ($_) in $file\n";
      return 1;
    }
  }
  close(MAYBEPOD) || die "Bizarre error closing $file: $!\nAborting";
  $verbose > 1 and print "  No POD in $file, skipping.\n";
  return 0;
}


sub _accessorize {  # A simple-minded method-maker
  shift;
  no strict 'refs';
  foreach my $attrname (@_) {
    *{caller() . '::' . $attrname} = sub {
      use strict;
      $Carp::CarpLevel = 1,  Carp::croak(
       "Accessor usage: \$obj->$attrname() or \$obj->$attrname(\$new_value)"
      ) unless (@_ == 1 or @_ == 2) and ref $_[0];

      # Read access:
      return $_[0]->{$attrname} if @_ == 1;

      # Write access:
      $_[0]->{$attrname} = $_[1];
      return $_[0]; # RETURNS MYSELF!
    };
  }
  # Ya know, they say accessories make the ensemble!
  return;
}

sub _state_as_string {
  my $self = $_[0];
  return '' unless ref $self;
  my @out = "{\n  # State of $self ...\n";
  foreach my $k (sort keys %$self) {
    push @out, "  ", _esc($k), " => ", _esc($self->{$k}), ",\n";
  }
  push @out, "}\n";
  my $x = join '', @out;
  $x =~ s/^/#/mg;
  return $x;
}

sub _esc {
  my $in = $_[0];
  return 'undef' unless defined $in;
  $in =~
    s<([^\x20\x21\x23\x27-\x3F\x41-\x5B\x5D-\x7E])>
     <'\\x'.(unpack("H2",$1))>eg;
  return qq{"$in"};
}


run() unless caller;  # run if "perl whatever/Search.pm"

1;


__END__


