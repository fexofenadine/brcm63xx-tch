package ExtUtils::Installed;

use 5.00503;
use strict;
use Carp qw();
use ExtUtils::Packlist;
use ExtUtils::MakeMaker;
use Config;
use File::Find;
use File::Basename;
use File::Spec;

my $Is_VMS = $^O eq 'VMS';
my $DOSISH = ($^O =~ /^(MSWin\d\d|os2|dos|mint)$/);

require VMS::Filespec if $Is_VMS;

use vars qw($VERSION);
$VERSION = '1.999005';
$VERSION = eval $VERSION;

sub _is_prefix {
    my ($self, $path, $prefix) = @_;
    return unless defined $prefix && defined $path;

    if( $Is_VMS ) {
        $prefix = VMS::Filespec::unixify($prefix);
        $path   = VMS::Filespec::unixify($path);
    }

    # Unix path normalization.
    $prefix = File::Spec->canonpath($prefix);

    return 1 if substr($path, 0, length($prefix)) eq $prefix;

    if ($DOSISH) {
        $path =~ s|\\|/|g;
        $prefix =~ s|\\|/|g;
        return 1 if $path =~ m{^\Q$prefix\E}i;
    }
    return(0);
}

sub _is_doc {
    my ($self, $path) = @_;

    my $man1dir = $self->{':private:'}{Config}{man1direxp};
    my $man3dir = $self->{':private:'}{Config}{man3direxp};
    return(($man1dir && $self->_is_prefix($path, $man1dir))
           ||
           ($man3dir && $self->_is_prefix($path, $man3dir))
           ? 1 : 0)
}

sub _is_type {
    my ($self, $path, $type) = @_;
    return 1 if $type eq "all";

    return($self->_is_doc($path)) if $type eq "doc";
    my $conf= $self->{':private:'}{Config};
    if ($type eq "prog") {
        return($self->_is_prefix($path, $conf->{prefix} || $conf->{prefixexp})
               && !($self->_is_doc($path)) ? 1 : 0);
    }
    return(0);
}

sub _is_under {
    my ($self, $path, @under) = @_;
    $under[0] = "" if (! @under);
    foreach my $dir (@under) {
        return(1) if ($self->_is_prefix($path, $dir));
    }

    return(0);
}

sub _fix_dirs {
    my ($self, @dirs)= @_;
    # File::Find does not know how to deal with VMS filepaths.
    if( $Is_VMS ) {
        $_ = VMS::Filespec::unixify($_)
            for @dirs;
    }

    if ($DOSISH) {
        s|\\|/|g for @dirs;
    }
    return wantarray ? @dirs : $dirs[0];
}

sub _make_entry {
    my ($self, $module, $packlist_file, $modfile)= @_;

    my $data= {
        module => $module,
        packlist => scalar(ExtUtils::Packlist->new($packlist_file)),
        packlist_file => $packlist_file,
    };

    if (!$modfile) {
        $data->{version} = $self->{':private:'}{Config}{version};
    } else {
        $data->{modfile} = $modfile;
        # Find the top-level module file in @INC
        $data->{version} = '';
        foreach my $dir (@{$self->{':private:'}{INC}}) {
            my $p = File::Spec->catfile($dir, $modfile);
            if (-r $p) {
                $module = _module_name($p, $module) if $Is_VMS;

                $data->{version} = MM->parse_version($p);
                $data->{version_from} = $p;
                $data->{packlist_valid} = exists $data->{packlist}{$p};
                last;
            }
        }
    }
    $self->{$module}= $data;
}

