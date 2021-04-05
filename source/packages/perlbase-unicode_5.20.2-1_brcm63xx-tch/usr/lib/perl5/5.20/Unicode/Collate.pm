package Unicode::Collate;

BEGIN {
    unless ("A" eq pack('U', 0x41)) {
	die "Unicode::Collate cannot stringify a Unicode code point\n";
    }
    unless (0x41 == unpack('U', 'A')) {
	die "Unicode::Collate cannot get a Unicode code point\n";
    }
}

use 5.006;
use strict;
use warnings;
use Carp;
use File::Spec;

no warnings 'utf8';

our $VERSION = '1.04';
our $PACKAGE = __PACKAGE__;

require DynaLoader;
our @ISA = qw(DynaLoader);
bootstrap Unicode::Collate $VERSION;

my @Path = qw(Unicode Collate);
my $KeyFile = "allkeys.txt";

use constant TRUE  => 1;
use constant FALSE => "";
use constant NOMATCHPOS => -1;

my $CVgetCombinClass;

use constant MinLevel => 1;
use constant MaxLevel => 4;

use constant Min2Wt => 0x20;
use constant Min3Wt => 0x02;

use constant Shift4Wt => 0xFFFF;

use constant VCE_TEMPLATE => 'Cn4';

use constant KEY_TEMPLATE => 'n*';

use constant TIE_TEMPLATE => 'N*';

use constant LEVEL_SEP => "\0\0";

use constant CODE_SEP => ';';
	# NOTE: in regex /;/ is used for $jcps!

use constant NON_VAR => 0; # Non-Variable character
use constant VAR     => 1; # Variable character

use constant Hangul_SIni   => 0xAC00;
use constant Hangul_SFin   => 0xD7A3;

my $DefaultRearrange = [ 0x0E40..0x0E44, 0x0EC0..0x0EC4 ];

my $HighestVCE = pack(VCE_TEMPLATE, 0, 0xFFFE, 0x20, 0x5, 0xFFFF);
my $minimalVCE = pack(VCE_TEMPLATE, 0,      1, 0x20, 0x5, 0xFFFE);

sub UCA_Version { "28" }

sub Base_Unicode_Version { "6.3.0" }


sub pack_U {
    return pack('U*', @_);
}

*unpack_U = exists &Unicode::Collate::bootstrap &&
	$] < 5.008 && \&unpackUfor56 && 0x41 == unpackUfor56('A')
    ? \&unpackUfor56 : sub { return unpack('U*', shift(@_).pack('U*')) };


my (%VariableOK);
@VariableOK{ qw/
    blanked  non-ignorable  shifted  shift-trimmed
  / } = (); # keys lowercased

our @ChangeOK = qw/
    alternate backwards level normalization rearrange
    katakana_before_hiragana upper_before_lower ignore_level2
    overrideCJK overrideHangul overrideOut preprocess UCA_Version
    hangul_terminator variable identical highestFFFF minimalFFFE
  /;

our @ChangeNG = qw/
    entry mapping table maxlength contraction
    ignoreChar ignoreName undefChar undefName rewrite
    versionTable alternateTable backwardsTable forwardsTable
    rearrangeTable variableTable
    derivCode normCode rearrangeHash backwardsFlag
    suppress suppressHash
    __useXS /; ### XS only

sub version {
    my $self = shift;
    return $self->{versionTable} || 'unknown';
}

my (%ChangeOK, %ChangeNG);
@ChangeOK{ @ChangeOK } = ();
@ChangeNG{ @ChangeNG } = ();

sub change {
    my $self = shift;
    my %hash = @_;
    my %old;
    if (exists $hash{alternate}) {
	if (exists $hash{variable}) {
	    delete $hash{alternate};
	} else {
	    $hash{variable} = $hash{alternate};
	}
    }
    foreach my $k (keys %hash) {
	if (exists $ChangeOK{$k}) {
	    $old{$k} = $self->{$k};
	    $self->{$k} = $hash{$k};
	} elsif (exists $ChangeNG{$k}) {
	    croak "change of $k via change() is not allowed!";
	}
	# else => ignored
    }
    $self->checkCollator();
    return wantarray ? %old : $self;
}

