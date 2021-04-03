package Digest::file;

use strict;

use Exporter ();
use Carp qw(croak);
use Digest ();

use vars qw($VERSION @ISA @EXPORT_OK);

$VERSION = "1.16";
@ISA = qw(Exporter);
@EXPORT_OK = qw(digest_file_ctx digest_file digest_file_hex digest_file_base64);

sub digest_file_ctx {
    my $file = shift;
    croak("No digest algorithm specified") unless @_;
    local *F;
    open(F, "<", $file) || croak("Can't open '$file': $!");
    binmode(F);
    my $ctx = Digest->new(@_);
    $ctx->addfile(*F);
    close(F);
    return $ctx;
}

sub digest_file {
    digest_file_ctx(@_)->digest;
}

sub digest_file_hex {
    digest_file_ctx(@_)->hexdigest;
}

sub digest_file_base64 {
    digest_file_ctx(@_)->b64digest;
}

1;

__END__

