
package Compress::Bzip2;

use 5.006;
our $VERSION = "2.22";
use strict;
use warnings;

use Carp;
use Getopt::Std;
use Fcntl qw(:DEFAULT :mode);

require Exporter;
use AutoLoader;

our @ISA = qw(Exporter);


our %EXPORT_TAGS =
    ( 'constants' => [ qw(
			  BZ_CONFIG_ERROR
			  BZ_DATA_ERROR
			  BZ_DATA_ERROR_MAGIC
			  BZ_FINISH
			  BZ_FINISH_OK
			  BZ_FLUSH
			  BZ_FLUSH_OK
			  BZ_IO_ERROR
			  BZ_MAX_UNUSED
			  BZ_MEM_ERROR
			  BZ_OK
			  BZ_OUTBUFF_FULL
			  BZ_PARAM_ERROR
			  BZ_RUN
			  BZ_RUN_OK
			  BZ_SEQUENCE_ERROR
			  BZ_STREAM_END
			  BZ_UNEXPECTED_EOF
			 ) ],

      'utilities' => [ qw(
			  &bzopen
			  &bzinflateInit
			  &bzdeflateInit
			  &memBzip &memBunzip
			  &compress &decompress
			  &bzip2 &bunzip2
			  &bzlibversion
			  $bzerrno
			  ) ],

      'bzip1' => [ qw(
		      &compress
		      &decompress
		      &compress_init
		      &decompress_init
		      &version
		      ) ],

      'gzip' => [ qw(
		     &gzopen
		     &inflateInit
		     &deflateInit
		     &compress &uncompress
		     &adler32 &crc32

		     ZLIB_VERSION

		     $gzerrno

		     Z_OK
		     Z_STREAM_END
		     Z_NEED_DICT
		     Z_ERRNO
		     Z_STREAM_ERROR
		     Z_DATA_ERROR
		     Z_MEM_ERROR
		     Z_BUF_ERROR
		     Z_VERSION_ERROR

		     Z_NO_FLUSH
		     Z_PARTIAL_FLUSH
		     Z_SYNC_FLUSH
		     Z_FULL_FLUSH
		     Z_FINISH
		     Z_BLOCK

		     Z_NO_COMPRESSION
		     Z_BEST_SPEED
		     Z_BEST_COMPRESSION
		     Z_DEFAULT_COMPRESSION

		     Z_FILTERED
		     Z_HUFFMAN_ONLY
		     Z_RLE
		     Z_DEFAULT_STRATEGY

		     Z_BINARY
		     Z_ASCII
		     Z_UNKNOWN

		     Z_DEFLATED
		     Z_NULL
		     ) ],
      );

our @EXPORT_OK = ( @{ $EXPORT_TAGS{'utilities'} },
		   @{ $EXPORT_TAGS{'constants'} },
		   @{ $EXPORT_TAGS{'bzip1'} },
		   @{ $EXPORT_TAGS{'gzip'} },
		   );

$EXPORT_TAGS{'all'} = [ @EXPORT_OK ];

our @EXPORT = ( @{ $EXPORT_TAGS{'utilities'} }, @{ $EXPORT_TAGS{'constants'} } );

our $bzerrno = "";
our $gzerrno;
*gzerrno = \$bzerrno;

use constant ZLIB_VERSION => '1.x';
use constant { Z_NO_FLUSH => 0, Z_PARTIAL_FLUSH => 1, Z_SYNC_FLUSH => 2,
	       Z_FULL_FLUSH => 3, Z_FINISH => 4, Z_BLOCK => 5 };
use constant { Z_OK => 0, Z_STREAM_END => 1, Z_NEED_DICT => 2, Z_ERRNO => -1,
	       Z_STREAM_ERROR => -2, Z_DATA_ERROR => -3, Z_MEM_ERROR => -4,
	       Z_BUF_ERROR => -5, Z_VERSION_ERROR => -6 };
use constant { Z_NO_COMPRESSION => 0, Z_BEST_SPEED => 1,
	       Z_BEST_COMPRESSION => 9, Z_DEFAULT_COMPRESSION => -1 };
use constant { Z_FILTERED => 1, Z_HUFFMAN_ONLY => 2, Z_RLE => 3,
	       Z_DEFAULT_STRATEGY => 0 };
use constant { Z_BINARY => 0, Z_ASCII => 1, Z_UNKNOWN => 2 };
use constant Z_DEFLATED => 8;
use constant Z_NULL => 0;