our $INSTALLED;
sub new {
    my ($class) = shift(@_);
    $class = ref($class) || $class;

    my %args = @_;

    return $INSTALLED if $INSTALLED and ($args{default_get} || $args{default});

    my $self = bless {}, $class;

    $INSTALLED= $self if $args{default_set} || $args{default};


    if ($args{config_override}) {
        eval {
            $self->{':private:'}{Config} = { %{$args{config_override}} };
        } or Carp::croak(
            "The 'config_override' parameter must be a hash reference."
        );
    }
    else {
        $self->{':private:'}{Config} = \%Config;
    }

    for my $tuple ([inc_override => INC => [ @INC ] ],
                   [ extra_libs => EXTRA => [] ])
    {
        my ($arg,$key,$val)=@$tuple;
        if ( $args{$arg} ) {
            eval {
                $self->{':private:'}{$key} = [ @{$args{$arg}} ];
            } or Carp::croak(
                "The '$arg' parameter must be an array reference."
            );
        }
        elsif ($val) {
            $self->{':private:'}{$key} = $val;
        }
    }
    {
        my %dupe;
        @{$self->{':private:'}{LIBDIRS}} =
            grep { $_ ne '.' || ! $args{skip_cwd} }
            grep { -e $_ && !$dupe{$_}++ }
            @{$self->{':private:'}{EXTRA}}, @{$self->{':private:'}{INC}};
    }

    my @dirs= $self->_fix_dirs(@{$self->{':private:'}{LIBDIRS}});

    # Read the core packlist
    my $archlib = $self->_fix_dirs($self->{':private:'}{Config}{archlibexp});
    $self->_make_entry("Perl",File::Spec->catfile($archlib, '.packlist'));

    my $root;
    # Read the module packlists
    my $sub = sub {
        # Only process module .packlists
        return if $_ ne ".packlist" || $File::Find::dir eq $archlib;

        # Hack of the leading bits of the paths & convert to a module name
        my $module = $File::Find::name;
        my $found = $module =~ s!^.*?/auto/(.*)/.packlist!$1!s
            or do {
            # warn "Woah! \$_=$_\n\$module=$module\n\$File::Find::dir=$File::Find::dir\n",
            #    join ("\n",@dirs);
            return;
        };

        my $modfile = "$module.pm";
        $module =~ s!/!::!g;

        return if $self->{$module}; #shadowing?
        $self->_make_entry($module,$File::Find::name,$modfile);
    };
    while (@dirs) {
        $root= shift @dirs;
        next if !-d $root;
        find($sub,$root);
    }

    return $self;
}

sub _module_name {
    my($file, $orig_module) = @_;

    my $module = '';
    if (open PACKFH, $file) {
        while (<PACKFH>) {
            if (/package\s+(\S+)\s*;/) {
                my $pack = $1;
                # Make a sanity check, that lower case $module
                # is identical to lowercase $pack before
                # accepting it
                if (lc($pack) eq lc($orig_module)) {
                    $module = $pack;
                    last;
                }
            }
        }
        close PACKFH;
    }

    print STDERR "Couldn't figure out the package name for $file\n"
      unless $module;

    return $module;
}

sub modules {
    my ($self) = @_;
    $self= $self->new(default=>1) if !ref $self;

    # Bug/feature of sort in scalar context requires this.
    return wantarray
        ? sort grep { not /^:private:$/ } keys %$self
        : grep { not /^:private:$/ } keys %$self;
}

sub files {
    my ($self, $module, $type, @under) = @_;
    $self= $self->new(default=>1) if !ref $self;

    # Validate arguments
    Carp::croak("$module is not installed") if (! exists($self->{$module}));
    $type = "all" if (! defined($type));
    Carp::croak('type must be "all", "prog" or "doc"')
        if ($type ne "all" && $type ne "prog" && $type ne "doc");

    my (@files);
    foreach my $file (keys(%{$self->{$module}{packlist}})) {
        push(@files, $file)
          if ($self->_is_type($file, $type) &&
              $self->_is_under($file, @under));
    }
    return(@files);
}

sub directories {
    my ($self, $module, $type, @under) = @_;
    $self= $self->new(default=>1) if !ref $self;
    my (%dirs);
    foreach my $file ($self->files($module, $type, @under)) {
        $dirs{dirname($file)}++;
    }
    return sort keys %dirs;
}

sub directory_tree {
    my ($self, $module, $type, @under) = @_;
    $self= $self->new(default=>1) if !ref $self;
    my (%dirs);
    foreach my $dir ($self->directories($module, $type, @under)) {
        $dirs{$dir}++;
        my ($last) = ("");
        while ($last ne $dir) {
            $last = $dir;
            $dir = dirname($dir);
            last if !$self->_is_under($dir, @under);
            $dirs{$dir}++;
        }
    }
    return(sort(keys(%dirs)));
}

sub validate {
    my ($self, $module, $remove) = @_;
    $self= $self->new(default=>1) if !ref $self;
    Carp::croak("$module is not installed") if (! exists($self->{$module}));
    return($self->{$module}{packlist}->validate($remove));
}

sub packlist {
    my ($self, $module) = @_;
    $self= $self->new(default=>1) if !ref $self;
    Carp::croak("$module is not installed") if (! exists($self->{$module}));
    return($self->{$module}{packlist});
}

sub version {
    my ($self, $module) = @_;
    $self= $self->new(default=>1) if !ref $self;
    Carp::croak("$module is not installed") if (! exists($self->{$module}));
    return($self->{$module}{version});
}

sub debug_dump {
    my ($self, $module) = @_;
    $self= $self->new(default=>1) if !ref $self;
    local $self->{":private:"}{Config};
    require Data::Dumper;
    print Data::Dumper->new([$self])->Sortkeys(1)->Indent(1)->Dump();
}


1;

__END__