sub _checkLevel {
    my $level = shift;
    my $key   = shift; # 'level' or 'backwards'
    MinLevel <= $level or croak sprintf
	"Illegal level %d (in value for key '%s') lower than %d.",
	    $level, $key, MinLevel;
    $level <= MaxLevel or croak sprintf
	"Unsupported level %d (in value for key '%s') higher than %d.",
	    $level, $key, MaxLevel;
}

my %DerivCode = (
    8 => \&_derivCE_8,
    9 => \&_derivCE_9,
   11 => \&_derivCE_9, # 11 == 9
   14 => \&_derivCE_14,
   16 => \&_derivCE_14, # 16 == 14
   18 => \&_derivCE_18,
   20 => \&_derivCE_20,
   22 => \&_derivCE_22,
   24 => \&_derivCE_24,
   26 => \&_derivCE_24, # 26 == 24
   28 => \&_derivCE_24, # 28 == 24
);

sub checkCollator {
    my $self = shift;
    _checkLevel($self->{level}, "level");

    $self->{derivCode} = $DerivCode{ $self->{UCA_Version} }
	or croak "Illegal UCA version (passed $self->{UCA_Version}).";

    $self->{variable} ||= $self->{alternate} || $self->{variableTable} ||
				$self->{alternateTable} || 'shifted';
    $self->{variable} = $self->{alternate} = lc($self->{variable});
    exists $VariableOK{ $self->{variable} }
	or croak "$PACKAGE unknown variable parameter name: $self->{variable}";

    if (! defined $self->{backwards}) {
	$self->{backwardsFlag} = 0;
    } elsif (! ref $self->{backwards}) {
	_checkLevel($self->{backwards}, "backwards");
	$self->{backwardsFlag} = 1 << $self->{backwards};
    } else {
	my %level;
	$self->{backwardsFlag} = 0;
	for my $b (@{ $self->{backwards} }) {
	    _checkLevel($b, "backwards");
	    $level{$b} = 1;
	}
	for my $v (sort keys %level) {
	    $self->{backwardsFlag} += 1 << $v;
	}
    }

    defined $self->{rearrange} or $self->{rearrange} = [];
    ref $self->{rearrange}
	or croak "$PACKAGE: list for rearrangement must be store in ARRAYREF";

    # keys of $self->{rearrangeHash} are $self->{rearrange}.
    $self->{rearrangeHash} = undef;

    if (@{ $self->{rearrange} }) {
	@{ $self->{rearrangeHash} }{ @{ $self->{rearrange} } } = ();
    }

    $self->{normCode} = undef;

    if (defined $self->{normalization}) {
	eval { require Unicode::Normalize };
	$@ and croak "Unicode::Normalize is required to normalize strings";

	$CVgetCombinClass ||= \&Unicode::Normalize::getCombinClass;

	if ($self->{normalization} =~ /^(?:NF)D\z/) { # tweak for default
	    $self->{normCode} = \&Unicode::Normalize::NFD;
	}
	elsif ($self->{normalization} ne 'prenormalized') {
	    my $norm = $self->{normalization};
	    $self->{normCode} = sub {
		Unicode::Normalize::normalize($norm, shift);
	    };
	    eval { $self->{normCode}->("") }; # try
	    $@ and croak "$PACKAGE unknown normalization form name: $norm";
	}
    }
    return;
}

