package ExtUtils::MM_Any;

use strict;
our $VERSION = '6.98';

use Carp;
use File::Spec;
use File::Basename;
BEGIN { our @ISA = qw(File::Spec); }

use ExtUtils::MakeMaker qw($Verbose);

use ExtUtils::MakeMaker::Config;


my $Curdir  = __PACKAGE__->curdir;
my $Rootdir = __PACKAGE__->rootdir;
my $Updir   = __PACKAGE__->updir;



sub os_flavor_is {
    my $self = shift;
    my %flavors = map { ($_ => 1) } $self->os_flavor;
    return (grep { $flavors{$_} } @_) ? 1 : 0;
}



sub can_load_xs {
    return defined &DynaLoader::boot_DynaLoader ? 1 : 0;
}



sub split_command {
    my($self, $cmd, @args) = @_;

    my @cmds = ();
    return(@cmds) unless @args;

    # If the command was given as a here-doc, there's probably a trailing
    # newline.
    chomp $cmd;

    # set aside 30% for macro expansion.
    my $len_left = int($self->max_exec_len * 0.70);
    $len_left -= length $self->_expand_macros($cmd);

    do {
        my $arg_str = '';
        my @next_args;
        while( @next_args = splice(@args, 0, 2) ) {
            # Two at a time to preserve pairs.
            my $next_arg_str = "\t  ". join ' ', @next_args, "\n";

            if( !length $arg_str ) {
                $arg_str .= $next_arg_str
            }
            elsif( length($arg_str) + length($next_arg_str) > $len_left ) {
                unshift @args, @next_args;
                last;
            }
            else {
                $arg_str .= $next_arg_str;
            }
        }
        chop $arg_str;

        push @cmds, $self->escape_newlines("$cmd \n$arg_str");
    } while @args;

    return @cmds;
}


sub _expand_macros {
    my($self, $cmd) = @_;

    $cmd =~ s{\$\((\w+)\)}{
        defined $self->{$1} ? $self->{$1} : "\$($1)"
    }e;
    return $cmd;
}