sub AUTOLOAD {
    # This AUTOLOAD is used to 'autoload' constants from the constant()
    # XS function.

    my $constname;
    our $AUTOLOAD;
    ($constname = $AUTOLOAD) =~ s/.*:://;
    croak "&Compress::Bzip2::constant not defined" if $constname eq 'constant';
    my ($error, $val) = constant($constname);
    if ($error) { croak $error; }
    {
	no strict 'refs';
	# Fixed between 5.005_53 and 5.005_61
	    *$AUTOLOAD = sub { $val };
    }
    goto &$AUTOLOAD;
}

require XSLoader;
XSLoader::load('Compress::Bzip2', $VERSION);



sub _writefileopen ( $$;$ ) {
  ## open a protected file for write
  my ( $handle, $filename, $force ) = @_;

  if ( sysopen($handle, $filename, $force ? O_WRONLY|O_CREAT|O_TRUNC : O_WRONLY|O_CREAT|O_EXCL, S_IWUSR|S_IRUSR) ) {
    $_[0] = $handle if !defined($_[0]);
    return $handle;
  }

  return undef;
}

sub _stat_snapshot ( $ ) {
  my ( $filename ) = @_;
  return undef if !defined($filename);

  my @stats = stat $filename;
  if (!@stats) {
    warn "stat of $filename failed: $!\n" if !@stats;
    return undef;
  }

  return \@stats;
}

sub _check_stat ( $$;$ ) {
  my ( $filename, $statsnap, $force ) = @_;

  if ( !defined($statsnap) || (ref($statsnap) eq 'ARRAY' && @$statsnap == 0) ) {
    $statsnap = _stat_snapshot( $filename );
    if ( $statsnap ) {
      if ( @_>1 ) {
	if ( !defined($_[1]) ) {
	  $_[1] = $statsnap;
	}
	elsif ( ref($_[1]) eq 'ARRAY' && @{ $_[1] } == 0 ) {
	  @{ $_[1] } = @$statsnap;
	}
      }
    }
    else {
      return undef;
    }
  }

  if ( S_ISDIR( $statsnap->[2] ) ) {
    bz_seterror( &BZ_IO_ERROR, "file $filename is a directory" );
    return 0;
  }

  if ( !S_ISREG( $statsnap->[2] ) ) {
    bz_seterror( &BZ_IO_ERROR, "file $filename is not a normal file" );
    return 0;
  }

  if ( !$force && S_ISLNK( $statsnap->[2] ) ) {
    bz_seterror( &BZ_IO_ERROR, "file $filename is a symlink" );
    return 0;
  }

  if ( !$force && $statsnap->[3] > 1 ) {
    bz_seterror( &BZ_IO_ERROR, "file $filename has too many hard links" );
    return 0;
  }

  return 1;
}

sub _set_stat_from_snapshot ( $$ ) {
  my ( $filename, $statsnap ) = @_;

  if ( !chmod( S_IMODE( $statsnap->[2] ), $filename ) ) {
    bz_seterror( &BZ_IO_ERROR, "chmod ".sprintf('%03o', S_IMODE( $statsnap->[2] ))." $filename failed: $!" );
    return undef;
  }

  if ( !utime @$statsnap[8,9], $filename ) {
    bz_seterror( &BZ_IO_ERROR,
		 "utime " . join(' ',map { strftime('%Y-%m-%d %H:%M:%S', localtime $_) } @$statsnap[8,9] ) .
		 " $filename failed: $!" );
    return undef;
  }

  if ( !chown @$statsnap[4,5], $filename ) {
    bz_seterror( &BZ_IO_ERROR,
		 "chown " . join(':', ( getpwuid($statsnap->[4]) )[0], ( getgrgid($statsnap->[5]) )[0]) .
		 " $filename failed: $!" );
    return 0;
  }

  return 1;
}

sub bzip2 ( @ ) {
  return _process_files( 'bzip2', 'cfvks123456789', @_ );
}

sub bunzip2 ( @ ) {
  return _process_files( 'bunzip2', 'cdzfks123456789', @_ );
}

sub bzcat ( @ ) {
  return _process_files( 'bzcat', 'cdzfks123456789', @_ );
}

