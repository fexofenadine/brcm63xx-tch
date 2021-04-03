
package Errno;
require Exporter;
use Config;
use strict;

"$Config{'archname'}-$Config{'osvers'}" eq
"mips-linux-uclibc-2.4.30" or
	die "Errno architecture (mips-linux-uclibc-2.4.30) does not match executable architecture ($Config{'archname'}-$Config{'osvers'})";

our $VERSION = "1.20_05";
$VERSION = eval $VERSION;
our @ISA = 'Exporter';

my %err;

BEGIN {
    %err = (
	EPERM => 1,
	ENOENT => 2,
	ESRCH => 3,
	EINTR => 4,
	EIO => 5,
	ENXIO => 6,
	E2BIG => 7,
	ENOEXEC => 8,
	EBADF => 9,
	ECHILD => 10,
	EAGAIN => 11,
	EWOULDBLOCK => 11,
	ENOMEM => 12,
	EACCES => 13,
	EFAULT => 14,
	ENOTBLK => 15,
	EBUSY => 16,
	EEXIST => 17,
	EXDEV => 18,
	ENODEV => 19,
	ENOTDIR => 20,
	EISDIR => 21,
	EINVAL => 22,
	ENFILE => 23,
	EMFILE => 24,
	ENOTTY => 25,
	ETXTBSY => 26,
	EFBIG => 27,
	ENOSPC => 28,
	ESPIPE => 29,
	EROFS => 30,
	EMLINK => 31,
	EPIPE => 32,
	EDOM => 33,
	ERANGE => 34,
	ENOMSG => 35,
	EIDRM => 36,
	ECHRNG => 37,
	EL2NSYNC => 38,
	EL3HLT => 39,
	EL3RST => 40,
	ELNRNG => 41,
	EUNATCH => 42,
	ENOCSI => 43,
	EL2HLT => 44,
	EDEADLK => 45,
	ENOLCK => 46,
	EBADE => 50,
	EBADR => 51,
	EXFULL => 52,
	ENOANO => 53,
	EBADRQC => 54,
	EBADSLT => 55,
	EDEADLOCK => 56,
	EBFONT => 59,
	ENOSTR => 60,
	ENODATA => 61,
	ETIME => 62,
	ENOSR => 63,
	ENONET => 64,
	ENOPKG => 65,
	EREMOTE => 66,
	ENOLINK => 67,
	EADV => 68,
	ESRMNT => 69,
	ECOMM => 70,
	EPROTO => 71,
	EDOTDOT => 73,
	EMULTIHOP => 74,
	EBADMSG => 77,
	ENAMETOOLONG => 78,
	EOVERFLOW => 79,
	ENOTUNIQ => 80,
	EBADFD => 81,
	EREMCHG => 82,
	ELIBACC => 83,
	ELIBBAD => 84,
	ELIBSCN => 85,
	ELIBMAX => 86,
	ELIBEXEC => 87,
	EILSEQ => 88,
	ENOSYS => 89,
	ELOOP => 90,
	ERESTART => 91,
	ESTRPIPE => 92,
	ENOTEMPTY => 93,
	EUSERS => 94,
	ENOTSOCK => 95,
	EDESTADDRREQ => 96,
	EMSGSIZE => 97,
	EPROTOTYPE => 98,
	ENOPROTOOPT => 99,
	EPROTONOSUPPORT => 120,
	ESOCKTNOSUPPORT => 121,
	ENOTSUP => 122,
	EOPNOTSUPP => 122,
	EPFNOSUPPORT => 123,
	EAFNOSUPPORT => 124,
	EADDRINUSE => 125,
	EADDRNOTAVAIL => 126,
	ENETDOWN => 127,
	ENETUNREACH => 128,
	ENETRESET => 129,
	ECONNABORTED => 130,
	ECONNRESET => 131,
	ENOBUFS => 132,
	EISCONN => 133,
	ENOTCONN => 134,
	EUCLEAN => 135,
	ENOTNAM => 137,
	ENAVAIL => 138,
	EISNAM => 139,
	EREMOTEIO => 140,
	EINIT => 141,
	EREMDEV => 142,
	ESHUTDOWN => 143,
	ETOOMANYREFS => 144,
	ETIMEDOUT => 145,
	ECONNREFUSED => 146,
	EHOSTDOWN => 147,
	EHOSTUNREACH => 148,
	EALREADY => 149,
	EINPROGRESS => 150,
	ESTALE => 151,
	ECANCELED => 158,
	ENOMEDIUM => 159,
	EMEDIUMTYPE => 160,
	ENOKEY => 161,
	EKEYEXPIRED => 162,
	EKEYREVOKED => 163,
	EKEYREJECTED => 164,
	EOWNERDEAD => 165,
	ENOTRECOVERABLE => 166,
	ERFKILL => 167,
	EHWPOISON => 168,
	EDQUOT => 1133,
    );
    # Generate proxy constant subroutines for all the values.
    # Well, almost all the values. Unfortunately we can't assume that at this
    # point that our symbol table is empty, as code such as if the parser has
    # seen code such as C<exists &Errno::EINVAL>, it will have created the
    # typeglob.
    # Doing this before defining @EXPORT_OK etc means that even if a platform is
    # crazy enough to define EXPORT_OK as an error constant, everything will
    # still work, because the parser will upgrade the PCS to a real typeglob.
    # We rely on the subroutine definitions below to update the internal caches.
    # Don't use %each, as we don't want a copy of the value.
    foreach my $name (keys %err) {
        if ($Errno::{$name}) {
            # We expect this to be reached fairly rarely, so take an approach
            # which uses the least compile time effort in the common case:
            eval "sub $name() { $err{$name} }; 1" or die $@;
        } else {
            $Errno::{$name} = \$err{$name};
        }
    }
}

