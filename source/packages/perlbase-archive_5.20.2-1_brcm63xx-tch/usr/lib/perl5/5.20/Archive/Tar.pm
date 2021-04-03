
package Archive::Tar;
require 5.005_03;

use Cwd;
use IO::Zlib;
use IO::File;
use Carp                qw(carp croak);
use File::Spec          ();
use File::Spec::Unix    ();
use File::Path          ();

use Archive::Tar::File;
use Archive::Tar::Constant;

require Exporter;

use strict;
use vars qw[$DEBUG $error $VERSION $WARN $FOLLOW_SYMLINK $CHOWN $CHMOD
            $DO_NOT_USE_PREFIX $HAS_PERLIO $HAS_IO_STRING $SAME_PERMISSIONS
            $INSECURE_EXTRACT_MODE $ZERO_PAD_NUMBERS @ISA @EXPORT $RESOLVE_SYMLINK
         ];

@ISA                    = qw[Exporter];
@EXPORT                 = qw[ COMPRESS_GZIP COMPRESS_BZIP ];
$DEBUG                  = 0;
$WARN                   = 1;
$FOLLOW_SYMLINK         = 0;
$VERSION                = "1.96";
$CHOWN                  = 1;
$CHMOD                  = 1;
$SAME_PERMISSIONS       = $> == 0 ? 1 : 0;
$DO_NOT_USE_PREFIX      = 0;
$INSECURE_EXTRACT_MODE  = 0;
$ZERO_PAD_NUMBERS       = 0;
$RESOLVE_SYMLINK        = $ENV{'PERL5_AT_RESOLVE_SYMLINK'} || 'speed';

BEGIN {
    use Config;
    $HAS_PERLIO = $Config::Config{useperlio};

    ### try and load IO::String anyway, so you can dynamically
    ### switch between perlio and IO::String
    $HAS_IO_STRING = eval {
        require IO::String;
        import IO::String;
        1;
    } || 0;
}


my $tmpl = {
    _data   => [ ],
    _file   => 'Unknown',
};

for my $key ( keys %$tmpl ) {
    no strict 'refs';
    *{__PACKAGE__."::$key"} = sub {
        my $self = shift;
        $self->{$key} = $_[0] if @_;
        return $self->{$key};
    }
}

sub new {
    my $class = shift;
    $class = ref $class if ref $class;

    ### copying $tmpl here since a shallow copy makes it use the
    ### same aref, causing for files to remain in memory always.
    my $obj = bless { _data => [ ], _file => 'Unknown', _error => '' }, $class;

    if (@_) {
        unless ( $obj->read( @_ ) ) {
            $obj->_error(qq[No data could be read from file]);
            return;
        }
    }

    return $obj;
}


sub read {
    my $self = shift;
    my $file = shift;
    my $gzip = shift || 0;
    my $opts = shift || {};

    unless( defined $file ) {
        $self->_error( qq[No file to read from!] );
        return;
    } else {
        $self->_file( $file );
    }

    my $handle = $self->_get_handle($file, $gzip, READ_ONLY->( ZLIB ) )
                    or return;

    my $data = $self->_read_tar( $handle, $opts ) or return;

    $self->_data( $data );

    return wantarray ? @$data : scalar @$data;
}

sub _get_handle {
    my $self     = shift;
    my $file     = shift;   return unless defined $file;
    my $compress = shift || 0;
    my $mode     = shift || READ_ONLY->( ZLIB ); # default to read only

    ### Check if file is a file handle or IO glob
    if ( ref $file ) {
	return $file if eval{ *$file{IO} };
	return $file if eval{ $file->isa(q{IO::Handle}) };
	$file = q{}.$file;
    }

    ### get a FH opened to the right class, so we can use it transparently
    ### throughout the program
    my $fh;
    {   ### reading magic only makes sense if we're opening a file for
        ### reading. otherwise, just use what the user requested.
        my $magic = '';
        if( MODE_READ->($mode) ) {
            open my $tmp, $file or do {
                $self->_error( qq[Could not open '$file' for reading: $!] );
                return;
            };

            ### read the first 4 bites of the file to figure out which class to
            ### use to open the file.
            sysread( $tmp, $magic, 4 );
            close $tmp;
        }

        ### is it bzip?
        ### if you asked specifically for bzip compression, or if we're in
        ### read mode and the magic numbers add up, use bzip
        if( BZIP and (
                ($compress eq COMPRESS_BZIP) or
                ( MODE_READ->($mode) and $magic =~ BZIP_MAGIC_NUM )
            )
        ) {

            ### different reader/writer modules, different error vars... sigh
            if( MODE_READ->($mode) ) {
                $fh = IO::Uncompress::Bunzip2->new( $file ) or do {
                    $self->_error( qq[Could not read '$file': ] .
                        $IO::Uncompress::Bunzip2::Bunzip2Error
                    );
                    return;
                };

            } else {
                $fh = IO::Compress::Bzip2->new( $file ) or do {
                    $self->_error( qq[Could not write to '$file': ] .
                        $IO::Compress::Bzip2::Bzip2Error
                    );
                    return;
                };
            }

        ### is it gzip?
        ### if you asked for compression, if you wanted to read or the gzip
        ### magic number is present (redundant with read)
        } elsif( ZLIB and (
                    $compress or MODE_READ->($mode) or $magic =~ GZIP_MAGIC_NUM
                 )
        ) {
            $fh = IO::Zlib->new;

            unless( $fh->open( $file, $mode ) ) {
                $self->_error(qq[Could not create filehandle for '$file': $!]);
                return;
            }

        ### is it plain tar?
        } else {
            $fh = IO::File->new;

            unless( $fh->open( $file, $mode ) ) {
                $self->_error(qq[Could not create filehandle for '$file': $!]);
                return;
            }

            ### enable bin mode on tar archives
            binmode $fh;
        }
    }

    return $fh;
}


