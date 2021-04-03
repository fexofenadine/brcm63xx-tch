package TAP::Parser::Source;

use strict;
use warnings;

use File::Basename qw( fileparse );
use base 'TAP::Object';

use constant BLK_SIZE => 512;


our $VERSION = '3.35';



sub _initialize {
    my ($self) = @_;
    $self->meta(   {} );
    $self->config( {} );
    return $self;
}



sub raw {
    my $self = shift;
    return $self->{raw} unless @_;
    $self->{raw} = shift;
    return $self;
}

sub meta {
    my $self = shift;
    return $self->{meta} unless @_;
    $self->{meta} = shift;
    return $self;
}

sub has_meta {
    return scalar %{ shift->meta } ? 1 : 0;
}

sub config {
    my $self = shift;
    return $self->{config} unless @_;
    $self->{config} = shift;
    return $self;
}

sub merge {
    my $self = shift;
    return $self->{merge} unless @_;
    $self->{merge} = shift;
    return $self;
}

sub switches {
    my $self = shift;
    return $self->{switches} unless @_;
    $self->{switches} = shift;
    return $self;
}

sub test_args {
    my $self = shift;
    return $self->{test_args} unless @_;
    $self->{test_args} = shift;
    return $self;
}


sub assemble_meta {
    my ($self) = @_;

    return $self->meta if $self->has_meta;

    my $meta = $self->meta;
    my $raw  = $self->raw;

    # rudimentary is object test - if it's blessed it'll
    # inherit from UNIVERSAL
    $meta->{is_object} = UNIVERSAL::isa( $raw, 'UNIVERSAL' ) ? 1 : 0;

    if ( $meta->{is_object} ) {
        $meta->{class} = ref($raw);
    }
    else {
        my $ref = lc( ref($raw) );
        $meta->{"is_$ref"} = 1;
    }

    if ( $meta->{is_scalar} ) {
        my $source = $$raw;
        $meta->{length} = length($$raw);
        $meta->{has_newlines} = $$raw =~ /\n/ ? 1 : 0;

        # only do file checks if it looks like a filename
        if ( !$meta->{has_newlines} and $meta->{length} < 1024 ) {
            my $file = {};
            $file->{exists} = -e $source ? 1 : 0;
            if ( $file->{exists} ) {
                $meta->{file} = $file;

                # avoid extra system calls (see `perldoc -f -X`)
                $file->{stat}    = [ stat(_) ];
                $file->{empty}   = -z _ ? 1 : 0;
                $file->{size}    = -s _;
                $file->{text}    = -T _ ? 1 : 0;
                $file->{binary}  = -B _ ? 1 : 0;
                $file->{read}    = -r _ ? 1 : 0;
                $file->{write}   = -w _ ? 1 : 0;
                $file->{execute} = -x _ ? 1 : 0;
                $file->{setuid}  = -u _ ? 1 : 0;
                $file->{setgid}  = -g _ ? 1 : 0;
                $file->{sticky}  = -k _ ? 1 : 0;

                $meta->{is_file} = $file->{is_file} = -f _ ? 1 : 0;
                $meta->{is_dir}  = $file->{is_dir}  = -d _ ? 1 : 0;

                # symlink check requires another system call
                $meta->{is_symlink} = $file->{is_symlink}
                  = -l $source ? 1 : 0;
                if ( $file->{is_symlink} ) {
                    $file->{lstat} = [ lstat(_) ];
                }

                # put together some common info about the file
                ( $file->{basename}, $file->{dir}, $file->{ext} )
                  = map { defined $_ ? $_ : '' }
                  fileparse( $source, qr/\.[^.]*/ );
                $file->{lc_ext} = lc( $file->{ext} );
                $file->{basename} .= $file->{ext} if $file->{ext};

                if ( !$file->{is_dir} && $file->{read} ) {
                    eval { $file->{shebang} = $self->shebang($$raw); };
                    if ( my $e = $@ ) {
                        warn $e;
                    }
                }
            }
        }
    }
    elsif ( $meta->{is_array} ) {
        $meta->{size} = $#$raw + 1;
    }
    elsif ( $meta->{is_hash} ) {
        ;    # do nothing
    }

    return $meta;
}


{

    # Global shebang cache.
    my %shebang_for;

    sub _read_shebang {
        my ( $class, $file ) = @_;
        open my $fh, '<', $file or die "Can't read $file: $!\n";

        # Might be a binary file - so read a fixed number of bytes.
        my $got = read $fh, my ($buf), BLK_SIZE;
        defined $got or die "I/O error: $!\n";
        return $1 if $buf =~ /(.*)/;
        return;
    }

    sub shebang {
        my ( $class, $file ) = @_;
        $shebang_for{$file} = $class->_read_shebang($file)
          unless exists $shebang_for{$file};
        return $shebang_for{$file};
    }
}


sub config_for {
    my ( $self, $class ) = @_;
    my ($abbrv_class) = ( $class =~ /(?:\:\:)?(\w+)$/ );
    my $config = $self->config->{$abbrv_class} || $self->config->{$class};
    return $config;
}

1;

__END__

