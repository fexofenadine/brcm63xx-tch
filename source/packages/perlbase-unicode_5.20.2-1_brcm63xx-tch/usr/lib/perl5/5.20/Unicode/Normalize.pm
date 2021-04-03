package Unicode::Normalize;

BEGIN {
    unless ('A' eq pack('U', 0x41)) {
	die "Unicode::Normalize cannot stringify a Unicode code point\n";
    }
    unless (0x41 == unpack('U', 'A')) {
	die "Unicode::Normalize cannot get Unicode code point\n";
    }
}

use 5.006;
use strict;
use warnings;
use Carp;

no warnings 'utf8';

our $VERSION = '1.17';
our $PACKAGE = __PACKAGE__;

our @EXPORT = qw( NFC NFD NFKC NFKD );
our @EXPORT_OK = qw(
    normalize decompose reorder compose
    checkNFD checkNFKD checkNFC checkNFKC check
    getCanon getCompat getComposite getCombinClass
    isExclusion isSingleton isNonStDecomp isComp2nd isComp_Ex
    isNFD_NO isNFC_NO isNFC_MAYBE isNFKD_NO isNFKC_NO isNFKC_MAYBE
    FCD checkFCD FCC checkFCC composeContiguous splitOnLastStarter
    normalize_partial NFC_partial NFD_partial NFKC_partial NFKD_partial
);
our %EXPORT_TAGS = (
    all       => [ @EXPORT, @EXPORT_OK ],
    normalize => [ @EXPORT, qw/normalize decompose reorder compose/ ],
    check     => [ qw/checkNFD checkNFKD checkNFC checkNFKC check/ ],
    fast      => [ qw/FCD checkFCD FCC checkFCC composeContiguous/ ],
);


sub pack_U {
    return pack('U*', @_);
}

sub unpack_U {
    return unpack('U*', shift(@_).pack('U*'));
}

require Exporter;


our @ISA = qw(Exporter DynaLoader);
require DynaLoader;
bootstrap Unicode::Normalize $VERSION;



sub FCD ($) {
    my $str = shift;
    return checkFCD($str) ? $str : NFD($str);
}

our %formNorm = (
    NFC  => \&NFC,	C  => \&NFC,
    NFD  => \&NFD,	D  => \&NFD,
    NFKC => \&NFKC,	KC => \&NFKC,
    NFKD => \&NFKD,	KD => \&NFKD,
    FCD  => \&FCD,	FCC => \&FCC,
);

sub normalize($$)
{
    my $form = shift;
    my $str = shift;
    if (exists $formNorm{$form}) {
	return $formNorm{$form}->($str);
    }
    croak($PACKAGE."::normalize: invalid form name: $form");
}


sub normalize_partial ($$) {
    if (exists $formNorm{$_[0]}) {
	my $n = normalize($_[0], $_[1]);
	my($p, $u) = splitOnLastStarter($n);
	$_[1] = $u;
	return $p;
    }
    croak($PACKAGE."::normalize_partial: invalid form name: $_[0]");
}

sub NFD_partial ($) { return normalize_partial('NFD', $_[0]) }
sub NFC_partial ($) { return normalize_partial('NFC', $_[0]) }
sub NFKD_partial($) { return normalize_partial('NFKD',$_[0]) }
sub NFKC_partial($) { return normalize_partial('NFKC',$_[0]) }


our %formCheck = (
    NFC  => \&checkNFC, 	C  => \&checkNFC,
    NFD  => \&checkNFD, 	D  => \&checkNFD,
    NFKC => \&checkNFKC,	KC => \&checkNFKC,
    NFKD => \&checkNFKD,	KD => \&checkNFKD,
    FCD  => \&checkFCD, 	FCC => \&checkFCC,
);

sub check($$)
{
    my $form = shift;
    my $str = shift;
    if (exists $formCheck{$form}) {
	return $formCheck{$form}->($str);
    }
    croak($PACKAGE."::check: invalid form name: $form");
}

1;
__END__