sub new
{
    my $class = shift;
    my $self = bless { @_ }, $class;

    if (! exists $self->{table}     && !defined $self->{rewrite} &&
	!defined $self->{undefName} && !defined $self->{ignoreName} &&
	!defined $self->{undefChar} && !defined $self->{ignoreChar}) {
	$self->{__useXS} = \&_fetch_simple;
    } else {
	$self->{__useXS} = undef;
    }

    # keys of $self->{suppressHash} are $self->{suppress}.
    if ($self->{suppress} && @{ $self->{suppress} }) {
	@{ $self->{suppressHash} }{ @{ $self->{suppress} } } = ();
    } # before read_table()

    # If undef is passed explicitly, no file is read.
    $self->{table} = $KeyFile if ! exists $self->{table};
    $self->read_table() if defined $self->{table};

    if ($self->{entry}) {
	while ($self->{entry} =~ /([^\n]+)/g) {
	    $self->parseEntry($1, TRUE);
	}
    }

    $self->{level} ||= MaxLevel;
    $self->{UCA_Version} ||= UCA_Version();

    $self->{overrideHangul} = FALSE
	if ! exists $self->{overrideHangul};
    $self->{overrideCJK} = FALSE
	if ! exists $self->{overrideCJK};
    $self->{normalization} = 'NFD'
	if ! exists $self->{normalization};
    $self->{rearrange} = $self->{rearrangeTable} ||
	($self->{UCA_Version} <= 11 ? $DefaultRearrange : [])
	if ! exists $self->{rearrange};
    $self->{backwards} = $self->{backwardsTable}
	if ! exists $self->{backwards};

    $self->checkCollator();

    return $self;
}

sub parseAtmark {
    my $self = shift;
    my $line = shift; # after s/^\s*\@//

    if ($line =~ /^version\s*(\S*)/) {
	$self->{versionTable} ||= $1;
    }
    elsif ($line =~ /^variable\s+(\S*)/) { # since UTS #10-9
	$self->{variableTable} ||= $1;
    }
    elsif ($line =~ /^alternate\s+(\S*)/) { # till UTS #10-8
	$self->{alternateTable} ||= $1;
    }
    elsif ($line =~ /^backwards\s+(\S*)/) {
	push @{ $self->{backwardsTable} }, $1;
    }
    elsif ($line =~ /^forwards\s+(\S*)/) { # perhaps no use
	push @{ $self->{forwardsTable} }, $1;
    }
    elsif ($line =~ /^rearrange\s+(.*)/) { # (\S*) is NG
	push @{ $self->{rearrangeTable} }, _getHexArray($1);
    }
}

sub read_table {
    my $self = shift;

    if ($self->{__useXS}) {
	my @rest = _fetch_rest(); # complex matter need to parse
	for my $line (@rest) {
	    next if $line =~ /^\s*#/;

	    if ($line =~ s/^\s*\@//) {
		$self->parseAtmark($line);
	    } else {
		$self->parseEntry($line);
	    }
	}
	return;
    }

    my($f, $fh);
    foreach my $d (@INC) {
	$f = File::Spec->catfile($d, @Path, $self->{table});
	last if open($fh, $f);
	$f = undef;
    }
    if (!defined $f) {
	$f = File::Spec->catfile(@Path, $self->{table});
	croak("$PACKAGE: Can't locate $f in \@INC (\@INC contains: @INC)");
    }

    while (my $line = <$fh>) {
	next if $line =~ /^\s*#/;

	if ($line =~ s/^\s*\@//) {
	    $self->parseAtmark($line);
	} else {
	    $self->parseEntry($line);
	}
    }
    close $fh;
}