sub _process_files ( @ ) {
  my $command = shift;
  my $opts = shift;

  local @ARGV = @_;

  my %opts;
  return undef if !getopt( $opts, \%opts );
  # c compress or decompress to stdout
  # d decompress
  # z compress
  # f force
  # v verbose
  # k keep
  # s small
  # 123456789

  $opts{c} = 1 if $command eq 'bzcat';
  $opts{d} = 1 if $command eq 'bunzip2' || $command eq 'bzcat';
  $opts{z} = 1 if $command eq 'bzip2';

  my $read_from_stdin;
  my ( $in, $bzin );
  my ( $out, $bzout );

  if ( !@ARGV ) {
    $read_from_stdin = 1;
    $opts{c} = 1;
    if ( !open( $in, "<&STDIN" ) ) {
      die "Error: failed to input from STDIN: '$!'\n";
    }

    $bzin = bzopen( $in, "r" );
  }

  if ( $opts{c} ) {
    if ( !open( $out, ">&STDOUT" ) ) {
      die "Error: failed to output to STDOUT: '$!'\n";
    }

    $bzout = bzopen( $out, "w" );
  }

  if ( !$opts{d} && !$opts{z} ) {
    die "Error: neither compress nor decompress was indicated.\n";
  }

  my $doneflag = 0;
  while ( !$doneflag ) {
    my $infile;
    my $outfile;
    my @statbuf;

    if ( !$read_from_stdin ) {
      $infile = shift @ARGV;
      if ( ! -r $infile ) {
	print STDERR "Error: file $infile is not readable\n";
	next;
      }

      @statbuf = stat _;
      if ( !@statbuf ) {
	print STDERR "Error: failed to stat $infile: '$!'\n";
	next;
      }

      if ( !_check_stat( $infile, \@statbuf, $opts{f} ) ) {
	print STDERR "Error: file $infile stat check fails: $bzerrno\n";
	next;
      }
    }

    my $outfile_exists;
    if ( !$opts{c} ) {
      undef $out;
      if ( $opts{d} ) {
	$outfile = $infile . '.bz2';
      }
      elsif ( $opts{z} ) {
	$outfile = $infile =~ /\.bz2$/ ? substr($infile,0,-4) : $infile.'.out';
      }

      $outfile_exists = -e $outfile;
      if ( !_writefileopen( $out, $outfile, $opts{f} ) ) {
	print STDERR "Error: failed to open $outfile for write: '$!'\n";
	next;
      }
    }

    if ( !$read_from_stdin ) {
      undef $in;
      if ( !open( $in, $infile ) ) {
	print STDERR "Error: unable to open $infile: '$!'\n";
	unlink( $outfile ) if !$outfile_exists;
	next;
      }
    }

    if ( $opts{d} ) {
      $bzin = bzopen( $in, "r" ) if !$read_from_stdin;

      my $buf;
      my $notdone = 1;
      while ( $notdone ) {
	my $ln = bzread( $in, $buf, 1024 );
	if ( $ln > 0 ) {
	  syswrite( $out, $buf, $ln );
	}
	elsif ( $ln == 0 ) {
	  undef $notdone;
	}
	else {
	}
      }

      close($out);

      if ( !$read_from_stdin ) {
	bzclose($in);
	unlink( $infile ) if !$opts{k};
	_set_stat_from_snapshot( $outfile, \@statbuf );
      }
    }
    elsif ( $opts{z} ) {
      $bzout = bzopen( $out, "w" ) if !$opts{c};

      my $buf;
      my $notdone = 1;
      while ( $notdone ) {
	my $ln = sysread( $in, $buf, 1024 );
	if ( $ln > 0 ) {
	  bzwrite( $bzout, $buf, $ln );
	}
	elsif ( $ln == 0 ) {
	  undef $notdone;
	}
	else {
	}
      }

      close($in);

      if ( !$opts{c} ) {
	bzclose($bzout);
	unlink( $infile ) if !$opts{k};
	_set_stat_from_snapshot( $outfile, \@statbuf );
      }
    }
  }
}


sub add ( $$ ) {
  my ( $obj, $buffer ) = @_;

  my @res = $obj->is_write ? $obj->bzdeflate( $buffer ) : $obj->bzinflate( $buffer );

  return $res[0];
}

sub finish ( $;$ ) {
  my ( $obj, $buffer ) = @_;
  my ( @res, $out );

  if ( defined($buffer) ) {
    @res = $obj->is_write ? $obj->bzdeflate( $buffer ) : $obj->bzinflate( $buffer );
    return undef if $res[1] != &BZ_OK;

    $out = $res[0];
  }
  $out = '' if !defined($out);

  @res = $obj->bzclose;
  return undef if $res[1] != &BZ_OK;

  return $out.$res[0];
}

sub input_size ( $ ) {
  my ( $obj ) = @_;
  return $obj->total_in;
}

sub output_size ( $ ) {
  my ( $obj ) = @_;
  return $obj->total_out;
}

sub version ( ) {
  return bzlibversion();
}

sub error ( $ ) {
  return $_[0]->bzerror;
}


