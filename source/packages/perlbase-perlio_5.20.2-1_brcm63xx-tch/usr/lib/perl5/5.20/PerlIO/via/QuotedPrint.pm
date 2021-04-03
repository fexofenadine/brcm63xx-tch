package PerlIO::via::QuotedPrint;

$VERSION= '0.07';

use strict;

use MIME::QuotedPrint (); # no need to pollute this namespace

1;


sub PUSHED { bless \*PUSHED,$_[0] } #PUSHED


sub FILL {

    # decode and return
    my $line= readline( $_[1] );
    return ( defined $line )
      ? MIME::QuotedPrint::decode_qp($line)
      : undef;
} #FILL


sub WRITE {

    # encode and write to handle: indicate result
    return ( print { $_[2] } MIME::QuotedPrint::encode_qp( $_[1] ) )
      ? length( $_[1] )
      : -1;
} #WRITE


__END__

