package TAP::Parser::YAMLish::Writer;

use strict;
use warnings;

use base 'TAP::Object';

our $VERSION = '3.30';

my $ESCAPE_CHAR = qr{ [ \x00-\x1f \" ] }x;
my $ESCAPE_KEY  = qr{ (?: ^\W ) | $ESCAPE_CHAR }x;

my @UNPRINTABLE = qw(
  z    x01  x02  x03  x04  x05  x06  a
  x08  t    n    v    f    r    x0e  x0f
  x10  x11  x12  x13  x14  x15  x16  x17
  x18  x19  x1a  e    x1c  x1d  x1e  x1f
);


sub write {
    my $self = shift;

    die "Need something to write"
      unless @_;

    my $obj = shift;
    my $out = shift || \*STDOUT;

    die "Need a reference to something I can write to"
      unless ref $out;

    $self->{writer} = $self->_make_writer($out);

    $self->_write_obj( '---', $obj );
    $self->_put('...');

    delete $self->{writer};
}

sub _make_writer {
    my $self = shift;
    my $out  = shift;

    my $ref = ref $out;

    if ( 'CODE' eq $ref ) {
        return $out;
    }
    elsif ( 'ARRAY' eq $ref ) {
        return sub { push @$out, shift };
    }
    elsif ( 'SCALAR' eq $ref ) {
        return sub { $$out .= shift() . "\n" };
    }
    elsif ( 'GLOB' eq $ref || 'IO::Handle' eq $ref ) {
        return sub { print $out shift(), "\n" };
    }

    die "Can't write to $out";
}

sub _put {
    my $self = shift;
    $self->{writer}->( join '', @_ );
}

sub _enc_scalar {
    my $self = shift;
    my $val  = shift;
    my $rule = shift;

    return '~' unless defined $val;

    if ( $val =~ /$rule/ ) {
        $val =~ s/\\/\\\\/g;
        $val =~ s/"/\\"/g;
        $val =~ s/ ( [\x00-\x1f] ) / '\\' . $UNPRINTABLE[ ord($1) ] /gex;
        return qq{"$val"};
    }

    if ( length($val) == 0 or $val =~ /\s/ ) {
        $val =~ s/'/''/;
        return "'$val'";
    }

    return $val;
}

sub _write_obj {
    my $self   = shift;
    my $prefix = shift;
    my $obj    = shift;
    my $indent = shift || 0;

    if ( my $ref = ref $obj ) {
        my $pad = '  ' x $indent;
        if ( 'HASH' eq $ref ) {
            if ( keys %$obj ) {
                $self->_put($prefix);
                for my $key ( sort keys %$obj ) {
                    my $value = $obj->{$key};
                    $self->_write_obj(
                        $pad . $self->_enc_scalar( $key, $ESCAPE_KEY ) . ':',
                        $value, $indent + 1
                    );
                }
            }
            else {
                $self->_put( $prefix, ' {}' );
            }
        }
        elsif ( 'ARRAY' eq $ref ) {
            if (@$obj) {
                $self->_put($prefix);
                for my $value (@$obj) {
                    $self->_write_obj(
                        $pad . '-', $value,
                        $indent + 1
                    );
                }
            }
            else {
                $self->_put( $prefix, ' []' );
            }
        }
        else {
            die "Don't know how to encode $ref";
        }
    }
    else {
        $self->_put( $prefix, ' ', $self->_enc_scalar( $obj, $ESCAPE_CHAR ) );
    }
}

1;

__END__