sub _read_tar {
    my $self    = shift;
    my $handle  = shift or return;
    my $opts    = shift || {};

    my $count   = $opts->{limit}    || 0;
    my $filter  = $opts->{filter};
    my $md5  = $opts->{md5} || 0;	# cdrake
    my $filter_cb = $opts->{filter_cb};
    my $extract = $opts->{extract}  || 0;

    ### set a cap on the amount of files to extract ###
    my $limit   = 0;
    $limit = 1 if $count > 0;

    my $tarfile = [ ];
    my $chunk;
    my $read = 0;
    my $real_name;  # to set the name of a file when
                    # we're encountering @longlink
    my $data;

    LOOP:
    while( $handle->read( $chunk, HEAD ) ) {
        ### IO::Zlib doesn't support this yet
        my $offset;
        if ( ref($handle) ne 'IO::Zlib' ) {
            local $@;
            $offset = eval { tell $handle } || 'unknown';
            $@ = '';
        }
        else {
            $offset = 'unknown';
        }

        unless( $read++ ) {
            my $gzip = GZIP_MAGIC_NUM;
            if( $chunk =~ /$gzip/ ) {
                $self->_error( qq[Cannot read compressed format in tar-mode] );
                return;
            }

            ### size is < HEAD, which means a corrupted file, as the minimum
            ### length is _at least_ HEAD
            if (length $chunk != HEAD) {
                $self->_error( qq[Cannot read enough bytes from the tarfile] );
                return;
            }
        }

        ### if we can't read in all bytes... ###
        last if length $chunk != HEAD;

        ### Apparently this should really be two blocks of 512 zeroes,
        ### but GNU tar sometimes gets it wrong. See comment in the
        ### source code (tar.c) to GNU cpio.
        next if $chunk eq TAR_END;

        ### according to the posix spec, the last 12 bytes of the header are
        ### null bytes, to pad it to a 512 byte block. That means if these
        ### bytes are NOT null bytes, it's a corrupt header. See:
        ### www.koders.com/c/fidCE473AD3D9F835D690259D60AD5654591D91D5BA.aspx
        ### line 111
        {   my $nulls = join '', "\0" x 12;
            unless( $nulls eq substr( $chunk, 500, 12 ) ) {
                $self->_error( qq[Invalid header block at offset $offset] );
                next LOOP;
            }
        }

        ### pass the realname, so we can set it 'proper' right away
        ### some of the heuristics are done on the name, so important
        ### to set it ASAP
        my $entry;
        {   my %extra_args = ();
            $extra_args{'name'} = $$real_name if defined $real_name;

            unless( $entry = Archive::Tar::File->new(   chunk => $chunk,
                                                        %extra_args )
            ) {
                $self->_error( qq[Couldn't read chunk at offset $offset] );
                next LOOP;
            }
        }

        ### ignore labels:
        ### http://www.gnu.org/software/tar/manual/html_chapter/Media.html#SEC159
        next if $entry->is_label;

        if( length $entry->type and ($entry->is_file || $entry->is_longlink) ) {

            if ( $entry->is_file && !$entry->validate ) {
                ### sometimes the chunk is rather fux0r3d and a whole 512
                ### bytes ends up in the ->name area.
                ### clean it up, if need be
                my $name = $entry->name;
                $name = substr($name, 0, 100) if length $name > 100;
                $name =~ s/\n/ /g;

                $self->_error( $name . qq[: checksum error] );
                next LOOP;
            }

            my $block = BLOCK_SIZE->( $entry->size );

            $data = $entry->get_content_by_ref;

	    my $skip = 0;
	    my $ctx;			# cdrake
	    ### skip this entry if we're filtering

	    if($md5) {			# cdrake
	      $ctx = Digest::MD5->new;	# cdrake
	        $skip=5;		# cdrake

	    } elsif ($filter && $entry->name !~ $filter) {
		$skip = 1;

	    ### skip this entry if it's a pax header. This is a special file added
	    ### by, among others, git-generated tarballs. It holds comments and is
	    ### not meant for extracting. See #38932: pax_global_header extracted
	    } elsif ( $entry->name eq PAX_HEADER or $entry->type =~ /^(x|g)$/ ) {
		$skip = 2;
	    } elsif ($filter_cb && ! $filter_cb->($entry)) {
		$skip = 3;
	    }

	    if ($skip) {
		#
		# Since we're skipping, do not allocate memory for the
		# whole file.  Read it 64 BLOCKS at a time.  Do not
		# complete the skip yet because maybe what we read is a
		# longlink and it won't get skipped after all
		#
		my $amt = $block;
		my $fsz=$entry->size;	# cdrake
		while ($amt > 0) {
		    $$data = '';
		    my $this = 64 * BLOCK;
		    $this = $amt if $this > $amt;
		    if( $handle->read( $$data, $this ) < $this ) {
			$self->_error( qq[Read error on tarfile (missing data) '].
					    $entry->full_path ."' at offset $offset" );
			next LOOP;
		    }
		    $amt -= $this;
		    $fsz -= $this;	# cdrake
		substr ($$data, $fsz) = "" if ($fsz<0);	# remove external junk prior to md5	# cdrake
		$ctx->add($$data) if($skip==5);	# cdrake
		}
		$$data = $ctx->hexdigest if($skip==5 && !$entry->is_longlink && !$entry->is_unknown && !$entry->is_label ) ;	# cdrake
            } else {

		### just read everything into memory
		### can't do lazy loading since IO::Zlib doesn't support 'seek'
		### this is because Compress::Zlib doesn't support it =/
		### this reads in the whole data in one read() call.
		if ( $handle->read( $$data, $block ) < $block ) {
		    $self->_error( qq[Read error on tarfile (missing data) '].
                                    $entry->full_path ."' at offset $offset" );
		    next LOOP;
		}
		### throw away trailing garbage ###
		substr ($$data, $entry->size) = "" if defined $$data;
            }

            ### part II of the @LongLink munging -- need to do /after/
            ### the checksum check.
            if( $entry->is_longlink ) {
                ### weird thing in tarfiles -- if the file is actually a
                ### @LongLink, the data part seems to have a trailing ^@
                ### (unprintable) char. to display, pipe output through less.
                ### but that doesn't *always* happen.. so check if the last
                ### character is a control character, and if so remove it
                ### at any rate, we better remove that character here, or tests
                ### like 'eq' and hash lookups based on names will SO not work
                ### remove it by calculating the proper size, and then
                ### tossing out everything that's longer than that size.

                ### count number of nulls
                my $nulls = $$data =~ tr/\0/\0/;

                ### cut data + size by that many bytes
                $entry->size( $entry->size - $nulls );
                substr ($$data, $entry->size) = "";
            }
        }

        ### clean up of the entries.. posix tar /apparently/ has some
        ### weird 'feature' that allows for filenames > 255 characters
        ### they'll put a header in with as name '././@LongLink' and the
        ### contents will be the name of the /next/ file in the archive
        ### pretty crappy and kludgy if you ask me

        ### set the name for the next entry if this is a @LongLink;
        ### this is one ugly hack =/ but needed for direct extraction
        if( $entry->is_longlink ) {
            $real_name = $data;
            next LOOP;
        } elsif ( defined $real_name ) {
            $entry->name( $$real_name );
            $entry->prefix('');
            undef $real_name;
        }

	if ($filter && $entry->name !~ $filter) {
	    next LOOP;

	### skip this entry if it's a pax header. This is a special file added
	### by, among others, git-generated tarballs. It holds comments and is
	### not meant for extracting. See #38932: pax_global_header extracted
	} elsif ( $entry->name eq PAX_HEADER or $entry->type =~ /^(x|g)$/ ) {
	    next LOOP;
	} elsif ($filter_cb && ! $filter_cb->($entry)) {
	    next LOOP;
	}

        if ( $extract && !$entry->is_longlink
                      && !$entry->is_unknown
                      && !$entry->is_label ) {
            $self->_extract_file( $entry ) or return;
        }

        ### Guard against tarfiles with garbage at the end
	    last LOOP if $entry->name eq '';

        ### push only the name on the rv if we're extracting
        ### -- for extract_archive
        push @$tarfile, ($extract ? $entry->name : $entry);

        if( $limit ) {
            $count-- unless $entry->is_longlink || $entry->is_dir;
            last LOOP unless $count;
        }
    } continue {
        undef $data;
    }

    return $tarfile;
}


sub contains_file {
    my $self = shift;
    my $full = shift;

    return unless defined $full;

    ### don't warn if the entry isn't there.. that's what this function
    ### is for after all.
    local $WARN = 0;
    return 1 if $self->_find_entry($full);
    return;
}


sub extract {
    my $self    = shift;
    my @args    = @_;
    my @files;

    # use the speed optimization for all extracted files
    local($self->{cwd}) = cwd() unless $self->{cwd};

    ### you requested the extraction of only certain files
    if( @args ) {
        for my $file ( @args ) {

            ### it's already an object?
            if( UNIVERSAL::isa( $file, 'Archive::Tar::File' ) ) {
                push @files, $file;
                next;

            ### go find it then
            } else {

                my $found;
                for my $entry ( @{$self->_data} ) {
                    next unless $file eq $entry->full_path;

                    ### we found the file you're looking for
                    push @files, $entry;
                    $found++;
                }

                unless( $found ) {
                    return $self->_error(
                        qq[Could not find '$file' in archive] );
                }
            }
        }

    ### just grab all the file items
    } else {
        @files = $self->get_files;
    }

    ### nothing found? that's an error
    unless( scalar @files ) {
        $self->_error( qq[No files found for ] . $self->_file );
        return;
    }

    ### now extract them
    for my $entry ( @files ) {
        unless( $self->_extract_file( $entry ) ) {
            $self->_error(q[Could not extract ']. $entry->full_path .q['] );
            return;
        }
    }

    return @files;
}


sub extract_file {
    my $self = shift;
    my $file = shift;   return unless defined $file;
    my $alt  = shift;

    my $entry = $self->_find_entry( $file )
        or $self->_error( qq[Could not find an entry for '$file'] ), return;

    return $self->_extract_file( $entry, $alt );
}

sub _extract_file {
    my $self    = shift;
    my $entry   = shift or return;
    my $alt     = shift;

    ### you wanted an alternate extraction location ###
    my $name = defined $alt ? $alt : $entry->full_path;

                            ### splitpath takes a bool at the end to indicate
                            ### that it's splitting a dir
    my ($vol,$dirs,$file);
    if ( defined $alt ) { # It's a local-OS path
        ($vol,$dirs,$file) = File::Spec->splitpath(       $alt,
                                                          $entry->is_dir );
    } else {
        ($vol,$dirs,$file) = File::Spec::Unix->splitpath( $name,
                                                          $entry->is_dir );
    }

    my $dir;
    ### is $name an absolute path? ###
    if( $vol || File::Spec->file_name_is_absolute( $dirs ) ) {

        ### absolute names are not allowed to be in tarballs under
        ### strict mode, so only allow it if a user tells us to do it
        if( not defined $alt and not $INSECURE_EXTRACT_MODE ) {
            $self->_error(
                q[Entry ']. $entry->full_path .q[' is an absolute path. ].
                q[Not extracting absolute paths under SECURE EXTRACT MODE]
            );
            return;
        }

        ### user asked us to, it's fine.
        $dir = File::Spec->catpath( $vol, $dirs, "" );

    ### it's a relative path ###
    } else {
        my $cwd     = (ref $self and defined $self->{cwd})
                        ? $self->{cwd}
                        : cwd();

        my @dirs = defined $alt
            ? File::Spec->splitdir( $dirs )         # It's a local-OS path
            : File::Spec::Unix->splitdir( $dirs );  # it's UNIX-style, likely
                                                    # straight from the tarball

        if( not defined $alt            and
            not $INSECURE_EXTRACT_MODE
        ) {

            ### paths that leave the current directory are not allowed under
            ### strict mode, so only allow it if a user tells us to do this.
            if( grep { $_ eq '..' } @dirs ) {

                $self->_error(
                    q[Entry ']. $entry->full_path .q[' is attempting to leave ].
                    q[the current working directory. Not extracting under ].
                    q[SECURE EXTRACT MODE]
                );
                return;
            }

            ### the archive may be asking us to extract into a symlink. This
            ### is not sane and a possible security issue, as outlined here:
            ### https://rt.cpan.org/Ticket/Display.html?id=30380
            ### https://bugzilla.redhat.com/show_bug.cgi?id=295021
            ### https://issues.rpath.com/browse/RPL-1716
            my $full_path = $cwd;
            for my $d ( @dirs ) {
                $full_path = File::Spec->catdir( $full_path, $d );

                ### we've already checked this one, and it's safe. Move on.
                next if ref $self and $self->{_link_cache}->{$full_path};

                if( -l $full_path ) {
                    my $to   = readlink $full_path;
                    my $diag = "symlinked directory ($full_path => $to)";

                    $self->_error(
                        q[Entry ']. $entry->full_path .q[' is attempting to ].
                        qq[extract to a $diag. This is considered a security ].
                        q[vulnerability and not allowed under SECURE EXTRACT ].
                        q[MODE]
                    );
                    return;
                }

                ### XXX keep a cache if possible, so the stats become cheaper:
                $self->{_link_cache}->{$full_path} = 1 if ref $self;
            }
        }

        ### '.' is the directory delimiter on VMS, which has to be escaped
        ### or changed to '_' on vms.  vmsify is used, because older versions
        ### of vmspath do not handle this properly.
        ### Must not add a '/' to an empty directory though.
        map { length() ? VMS::Filespec::vmsify($_.'/') : $_ } @dirs if ON_VMS;

        my ($cwd_vol,$cwd_dir,$cwd_file)
                    = File::Spec->splitpath( $cwd );
        my @cwd     = File::Spec->splitdir( $cwd_dir );
        push @cwd, $cwd_file if length $cwd_file;

        ### We need to pass '' as the last element to catpath. Craig Berry
        ### explains why (msgid <p0624083dc311ae541393@[172.16.52.1]>):
        ### The root problem is that splitpath on UNIX always returns the
        ### final path element as a file even if it is a directory, and of
        ### course there is no way it can know the difference without checking
        ### against the filesystem, which it is documented as not doing.  When
        ### you turn around and call catpath, on VMS you have to know which bits
        ### are directory bits and which bits are file bits.  In this case we
        ### know the result should be a directory.  I had thought you could omit
        ### the file argument to catpath in such a case, but apparently on UNIX
        ### you can't.
        $dir        = File::Spec->catpath(
                            $cwd_vol, File::Spec->catdir( @cwd, @dirs ), ''
                        );

        ### catdir() returns undef if the path is longer than 255 chars on
        ### older VMS systems.
        unless ( defined $dir ) {
            $^W && $self->_error( qq[Could not compose a path for '$dirs'\n] );
            return;
        }

    }

    if( -e $dir && !-d _ ) {
        $^W && $self->_error( qq['$dir' exists, but it's not a directory!\n] );
        return;
    }

    unless ( -d _ ) {
        eval { File::Path::mkpath( $dir, 0, 0777 ) };
        if( $@ ) {
            my $fp = $entry->full_path;
            $self->_error(qq[Could not create directory '$dir' for '$fp': $@]);
            return;
        }

        ### XXX chown here? that might not be the same as in the archive
        ### as we're only chown'ing to the owner of the file we're extracting
        ### not to the owner of the directory itself, which may or may not
        ### be another entry in the archive
        ### Answer: no, gnu tar doesn't do it either, it'd be the wrong
        ### way to go.
        #if( $CHOWN && CAN_CHOWN ) {
        #    chown $entry->uid, $entry->gid, $dir or
        #        $self->_error( qq[Could not set uid/gid on '$dir'] );
        #}
    }

    ### we're done if we just needed to create a dir ###
    return 1 if $entry->is_dir;

    my $full = File::Spec->catfile( $dir, $file );

    if( $entry->is_unknown ) {
        $self->_error( qq[Unknown file type for file '$full'] );
        return;
    }

    if( length $entry->type && $entry->is_file ) {
        my $fh = IO::File->new;
        $fh->open( '>' . $full ) or (
            $self->_error( qq[Could not open file '$full': $!] ),
            return
        );

        if( $entry->size ) {
            binmode $fh;
            syswrite $fh, $entry->data or (
                $self->_error( qq[Could not write data to '$full'] ),
                return
            );
        }

        close $fh or (
            $self->_error( qq[Could not close file '$full'] ),
            return
        );

    } else {
        $self->_make_special_file( $entry, $full ) or return;
    }

    ### only update the timestamp if it's not a symlink; that will change the
    ### timestamp of the original. This addresses bug #33669: Could not update
    ### timestamp warning on symlinks
    if( not -l $full ) {
        utime time, $entry->mtime - TIME_OFFSET, $full or
            $self->_error( qq[Could not update timestamp] );
    }

    if( $CHOWN && CAN_CHOWN->() and not -l $full ) {
        chown $entry->uid, $entry->gid, $full or
            $self->_error( qq[Could not set uid/gid on '$full'] );
    }

    ### only chmod if we're allowed to, but never chmod symlinks, since they'll
    ### change the perms on the file they're linking too...
    if( $CHMOD and not -l $full ) {
        my $mode = $entry->mode;
        unless ($SAME_PERMISSIONS) {
            $mode &= ~(oct(7000) | umask);
        }
        chmod $mode, $full or
            $self->_error( qq[Could not chown '$full' to ] . $entry->mode );
    }

    return 1;
}

sub _make_special_file {
    my $self    = shift;
    my $entry   = shift     or return;
    my $file    = shift;    return unless defined $file;

    my $err;

    if( $entry->is_symlink ) {
        my $fail;
        if( ON_UNIX ) {
            symlink( $entry->linkname, $file ) or $fail++;

        } else {
            $self->_extract_special_file_as_plain_file( $entry, $file )
                or $fail++;
        }

        $err =  qq[Making symbolic link '$file' to '] .
                $entry->linkname .q[' failed] if $fail;

    } elsif ( $entry->is_hardlink ) {
        my $fail;
        if( ON_UNIX ) {
            link( $entry->linkname, $file ) or $fail++;

        } else {
            $self->_extract_special_file_as_plain_file( $entry, $file )
                or $fail++;
        }

        $err =  qq[Making hard link from '] . $entry->linkname .
                qq[' to '$file' failed] if $fail;

    } elsif ( $entry->is_fifo ) {
        ON_UNIX && !system('mknod', $file, 'p') or
            $err = qq[Making fifo ']. $entry->name .qq[' failed];

    } elsif ( $entry->is_blockdev or $entry->is_chardev ) {
        my $mode = $entry->is_blockdev ? 'b' : 'c';

        ON_UNIX && !system('mknod', $file, $mode,
                            $entry->devmajor, $entry->devminor) or
            $err =  qq[Making block device ']. $entry->name .qq[' (maj=] .
                    $entry->devmajor . qq[ min=] . $entry->devminor .
                    qq[) failed.];

    } elsif ( $entry->is_socket ) {
        ### the original doesn't do anything special for sockets.... ###
        1;
    }

    return $err ? $self->_error( $err ) : 1;
}

sub _extract_special_file_as_plain_file {
    my $self    = shift;
    my $entry   = shift     or return;
    my $file    = shift;    return unless defined $file;

    my $err;
    TRY: {
        my $orig = $self->_find_entry( $entry->linkname, $entry );

        unless( $orig ) {
            $err =  qq[Could not find file '] . $entry->linkname .
                    qq[' in memory.];
            last TRY;
        }

        ### clone the entry, make it appear as a normal file ###
        my $clone = $orig->clone;
        $clone->_downgrade_to_plainfile;
        $self->_extract_file( $clone, $file ) or last TRY;

        return 1;
    }

    return $self->_error($err);
}


sub list_files {
    my $self = shift;
    my $aref = shift || [ ];

    unless( $self->_data ) {
        $self->read() or return;
    }

    if( @$aref == 0 or ( @$aref == 1 and $aref->[0] eq 'name' ) ) {
        return map { $_->full_path } @{$self->_data};
    } else {

        #my @rv;
        #for my $obj ( @{$self->_data} ) {
        #    push @rv, { map { $_ => $obj->$_() } @$aref };
        #}
        #return @rv;

        ### this does the same as the above.. just needs a +{ }
        ### to make sure perl doesn't confuse it for a block
        return map {    my $o=$_;
                        +{ map { $_ => $o->$_() } @$aref }
                    } @{$self->_data};
    }
}

sub _find_entry {
    my $self = shift;
    my $file = shift;

    unless( defined $file ) {
        $self->_error( qq[No file specified] );
        return;
    }

    ### it's an object already
    return $file if UNIVERSAL::isa( $file, 'Archive::Tar::File' );

seach_entry:
		if($self->_data){
			for my $entry ( @{$self->_data} ) {
					my $path = $entry->full_path;
					return $entry if $path eq $file;
			}
		}

		if($Archive::Tar::RESOLVE_SYMLINK!~/none/){
			if(my $link_entry = shift()){#fallback mode when symlinks are using relative notations ( ../a/./b/text.bin )
				$file = _symlinks_resolver( $link_entry->name, $file );
				goto seach_entry if $self->_data;

				#this will be slower than never, but won't failed!

				my $iterargs = $link_entry->{'_archive'};
				if($Archive::Tar::RESOLVE_SYMLINK=~/speed/ && @$iterargs==3){
				#faster	but whole archive will be read in memory
					#read whole archive and share data
					my $archive = Archive::Tar->new;
					$archive->read( @$iterargs );
					push @$iterargs, $archive; #take a trace for destruction
					if($archive->_data){
						$self->_data( $archive->_data );
						goto seach_entry;
					}
				}#faster

				{#slower but lower memory usage
					# $iterargs = [$filename, $compressed, $opts];
					my $next = Archive::Tar->iter( @$iterargs );
					while(my $e = $next->()){
						if($e->full_path eq $file){
							undef $next;
							return $e;
						}
					}
				}#slower
			}
		}

    $self->_error( qq[No such file in archive: '$file'] );
    return;
}


sub get_files {
    my $self = shift;

    return @{ $self->_data } unless @_;

    my @list;
    for my $file ( @_ ) {
        push @list, grep { defined } $self->_find_entry( $file );
    }

    return @list;
}


sub get_content {
    my $self = shift;
    my $entry = $self->_find_entry( shift ) or return;

    return $entry->data;
}


sub replace_content {
    my $self = shift;
    my $entry = $self->_find_entry( shift ) or return;

    return $entry->replace_content( shift );
}


sub rename {
    my $self = shift;
    my $file = shift; return unless defined $file;
    my $new  = shift; return unless defined $new;

    my $entry = $self->_find_entry( $file ) or return;

    return $entry->rename( $new );
}


sub chmod {
    my $self = shift;
    my $file = shift; return unless defined $file;
    my $mode = shift; return unless defined $mode && $mode =~ /^[0-7]{1,4}$/;
    my @args = ("$mode");

    my $entry = $self->_find_entry( $file ) or return;
    my $x = $entry->chmod( @args );
    return $x;
}


sub chown {
    my $self = shift;
    my $file = shift; return unless defined $file;
    my $uname  = shift; return unless defined $uname;
    my @args   = ($uname);
    push(@args, shift);

    my $entry = $self->_find_entry( $file ) or return;
    my $x = $entry->chown( @args );
    return $x;
}


sub remove {
    my $self = shift;
    my @list = @_;

    my %seen = map { $_->full_path => $_ } @{$self->_data};
    delete $seen{ $_ } for @list;

    $self->_data( [values %seen] );

    return values %seen;
}


sub clear {
    my $self = shift or return;

    $self->_data( [] );
    $self->_file( '' );

    return 1;
}



sub write {
    my $self        = shift;
    my $file        = shift; $file = '' unless defined $file;
    my $gzip        = shift || 0;
    my $ext_prefix  = shift; $ext_prefix = '' unless defined $ext_prefix;
    my $dummy       = '';

    ### only need a handle if we have a file to print to ###
    my $handle = length($file)
                    ? ( $self->_get_handle($file, $gzip, WRITE_ONLY->($gzip) )
                        or return )
                    : $HAS_PERLIO    ? do { open my $h, '>', \$dummy; $h }
                    : $HAS_IO_STRING ? IO::String->new
                    : __PACKAGE__->no_string_support();

    ### Addresses: #41798: Nonempty $\ when writing a TAR file produces a
    ### corrupt TAR file. Must clear out $\ to make sure no garbage is
    ### printed to the archive
    local $\;

    for my $entry ( @{$self->_data} ) {
        ### entries to be written to the tarfile ###
        my @write_me;

        ### only now will we change the object to reflect the current state
        ### of the name and prefix fields -- this needs to be limited to
        ### write() only!
        my $clone = $entry->clone;


        ### so, if you don't want use to use the prefix, we'll stuff
        ### everything in the name field instead
        if( $DO_NOT_USE_PREFIX ) {

            ### you might have an extended prefix, if so, set it in the clone
            ### XXX is ::Unix right?
            $clone->name( length $ext_prefix
                            ? File::Spec::Unix->catdir( $ext_prefix,
                                                        $clone->full_path)
                            : $clone->full_path );
            $clone->prefix( '' );

        ### otherwise, we'll have to set it properly -- prefix part in the
        ### prefix and name part in the name field.
        } else {

            ### split them here, not before!
            my ($prefix,$name) = $clone->_prefix_and_file( $clone->full_path );

            ### you might have an extended prefix, if so, set it in the clone
            ### XXX is ::Unix right?
            $prefix = File::Spec::Unix->catdir( $ext_prefix, $prefix )
                if length $ext_prefix;

            $clone->prefix( $prefix );
            $clone->name( $name );
        }

        ### names are too long, and will get truncated if we don't add a
        ### '@LongLink' file...
        my $make_longlink = (   length($clone->name)    > NAME_LENGTH or
                                length($clone->prefix)  > PREFIX_LENGTH
                            ) || 0;

        ### perhaps we need to make a longlink file?
        if( $make_longlink ) {
            my $longlink = Archive::Tar::File->new(
                            data => LONGLINK_NAME,
                            $clone->full_path,
                            { type => LONGLINK }
                        );

            unless( $longlink ) {
                $self->_error(  qq[Could not create 'LongLink' entry for ] .
                                qq[oversize file '] . $clone->full_path ."'" );
                return;
            };

            push @write_me, $longlink;
        }

        push @write_me, $clone;

        ### write the one, optionally 2 a::t::file objects to the handle
        for my $clone (@write_me) {

            ### if the file is a symlink, there are 2 options:
            ### either we leave the symlink intact, but then we don't write any
            ### data OR we follow the symlink, which means we actually make a
            ### copy. if we do the latter, we have to change the TYPE of the
            ### clone to 'FILE'
            my $link_ok =  $clone->is_symlink && $Archive::Tar::FOLLOW_SYMLINK;
            my $data_ok = !$clone->is_symlink && $clone->has_content;

            ### downgrade to a 'normal' file if it's a symlink we're going to
            ### treat as a regular file
            $clone->_downgrade_to_plainfile if $link_ok;

            ### get the header for this block
            my $header = $self->_format_tar_entry( $clone );
            unless( $header ) {
                $self->_error(q[Could not format header for: ] .
                                    $clone->full_path );
                return;
            }

            unless( print $handle $header ) {
                $self->_error(q[Could not write header for: ] .
                                    $clone->full_path);
                return;
            }

            if( $link_ok or $data_ok ) {
                unless( print $handle $clone->data ) {
                    $self->_error(q[Could not write data for: ] .
                                    $clone->full_path);
                    return;
                }

                ### pad the end of the clone if required ###
                print $handle TAR_PAD->( $clone->size ) if $clone->size % BLOCK
            }

        } ### done writing these entries
    }

    ### write the end markers ###
    print $handle TAR_END x 2 or
            return $self->_error( qq[Could not write tar end markers] );

    ### did you want it written to a file, or returned as a string? ###
    my $rv =  length($file) ? 1
                        : $HAS_PERLIO ? $dummy
                        : do { seek $handle, 0, 0; local $/; <$handle> };

    ### make sure to close the handle if we created it
    if ( $file ne $handle ) {
	unless( close $handle ) {
	    $self->_error( qq[Could not write tar] );
	    return;
	}
    }

    return $rv;
}

sub _format_tar_entry {
    my $self        = shift;
    my $entry       = shift or return;
    my $ext_prefix  = shift; $ext_prefix = '' unless defined $ext_prefix;
    my $no_prefix   = shift || 0;

    my $file    = $entry->name;
    my $prefix  = $entry->prefix; $prefix = '' unless defined $prefix;

    ### remove the prefix from the file name
    ### not sure if this is still needed --kane
    ### no it's not -- Archive::Tar::File->_new_from_file will take care of
    ### this for us. Even worse, this would break if we tried to add a file
    ### like x/x.
    #if( length $prefix ) {
    #    $file =~ s/^$match//;
    #}

    $prefix = File::Spec::Unix->catdir($ext_prefix, $prefix)
                if length $ext_prefix;

    ### not sure why this is... ###
    my $l = PREFIX_LENGTH; # is ambiguous otherwise...
    substr ($prefix, 0, -$l) = "" if length $prefix >= PREFIX_LENGTH;

    my $f1 = "%06o"; my $f2  = $ZERO_PAD_NUMBERS ? "%011o" : "%11o";

    ### this might be optimizable with a 'changed' flag in the file objects ###
    my $tar = pack (
                PACK,
                $file,

                (map { sprintf( $f1, $entry->$_() ) } qw[mode uid gid]),
                (map { sprintf( $f2, $entry->$_() ) } qw[size mtime]),

                "",  # checksum field - space padded a bit down

                (map { $entry->$_() }                 qw[type linkname magic]),

                $entry->version || TAR_VERSION,

                (map { $entry->$_() }                 qw[uname gname]),
                (map { sprintf( $f1, $entry->$_() ) } qw[devmajor devminor]),

                ($no_prefix ? '' : $prefix)
    );

    ### add the checksum ###
    my $checksum_fmt = $ZERO_PAD_NUMBERS ? "%06o\0" : "%06o\0";
    substr($tar,148,7) = sprintf("%6o\0", unpack("%16C*",$tar));

    return $tar;
}


sub add_files {
    my $self    = shift;
    my @files   = @_ or return;

    my @rv;
    for my $file ( @files ) {

        ### you passed an Archive::Tar::File object
        ### clone it so we don't accidentally have a reference to
        ### an object from another archive
        if( UNIVERSAL::isa( $file,'Archive::Tar::File' ) ) {
            push @rv, $file->clone;
            next;
        }

        eval {
            if( utf8::is_utf8( $file )) {
              utf8::encode( $file );
            }
        };

        unless( -e $file || -l $file ) {
            $self->_error( qq[No such file: '$file'] );
            next;
        }

        my $obj = Archive::Tar::File->new( file => $file );
        unless( $obj ) {
            $self->_error( qq[Unable to add file: '$file'] );
            next;
        }

        push @rv, $obj;
    }

    push @{$self->{_data}}, @rv;

    return @rv;
}


sub add_data {
    my $self    = shift;
    my ($file, $data, $opt) = @_;

    my $obj = Archive::Tar::File->new( data => $file, $data, $opt );
    unless( $obj ) {
        $self->_error( qq[Unable to add file: '$file'] );
        return;
    }

    push @{$self->{_data}}, $obj;

    return $obj;
}


{
    $error = '';
    my $longmess;

    sub _error {
        my $self    = shift;
        my $msg     = $error = shift;
        $longmess   = Carp::longmess($error);
        if (ref $self) {
            $self->{_error} = $error;
            $self->{_longmess} = $longmess;
        }

        ### set Archive::Tar::WARN to 0 to disable printing
        ### of errors
        if( $WARN ) {
            carp $DEBUG ? $longmess : $msg;
        }

        return;
    }

    sub error {
        my $self = shift;
        if (ref $self) {
            return shift() ? $self->{_longmess} : $self->{_error};
        } else {
            return shift() ? $longmess : $error;
        }
    }
}


sub setcwd {
    my $self     = shift;
    my $cwd      = shift;

    $self->{cwd} = $cwd;
}


sub create_archive {
    my $class = shift;

    my $file    = shift; return unless defined $file;
    my $gzip    = shift || 0;
    my @files   = @_;

    unless( @files ) {
        return $class->_error( qq[Cowardly refusing to create empty archive!] );
    }

    my $tar = $class->new;
    $tar->add_files( @files );
    return $tar->write( $file, $gzip );
}



sub iter {
    my $class       = shift;
    my $filename    = shift or return;
    my $compressed  = shift || 0;
    my $opts        = shift || {};

    ### get a handle to read from.
    my $handle = $class->_get_handle(
        $filename,
        $compressed,
        READ_ONLY->( ZLIB )
    ) or return;

    my @data;
		my $CONSTRUCT_ARGS = [ $filename, $compressed, $opts ];
    return sub {
        return shift(@data)     if @data;       # more than one file returned?
        return                  unless $handle; # handle exhausted?

        ### read data, should only return file
        my $tarfile = $class->_read_tar($handle, { %$opts, limit => 1 });
        @data = @$tarfile if ref $tarfile && ref $tarfile eq 'ARRAY';
				if($Archive::Tar::RESOLVE_SYMLINK!~/none/){
					foreach(@data){
						#may refine this heuristic for ON_UNIX?
						if($_->linkname){
							#is there a better slot to store/share it ?
							$_->{'_archive'} = $CONSTRUCT_ARGS;
						}
					}
				}

        ### return one piece of data
        return shift(@data)     if @data;

        ### data is exhausted, free the filehandle
        undef $handle;
				if(@$CONSTRUCT_ARGS == 4){
					#free archive in memory
					undef $CONSTRUCT_ARGS->[-1];
				}
        return;
    };
}


sub list_archive {
    my $class   = shift;
    my $file    = shift; return unless defined $file;
    my $gzip    = shift || 0;

    my $tar = $class->new($file, $gzip);
    return unless $tar;

    return $tar->list_files( @_ );
}


sub extract_archive {
    my $class   = shift;
    my $file    = shift; return unless defined $file;
    my $gzip    = shift || 0;

    my $tar = $class->new( ) or return;

    return $tar->read( $file, $gzip, { extract => 1 } );
}


sub has_io_string { return $HAS_IO_STRING; }


sub has_perlio { return $HAS_PERLIO; }


sub has_zlib_support { return ZLIB }


sub has_bzip2_support { return BZIP }


sub can_handle_compressed_files { return ZLIB && BZIP ? 1 : 0 }

sub no_string_support {
    croak("You have to install IO::String to support writing archives to strings");
}

sub _symlinks_resolver{
  my ($src, $trg) = @_;
  my @src = split /[\/\\]/, $src;
  my @trg = split /[\/\\]/, $trg;
  pop @src; #strip out current object name
  if(@trg and $trg[0] eq ''){
    shift @trg;
    #restart path from scratch
    @src = ( );
  }
  foreach my $part ( @trg ){
    next if $part eq '.'; #ignore current
    if($part eq '..'){
      #got to parent
      pop @src;
    }
    else{
      #append it
      push @src, $part;
    }
  }
  my $path = join('/', @src);
  warn "_symlinks_resolver('$src','$trg') = $path" if $DEBUG;
  return $path;
}

1;

__END__