sub parseEntry
{
    my $self = shift;
    my $line = shift;
    my $tailoring = shift;
    my($name, $entry, @uv, @key);

    if (defined $self->{rewrite}) {
	$line = $self->{rewrite}->($line);
    }

    return if $line !~ /^\s*[0-9A-Fa-f]/;

    # removes comment and gets name
    $name = $1
	if $line =~ s/[#%]\s*(.*)//;
    return if defined $self->{undefName} && $name =~ /$self->{undefName}/;

    # gets element
    my($e, $k) = split /;/, $line;
    croak "Wrong Entry: <charList> must be separated by ';' from <collElement>"
	if ! $k;

    @uv = _getHexArray($e);
    return if !@uv;
    return if @uv > 1 && $self->{suppressHash} && !$tailoring &&
		  exists $self->{suppressHash}{$uv[0]};
    $entry = join(CODE_SEP, @uv); # in JCPS

    if (defined $self->{undefChar} || defined $self->{ignoreChar}) {
	my $ele = pack_U(@uv);

	# regarded as if it were not stored in the table
	return
	    if defined $self->{undefChar} && $ele =~ /$self->{undefChar}/;

	# replaced as completely ignorable
	$k = '[.0000.0000.0000.0000]'
	    if defined $self->{ignoreChar} && $ele =~ /$self->{ignoreChar}/;
    }

    # replaced as completely ignorable
    $k = '[.0000.0000.0000.0000]'
	if defined $self->{ignoreName} && $name =~ /$self->{ignoreName}/;

    my $is_L3_ignorable = TRUE;

    foreach my $arr ($k =~ /\[([^\[\]]+)\]/g) { # SPACEs allowed
	my $var = $arr =~ /\*/; # exactly /^\*/ but be lenient.
	my @wt = _getHexArray($arr);
	push @key, pack(VCE_TEMPLATE, $var, @wt);
	$is_L3_ignorable = FALSE
	    if $wt[0] || $wt[1] || $wt[2];
	# Conformance Test for 3.1.1 and 4.0.0 shows Level 3 ignorable
	# is completely ignorable.
	# For expansion, an entry $is_L3_ignorable
	# if and only if "all" CEs are [.0000.0000.0000].
    }

    $self->{mapping}{$entry} = $is_L3_ignorable ? [] : \@key;

    if (@uv > 1) {
	if (!$self->{maxlength}{$uv[0]} || $self->{maxlength}{$uv[0]} < @uv) {
	    $self->{maxlength}{$uv[0]} = @uv;
	}
    }
    if (@uv > 2) {
	while (@uv) {
	    pop @uv;
	    my $fake_entry = join(CODE_SEP, @uv); # in JCPS
	    $self->{contraction}{$fake_entry} = 1;
	}
    }
}


sub viewSortKey
{
    my $self = shift;
    my $str  = shift;
    $self->visualizeSortKey($self->getSortKey($str));
}


sub process
{
    my $self = shift;
    my $str  = shift;
    my $prep = $self->{preprocess};
    my $norm = $self->{normCode};

    $str = &$prep($str) if ref $prep;
    $str = &$norm($str) if ref $norm;
    return $str;
}

sub splitEnt
{
    my $self = shift;
    my $str  = shift;
    my $wLen = shift; # with Length

    my $map  = $self->{mapping};
    my $max  = $self->{maxlength};
    my $reH  = $self->{rearrangeHash};
    my $vers = $self->{UCA_Version};
    my $ver9 = $vers >= 9 && $vers <= 11;
    my $uXS  = $self->{__useXS}; ### XS only

    my @buf;

    # get array of Unicode code point of string.
    my @src = unpack_U($str);

    # rearrangement:
    # Character positions are not kept if rearranged,
    # then neglected if $wLen is true.
    if ($reH && ! $wLen) {
	for (my $i = 0; $i < @src; $i++) {
	    if (exists $reH->{ $src[$i] } && $i + 1 < @src) {
		($src[$i], $src[$i+1]) = ($src[$i+1], $src[$i]);
		$i++;
	    }
	}
    }

    # remove a code point marked as a completely ignorable.
    for (my $i = 0; $i < @src; $i++) {
	if ($vers <= 20 && _isIllegal($src[$i])) {
	    $src[$i] = undef;
	} elsif ($ver9) {
	    $src[$i] = undef if $map->{ $src[$i] }
			   ? @{ $map->{ $src[$i] } } == 0
			   : $uXS && _ignorable_simple($src[$i]); ### XS only
	}
    }

    for (my $i = 0; $i < @src; $i++) {
	my $jcps = $src[$i];

	# skip removed code point
	if (! defined $jcps) {
	    if ($wLen && @buf) {
		$buf[-1][2] = $i + 1;
	    }
	    next;
	}

	my $i_orig = $i;

	# find contraction
	if ($max->{$jcps}) {
	    my $temp_jcps = $jcps;
	    my $jcpsLen = 1;
	    my $maxLen = $max->{$jcps};

	    for (my $p = $i + 1; $jcpsLen < $maxLen && $p < @src; $p++) {
		next if ! defined $src[$p];
		$temp_jcps .= CODE_SEP . $src[$p];
		$jcpsLen++;
		if ($map->{$temp_jcps}) {
		    $jcps = $temp_jcps;
		    $i = $p;
		}
	    }

	# discontiguous contraction with Combining Char (cf. UTS#10, S2.1).
	# This process requires Unicode::Normalize.
	# If "normalization" is undef, here should be skipped *always*
	# (in spite of bool value of $CVgetCombinClass),
	# since canonical ordering cannot be expected.
	# Blocked combining character should not be contracted.

	    # $self->{normCode} is false in the case of "prenormalized".
	    if ($self->{normalization}) {
		my $cont = $self->{contraction};
		my $preCC = 0;
		my $preCC_uc = 0;
		my $jcps_uc = $jcps;
		my(@out, @out_uc);

		for (my $p = $i + 1; $p < @src; $p++) {
		    next if ! defined $src[$p];
		    my $curCC = $CVgetCombinClass->($src[$p]);
		    last unless $curCC;
		    my $tail = CODE_SEP . $src[$p];

		    if ($preCC_uc != $curCC && ($map->{$jcps_uc.$tail} ||
					       $cont->{$jcps_uc.$tail})) {
			$jcps_uc .= $tail;
			push @out_uc, $p;
		    } else {
			$preCC_uc = $curCC;
		    }

		    if ($preCC != $curCC && $map->{$jcps.$tail}) {
			$jcps .= $tail;
			push @out, $p;
		    } else {
			$preCC = $curCC;
		    }
		}

		if ($map->{$jcps_uc}) {
		    $jcps = $jcps_uc;
		    $src[$_] = undef for @out_uc;
		} else {
		    $src[$_] = undef for @out;
		}
	    }
	}

	# skip completely ignorable
	if ($map->{$jcps} ? @{ $map->{$jcps} } == 0 :
	    $uXS && $jcps !~ /;/ && _ignorable_simple($jcps)) { ### XS only
	    if ($wLen && @buf) {
		$buf[-1][2] = $i + 1;
	    }
	    next;
	}

	push @buf, $wLen ? [$jcps, $i_orig, $i + 1] : $jcps;
    }
    return \@buf;
}

sub _pack_override ($$$) {
    my $r = shift;
    my $u = shift;
    my $der = shift;

    if (ref $r) {
	return pack(VCE_TEMPLATE, NON_VAR, @$r);
    } elsif (defined $r) {
	return pack(VCE_TEMPLATE, NON_VAR, $r, Min2Wt, Min3Wt, $u);
    } else {
	$u = 0xFFFD if 0x10FFFF < $u;
	return $der->($u);
    }
}

sub getWt
{
    my $self = shift;
    my $u    = shift;
    my $map  = $self->{mapping};
    my $der  = $self->{derivCode};
    my $out  = $self->{overrideOut};
    my $uXS  = $self->{__useXS}; ### XS only

    return if !defined $u;
    return $self->varCE($HighestVCE) if $u eq 0xFFFF && $self->{highestFFFF};
    return $self->varCE($minimalVCE) if $u eq 0xFFFE && $self->{minimalFFFE};
    $u = 0xFFFD if $u !~ /;/ && 0x10FFFF < $u && !$out;

    my @ce;
    if ($map->{$u}) {
	@ce = @{ $map->{$u} }; # $u may be a contraction
    } elsif ($uXS && _exists_simple($u)) {
	@ce = _fetch_simple($u);
    } elsif (Hangul_SIni <= $u && $u <= Hangul_SFin) {
	my $hang = $self->{overrideHangul};
	if ($hang) {
	    @ce = map _pack_override($_, $u, $der), $hang->($u);
	} elsif (!defined $hang) {
	    @ce = $der->($u);
	} else {
	    my $max  = $self->{maxlength};
	    my @decH = _decompHangul($u);

	    if (@decH == 2) {
		my $contract = join(CODE_SEP, @decH);
		@decH = ($contract) if $map->{$contract};
	    } else { # must be <@decH == 3>
		if ($max->{$decH[0]}) {
		    my $contract = join(CODE_SEP, @decH);
		    if ($map->{$contract}) {
			@decH = ($contract);
		    } else {
			$contract = join(CODE_SEP, @decH[0,1]);
			$map->{$contract} and @decH = ($contract, $decH[2]);
		    }
		    # even if V's ignorable, LT contraction is not supported.
		    # If such a situation were required, NFD should be used.
		}
		if (@decH == 3 && $max->{$decH[1]}) {
		    my $contract = join(CODE_SEP, @decH[1,2]);
		    $map->{$contract} and @decH = ($decH[0], $contract);
		}
	    }

	    @ce = map({
		    $map->{$_} ? @{ $map->{$_} } :
		$uXS && _exists_simple($_) ? _fetch_simple($_) : ### XS only
		    $der->($_);
		} @decH);
	}
    } elsif ($out && 0x10FFFF < $u) {
	@ce = map _pack_override($_, $u, $der), $out->($u);
    } else {
	my $cjk  = $self->{overrideCJK};
	my $vers = $self->{UCA_Version};
	if ($cjk && _isUIdeo($u, $vers)) {
	    @ce = map _pack_override($_, $u, $der), $cjk->($u);
	} elsif ($vers == 8 && defined $cjk && _isUIdeo($u, 0)) {
	    @ce = _uideoCE_8($u);
	} else {
	    @ce = $der->($u);
	}
    }
    return map $self->varCE($_), @ce;
}


sub getSortKey
{
    my $self = shift;
    my $orig = shift;
    my $str  = $self->process($orig);
    my $rEnt = $self->splitEnt($str); # get an arrayref of JCPS
    my $vers = $self->{UCA_Version};
    my $term = $self->{hangul_terminator};
    my $lev  = $self->{level};
    my $iden = $self->{identical};

    my @buf; # weight arrays
    if ($term) {
	my $preHST = '';
	my $termCE = $self->varCE(pack(VCE_TEMPLATE, NON_VAR, $term, 0,0,0));
	foreach my $jcps (@$rEnt) {
	    # weird things like VL, TL-contraction are not considered!
	    my $curHST = join '', map getHST($_, $vers), split /;/, $jcps;
	    if ($preHST && !$curHST || # hangul before non-hangul
		$preHST =~ /L\z/ && $curHST =~ /^T/ ||
		$preHST =~ /V\z/ && $curHST =~ /^L/ ||
		$preHST =~ /T\z/ && $curHST =~ /^[LV]/) {
		push @buf, $termCE;
	    }
	    $preHST = $curHST;
	    push @buf, $self->getWt($jcps);
	}
	push @buf, $termCE if $preHST; # end at hangul
    } else {
	foreach my $jcps (@$rEnt) {
	    push @buf, $self->getWt($jcps);
	}
    }

    my $rkey = $self->mk_SortKey(\@buf); ### XS only

    if ($iden || $vers >= 26 && $lev == MaxLevel) {
	$rkey .= LEVEL_SEP;
	$rkey .= pack(TIE_TEMPLATE, unpack_U($str)) if $iden;
    }
    return $rkey;
}


sub cmp { $_[0]->getSortKey($_[1]) cmp $_[0]->getSortKey($_[2]) }
sub eq  { $_[0]->getSortKey($_[1]) eq  $_[0]->getSortKey($_[2]) }
sub ne  { $_[0]->getSortKey($_[1]) ne  $_[0]->getSortKey($_[2]) }
sub lt  { $_[0]->getSortKey($_[1]) lt  $_[0]->getSortKey($_[2]) }
sub le  { $_[0]->getSortKey($_[1]) le  $_[0]->getSortKey($_[2]) }
sub gt  { $_[0]->getSortKey($_[1]) gt  $_[0]->getSortKey($_[2]) }
sub ge  { $_[0]->getSortKey($_[1]) ge  $_[0]->getSortKey($_[2]) }

sub sort {
    my $obj = shift;
    return
	map { $_->[1] }
	    sort{ $a->[0] cmp $b->[0] }
		map [ $obj->getSortKey($_), $_ ], @_;
}


sub _nonIgnorAtLevel($$)
{
    my $wt = shift;
    return if ! defined $wt;
    my $lv = shift;
    return grep($wt->[$_-1] != 0, MinLevel..$lv) ? TRUE : FALSE;
}

sub _eqArray($$$)
{
    my $source = shift;
    my $substr = shift;
    my $lev = shift;

    for my $g (0..@$substr-1){
	# Do the $g'th graphemes have the same number of AV weights?
	return if @{ $source->[$g] } != @{ $substr->[$g] };

	for my $w (0..@{ $substr->[$g] }-1) {
	    for my $v (0..$lev-1) {
		return if $source->[$g][$w][$v] != $substr->[$g][$w][$v];
	    }
	}
    }
    return 1;
}

sub index
{
    my $self = shift;
    $self->{preprocess} and
	croak "Don't use Preprocess with index(), match(), etc.";
    $self->{normCode} and
	croak "Don't use Normalization with index(), match(), etc.";

    my $str  = shift;
    my $len  = length($str);
    my $sub  = shift;
    my $subE = $self->splitEnt($sub);
    my $pos  = @_ ? shift : 0;
       $pos  = 0 if $pos < 0;
    my $glob = shift;

    my $lev  = $self->{level};
    my $v2i  = $self->{UCA_Version} >= 9 &&
		$self->{variable} ne 'non-ignorable';

    if (! @$subE) {
	my $temp = $pos <= 0 ? 0 : $len <= $pos ? $len : $pos;
	return $glob
	    ? map([$_, 0], $temp..$len)
	    : wantarray ? ($temp,0) : $temp;
    }
    $len < $pos
	and return wantarray ? () : NOMATCHPOS;
    my $strE = $self->splitEnt($pos ? substr($str, $pos) : $str, TRUE);
    @$strE
	or return wantarray ? () : NOMATCHPOS;

    my(@strWt, @iniPos, @finPos, @subWt, @g_ret);

    my $last_is_variable;
    for my $vwt (map $self->getWt($_), @$subE) {
	my($var, @wt) = unpack(VCE_TEMPLATE, $vwt);
	my $to_be_pushed = _nonIgnorAtLevel(\@wt,$lev);

	# "Ignorable (L1, L2) after Variable" since track. v. 9
	if ($v2i) {
	    if ($var) {
		$last_is_variable = TRUE;
	    }
	    elsif (!$wt[0]) { # ignorable
		$to_be_pushed = FALSE if $last_is_variable;
	    }
	    else {
		$last_is_variable = FALSE;
	    }
	}

	if (@subWt && !$var && !$wt[0]) {
	    push @{ $subWt[-1] }, \@wt if $to_be_pushed;
	} elsif ($to_be_pushed) {
	    push @subWt, [ \@wt ];
	}
	# else ===> skipped
    }

    my $count = 0;
    my $end = @$strE - 1;

    $last_is_variable = FALSE; # reuse
    for (my $i = 0; $i <= $end; ) { # no $i++
	my $found_base = 0;

	# fetch a grapheme
	while ($i <= $end && $found_base == 0) {
	    for my $vwt ($self->getWt($strE->[$i][0])) {
		my($var, @wt) = unpack(VCE_TEMPLATE, $vwt);
		my $to_be_pushed = _nonIgnorAtLevel(\@wt,$lev);

		# "Ignorable (L1, L2) after Variable" since track. v. 9
		if ($v2i) {
		    if ($var) {
			$last_is_variable = TRUE;
		    }
		    elsif (!$wt[0]) { # ignorable
			$to_be_pushed = FALSE if $last_is_variable;
		    }
		    else {
			$last_is_variable = FALSE;
		    }
		}

		if (@strWt && !$var && !$wt[0]) {
		    push @{ $strWt[-1] }, \@wt if $to_be_pushed;
		    $finPos[-1] = $strE->[$i][2];
		} elsif ($to_be_pushed) {
		    push @strWt, [ \@wt ];
		    push @iniPos, $found_base ? NOMATCHPOS : $strE->[$i][1];
		    $finPos[-1] = NOMATCHPOS if $found_base;
		    push @finPos, $strE->[$i][2];
		    $found_base++;
		}
		# else ===> no-op
	    }
	    $i++;
	}

	# try to match
	while ( @strWt > @subWt || (@strWt == @subWt && $i > $end) ) {
	    if ($iniPos[0] != NOMATCHPOS &&
		    $finPos[$#subWt] != NOMATCHPOS &&
			_eqArray(\@strWt, \@subWt, $lev)) {
		my $temp = $iniPos[0] + $pos;

		if ($glob) {
		    push @g_ret, [$temp, $finPos[$#subWt] - $iniPos[0]];
		    splice @strWt,  0, $#subWt;
		    splice @iniPos, 0, $#subWt;
		    splice @finPos, 0, $#subWt;
		}
		else {
		    return wantarray
			? ($temp, $finPos[$#subWt] - $iniPos[0])
			:  $temp;
		}
	    }
	    shift @strWt;
	    shift @iniPos;
	    shift @finPos;
	}
    }

    return $glob
	? @g_ret
	: wantarray ? () : NOMATCHPOS;
}

sub match
{
    my $self = shift;
    if (my($pos,$len) = $self->index($_[0], $_[1])) {
	my $temp = substr($_[0], $pos, $len);
	return wantarray ? $temp : \$temp;
	# An lvalue ref \substr should be avoided,
	# since its value is affected by modification of its referent.
    }
    else {
	return;
    }
}

sub gmatch
{
    my $self = shift;
    my $str  = shift;
    my $sub  = shift;
    return map substr($str, $_->[0], $_->[1]),
		$self->index($str, $sub, 0, 'g');
}

sub subst
{
    my $self = shift;
    my $code = ref $_[2] eq 'CODE' ? $_[2] : FALSE;

    if (my($pos,$len) = $self->index($_[0], $_[1])) {
	if ($code) {
	    my $mat = substr($_[0], $pos, $len);
	    substr($_[0], $pos, $len, $code->($mat));
	} else {
	    substr($_[0], $pos, $len, $_[2]);
	}
	return TRUE;
    }
    else {
	return FALSE;
    }
}

sub gsubst
{
    my $self = shift;
    my $code = ref $_[2] eq 'CODE' ? $_[2] : FALSE;
    my $cnt = 0;

    # Replacement is carried out from the end, then use reverse.
    for my $pos_len (reverse $self->index($_[0], $_[1], 0, 'g')) {
	if ($code) {
	    my $mat = substr($_[0], $pos_len->[0], $pos_len->[1]);
	    substr($_[0], $pos_len->[0], $pos_len->[1], $code->($mat));
	} else {
	    substr($_[0], $pos_len->[0], $pos_len->[1], $_[2]);
	}
	$cnt++;
    }
    return $cnt;
}

1;
__END__

