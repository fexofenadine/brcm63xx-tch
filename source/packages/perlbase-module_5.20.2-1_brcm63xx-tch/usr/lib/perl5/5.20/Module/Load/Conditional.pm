package Module::Load::Conditional;

use strict;

use Module::Load qw/load autoload_remote/;
use Params::Check                       qw[check];
use Locale::Maketext::Simple Style  => 'gettext';

use Carp        ();
use File::Spec  ();
use FileHandle  ();
use version;

use Module::Metadata ();

use constant ON_VMS   => $^O eq 'VMS';
use constant ON_WIN32 => $^O eq 'MSWin32' ? 1 : 0;
use constant QUOTE    => do { ON_WIN32 ? q["] : q['] };

BEGIN {
    use vars        qw[ $VERSION @ISA $VERBOSE $CACHE @EXPORT_OK $DEPRECATED
                        $FIND_VERSION $ERROR $CHECK_INC_HASH];
    use Exporter;
    @ISA            = qw[Exporter];
    $VERSION        = '0.62';
    $VERBOSE        = 0;
    $DEPRECATED     = 0;
    $FIND_VERSION   = 1;
    $CHECK_INC_HASH = 0;
    @EXPORT_OK      = qw[check_install can_load requires];
}


sub check_install {
    my %hash = @_;

    my $tmpl = {
            version => { default    => '0.0'    },
            module  => { required   => 1        },
            verbose => { default    => $VERBOSE },
    };

    my $args;
    unless( $args = check( $tmpl, \%hash, $VERBOSE ) ) {
        warn loc( q[A problem occurred checking arguments] ) if $VERBOSE;
        return;
    }

    my $file     = File::Spec->catfile( split /::/, $args->{module} ) . '.pm';
    my $file_inc = File::Spec::Unix->catfile(
                        split /::/, $args->{module}
                    ) . '.pm';

    ### where we store the return value ###
    my $href = {
            file        => undef,
            version     => undef,
            uptodate    => undef,
    };

    my $filename;

    ### check the inc hash if we're allowed to
    if( $CHECK_INC_HASH ) {
        $filename = $href->{'file'} =
            $INC{ $file_inc } if defined $INC{ $file_inc };

        ### find the version by inspecting the package
        if( defined $filename && $FIND_VERSION ) {
            no strict 'refs';
            $href->{version} = ${ "$args->{module}"."::VERSION" };
        }
    }

    ### we didn't find the filename yet by looking in %INC,
    ### so scan the dirs
    unless( $filename ) {

        DIR: for my $dir ( @INC ) {

            my $fh;

            if ( ref $dir ) {
                ### @INC hook -- we invoke it and get the filehandle back
                ### this is actually documented behaviour as of 5.8 ;)

                my $existed_in_inc = $INC{$file_inc};

                if (UNIVERSAL::isa($dir, 'CODE')) {
                    ($fh) = $dir->($dir, $file);

                } elsif (UNIVERSAL::isa($dir, 'ARRAY')) {
                    ($fh) = $dir->[0]->($dir, $file, @{$dir}{1..$#{$dir}})

                } elsif (UNIVERSAL::can($dir, 'INC')) {
                    ($fh) = $dir->INC($file);
                }

                if (!UNIVERSAL::isa($fh, 'GLOB')) {
                    warn loc(q[Cannot open file '%1': %2], $file, $!)
                            if $args->{verbose};
                    next;
                }

                $filename = $INC{$file_inc} || $file;

                delete $INC{$file_inc} if not $existed_in_inc;

            } else {
                $filename = File::Spec->catfile($dir, $file);
                next unless -e $filename;

                $fh = new FileHandle;
                if (!$fh->open($filename)) {
                    warn loc(q[Cannot open file '%1': %2], $file, $!)
                            if $args->{verbose};
                    next;
                }
            }

            ### store the directory we found the file in
            $href->{dir} = $dir;

            ### files need to be in unix format under vms,
            ### or they might be loaded twice
            $href->{file} = ON_VMS
                ? VMS::Filespec::unixify( $filename )
                : $filename;

            ### if we don't need the version, we're done
            last DIR unless $FIND_VERSION;

            ### otherwise, the user wants us to find the version from files
            my $mod_info = Module::Metadata->new_from_handle( $fh, $filename );
            my $ver      = $mod_info->version( $args->{module} );

            if( defined $ver ) {
                $href->{version} = $ver;

                last DIR;
            }
        }
    }

    ### if we couldn't find the file, return undef ###
    return unless defined $href->{file};

    ### only complain if we're expected to find a version higher than 0.0 anyway
    if( $FIND_VERSION and not defined $href->{version} ) {
        {   ### don't warn about the 'not numeric' stuff ###
            local $^W;

            ### if we got here, we didn't find the version
            warn loc(q[Could not check version on '%1'], $args->{module} )
                    if $args->{verbose} and $args->{version} > 0;
        }
        $href->{uptodate} = 1;

    } else {
        ### don't warn about the 'not numeric' stuff ###
        local $^W;

        ### use qv(), as it will deal with developer release number
        ### ie ones containing _ as well. This addresses bug report
        ### #29348: Version compare logic doesn't handle alphas?
        ###
        ### Update from JPeacock: apparently qv() and version->new
        ### are different things, and we *must* use version->new
        ### here, or things like #30056 might start happening

        ### We have to wrap this in an eval as version-0.82 raises
        ### exceptions and not warnings now *sigh*

        eval {

          $href->{uptodate} =
            version->new( $args->{version} ) <= version->new( $href->{version} )
                ? 1
                : 0;

        };
    }

    if ( $DEPRECATED and "$]" >= 5.011 ) {
        require Module::CoreList;
        require Config;

        $href->{uptodate} = 0 if
           exists $Module::CoreList::version{ 0+$] }{ $args->{module} } and
           Module::CoreList::is_deprecated( $args->{module} ) and
           $Config::Config{privlibexp} eq $href->{dir};
    }

    return $href;
}


sub can_load {
    my %hash = @_;

    my $tmpl = {
        modules     => { default => {}, strict_type => 1 },
        verbose     => { default => $VERBOSE },
        nocache     => { default => 0 },
        autoload    => { default => 0 },
    };

    my $args;

    unless( $args = check( $tmpl, \%hash, $VERBOSE ) ) {
        $ERROR = loc(q[Problem validating arguments!]);
        warn $ERROR if $VERBOSE;
        return;
    }

    ### layout of $CACHE:
    ### $CACHE = {
    ###     $ module => {
    ###             usable  => BOOL,
    ###             version => \d,
    ###             file    => /path/to/file,
    ###     },
    ### };

    $CACHE ||= {}; # in case it was undef'd

    my $error;
    BLOCK: {
        my $href = $args->{modules};

        my @load;
        for my $mod ( keys %$href ) {

            next if $CACHE->{$mod}->{usable} && !$args->{nocache};

            ### else, check if the hash key is defined already,
            ### meaning $mod => 0,
            ### indicating UNSUCCESSFUL prior attempt of usage

            ### use qv(), as it will deal with developer release number
            ### ie ones containing _ as well. This addresses bug report
            ### #29348: Version compare logic doesn't handle alphas?
            ###
            ### Update from JPeacock: apparently qv() and version->new
            ### are different things, and we *must* use version->new
            ### here, or things like #30056 might start happening
            if (    !$args->{nocache}
                    && defined $CACHE->{$mod}->{usable}
                    && (version->new( $CACHE->{$mod}->{version}||0 )
                        >= version->new( $href->{$mod} ) )
            ) {
                $error = loc( q[Already tried to use '%1', which was unsuccessful], $mod);
                last BLOCK;
            }

            my $mod_data = check_install(
                                    module  => $mod,
                                    version => $href->{$mod}
                                );

            if( !$mod_data or !defined $mod_data->{file} ) {
                $error = loc(q[Could not find or check module '%1'], $mod);
                $CACHE->{$mod}->{usable} = 0;
                last BLOCK;
            }

            map {
                $CACHE->{$mod}->{$_} = $mod_data->{$_}
            } qw[version file uptodate];

            push @load, $mod;
        }

        for my $mod ( @load ) {

            if ( $CACHE->{$mod}->{uptodate} ) {

                if ( $args->{autoload} ) {
                    my $who = (caller())[0];
                    eval { autoload_remote $who, $mod };
                } else {
                    eval { load $mod };
                }

                ### in case anything goes wrong, log the error, the fact
                ### we tried to use this module and return 0;
                if( $@ ) {
                    $error = $@;
                    $CACHE->{$mod}->{usable} = 0;
                    last BLOCK;
                } else {
                    $CACHE->{$mod}->{usable} = 1;
                }

            ### module not found in @INC, store the result in
            ### $CACHE and return 0
            } else {

                $error = loc(q[Module '%1' is not uptodate!], $mod);
                $CACHE->{$mod}->{usable} = 0;
                last BLOCK;
            }
        }

    } # BLOCK

    if( defined $error ) {
        $ERROR = $error;
        Carp::carp( loc(q|%1 [THIS MAY BE A PROBLEM!]|,$error) ) if $args->{verbose};
        return;
    } else {
        return 1;
    }
}


sub requires {
    my $who = shift;

    unless( check_install( module => $who ) ) {
        warn loc(q[You do not have module '%1' installed], $who) if $VERBOSE;
        return undef;
    }

    my $lib = join " ", map { qq["-I$_"] } @INC;
    my $oneliner = 'print(join(qq[\n],map{qq[BONG=$_]}keys(%INC)),qq[\n])';
    my $cmd = join '', qq["$^X" $lib -M$who -e], QUOTE, $oneliner, QUOTE;

    return  sort
                grep { !/^$who$/  }
                map  { chomp; s|/|::|g; $_ }
                grep { s|\.pm$||i; }
                map  { s!^BONG\=!!; $_ }
                grep { m!^BONG\=! }
            `$cmd`;
}

1;

__END__