our @EXPORT_OK = keys %err;

our %EXPORT_TAGS = (
    POSIX => [qw(
	E2BIG EACCES EADDRINUSE EADDRNOTAVAIL EAFNOSUPPORT EAGAIN EALREADY
	EBADF EBUSY ECHILD ECONNABORTED ECONNREFUSED ECONNRESET EDEADLK
	EDESTADDRREQ EDOM EDQUOT EEXIST EFAULT EFBIG EHOSTDOWN EHOSTUNREACH
	EINPROGRESS EINTR EINVAL EIO EISCONN EISDIR ELOOP EMFILE EMLINK
	EMSGSIZE ENAMETOOLONG ENETDOWN ENETRESET ENETUNREACH ENFILE ENOBUFS
	ENODEV ENOENT ENOEXEC ENOLCK ENOMEM ENOPROTOOPT ENOSPC ENOSYS ENOTBLK
	ENOTCONN ENOTDIR ENOTEMPTY ENOTSOCK ENOTTY ENXIO EOPNOTSUPP EPERM
	EPFNOSUPPORT EPIPE EPROTONOSUPPORT EPROTOTYPE ERANGE EREMOTE ERESTART
	EROFS ESHUTDOWN ESOCKTNOSUPPORT ESPIPE ESRCH ESTALE ETIMEDOUT
	ETOOMANYREFS ETXTBSY EUSERS EWOULDBLOCK EXDEV
    )]
);

sub TIEHASH { bless \%err }

sub FETCH {
    my (undef, $errname) = @_;
    return "" unless exists $err{$errname};
    my $errno = $err{$errname};
    return $errno == $! ? $errno : 0;
}

sub STORE {
    require Carp;
    Carp::confess("ERRNO hash is read only!");
}

*CLEAR = *DELETE = \*STORE; # Typeglob aliasing uses less space

sub NEXTKEY {
    each %err;
}

sub FIRSTKEY {
    my $s = scalar keys %err;	# initialize iterator
    each %err;
}

sub EXISTS {
    my (undef, $errname) = @_;
    exists $err{$errname};
}

tie %!, __PACKAGE__; # Returns an object, objects are true.

__END__