sub _bzerror2gzerror {
  my ( $bz_error_num ) = @_;
  my $gz_error_num =
      $bz_error_num == &BZ_OK ? Z_OK :
      $bz_error_num == &BZ_RUN_OK ? Z_OK :
      $bz_error_num == &BZ_FLUSH_OK ? Z_STREAM_END :
      $bz_error_num == &BZ_FINISH_OK ? Z_STREAM_END :
      $bz_error_num == &BZ_STREAM_END ? Z_STREAM_END :

      $bz_error_num == &BZ_SEQUENCE_ERROR ? Z_VERSION_ERROR :
      $bz_error_num == &BZ_PARAM_ERROR ? Z_ERRNO :
      $bz_error_num == &BZ_MEM_ERROR ? Z_MEM_ERROR :
      $bz_error_num == &BZ_DATA_ERROR ? Z_DATA_ERROR :
      $bz_error_num == &BZ_DATA_ERROR_MAGIC ? Z_DATA_ERROR :
      $bz_error_num == &BZ_IO_ERROR ? Z_ERRNO :
      $bz_error_num == &BZ_UNEXPECTED_EOF ? Z_STREAM_ERROR :
      $bz_error_num == &BZ_OUTBUFF_FULL ? Z_BUF_ERROR :
      $bz_error_num == &BZ_CONFIG_ERROR ? Z_VERSION_ERROR :
      Z_VERSION_ERROR
      ;

  return $gz_error_num;
}

sub gzopen ( $$ ) {
  goto &bzopen;
}

sub gzread ( $$;$ ) {
  goto &bzread;
}

sub gzreadline ( $$ ) {
  goto &bzreadline;
}

sub gzwrite ( $$ ) {
  goto &bzwrite;
}

sub gzflush ( $;$ ) {
  my ( $obj, $flush ) = @_;
  return Z_OK if $flush == Z_NO_FLUSH;
  goto &bzflush;
}

sub gzclose ( $ ) {
  goto &bzclose;
}

sub gzeof ( $ ) {
  goto &bzeof;
}

sub gzsetparams ( $$$ ) {
  ## ignore params
  my ( $obj, $level, $strategy ) = @_;
  return Z_OK;
}

sub gzerror ( $ ) {
  goto &bzerror;
}

sub deflateInit ( @ ) {
  ## ignore all options:
  ## -Level, -Method, -WindowBits, -MemLevel, -Strategy, -Dictionary, -Bufsize

  my @res = bzdeflateInit();
  return $res[0] if !wantarray;

  return ( $res[0], _bzerror2gzerror( $res[1] ) );
}

sub deflate ( $$ ) {
  my ( $obj, $buffer ) = @_;

  my @res = $obj->bzdeflate( $buffer );

  return $res[0] if !wantarray;
  return ( $res[0], _bzerror2gzerror( $res[1] ) );
}

sub deflateParams ( $;@ ) {
  ## ignore all options
  return Z_OK;
}

sub flush ( $;$ ) {
  my ( $obj, $flush_type ) = @_;

  $flush_type = Z_FINISH if !defined($flush_type);
  return Z_OK if $flush_type == Z_NO_FLUSH;

  my $bz_flush_type;
  my @res;

  $bz_flush_type =
      $flush_type == Z_PARTIAL_FLUSH || $flush_type == Z_SYNC_FLUSH ? &BZ_FLUSH :
      $flush_type == Z_FULL_FLUSH ? &BZ_FINISH :
      &BZ_FINISH;

  @res = $obj->bzflush( $bz_flush_type );

  return $res[0] if !wantarray;
  return ( $res[0], _bzerror2gzerror( $res[1] ) );
}

sub dict_adler ( $ ) {
  return 1;			# ???
}

sub msg ( $ ) {
  my ( $obj ) = @_;

  return ''.($obj->bzerror).'';	# stringify
}

sub inflateInit ( @ ) {
  ## ignore all options:
  ## -WindowBits, -Dictionary, -Bufsize

  my @res = bzinflateInit();
  return $res[0] if !wantarray;

  return ( $res[0], _bzerror2gzerror( $res[1] ) );
}

sub inflate ( $$ ) {
  my ( $obj, $buffer ) = @_;

  my @res = $obj->bzinflate( $buffer );

  return $res[0] if !wantarray;
  return ( $res[0], _bzerror2gzerror( $res[1] ) );
}

sub inflateSync ( $ ) {
  return Z_VERSION_ERROR;	# ?? what
}

sub memGzip ( $ ) {
  goto &memBzip;
}

sub memGunzip ( $ ) {
  goto &memBunzip;
}

sub adler32 ( $;$ ) {
  return 0;
}

sub crc32 ( $;$ ) {
  return 0;
}


sub uncompress ( $ ) {
  my ( $source, $level ) = @_;
  return memBunzip( $source );
}


1;

__END__