sub echo {
    my($self, $text, $file, $opts) = @_;

    # Compatibility with old options
    if( !ref $opts ) {
        my $append = $opts;
        $opts = { append => $append || 0 };
    }
    $opts->{allow_variables} = 0 unless defined $opts->{allow_variables};

    my $ql_opts = { allow_variables => $opts->{allow_variables} };
    my @cmds = map { '$(NOECHO) $(ECHO) '.$self->quote_literal($_, $ql_opts) }
               split /\n/, $text;
    if( $file ) {
        my $redirect = $opts->{append} ? '>>' : '>';
        $cmds[0] .= " $redirect $file";
        $_ .= " >> $file" foreach @cmds[1..$#cmds];
    }

    return @cmds;
}



sub wraplist {
    my $self = shift;
    return join " \\\n\t", @_;
}



sub maketext_filter { return $_[1] }



sub escape_dollarsigns {
    my($self, $text) = @_;

    # Escape dollar signs which are not starting a variable
    $text =~ s{\$ (?!\() }{\$\$}gx;

    return $text;
}



sub escape_all_dollarsigns {
    my($self, $text) = @_;

    # Escape dollar signs
    $text =~ s{\$}{\$\$}gx;

    return $text;
}



sub make {
    my $self = shift;

    my $make = lc $self->{MAKE};

    # Truncate anything like foomake6 to just foomake.
    $make =~ s/^(\w+make).*/$1/;

    # Turn gnumake into gmake.
    $make =~ s/^gnu/g/;

    return $make;
}



sub all_target {
    my $self = shift;

    return <<'MAKE_EXT';
all :: pure_all
	$(NOECHO) $(NOOP)
MAKE_EXT

}



sub blibdirs_target {
    my $self = shift;

    my @dirs = map { uc "\$(INST_$_)" } qw(libdir archlib
                                           autodir archautodir
                                           bin script
                                           man1dir man3dir
                                          );

    my @exists = map { $_.'$(DFSEP).exists' } @dirs;

    my $make = sprintf <<'MAKE', join(' ', @exists);
blibdirs : %s
	$(NOECHO) $(NOOP)

blibdirs.ts : blibdirs
	$(NOECHO) $(NOOP)

MAKE

    $make .= $self->dir_target(@dirs);

    return $make;
}



sub clean {

    my($self, %attribs) = @_;
    my @m;
    push(@m, '

clean :: clean_subdirs
');

    my @files = sort values %{$self->{XS}}; # .c files from *.xs files
    my @dirs  = qw(blib);

    # Normally these are all under blib but they might have been
    # redefined.
    # XXX normally this would be a good idea, but the Perl core sets
    # INST_LIB = ../../lib rather than actually installing the files.
    # So a "make clean" in an ext/ directory would blow away lib.
    # Until the core is adjusted let's leave this out.


    if( $attribs{FILES} ) {
        # Use @dirs because we don't know what's in here.
        push @dirs, ref $attribs{FILES}                ?
                        @{$attribs{FILES}}             :
                        split /\s+/, $attribs{FILES}   ;
    }

    push(@files, qw[$(MAKE_APERL_FILE)
                    MYMETA.json MYMETA.yml perlmain.c tmon.out mon.out so_locations
                    blibdirs.ts pm_to_blib pm_to_blib.ts
                    *$(OBJ_EXT) *$(LIB_EXT) perl.exe perl perl$(EXE_EXT)
                    $(BOOTSTRAP) $(BASEEXT).bso
                    $(BASEEXT).def lib$(BASEEXT).def
                    $(BASEEXT).exp $(BASEEXT).x
                   ]);

    push(@files, $self->catfile('$(INST_ARCHAUTODIR)','extralibs.all'));
    push(@files, $self->catfile('$(INST_ARCHAUTODIR)','extralibs.ld'));

    # core files
    if ($^O eq 'vos') {
        push(@files, qw[perl*.kp]);
    }
    else {
        push(@files, qw[core core.*perl.*.? *perl.core]);
    }

    push(@files, map { "core." . "[0-9]"x$_ } (1..5));

    # OS specific things to clean up.  Use @dirs since we don't know
    # what might be in here.
    push @dirs, $self->extra_clean_files;

    # Occasionally files are repeated several times from different sources
    { my(%f) = map { ($_ => 1) } @files; @files = sort keys %f; }
    { my(%d) = map { ($_ => 1) } @dirs;  @dirs  = sort keys %d; }

    push @m, map "\t$_\n", $self->split_command('- $(RM_F)',  @files);
    push @m, map "\t$_\n", $self->split_command('- $(RM_RF)', @dirs);

    # Leave Makefile.old around for realclean
    push @m, <<'MAKE';
	  $(NOECHO) $(RM_F) $(MAKEFILE_OLD)
	- $(MV) $(FIRST_MAKEFILE) $(MAKEFILE_OLD) $(DEV_NULL)
MAKE

    push(@m, "\t$attribs{POSTOP}\n")   if $attribs{POSTOP};

    join("", @m);
}



sub clean_subdirs_target {
    my($self) = shift;

    # No subdirectories, no cleaning.
    return <<'NOOP_FRAG' unless @{$self->{DIR}};
clean_subdirs :
	$(NOECHO) $(NOOP)
NOOP_FRAG


    my $clean = "clean_subdirs :\n";

    for my $dir (@{$self->{DIR}}) {
        my $subclean = $self->oneliner(sprintf <<'CODE', $dir);
exit 0 unless chdir '%s';  system '$(MAKE) clean' if -f '$(FIRST_MAKEFILE)';
CODE

        $clean .= "\t$subclean\n";
    }

    return $clean;
}



sub dir_target {
    my($self, @dirs) = @_;

    my $make = '';
    foreach my $dir (@dirs) {
        $make .= sprintf <<'MAKE', ($dir) x 4;
%s$(DFSEP).exists :: Makefile.PL
	$(NOECHO) $(MKPATH) %s
	$(NOECHO) $(CHMOD) $(PERM_DIR) %s
	$(NOECHO) $(TOUCH) %s$(DFSEP).exists

MAKE

    }

    return $make;
}



*dist_dir = *distdir;

sub distdir {
    my($self) = shift;

    my $meta_target = $self->{NO_META} ? '' : 'distmeta';
    my $sign_target = !$self->{SIGN}   ? '' : 'distsignature';

    return sprintf <<'MAKE_FRAG', $meta_target, $sign_target;
create_distdir :
	$(RM_RF) $(DISTVNAME)
	$(PERLRUN) "-MExtUtils::Manifest=manicopy,maniread" \
		-e "manicopy(maniread(),'$(DISTVNAME)', '$(DIST_CP)');"

distdir : create_distdir %s %s
	$(NOECHO) $(NOOP)

MAKE_FRAG

}



sub dist_test {
    my($self) = shift;

    my $mpl_args = join " ", map qq["$_"], @ARGV;

    my $test = $self->cd('$(DISTVNAME)',
                         '$(ABSPERLRUN) Makefile.PL '.$mpl_args,
                         '$(MAKE) $(PASTHRU)',
                         '$(MAKE) test $(PASTHRU)'
                        );

    return sprintf <<'MAKE_FRAG', $test;
disttest : distdir
	%s

MAKE_FRAG


}



sub dynamic {

    my($self) = shift;
    '
dynamic :: $(FIRST_MAKEFILE) $(BOOTSTRAP) $(INST_DYNAMIC)
	$(NOECHO) $(NOOP)
';
}



sub makemakerdflt_target {
    return <<'MAKE_FRAG';
makemakerdflt : all
	$(NOECHO) $(NOOP)
MAKE_FRAG

}



sub manifypods_target {
    my($self) = shift;

    my $man1pods      = '';
    my $man3pods      = '';
    my $dependencies  = '';

    # populate manXpods & dependencies:
    foreach my $name (sort keys %{$self->{MAN1PODS}}, sort keys %{$self->{MAN3PODS}}) {
        $dependencies .= " \\\n\t$name";
    }

    my $manify = <<END;
manifypods : pure_all $dependencies
END

    my @man_cmds;
    foreach my $section (qw(1 3)) {
        my $pods = $self->{"MAN${section}PODS"};
        push @man_cmds, $self->split_command(<<CMD, map {($_,$pods->{$_})} sort keys %$pods);
	\$(NOECHO) \$(POD2MAN) --section=$section --perm_rw=\$(PERM_RW)
CMD
    }

    $manify .= "\t\$(NOECHO) \$(NOOP)\n" unless @man_cmds;
    $manify .= join '', map { "$_\n" } @man_cmds;

    return $manify;
}

sub _has_cpan_meta {
    return eval {
      require CPAN::Meta;
      CPAN::Meta->VERSION(2.112150);
      1;
    };
}


sub metafile_target {
    my $self = shift;
    return <<'MAKE_FRAG' if $self->{NO_META} or ! _has_cpan_meta();
metafile :
	$(NOECHO) $(NOOP)
MAKE_FRAG

    my %metadata   = $self->metafile_data(
        $self->{META_ADD}   || {},
        $self->{META_MERGE} || {},
    );

    _fix_metadata_before_conversion( \%metadata );

    # paper over validation issues, but still complain, necessary because
    # there's no guarantee that the above will fix ALL errors
    my $meta = eval { CPAN::Meta->create( \%metadata, { lazy_validation => 1 } ) };
    warn $@ if $@ and
               $@ !~ /encountered CODE.*, but JSON can only represent references to arrays or hashes/;

    # use the original metadata straight if the conversion failed
    # or if it can't be stringified.
    if( !$meta                                                  ||
        !eval { $meta->as_string( { version => "1.4" } ) }      ||
        !eval { $meta->as_string }
    )
    {
        $meta = bless \%metadata, 'CPAN::Meta';
    }

    my @write_metayml = $self->echo(
      $meta->as_string({version => "1.4"}), 'META_new.yml'
    );
    my @write_metajson = $self->echo(
      $meta->as_string(), 'META_new.json'
    );

    my $metayml = join("\n\t", @write_metayml);
    my $metajson = join("\n\t", @write_metajson);
    return sprintf <<'MAKE_FRAG', $metayml, $metajson;
metafile : create_distdir
	$(NOECHO) $(ECHO) Generating META.yml
	%s
	-$(NOECHO) $(MV) META_new.yml $(DISTVNAME)/META.yml
	$(NOECHO) $(ECHO) Generating META.json
	%s
	-$(NOECHO) $(MV) META_new.json $(DISTVNAME)/META.json
MAKE_FRAG

}


sub _fix_metadata_before_conversion {
    my ( $metadata ) = @_;

    # we should never be called unless this already passed but
    # prefer to be defensive in case somebody else calls this

    return unless _has_cpan_meta;

    my $bad_version = $metadata->{version} &&
                      !CPAN::Meta::Validator->new->version( 'version', $metadata->{version} );

    # just delete all invalid versions
    if( $bad_version ) {
        warn "Can't parse version '$metadata->{version}'\n";
        $metadata->{version} = '';
    }

    my $validator = CPAN::Meta::Validator->new( $metadata );
    return if $validator->is_valid;

    # fix non-camelcase custom resource keys (only other trick we know)
    for my $error ( $validator->errors ) {
        my ( $key ) = ( $error =~ /Custom resource '(.*)' must be in CamelCase./ );
        next if !$key;

        # first try to remove all non-alphabetic chars
        ( my $new_key = $key ) =~ s/[^_a-zA-Z]//g;

        # if that doesn't work, uppercase first one
        $new_key = ucfirst $new_key if !$validator->custom_1( $new_key );

        # copy to new key if that worked
        $metadata->{resources}{$new_key} = $metadata->{resources}{$key}
          if $validator->custom_1( $new_key );

        # and delete old one in any case
        delete $metadata->{resources}{$key};
    }

    return;
}



sub _sort_pairs {
    my $sort  = shift;
    my $pairs = shift;
    return map  { $_ => $pairs->{$_} }
           sort $sort
           keys %$pairs;
}


sub _hash_merge {
    my ($self, $h, $k, $v) = @_;
    if (ref $h->{$k} eq 'ARRAY') {
        push @{$h->{$k}}, ref $v ? @$v : $v;
    } elsif (ref $h->{$k} eq 'HASH') {
        $self->_hash_merge($h->{$k}, $_, $v->{$_}) foreach keys %$v;
    } else {
        $h->{$k} = $v;
    }
}



sub metafile_data {
    my $self = shift;
    my($meta_add, $meta_merge) = @_;

    my %meta = (
        # required
        name         => $self->{DISTNAME},
        version      => _normalize_version($self->{VERSION}),
        abstract     => $self->{ABSTRACT} || 'unknown',
        license      => $self->{LICENSE} || 'unknown',
        dynamic_config => 1,

        # optional
        distribution_type => $self->{PM} ? 'module' : 'script',

        no_index     => {
            directory   => [qw(t inc)]
        },

        generated_by => "ExtUtils::MakeMaker version $ExtUtils::MakeMaker::VERSION",
        'meta-spec'  => {
            url         => 'http://module-build.sourceforge.net/META-spec-v1.4.html',
            version     => 1.4
        },
    );

    # The author key is required and it takes a list.
    $meta{author}   = defined $self->{AUTHOR}    ? $self->{AUTHOR} : [];

    {
      my $vers = _metaspec_version( $meta_add, $meta_merge );
      my $method = $vers =~ m!^2!
               ? '_add_requirements_to_meta_v2'
               : '_add_requirements_to_meta_v1_4';
      %meta = $self->$method( %meta );
    }

    while( my($key, $val) = each %$meta_add ) {
        $meta{$key} = $val;
    }

    while( my($key, $val) = each %$meta_merge ) {
        $self->_hash_merge(\%meta, $key, $val);
    }

    return %meta;
}



sub _metaspec_version {
  my ( $meta_add, $meta_merge ) = @_;
  return $meta_add->{'meta-spec'}->{version}
    if defined $meta_add->{'meta-spec'}
       and defined $meta_add->{'meta-spec'}->{version};
  return $meta_merge->{'meta-spec'}->{version}
    if defined $meta_merge->{'meta-spec'}
       and  defined $meta_merge->{'meta-spec'}->{version};
  return '1.4';
}

sub _add_requirements_to_meta_v1_4 {
    my ( $self, %meta ) = @_;

    # Check the original args so we can tell between the user setting it
    # to an empty hash and it just being initialized.
    if( $self->{ARGS}{CONFIGURE_REQUIRES} ) {
        $meta{configure_requires}
            = _normalize_prereqs($self->{CONFIGURE_REQUIRES});
    } else {
        $meta{configure_requires} = {
            'ExtUtils::MakeMaker'       => 0,
        };
    }

    if( $self->{ARGS}{BUILD_REQUIRES} ) {
        $meta{build_requires} = _normalize_prereqs($self->{BUILD_REQUIRES});
    } else {
        $meta{build_requires} = {
            'ExtUtils::MakeMaker'       => 0,
        };
    }

    if( $self->{ARGS}{TEST_REQUIRES} ) {
        $meta{build_requires} = {
          %{ $meta{build_requires} },
          %{ _normalize_prereqs($self->{TEST_REQUIRES}) },
        };
    }

    $meta{requires} = _normalize_prereqs($self->{PREREQ_PM})
        if defined $self->{PREREQ_PM};
    $meta{requires}{perl} = _normalize_version($self->{MIN_PERL_VERSION})
        if $self->{MIN_PERL_VERSION};

    return %meta;
}

sub _add_requirements_to_meta_v2 {
    my ( $self, %meta ) = @_;

    # Check the original args so we can tell between the user setting it
    # to an empty hash and it just being initialized.
    if( $self->{ARGS}{CONFIGURE_REQUIRES} ) {
        $meta{prereqs}{configure}{requires}
            = _normalize_prereqs($self->{CONFIGURE_REQUIRES});
    } else {
        $meta{prereqs}{configure}{requires} = {
            'ExtUtils::MakeMaker'       => 0,
        };
    }

    if( $self->{ARGS}{BUILD_REQUIRES} ) {
        $meta{prereqs}{build}{requires} = _normalize_prereqs($self->{BUILD_REQUIRES});
    } else {
        $meta{prereqs}{build}{requires} = {
            'ExtUtils::MakeMaker'       => 0,
        };
    }

    if( $self->{ARGS}{TEST_REQUIRES} ) {
        $meta{prereqs}{test}{requires} = _normalize_prereqs($self->{TEST_REQUIRES});
    }

    $meta{prereqs}{runtime}{requires} = _normalize_prereqs($self->{PREREQ_PM})
        if $self->{ARGS}{PREREQ_PM};
    $meta{prereqs}{runtime}{requires}{perl} = _normalize_version($self->{MIN_PERL_VERSION})
        if $self->{MIN_PERL_VERSION};

    return %meta;
}

sub _normalize_prereqs {
  my ($hash) = @_;
  my %prereqs;
  while ( my ($k,$v) = each %$hash ) {
    $prereqs{$k} = _normalize_version($v);
  }
  return \%prereqs;
}

sub _normalize_version {
  my ($version) = @_;
  $version = 0 unless defined $version;

  if ( ref $version eq 'version' ) { # version objects
    $version = $version->is_qv ? $version->normal : $version->stringify;
  }
  elsif ( $version =~ /^[^v][^.]*\.[^.]+\./ ) { # no leading v, multiple dots
    # normalize string tuples without "v": "1.2.3" -> "v1.2.3"
    $version = "v$version";
  }
  else {
    # leave alone
  }
  return $version;
}


sub _dump_hash {
    croak "first argument should be a hash ref" unless ref $_[0] eq 'HASH';
    my $options = shift;
    my %hash = @_;

    # Use a list to preserve order.
    my @pairs;

    my $k_sort
        = exists $options->{key_sort} ? $options->{key_sort}
                                      : sub { lc $a cmp lc $b };
    if ($k_sort) {
        croak "'key_sort' should be a coderef" unless ref $k_sort eq 'CODE';
        @pairs = _sort_pairs($k_sort, \%hash);
    } else { # list of pairs, no sorting
        @pairs = @_;
    }

    my $yaml     = $options->{use_header} ? "--- #YAML:1.0\n" : '';
    my $indent   = $options->{indent} || '';
    my $k_length = min(
        ($options->{max_key_length} || 20),
        max(map { length($_) + 1 } grep { !ref $hash{$_} } keys %hash)
    );
    my $customs  = $options->{customs} || {};

    # printf format for key
    my $k_format = "%-${k_length}s";

    while( @pairs ) {
        my($key, $val) = splice @pairs, 0, 2;
        $val = '~' unless defined $val;
        if(ref $val eq 'HASH') {
            if ( keys %$val ) {
                my %k_options = ( # options for recursive call
                    delta => $options->{delta},
                    use_header => 0,
                    indent => $indent . $options->{delta},
                );
                if (exists $customs->{$key}) {
                    my %k_custom = %{$customs->{$key}};
                    foreach my $k (qw(key_sort max_key_length customs)) {
                        $k_options{$k} = $k_custom{$k} if exists $k_custom{$k};
                    }
                }
                $yaml .= $indent . "$key:\n"
                  . _dump_hash(\%k_options, %$val);
            }
            else {
                $yaml .= $indent . "$key:  {}\n";
            }
        }
        elsif (ref $val eq 'ARRAY') {
            if( @$val ) {
                $yaml .= $indent . "$key:\n";

                for (@$val) {
                    croak "only nested arrays of non-refs are supported" if ref $_;
                    $yaml .= $indent . $options->{delta} . "- $_\n";
                }
            }
            else {
                $yaml .= $indent . "$key:  []\n";
            }
        }
        elsif( ref $val and !blessed($val) ) {
            croak "only nested hashes, arrays and objects are supported";
        }
        else {  # if it's an object, just stringify it
            $yaml .= $indent . sprintf "$k_format  %s\n", "$key:", $val;
        }
    };

    return $yaml;

}

sub blessed {
    return eval { $_[0]->isa("UNIVERSAL"); };
}

sub max {
    return (sort { $b <=> $a } @_)[0];
}

sub min {
    return (sort { $a <=> $b } @_)[0];
}


sub metafile_file {
    my $self = shift;

    my %dump_options = (
        use_header => 1,
        delta      => ' ' x 4,
        key_sort   => undef,
    );
    return _dump_hash(\%dump_options, @_);

}



sub distmeta_target {
    my $self = shift;

    my @add_meta = (
      $self->oneliner(<<'CODE', ['-MExtUtils::Manifest=maniadd']),
exit unless -e q{META.yml};
eval { maniadd({q{META.yml} => q{Module YAML meta-data (added by MakeMaker)}}) }
    or print "Could not add META.yml to MANIFEST: $${'@'}\n"
CODE
      $self->oneliner(<<'CODE', ['-MExtUtils::Manifest=maniadd'])
exit unless -f q{META.json};
eval { maniadd({q{META.json} => q{Module JSON meta-data (added by MakeMaker)}}) }
    or print "Could not add META.json to MANIFEST: $${'@'}\n"
CODE
    );

    my @add_meta_to_distdir = map { $self->cd('$(DISTVNAME)', $_) } @add_meta;

    return sprintf <<'MAKE', @add_meta_to_distdir;
distmeta : create_distdir metafile
	$(NOECHO) %s
	$(NOECHO) %s

MAKE

}



sub mymeta {
    my $self = shift;
    my $file = shift || ''; # for testing

    my $mymeta = $self->_mymeta_from_meta($file);
    my $v2 = 1;

    unless ( $mymeta ) {
        my @metadata = $self->metafile_data(
            $self->{META_ADD}   || {},
            $self->{META_MERGE} || {},
        );
        $mymeta = {@metadata};
        $v2 = 0;
    }

    # Overwrite the non-configure dependency hashes

    my $method = $v2
               ? '_add_requirements_to_meta_v2'
               : '_add_requirements_to_meta_v1_4';

    $mymeta = { $self->$method( %$mymeta ) };

    $mymeta->{dynamic_config} = 0;

    return $mymeta;
}


sub _mymeta_from_meta {
    my $self = shift;
    my $metafile = shift || ''; # for testing

    return unless _has_cpan_meta();

    my $meta;
    for my $file ( $metafile, "META.json", "META.yml" ) {
      next unless -e $file;
      eval {
          $meta = CPAN::Meta->load_file($file)->as_struct( { version => 2 } );
      };
      last if $meta;
    }
    return unless $meta;

    # META.yml before 6.25_01 cannot be trusted.  META.yml lived in the source directory.
    # There was a good chance the author accidentally uploaded a stale META.yml if they
    # rolled their own tarball rather than using "make dist".
    if ($meta->{generated_by} &&
        $meta->{generated_by} =~ /ExtUtils::MakeMaker version ([\d\._]+)/) {
        my $eummv = do { local $^W = 0; $1+0; };
        if ($eummv < 6.2501) {
            return;
        }
    }

    return $meta;
}


sub write_mymeta {
    my $self = shift;
    my $mymeta = shift;

    return unless _has_cpan_meta();

    _fix_metadata_before_conversion( $mymeta );

    # this can still blow up
    # not sure if i should just eval this and skip file creation if it
    # blows up
    my $meta_obj = CPAN::Meta->new( $mymeta, { lazy_validation => 1 } );
    $meta_obj->save( 'MYMETA.json' );
    $meta_obj->save( 'MYMETA.yml', { version => "1.4" } );
    return 1;
}


sub realclean {
    my($self, %attribs) = @_;

    my @dirs  = qw($(DISTVNAME));
    my @files = qw($(FIRST_MAKEFILE) $(MAKEFILE_OLD));

    # Special exception for the perl core where INST_* is not in blib.
    # This cleans up the files built from the ext/ directory (all XS).
    if( $self->{PERL_CORE} ) {
        push @dirs, qw($(INST_AUTODIR) $(INST_ARCHAUTODIR));
        push @files, values %{$self->{PM}};
    }

    if( $self->has_link_code ){
        push @files, qw($(OBJECT));
    }

    if( $attribs{FILES} ) {
        if( ref $attribs{FILES} ) {
            push @dirs, @{ $attribs{FILES} };
        }
        else {
            push @dirs, split /\s+/, $attribs{FILES};
        }
    }

    # Occasionally files are repeated several times from different sources
    { my(%f) = map { ($_ => 1) } @files;  @files = keys %f; }
    { my(%d) = map { ($_ => 1) } @dirs;   @dirs  = keys %d; }

    my $rm_cmd  = join "\n\t", map { "$_" }
                    $self->split_command('- $(RM_F)',  @files);
    my $rmf_cmd = join "\n\t", map { "$_" }
                    $self->split_command('- $(RM_RF)', @dirs);

    my $m = sprintf <<'MAKE', $rm_cmd, $rmf_cmd;
realclean purge ::  clean realclean_subdirs
	%s
	%s
MAKE

    $m .= "\t$attribs{POSTOP}\n" if $attribs{POSTOP};

    return $m;
}



sub realclean_subdirs_target {
    my $self = shift;

    return <<'NOOP_FRAG' unless @{$self->{DIR}};
realclean_subdirs :
	$(NOECHO) $(NOOP)
NOOP_FRAG

    my $rclean = "realclean_subdirs :\n";

    foreach my $dir (@{$self->{DIR}}) {
        foreach my $makefile ('$(MAKEFILE_OLD)', '$(FIRST_MAKEFILE)' ) {
            my $subrclean .= $self->oneliner(sprintf <<'CODE', $dir, ($makefile) x 2);
chdir '%s';  system '$(MAKE) $(USEMAKEFILE) %s realclean' if -f '%s';
CODE

            $rclean .= sprintf <<'RCLEAN', $subrclean;
	- %s
RCLEAN

        }
    }

    return $rclean;
}



sub signature_target {
    my $self = shift;

    return <<'MAKE_FRAG';
signature :
	cpansign -s
MAKE_FRAG

}



sub distsignature_target {
    my $self = shift;

    my $add_sign = $self->oneliner(<<'CODE', ['-MExtUtils::Manifest=maniadd']);
eval { maniadd({q{SIGNATURE} => q{Public-key signature (added by MakeMaker)}}) }
    or print "Could not add SIGNATURE to MANIFEST: $${'@'}\n"
CODE

    my $sign_dist        = $self->cd('$(DISTVNAME)' => 'cpansign -s');

    # cpansign -s complains if SIGNATURE is in the MANIFEST yet does not
    # exist
    my $touch_sig        = $self->cd('$(DISTVNAME)' => '$(TOUCH) SIGNATURE');
    my $add_sign_to_dist = $self->cd('$(DISTVNAME)' => $add_sign );

    return sprintf <<'MAKE', $add_sign_to_dist, $touch_sig, $sign_dist
distsignature : create_distdir
	$(NOECHO) %s
	$(NOECHO) %s
	%s

MAKE

}



sub special_targets {
    my $make_frag = <<'MAKE_FRAG';
.SUFFIXES : .xs .c .C .cpp .i .s .cxx .cc $(OBJ_EXT)

.PHONY: all config static dynamic test linkext manifest blibdirs clean realclean disttest distdir

MAKE_FRAG

    $make_frag .= <<'MAKE_FRAG' if $ENV{CLEARCASE_ROOT};
.NO_CONFIG_REC: Makefile

MAKE_FRAG

    return $make_frag;
}





sub init_ABSTRACT {
    my $self = shift;

    if( $self->{ABSTRACT_FROM} and $self->{ABSTRACT} ) {
        warn "Both ABSTRACT_FROM and ABSTRACT are set.  ".
             "Ignoring ABSTRACT_FROM.\n";
        return;
    }

    if ($self->{ABSTRACT_FROM}){
        $self->{ABSTRACT} = $self->parse_abstract($self->{ABSTRACT_FROM}) or
            carp "WARNING: Setting ABSTRACT via file ".
                 "'$self->{ABSTRACT_FROM}' failed\n";
    }

    if ($self->{ABSTRACT} && $self->{ABSTRACT} =~ m![[:cntrl:]]+!) {
            warn "WARNING: ABSTRACT contains control character(s),".
                 " they will be removed\n";
            $self->{ABSTRACT} =~ s![[:cntrl:]]+!!g;
            return;
    }
}


sub init_INST {
    my($self) = shift;

    $self->{INST_ARCHLIB} ||= $self->catdir($Curdir,"blib","arch");
    $self->{INST_BIN}     ||= $self->catdir($Curdir,'blib','bin');

    # INST_LIB typically pre-set if building an extension after
    # perl has been built and installed. Setting INST_LIB allows
    # you to build directly into, say $Config{privlibexp}.
    unless ($self->{INST_LIB}){
        if ($self->{PERL_CORE}) {
            $self->{INST_LIB} = $self->{INST_ARCHLIB} = $self->{PERL_LIB};
        } else {
            $self->{INST_LIB} = $self->catdir($Curdir,"blib","lib");
        }
    }

    my @parentdir = split(/::/, $self->{PARENT_NAME});
    $self->{INST_LIBDIR}      = $self->catdir('$(INST_LIB)',     @parentdir);
    $self->{INST_ARCHLIBDIR}  = $self->catdir('$(INST_ARCHLIB)', @parentdir);
    $self->{INST_AUTODIR}     = $self->catdir('$(INST_LIB)', 'auto',
                                              '$(FULLEXT)');
    $self->{INST_ARCHAUTODIR} = $self->catdir('$(INST_ARCHLIB)', 'auto',
                                              '$(FULLEXT)');

    $self->{INST_SCRIPT}  ||= $self->catdir($Curdir,'blib','script');

    $self->{INST_MAN1DIR} ||= $self->catdir($Curdir,'blib','man1');
    $self->{INST_MAN3DIR} ||= $self->catdir($Curdir,'blib','man3');

    return 1;
}



sub init_INSTALL {
    my($self) = shift;

    if( $self->{ARGS}{INSTALL_BASE} and $self->{ARGS}{PREFIX} ) {
        die "Only one of PREFIX or INSTALL_BASE can be given.  Not both.\n";
    }

    if( $self->{ARGS}{INSTALL_BASE} ) {
        $self->init_INSTALL_from_INSTALL_BASE;
    }
    else {
        $self->init_INSTALL_from_PREFIX;
    }
}



sub init_INSTALL_from_PREFIX {
    my $self = shift;

    $self->init_lib2arch;

    # There are often no Config.pm defaults for these new man variables so
    # we fall back to the old behavior which is to use installman*dir
    foreach my $num (1, 3) {
        my $k = 'installsiteman'.$num.'dir';

        $self->{uc $k} ||= uc "\$(installman${num}dir)"
          unless $Config{$k};
    }

    foreach my $num (1, 3) {
        my $k = 'installvendorman'.$num.'dir';

        unless( $Config{$k} ) {
            $self->{uc $k}  ||= $Config{usevendorprefix}
                              ? uc "\$(installman${num}dir)"
                              : '';
        }
    }

    $self->{INSTALLSITEBIN} ||= '$(INSTALLBIN)'
      unless $Config{installsitebin};
    $self->{INSTALLSITESCRIPT} ||= '$(INSTALLSCRIPT)'
      unless $Config{installsitescript};

    unless( $Config{installvendorbin} ) {
        $self->{INSTALLVENDORBIN} ||= $Config{usevendorprefix}
                                    ? $Config{installbin}
                                    : '';
    }
    unless( $Config{installvendorscript} ) {
        $self->{INSTALLVENDORSCRIPT} ||= $Config{usevendorprefix}
                                       ? $Config{installscript}
                                       : '';
    }


    my $iprefix = $Config{installprefixexp} || $Config{installprefix} ||
                  $Config{prefixexp}        || $Config{prefix} || '';
    my $vprefix = $Config{usevendorprefix}  ? $Config{vendorprefixexp} : '';
    my $sprefix = $Config{siteprefixexp}    || '';

    # 5.005_03 doesn't have a siteprefix.
    $sprefix = $iprefix unless $sprefix;


    $self->{PREFIX}       ||= '';

    if( $self->{PREFIX} ) {
        @{$self}{qw(PERLPREFIX SITEPREFIX VENDORPREFIX)} =
          ('$(PREFIX)') x 3;
    }
    else {
        $self->{PERLPREFIX}   ||= $iprefix;
        $self->{SITEPREFIX}   ||= $sprefix;
        $self->{VENDORPREFIX} ||= $vprefix;

        # Lots of MM extension authors like to use $(PREFIX) so we
        # put something sensible in there no matter what.
        $self->{PREFIX} = '$('.uc $self->{INSTALLDIRS}.'PREFIX)';
    }

    my $arch    = $Config{archname};
    my $version = $Config{version};

    # default style
    my $libstyle = $Config{installstyle} || 'lib/perl5';
    my $manstyle = '';

    if( $self->{LIBSTYLE} ) {
        $libstyle = $self->{LIBSTYLE};
        $manstyle = $self->{LIBSTYLE} eq 'lib/perl5' ? 'lib/perl5' : '';
    }

    # Some systems, like VOS, set installman*dir to '' if they can't
    # read man pages.
    for my $num (1, 3) {
        $self->{'INSTALLMAN'.$num.'DIR'} ||= 'none'
          unless $Config{'installman'.$num.'dir'};
    }

    my %bin_layouts =
    (
        bin         => { s => $iprefix,
                         t => 'perl',
                         d => 'bin' },
        vendorbin   => { s => $vprefix,
                         t => 'vendor',
                         d => 'bin' },
        sitebin     => { s => $sprefix,
                         t => 'site',
                         d => 'bin' },
        script      => { s => $iprefix,
                         t => 'perl',
                         d => 'bin' },
        vendorscript=> { s => $vprefix,
                         t => 'vendor',
                         d => 'bin' },
        sitescript  => { s => $sprefix,
                         t => 'site',
                         d => 'bin' },
    );

    my %man_layouts =
    (
        man1dir         => { s => $iprefix,
                             t => 'perl',
                             d => 'man/man1',
                             style => $manstyle, },
        siteman1dir     => { s => $sprefix,
                             t => 'site',
                             d => 'man/man1',
                             style => $manstyle, },
        vendorman1dir   => { s => $vprefix,
                             t => 'vendor',
                             d => 'man/man1',
                             style => $manstyle, },

        man3dir         => { s => $iprefix,
                             t => 'perl',
                             d => 'man/man3',
                             style => $manstyle, },
        siteman3dir     => { s => $sprefix,
                             t => 'site',
                             d => 'man/man3',
                             style => $manstyle, },
        vendorman3dir   => { s => $vprefix,
                             t => 'vendor',
                             d => 'man/man3',
                             style => $manstyle, },
    );

    my %lib_layouts =
    (
        privlib     => { s => $iprefix,
                         t => 'perl',
                         d => '',
                         style => $libstyle, },
        vendorlib   => { s => $vprefix,
                         t => 'vendor',
                         d => '',
                         style => $libstyle, },
        sitelib     => { s => $sprefix,
                         t => 'site',
                         d => 'site_perl',
                         style => $libstyle, },

        archlib     => { s => $iprefix,
                         t => 'perl',
                         d => "$version/$arch",
                         style => $libstyle },
        vendorarch  => { s => $vprefix,
                         t => 'vendor',
                         d => "$version/$arch",
                         style => $libstyle },
        sitearch    => { s => $sprefix,
                         t => 'site',
                         d => "site_perl/$version/$arch",
                         style => $libstyle },
    );


    # Special case for LIB.
    if( $self->{LIB} ) {
        foreach my $var (keys %lib_layouts) {
            my $Installvar = uc "install$var";

            if( $var =~ /arch/ ) {
                $self->{$Installvar} ||=
                  $self->catdir($self->{LIB}, $Config{archname});
            }
            else {
                $self->{$Installvar} ||= $self->{LIB};
            }
        }
    }

    my %type2prefix = ( perl    => 'PERLPREFIX',
                        site    => 'SITEPREFIX',
                        vendor  => 'VENDORPREFIX'
                      );

    my %layouts = (%bin_layouts, %man_layouts, %lib_layouts);
    while( my($var, $layout) = each(%layouts) ) {
        my($s, $t, $d, $style) = @{$layout}{qw(s t d style)};
        my $r = '$('.$type2prefix{$t}.')';

        warn "Prefixing $var\n" if $Verbose >= 2;

        my $installvar = "install$var";
        my $Installvar = uc $installvar;
        next if $self->{$Installvar};

        $d = "$style/$d" if $style;
        $self->prefixify($installvar, $s, $r, $d);

        warn "  $Installvar == $self->{$Installvar}\n"
          if $Verbose >= 2;
    }

    # Generate these if they weren't figured out.
    $self->{VENDORARCHEXP} ||= $self->{INSTALLVENDORARCH};
    $self->{VENDORLIBEXP}  ||= $self->{INSTALLVENDORLIB};

    return 1;
}



my %map = (
           lib      => [qw(lib perl5)],
           arch     => [('lib', 'perl5', $Config{archname})],
           bin      => [qw(bin)],
           man1dir  => [qw(man man1)],
           man3dir  => [qw(man man3)]
          );
$map{script} = $map{bin};

sub init_INSTALL_from_INSTALL_BASE {
    my $self = shift;

    @{$self}{qw(PREFIX VENDORPREFIX SITEPREFIX PERLPREFIX)} =
                                                         '$(INSTALL_BASE)';

    my %install;
    foreach my $thing (keys %map) {
        foreach my $dir (('', 'SITE', 'VENDOR')) {
            my $uc_thing = uc $thing;
            my $key = "INSTALL".$dir.$uc_thing;

            $install{$key} ||=
              $self->catdir('$(INSTALL_BASE)', @{$map{$thing}});
        }
    }

    # Adjust for variable quirks.
    $install{INSTALLARCHLIB} ||= delete $install{INSTALLARCH};
    $install{INSTALLPRIVLIB} ||= delete $install{INSTALLLIB};

    foreach my $key (keys %install) {
        $self->{$key} ||= $install{$key};
    }

    return 1;
}



sub init_VERSION {
    my($self) = shift;

    $self->{MAKEMAKER}  = $ExtUtils::MakeMaker::Filename;
    $self->{MM_VERSION} = $ExtUtils::MakeMaker::VERSION;
    $self->{MM_REVISION}= $ExtUtils::MakeMaker::Revision;
    $self->{VERSION_FROM} ||= '';

    if ($self->{VERSION_FROM}){
        $self->{VERSION} = $self->parse_version($self->{VERSION_FROM});
        if( $self->{VERSION} eq 'undef' ) {
            carp("WARNING: Setting VERSION via file ".
                 "'$self->{VERSION_FROM}' failed\n");
        }
    }

    if (defined $self->{VERSION}) {
        if ( $self->{VERSION} !~ /^\s*v?[\d_\.]+\s*$/ ) {
          require version;
          my $normal = eval { version->parse( $self->{VERSION} ) };
          $self->{VERSION} = $normal if defined $normal;
        }
        $self->{VERSION} =~ s/^\s+//;
        $self->{VERSION} =~ s/\s+$//;
    }
    else {
        $self->{VERSION} = '';
    }


    $self->{VERSION_MACRO}  = 'VERSION';
    ($self->{VERSION_SYM} = $self->{VERSION}) =~ s/\W/_/g;
    $self->{DEFINE_VERSION} = '-D$(VERSION_MACRO)=\"$(VERSION)\"';


    # Graham Barr and Paul Marquess had some ideas how to ensure
    # version compatibility between the *.pm file and the
    # corresponding *.xs file. The bottom line was, that we need an
    # XS_VERSION macro that defaults to VERSION:
    $self->{XS_VERSION} ||= $self->{VERSION};

    $self->{XS_VERSION_MACRO}  = 'XS_VERSION';
    $self->{XS_DEFINE_VERSION} = '-D$(XS_VERSION_MACRO)=\"$(XS_VERSION)\"';

}



sub init_tools {
    my $self = shift;

    $self->{ECHO}     ||= $self->oneliner('print qq{@ARGV}', ['-l']);
    $self->{ECHO_N}   ||= $self->oneliner('print qq{@ARGV}');

    $self->{TOUCH}    ||= $self->oneliner('touch', ["-MExtUtils::Command"]);
    $self->{CHMOD}    ||= $self->oneliner('chmod', ["-MExtUtils::Command"]);
    $self->{RM_F}     ||= $self->oneliner('rm_f',  ["-MExtUtils::Command"]);
    $self->{RM_RF}    ||= $self->oneliner('rm_rf', ["-MExtUtils::Command"]);
    $self->{TEST_F}   ||= $self->oneliner('test_f', ["-MExtUtils::Command"]);
    $self->{TEST_S}   ||= $self->oneliner('test_s', ["-MExtUtils::Command::MM"]);
    $self->{CP_NONEMPTY} ||= $self->oneliner('cp_nonempty', ["-MExtUtils::Command::MM"]);
    $self->{FALSE}    ||= $self->oneliner('exit 1');
    $self->{TRUE}     ||= $self->oneliner('exit 0');

    $self->{MKPATH}   ||= $self->oneliner('mkpath', ["-MExtUtils::Command"]);

    $self->{CP}       ||= $self->oneliner('cp', ["-MExtUtils::Command"]);
    $self->{MV}       ||= $self->oneliner('mv', ["-MExtUtils::Command"]);

    $self->{MOD_INSTALL} ||=
      $self->oneliner(<<'CODE', ['-MExtUtils::Install']);
install([ from_to => {@ARGV}, verbose => '$(VERBINST)', uninstall_shadows => '$(UNINST)', dir_mode => '$(PERM_DIR)' ]);
CODE
    $self->{DOC_INSTALL} ||= $self->oneliner('perllocal_install', ["-MExtUtils::Command::MM"]);
    $self->{UNINSTALL}   ||= $self->oneliner('uninstall', ["-MExtUtils::Command::MM"]);
    $self->{WARN_IF_OLD_PACKLIST} ||=
      $self->oneliner('warn_if_old_packlist', ["-MExtUtils::Command::MM"]);
    $self->{FIXIN}       ||= $self->oneliner('MY->fixin(shift)', ["-MExtUtils::MY"]);
    $self->{EQUALIZE_TIMESTAMP} ||= $self->oneliner('eqtime', ["-MExtUtils::Command"]);

    $self->{UNINST}     ||= 0;
    $self->{VERBINST}   ||= 0;

    $self->{SHELL}              ||= $Config{sh};

    # UMASK_NULL is not used by MakeMaker but some CPAN modules
    # make use of it.
    $self->{UMASK_NULL}         ||= "umask 0";

    # Not the greatest default, but its something.
    $self->{DEV_NULL}           ||= "> /dev/null 2>&1";

    $self->{NOOP}               ||= '$(TRUE)';
    $self->{NOECHO}             = '@' unless defined $self->{NOECHO};

    $self->{FIRST_MAKEFILE}     ||= $self->{MAKEFILE} || 'Makefile';
    $self->{MAKEFILE}           ||= $self->{FIRST_MAKEFILE};
    $self->{MAKEFILE_OLD}       ||= $self->{MAKEFILE}.'.old';
    $self->{MAKE_APERL_FILE}    ||= $self->{MAKEFILE}.'.aperl';

    # Not everybody uses -f to indicate "use this Makefile instead"
    $self->{USEMAKEFILE}        ||= '-f';

    # Some makes require a wrapper around macros passed in on the command
    # line.
    $self->{MACROSTART}         ||= '';
    $self->{MACROEND}           ||= '';

    return;
}



sub init_others {
    my $self = shift;

    $self->{LD_RUN_PATH} = "";

    $self->{LIBS} = $self->_fix_libs($self->{LIBS});

    # Compute EXTRALIBS, BSLOADLIBS and LDLOADLIBS from $self->{LIBS}
    foreach my $libs ( @{$self->{LIBS}} ){
        $libs =~ s/^\s*(.*\S)\s*$/$1/; # remove leading and trailing whitespace
        my(@libs) = $self->extliblist($libs);
        if ($libs[0] or $libs[1] or $libs[2]){
            # LD_RUN_PATH now computed by ExtUtils::Liblist
            ($self->{EXTRALIBS},  $self->{BSLOADLIBS},
             $self->{LDLOADLIBS}, $self->{LD_RUN_PATH}) = @libs;
            last;
        }
    }

    if ( $self->{OBJECT} ) {
        $self->{OBJECT} = join(" ", @{$self->{OBJECT}}) if ref $self->{OBJECT};
        $self->{OBJECT} =~ s!\.o(bj)?\b!\$(OBJ_EXT)!g;
    } elsif ( $self->{MAGICXS} && @{$self->{O_FILES}||[]} ) {
        $self->{OBJECT} = join(" ", @{$self->{O_FILES}});
        $self->{OBJECT} =~ s!\.o(bj)?\b!\$(OBJ_EXT)!g;
    } else {
        # init_dirscan should have found out, if we have C files
        $self->{OBJECT} = "";
        $self->{OBJECT} = '$(BASEEXT)$(OBJ_EXT)' if @{$self->{C}||[]};
    }
    $self->{OBJECT} =~ s/\n+/ \\\n\t/g;

    $self->{BOOTDEP}  = (-f "$self->{BASEEXT}_BS") ? "$self->{BASEEXT}_BS" : "";
    $self->{PERLMAINCC} ||= '$(CC)';
    $self->{LDFROM} = '$(OBJECT)' unless $self->{LDFROM};

    # Sanity check: don't define LINKTYPE = dynamic if we're skipping
    # the 'dynamic' section of MM.  We don't have this problem with
    # 'static', since we either must use it (%Config says we can't
    # use dynamic loading) or the caller asked for it explicitly.
    if (!$self->{LINKTYPE}) {
       $self->{LINKTYPE} = $self->{SKIPHASH}{'dynamic'}
                        ? 'static'
                        : ($Config{usedl} ? 'dynamic' : 'static');
    }

    return;
}


sub _fix_libs {
    my($self, $libs) = @_;

    return !defined $libs       ? ['']          :
           !ref $libs           ? [$libs]       :
           !defined $libs->[0]  ? ['']          :
                                  $libs         ;
}



sub tools_other {
    my($self) = shift;
    my @m;

    # We set PM_FILTER as late as possible so it can see all the earlier
    # on macro-order sensitive makes such as nmake.
    for my $tool (qw{ SHELL CHMOD CP MV NOOP NOECHO RM_F RM_RF TEST_F TOUCH
                      UMASK_NULL DEV_NULL MKPATH EQUALIZE_TIMESTAMP
                      FALSE TRUE
                      ECHO ECHO_N
                      UNINST VERBINST
                      MOD_INSTALL DOC_INSTALL UNINSTALL
                      WARN_IF_OLD_PACKLIST
                      MACROSTART MACROEND
                      USEMAKEFILE
                      PM_FILTER
                      FIXIN
                      CP_NONEMPTY
                    } )
    {
        next unless defined $self->{$tool};
        push @m, "$tool = $self->{$tool}\n";
    }

    return join "", @m;
}



sub init_platform {
    return '';
}



sub init_MAKE {
    my $self = shift;

    $self->{MAKE} ||= $ENV{MAKE} || $Config{make};
}



sub manifypods {
    my $self          = shift;

    my $POD2MAN_macro = $self->POD2MAN_macro();
    my $manifypods_target = $self->manifypods_target();

    return <<END_OF_TARGET;

$POD2MAN_macro

$manifypods_target

END_OF_TARGET

}



sub POD2MAN_macro {
    my $self = shift;

    return <<'END_OF_DEF';
POD2MAN_EXE = $(PERLRUN) "-MExtUtils::Command::MM" -e pod2man "--"
POD2MAN = $(POD2MAN_EXE)
END_OF_DEF
}



sub test_via_harness {
    my($self, $perl, $tests) = @_;

    return qq{\t$perl "-MExtUtils::Command::MM" "-MTest::Harness" }.
           qq{"-e" "undef *Test::Harness::Switches; test_harness(\$(TEST_VERBOSE), '\$(INST_LIB)', '\$(INST_ARCHLIB)')" $tests\n};
}


sub test_via_script {
    my($self, $perl, $script) = @_;
    return qq{\t$perl "-I\$(INST_LIB)" "-I\$(INST_ARCHLIB)" $script\n};
}



sub tool_autosplit {
    my($self, %attribs) = @_;

    my $maxlen = $attribs{MAXLEN} ? '$$AutoSplit::Maxlen=$attribs{MAXLEN};'
                                  : '';

    my $asplit = $self->oneliner(sprintf <<'PERL_CODE', $maxlen);
use AutoSplit; %s autosplit($$ARGV[0], $$ARGV[1], 0, 1, 1)
PERL_CODE

    return sprintf <<'MAKE_FRAG', $asplit;
AUTOSPLITFILE = %s

MAKE_FRAG

}



sub arch_check {
    my $self = shift;
    my($pconfig, $cconfig) = @_;

    return 1 if $self->{PERL_SRC};

    my($pvol, $pthinks) = $self->splitpath($pconfig);
    my($cvol, $cthinks) = $self->splitpath($cconfig);

    $pthinks = $self->canonpath($pthinks);
    $cthinks = $self->canonpath($cthinks);

    my $ret = 1;
    if ($pthinks ne $cthinks) {
        print "Have $pthinks\n";
        print "Want $cthinks\n";

        $ret = 0;

        my $arch = (grep length, $self->splitdir($pthinks))[-1];

        print <<END unless $self->{UNINSTALLED_PERL};
Your perl and your Config.pm seem to have different ideas about the
architecture they are running on.
Perl thinks: [$arch]
Config says: [$Config{archname}]
This may or may not cause problems. Please check your installation of perl
if you have problems building this extension.
END
    }

    return $ret;
}




sub catfile {
    my $self = shift;
    return $self->canonpath($self->SUPER::catfile(@_));
}




sub find_tests {
    my($self) = shift;
    return -d 't' ? 't/*.t' : '';
}


sub find_tests_recursive {
    my($self) = shift;
    return '' unless -d 't';

    require File::Find;

    my %testfiles;

    my $wanted = sub {
        return unless m!\.t$!;
        my ($volume,$directories,$file) =
            File::Spec->splitpath( $File::Find::name  );
        my @dirs = File::Spec->splitdir( $directories );
        for ( @dirs ) {
          next if $_ eq 't';
          unless ( $_ ) {
            $_ = '*.t';
            next;
          }
          $_ = '*';
        }
        my $testfile = join '/', @dirs;
        $testfiles{ $testfile } = 1;
    };

    File::Find::find( $wanted, 't' );

    return join ' ', sort keys %testfiles;
}


sub extra_clean_files {
    return;
}



sub installvars {
    return qw(PRIVLIB SITELIB  VENDORLIB
              ARCHLIB SITEARCH VENDORARCH
              BIN     SITEBIN  VENDORBIN
              SCRIPT  SITESCRIPT  VENDORSCRIPT
              MAN1DIR SITEMAN1DIR VENDORMAN1DIR
              MAN3DIR SITEMAN3DIR VENDORMAN3DIR
             );
}



sub libscan {
    my($self,$path) = @_;
    my($dirs,$file) = ($self->splitpath($path))[1,2];
    return '' if grep /^(?:RCS|CVS|SCCS|\.svn|_darcs)$/,
                     $self->splitdir($dirs), $file;

    return $path;
}



sub platform_constants {
    return '';
}


sub _PREREQ_PRINT {
    my $self = shift;

    require Data::Dumper;
    my @what = ('PREREQ_PM');
    push @what, 'MIN_PERL_VERSION' if $self->{MIN_PERL_VERSION};
    push @what, 'BUILD_REQUIRES'   if $self->{BUILD_REQUIRES};
    print Data::Dumper->Dump([@{$self}{@what}], \@what);
    exit 0;
}



sub _PRINT_PREREQ {
    my $self = shift;

    my $prereqs= $self->{PREREQ_PM};
    my @prereq = map { [$_, $prereqs->{$_}] } keys %$prereqs;

    if ( $self->{MIN_PERL_VERSION} ) {
        push @prereq, ['perl' => $self->{MIN_PERL_VERSION}];
    }

    print join(" ", map { "perl($_->[0])>=$_->[1] " }
                 sort { $a->[0] cmp $b->[0] } @prereq), "\n";
    exit 0;
}



sub _all_prereqs {
    my $self = shift;

    return { %{$self->{PREREQ_PM}}, %{$self->{BUILD_REQUIRES}} };
}


sub _perl_header_files {
    my $self = shift;

    my $header_dir = $self->{PERL_SRC} || $self->catdir($Config{archlibexp}, 'CORE');
    opendir my $dh, $header_dir
        or die "Failed to opendir '$header_dir' to find header files: $!";

    # we need to use a temporary here as the sort in scalar context would have undefined results.
    my @perl_headers= sort grep { /\.h\z/ } readdir($dh);

    closedir $dh;

    return @perl_headers;
}


sub _perl_header_files_fragment {
    my ($self, $separator)= @_;
    $separator ||= "";
    return join("\\\n",
                "PERL_HDRS = ",
                map {
                    sprintf( "        \$(PERL_INC)%s%s            ", $separator, $_ )
                } $self->_perl_header_files()
           ) . "\n\n"
           . "\$(OBJECT) : \$(PERL_HDRS)\n";
}



1;
