package Unicode::UCD;

use strict;
use warnings;
no warnings 'surrogate';    # surrogates can be inputs to this
use charnames ();

our $VERSION = '0.58';

require Exporter;

our @ISA = qw(Exporter);

our @EXPORT_OK = qw(charinfo
		    charblock charscript
		    charblocks charscripts
		    charinrange
		    general_categories bidi_types
		    compexcl
		    casefold all_casefolds casespec
		    namedseq
                    num
                    prop_aliases
                    prop_value_aliases
                    prop_invlist
                    prop_invmap
                    search_invlist
                    MAX_CP
                );

use Carp;

sub IS_ASCII_PLATFORM { ord("A") == 65 }


my $BLOCKSFH;
my $VERSIONFH;
my $CASEFOLDFH;
my $CASESPECFH;
my $NAMEDSEQFH;
my $v_unicode_version;  # v-string.

sub openunicode {
    my ($rfh, @path) = @_;
    my $f;
    unless (defined $$rfh) {
	for my $d (@INC) {
	    use File::Spec;
	    $f = File::Spec->catfile($d, "unicore", @path);
	    last if open($$rfh, $f);
	    undef $f;
	}
	croak __PACKAGE__, ": failed to find ",
              File::Spec->catfile(@path), " in @INC"
	    unless defined $f;
    }
    return $f;
}

sub _dclone ($) {   # Use Storable::dclone if available; otherwise emulate it.

    use if defined &DynaLoader::boot_DynaLoader, Storable => qw(dclone);

    return dclone(shift) if defined &dclone;

    my $arg = shift;
    my $type = ref $arg;
    return $arg unless $type;   # No deep cloning needed for scalars

    if ($type eq 'ARRAY') {
        my @return;
        foreach my $element (@$arg) {
            push @return, &_dclone($element);
        }
        return \@return;
    }
    elsif ($type eq 'HASH') {
        my %return;
        foreach my $key (keys %$arg) {
            $return{$key} = &_dclone($arg->{$key});
        }
        return \%return;
    }
    else {
        croak "_dclone can't handle " . $type;
    }
}


sub _getcode {
    my $arg = shift;

    if ($arg =~ /^[1-9]\d*$/) {
	return $arg;
    }
    elsif ($arg =~ /^(?:0[xX])?([[:xdigit:]]+)$/) {
	return CORE::hex($1);
    }
    elsif ($arg =~ /^[Uu]\+([[:xdigit:]]+)$/) { # Is of form U+0000, means
                                                # wants the Unicode code
                                                # point, not the native one
        my $decimal = CORE::hex($1);
        return $decimal if IS_ASCII_PLATFORM;
        return utf8::unicode_to_native($decimal);
    }

    return;
}

my %real_to_rational;

my @BIDIS;
my @CATEGORIES;
my @DECOMPOSITIONS;
my @NUMERIC_TYPES;
my %SIMPLE_LOWER;
my %SIMPLE_TITLE;
my %SIMPLE_UPPER;
my %UNICODE_1_NAMES;
my %ISO_COMMENT;

sub charinfo {

    # This function has traditionally mimicked what is in UnicodeData.txt,
    # warts and all.  This is a re-write that avoids UnicodeData.txt so that
    # it can be removed to save disk space.  Instead, this assembles
    # information gotten by other methods that get data from various other
    # files.  It uses charnames to get the character name; and various
    # mktables tables.

    use feature 'unicode_strings';

    # Will fail if called under minitest
    use if defined &DynaLoader::boot_DynaLoader, "Unicode::Normalize" => qw(getCombinClass NFD);

    my $arg  = shift;
    my $code = _getcode($arg);
    croak __PACKAGE__, "::charinfo: unknown code '$arg'" unless defined $code;

    # Non-unicode implies undef.
    return if $code > 0x10FFFF;

    my %prop;
    my $char = chr($code);

    @CATEGORIES =_read_table("To/Gc.pl") unless @CATEGORIES;
    $prop{'category'} = _search(\@CATEGORIES, 0, $#CATEGORIES, $code)
                        // $utf8::SwashInfo{'ToGc'}{'missing'};

    return if $prop{'category'} eq 'Cn';    # Unassigned code points are undef

    $prop{'code'} = sprintf "%04X", $code;
    $prop{'name'} = ($char =~ /\p{Cntrl}/) ? '<control>'
                                           : (charnames::viacode($code) // "");

    $prop{'combining'} = getCombinClass($code);

    @BIDIS =_read_table("To/Bc.pl") unless @BIDIS;
    $prop{'bidi'} = _search(\@BIDIS, 0, $#BIDIS, $code)
                    // $utf8::SwashInfo{'ToBc'}{'missing'};

    # For most code points, we can just read in "unicore/Decomposition.pl", as
    # its contents are exactly what should be output.  But that file doesn't
    # contain the data for the Hangul syllable decompositions, which can be
    # algorithmically computed, and NFD() does that, so we call NFD() for
    # those.  We can't use NFD() for everything, as it does a complete
    # recursive decomposition, and what this function has always done is to
    # return what's in UnicodeData.txt which doesn't show that recursiveness.
    # Fortunately, the NFD() of the Hanguls doesn't have any recursion
    # issues.
    # Having no decomposition implies an empty field; otherwise, all but
    # "Canonical" imply a compatible decomposition, and the type is prefixed
    # to that, as it is in UnicodeData.txt
    UnicodeVersion() unless defined $v_unicode_version;
    if ($v_unicode_version ge v2.0.0 && $char =~ /\p{Block=Hangul_Syllables}/) {
        # The code points of the decomposition are output in standard Unicode
        # hex format, separated by blanks.
        $prop{'decomposition'} = join " ", map { sprintf("%04X", $_)}
                                           unpack "U*", NFD($char);
    }
    else {
        @DECOMPOSITIONS = _read_table("Decomposition.pl")
                          unless @DECOMPOSITIONS;
        $prop{'decomposition'} = _search(\@DECOMPOSITIONS, 0, $#DECOMPOSITIONS,
                                                                $code) // "";
    }

    # Can use num() to get the numeric values, if any.
    if (! defined (my $value = num($char))) {
        $prop{'decimal'} = $prop{'digit'} = $prop{'numeric'} = "";
    }
    else {
        if ($char =~ /\d/) {
            $prop{'decimal'} = $prop{'digit'} = $prop{'numeric'} = $value;
        }
        else {

            # For non-decimal-digits, we have to read in the Numeric type
            # to distinguish them.  It is not just a matter of integer vs.
            # rational, as some whole number values are not considered digits,
            # e.g., TAMIL NUMBER TEN.
            $prop{'decimal'} = "";

            @NUMERIC_TYPES =_read_table("To/Nt.pl") unless @NUMERIC_TYPES;
            if ((_search(\@NUMERIC_TYPES, 0, $#NUMERIC_TYPES, $code) // "")
                eq 'Digit')
            {
                $prop{'digit'} = $prop{'numeric'} = $value;
            }
            else {
                $prop{'digit'} = "";
                $prop{'numeric'} = $real_to_rational{$value} // $value;
            }
        }
    }

    $prop{'mirrored'} = ($char =~ /\p{Bidi_Mirrored}/) ? 'Y' : 'N';

    %UNICODE_1_NAMES =_read_table("To/Na1.pl", "use_hash") unless %UNICODE_1_NAMES;
    $prop{'unicode10'} = $UNICODE_1_NAMES{$code} // "";

    UnicodeVersion() unless defined $v_unicode_version;
    if ($v_unicode_version ge v6.0.0) {
        $prop{'comment'} = "";
    }
    else {
        %ISO_COMMENT = _read_table("To/Isc.pl", "use_hash") unless %ISO_COMMENT;
        $prop{'comment'} = (defined $ISO_COMMENT{$code})
                           ? $ISO_COMMENT{$code}
                           : "";
    }

    %SIMPLE_UPPER = _read_table("To/Uc.pl", "use_hash") unless %SIMPLE_UPPER;
    $prop{'upper'} = (defined $SIMPLE_UPPER{$code})
                     ? sprintf("%04X", $SIMPLE_UPPER{$code})
                     : "";

    %SIMPLE_LOWER = _read_table("To/Lc.pl", "use_hash") unless %SIMPLE_LOWER;
    $prop{'lower'} = (defined $SIMPLE_LOWER{$code})
                     ? sprintf("%04X", $SIMPLE_LOWER{$code})
                     : "";

    %SIMPLE_TITLE = _read_table("To/Tc.pl", "use_hash") unless %SIMPLE_TITLE;
    $prop{'title'} = (defined $SIMPLE_TITLE{$code})
                     ? sprintf("%04X", $SIMPLE_TITLE{$code})
                     : "";

    $prop{block}  = charblock($code);
    $prop{script} = charscript($code);
    return \%prop;
}

sub _search { # Binary search in a [[lo,hi,prop],[...],...] table.
    my ($table, $lo, $hi, $code) = @_;

    return if $lo > $hi;

    my $mid = int(($lo+$hi) / 2);

    if ($table->[$mid]->[0] < $code) {
	if ($table->[$mid]->[1] >= $code) {
	    return $table->[$mid]->[2];
	} else {
	    _search($table, $mid + 1, $hi, $code);
	}
    } elsif ($table->[$mid]->[0] > $code) {
	_search($table, $lo, $mid - 1, $code);
    } else {
	return $table->[$mid]->[2];
    }
}

sub _read_table ($;$) {

    # Returns the contents of the mktables generated table file located at $1
    # in the form of either an array of arrays or a hash, depending on if the
    # optional second parameter is true (for hash return) or not.  In the case
    # of a hash return, each key is a code point, and its corresponding value
    # is what the table gives as the code point's corresponding value.  In the
    # case of an array return, each outer array denotes a range with [0] the
    # start point of that range; [1] the end point; and [2] the value that
    # every code point in the range has.  The hash return is useful for fast
    # lookup when the table contains only single code point ranges.  The array
    # return takes much less memory when there are large ranges.
    #
    # This function has the side effect of setting
    # $utf8::SwashInfo{$property}{'format'} to be the mktables format of the
    #                                       table; and
    # $utf8::SwashInfo{$property}{'missing'} to be the value for all entries
    #                                        not listed in the table.
    # where $property is the Unicode property name, preceded by 'To' for map
    # properties., e.g., 'ToSc'.
    #
    # Table entries look like one of:
    # 0000	0040	Common	# [65]
    # 00AA		Latin

    my $table = shift;
    my $return_hash = shift;
    $return_hash = 0 unless defined $return_hash;
    my @return;
    my %return;
    local $_;
    my $list = do "unicore/$table";

    # Look up if this property requires adjustments, which we do below if it
    # does.
    require "unicore/Heavy.pl";
    my $property = $table =~ s/\.pl//r;
    $property = $utf8::file_to_swash_name{$property};
    my $to_adjust = defined $property
                    && $utf8::SwashInfo{$property}{'format'} =~ / ^ a /x;

    for (split /^/m, $list) {
        my ($start, $end, $value) = / ^ (.+?) \t (.*?) \t (.+?)
                                        \s* ( \# .* )?  # Optional comment
                                        $ /x;
        my $decimal_start = hex $start;
        my $decimal_end = ($end eq "") ? $decimal_start : hex $end;
        $value = hex $value if $to_adjust
                               && $utf8::SwashInfo{$property}{'format'} eq 'ax';
        if ($return_hash) {
            foreach my $i ($decimal_start .. $decimal_end) {
                $return{$i} = ($to_adjust)
                              ? $value + $i - $decimal_start
                              : $value;
            }
        }
        elsif (! $to_adjust
               && @return
               && $return[-1][1] == $decimal_start - 1
               && $return[-1][2] eq $value)
        {
            # If this is merely extending the previous range, do just that.
            $return[-1]->[1] = $decimal_end;
        }
        else {
            push @return, [ $decimal_start, $decimal_end, $value ];
        }
    }
    return ($return_hash) ? %return : @return;
}

sub charinrange {
    my ($range, $arg) = @_;
    my $code = _getcode($arg);
    croak __PACKAGE__, "::charinrange: unknown code '$arg'"
	unless defined $code;
    _search($range, 0, $#$range, $code);
}


my @BLOCKS;
my %BLOCKS;

sub _charblocks {

    # Can't read from the mktables table because it loses the hyphens in the
    # original.
    unless (@BLOCKS) {
        UnicodeVersion() unless defined $v_unicode_version;
        if ($v_unicode_version lt v2.0.0) {
            my $subrange = [ 0, 0x10FFFF, 'No_Block' ];
            push @BLOCKS, $subrange;
            push @{$BLOCKS{'No_Block'}}, $subrange;
        }
        elsif (openunicode(\$BLOCKSFH, "Blocks.txt")) {
	    local $_;
	    local $/ = "\n";
	    while (<$BLOCKSFH>) {
		if (/^([0-9A-F]+)\.\.([0-9A-F]+);\s+(.+)/) {
		    my ($lo, $hi) = (hex($1), hex($2));
		    my $subrange = [ $lo, $hi, $3 ];
		    push @BLOCKS, $subrange;
		    push @{$BLOCKS{$3}}, $subrange;
		}
	    }
	    close($BLOCKSFH);
            if (! IS_ASCII_PLATFORM) {
                # The first two blocks, through 0xFF, are wrong on EBCDIC
                # platforms.

                my @new_blocks = _read_table("To/Blk.pl");

                # Get rid of the first two ranges in the Unicode version, and
                # replace them with the ones computed by mktables.
                shift @BLOCKS;
                shift @BLOCKS;
                delete $BLOCKS{'Basic Latin'};
                delete $BLOCKS{'Latin-1 Supplement'};

                # But there are multiple entries in the computed versions, and
                # we change their names to (which we know) to be the old-style
                # ones.
                for my $i (0.. @new_blocks - 1) {
                    if ($new_blocks[$i][2] =~ s/Basic_Latin/Basic Latin/
                        or $new_blocks[$i][2] =~
                                    s/Latin_1_Supplement/Latin-1 Supplement/)
                    {
                        push @{$BLOCKS{$new_blocks[$i][2]}}, $new_blocks[$i];
                    }
                    else {
                        splice @new_blocks, $i;
                        last;
                    }
                }
                unshift @BLOCKS, @new_blocks;
            }
	}
    }
}

sub charblock {
    my $arg = shift;

    _charblocks() unless @BLOCKS;

    my $code = _getcode($arg);

    if (defined $code) {
	my $result = _search(\@BLOCKS, 0, $#BLOCKS, $code);
        return $result if defined $result;
        return 'No_Block';
    }
    elsif (exists $BLOCKS{$arg}) {
        return _dclone $BLOCKS{$arg};
    }
}


my @SCRIPTS;
my %SCRIPTS;

sub _charscripts {
    unless (@SCRIPTS) {
        UnicodeVersion() unless defined $v_unicode_version;
        if ($v_unicode_version lt v3.1.0) {
            push @SCRIPTS, [ 0, 0x10FFFF, 'Unknown' ];
        }
        else {
            @SCRIPTS =_read_table("To/Sc.pl");
        }
    }
    foreach my $entry (@SCRIPTS) {
        $entry->[2] =~ s/(_\w)/\L$1/g;  # Preserve old-style casing
        push @{$SCRIPTS{$entry->[2]}}, $entry;
    }
}

sub charscript {
    my $arg = shift;

    _charscripts() unless @SCRIPTS;

    my $code = _getcode($arg);

    if (defined $code) {
	my $result = _search(\@SCRIPTS, 0, $#SCRIPTS, $code);
        return $result if defined $result;
        return $utf8::SwashInfo{'ToSc'}{'missing'};
    } elsif (exists $SCRIPTS{$arg}) {
        return _dclone $SCRIPTS{$arg};
    }

    return;
}


sub charblocks {
    _charblocks() unless %BLOCKS;
    return _dclone \%BLOCKS;
}


sub charscripts {
    _charscripts() unless %SCRIPTS;
    return _dclone \%SCRIPTS;
}


my %GENERAL_CATEGORIES =
 (
    'L'  =>         'Letter',
    'LC' =>         'CasedLetter',
    'Lu' =>         'UppercaseLetter',
    'Ll' =>         'LowercaseLetter',
    'Lt' =>         'TitlecaseLetter',
    'Lm' =>         'ModifierLetter',
    'Lo' =>         'OtherLetter',
    'M'  =>         'Mark',
    'Mn' =>         'NonspacingMark',
    'Mc' =>         'SpacingMark',
    'Me' =>         'EnclosingMark',
    'N'  =>         'Number',
    'Nd' =>         'DecimalNumber',
    'Nl' =>         'LetterNumber',
    'No' =>         'OtherNumber',
    'P'  =>         'Punctuation',
    'Pc' =>         'ConnectorPunctuation',
    'Pd' =>         'DashPunctuation',
    'Ps' =>         'OpenPunctuation',
    'Pe' =>         'ClosePunctuation',
    'Pi' =>         'InitialPunctuation',
    'Pf' =>         'FinalPunctuation',
    'Po' =>         'OtherPunctuation',
    'S'  =>         'Symbol',
    'Sm' =>         'MathSymbol',
    'Sc' =>         'CurrencySymbol',
    'Sk' =>         'ModifierSymbol',
    'So' =>         'OtherSymbol',
    'Z'  =>         'Separator',
    'Zs' =>         'SpaceSeparator',
    'Zl' =>         'LineSeparator',
    'Zp' =>         'ParagraphSeparator',
    'C'  =>         'Other',
    'Cc' =>         'Control',
    'Cf' =>         'Format',
    'Cs' =>         'Surrogate',
    'Co' =>         'PrivateUse',
    'Cn' =>         'Unassigned',
 );

sub general_categories {
    return _dclone \%GENERAL_CATEGORIES;
}


my %BIDI_TYPES =
 (
   'L'   => 'Left-to-Right',
   'LRE' => 'Left-to-Right Embedding',
   'LRO' => 'Left-to-Right Override',
   'R'   => 'Right-to-Left',
   'AL'  => 'Right-to-Left Arabic',
   'RLE' => 'Right-to-Left Embedding',
   'RLO' => 'Right-to-Left Override',
   'PDF' => 'Pop Directional Format',
   'EN'  => 'European Number',
   'ES'  => 'European Number Separator',
   'ET'  => 'European Number Terminator',
   'AN'  => 'Arabic Number',
   'CS'  => 'Common Number Separator',
   'NSM' => 'Non-Spacing Mark',
   'BN'  => 'Boundary Neutral',
   'B'   => 'Paragraph Separator',
   'S'   => 'Segment Separator',
   'WS'  => 'Whitespace',
   'ON'  => 'Other Neutrals',
 ); 


sub bidi_types {
    return _dclone \%BIDI_TYPES;
}


sub compexcl {
    my $arg  = shift;
    my $code = _getcode($arg);
    croak __PACKAGE__, "::compexcl: unknown code '$arg'"
	unless defined $code;

    UnicodeVersion() unless defined $v_unicode_version;
    return if $v_unicode_version lt v3.0.0;

    no warnings "non_unicode";     # So works on non-Unicode code points
    return chr($code) =~ /\p{Composition_Exclusion}/;
}


my %CASEFOLD;

sub _casefold {
    unless (%CASEFOLD) {   # Populate the hash
        my ($full_invlist_ref, $full_invmap_ref, undef, $default)
                                                = prop_invmap('Case_Folding');

        # Use the recipe given in the prop_invmap() pod to convert the
        # inversion map into the hash.
        for my $i (0 .. @$full_invlist_ref - 1 - 1) {
            next if $full_invmap_ref->[$i] == $default;
            my $adjust = -1;
            for my $j ($full_invlist_ref->[$i] .. $full_invlist_ref->[$i+1] -1) {
                $adjust++;
                if (! ref $full_invmap_ref->[$i]) {

                    # This is a single character mapping
                    $CASEFOLD{$j}{'status'} = 'C';
                    $CASEFOLD{$j}{'simple'}
                        = $CASEFOLD{$j}{'full'}
                        = $CASEFOLD{$j}{'mapping'}
                        = sprintf("%04X", $full_invmap_ref->[$i] + $adjust);
                    $CASEFOLD{$j}{'code'} = sprintf("%04X", $j);
                    $CASEFOLD{$j}{'turkic'} = "";
                }
                else {  # prop_invmap ensures that $adjust is 0 for a ref
                    $CASEFOLD{$j}{'status'} = 'F';
                    $CASEFOLD{$j}{'full'}
                    = $CASEFOLD{$j}{'mapping'}
                    = join " ", map { sprintf "%04X", $_ }
                                                    @{$full_invmap_ref->[$i]};
                    $CASEFOLD{$j}{'simple'} = "";
                    $CASEFOLD{$j}{'code'} = sprintf("%04X", $j);
                    $CASEFOLD{$j}{'turkic'} = "";
                }
            }
        }

        # We have filled in the full mappings above, assuming there were no
        # simple ones for the ones with multi-character maps.  Now, we find
        # and fix the cases where that assumption was false.
        (my ($simple_invlist_ref, $simple_invmap_ref, undef), $default)
                                        = prop_invmap('Simple_Case_Folding');
        for my $i (0 .. @$simple_invlist_ref - 1 - 1) {
            next if $simple_invmap_ref->[$i] == $default;
            my $adjust = -1;
            for my $j ($simple_invlist_ref->[$i]
                       .. $simple_invlist_ref->[$i+1] -1)
            {
                $adjust++;
                next if $CASEFOLD{$j}{'status'} eq 'C';
                $CASEFOLD{$j}{'status'} = 'S';
                $CASEFOLD{$j}{'simple'}
                    = $CASEFOLD{$j}{'mapping'}
                    = sprintf("%04X", $simple_invmap_ref->[$i] + $adjust);
                $CASEFOLD{$j}{'code'} = sprintf("%04X", $j);
                $CASEFOLD{$j}{'turkic'} = "";
            }
        }

        # We hard-code in the turkish rules
        UnicodeVersion() unless defined $v_unicode_version;
        if ($v_unicode_version ge v3.2.0) {

            # These two code points should already have regular entries, so
            # just fill in the turkish fields
            $CASEFOLD{ord('I')}{'turkic'} = '0131';
            $CASEFOLD{0x130}{'turkic'} = sprintf "%04X", ord('i');
        }
        elsif ($v_unicode_version ge v3.1.0) {

            # These two code points don't have entries otherwise.
            $CASEFOLD{0x130}{'code'} = '0130';
            $CASEFOLD{0x131}{'code'} = '0131';
            $CASEFOLD{0x130}{'status'} = $CASEFOLD{0x131}{'status'} = 'I';
            $CASEFOLD{0x130}{'turkic'}
                = $CASEFOLD{0x130}{'mapping'}
                = $CASEFOLD{0x130}{'full'}
                = $CASEFOLD{0x130}{'simple'}
                = $CASEFOLD{0x131}{'turkic'}
                = $CASEFOLD{0x131}{'mapping'}
                = $CASEFOLD{0x131}{'full'}
                = $CASEFOLD{0x131}{'simple'}
                = sprintf "%04X", ord('i');
        }
    }
}

sub casefold {
    my $arg  = shift;
    my $code = _getcode($arg);
    croak __PACKAGE__, "::casefold: unknown code '$arg'"
	unless defined $code;

    _casefold() unless %CASEFOLD;

    return $CASEFOLD{$code};
}


sub all_casefolds () {
    _casefold() unless %CASEFOLD;
    return _dclone \%CASEFOLD;
}


my %CASESPEC;

sub _casespec {
    unless (%CASESPEC) {
        UnicodeVersion() unless defined $v_unicode_version;
        if ($v_unicode_version lt v2.1.8) {
            %CASESPEC = {};
        }
	elsif (openunicode(\$CASESPECFH, "SpecialCasing.txt")) {
	    local $_;
	    local $/ = "\n";
	    while (<$CASESPECFH>) {
		if (/^([0-9A-F]+); ([0-9A-F]+(?: [0-9A-F]+)*)?; ([0-9A-F]+(?: [0-9A-F]+)*)?; ([0-9A-F]+(?: [0-9A-F]+)*)?; (\w+(?: \w+)*)?/) {

		    my ($hexcode, $lower, $title, $upper, $condition) =
			($1, $2, $3, $4, $5);
                    if (! IS_ASCII_PLATFORM) { # Remap entry to native
                        foreach my $var_ref (\$hexcode,
                                             \$lower,
                                             \$title,
                                             \$upper)
                        {
                            next unless defined $$var_ref;
                            $$var_ref = join " ",
                                        map { sprintf("%04X",
                                              utf8::unicode_to_native(hex $_)) }
                                        split " ", $$var_ref;
                        }
                    }

		    my $code = hex($hexcode);

                    # In 2.1.8, there were duplicate entries; ignore all but
                    # the first one -- there were no conditions in the file
                    # anyway.
		    if (exists $CASESPEC{$code} && $v_unicode_version ne v2.1.8)
                    {
			if (exists $CASESPEC{$code}->{code}) {
			    my ($oldlower,
				$oldtitle,
				$oldupper,
				$oldcondition) =
				    @{$CASESPEC{$code}}{qw(lower
							   title
							   upper
							   condition)};
			    if (defined $oldcondition) {
				my ($oldlocale) =
				($oldcondition =~ /^([a-z][a-z](?:_\S+)?)/);
				delete $CASESPEC{$code};
				$CASESPEC{$code}->{$oldlocale} =
				{ code      => $hexcode,
				  lower     => $oldlower,
				  title     => $oldtitle,
				  upper     => $oldupper,
				  condition => $oldcondition };
			    }
			}
			my ($locale) =
			    ($condition =~ /^([a-z][a-z](?:_\S+)?)/);
			$CASESPEC{$code}->{$locale} =
			{ code      => $hexcode,
			  lower     => $lower,
			  title     => $title,
			  upper     => $upper,
			  condition => $condition };
		    } else {
			$CASESPEC{$code} =
			{ code      => $hexcode,
			  lower     => $lower,
			  title     => $title,
			  upper     => $upper,
			  condition => $condition };
		    }
		}
	    }
	    close($CASESPECFH);
	}
    }
}

sub casespec {
    my $arg  = shift;
    my $code = _getcode($arg);
    croak __PACKAGE__, "::casespec: unknown code '$arg'"
	unless defined $code;

    _casespec() unless %CASESPEC;

    return ref $CASESPEC{$code} ? _dclone $CASESPEC{$code} : $CASESPEC{$code};
}


my %NAMEDSEQ;

sub _namedseq {
    unless (%NAMEDSEQ) {
	if (openunicode(\$NAMEDSEQFH, "Name.pl")) {
	    local $_;
	    local $/ = "\n";
	    while (<$NAMEDSEQFH>) {
		if (/^ [0-9A-F]+ \  /x) {
                    chomp;
                    my ($sequence, $name) = split /\t/;
		    my @s = map { chr(hex($_)) } split(' ', $sequence);
		    $NAMEDSEQ{$name} = join("", @s);
		}
	    }
	    close($NAMEDSEQFH);
	}
    }
}

sub namedseq {

    # Use charnames::string_vianame() which now returns this information,
    # unless the caller wants the hash returned, in which case we read it in,
    # and thereafter use it instead of calling charnames, as it is faster.

    my $wantarray = wantarray();
    if (defined $wantarray) {
	if ($wantarray) {
	    if (@_ == 0) {
                _namedseq() unless %NAMEDSEQ;
		return %NAMEDSEQ;
	    } elsif (@_ == 1) {
		my $s;
                if (%NAMEDSEQ) {
                    $s = $NAMEDSEQ{ $_[0] };
                }
                else {
                    $s = charnames::string_vianame($_[0]);
                }
		return defined $s ? map { ord($_) } split('', $s) : ();
	    }
	} elsif (@_ == 1) {
            return $NAMEDSEQ{ $_[0] } if %NAMEDSEQ;
            return charnames::string_vianame($_[0]);
	}
    }
    return;
}

my %NUMERIC;

sub _numeric {
    my @numbers = _read_table("To/Nv.pl");
    foreach my $entry (@numbers) {
        my ($start, $end, $value) = @$entry;

        # If value contains a slash, convert to decimal, add a reverse hash
        # used by charinfo.
        if ((my @rational = split /\//, $value) == 2) {
            my $real = $rational[0] / $rational[1];
            $real_to_rational{$real} = $value;
            $value = $real;

            # Should only be single element, but just in case...
            for my $i ($start .. $end) {
                $NUMERIC{$i} = $value;
            }
        }
        else {
            # The values require adjusting, as is in 'a' format
            for my $i ($start .. $end) {
                $NUMERIC{$i} = $value + $i - $start;
            }
        }
    }

    # Decided unsafe to use these that aren't officially part of the Unicode
    # standard.
    #use Math::Trig;
    #my $pi = acos(-1.0);
    #$NUMERIC{0x03C0} = $pi;

    # Euler's constant, not to be confused with Euler's number
    #$NUMERIC{0x2107} = 0.57721566490153286060651209008240243104215933593992;

    # Euler's number
    #$NUMERIC{0x212F} = 2.7182818284590452353602874713526624977572;

    return;
}






sub num {
    my $string = $_[0];

    _numeric unless %NUMERIC;

    my $length = length($string);
    return $NUMERIC{ord($string)} if $length == 1;
    return if $string =~ /\D/;
    my $first_ord = ord(substr($string, 0, 1));
    my $value = $NUMERIC{$first_ord};

    # To be a valid decimal number, it should be in a block of 10 consecutive
    # characters, whose values are 0, 1, 2, ... 9.  Therefore this digit's
    # value is its offset in that block from the character that means zero.
    my $zero_ord = $first_ord - $value;

    # Unicode 6.0 instituted the rule that only digits in a consecutive
    # block of 10 would be considered decimal digits.  If this is an earlier
    # release, we verify that this first character is a member of such a
    # block.  That is, that the block of characters surrounding this one
    # consists of all \d characters whose numeric values are the expected
    # ones.
    UnicodeVersion() unless defined $v_unicode_version;
    if ($v_unicode_version lt v6.0.0) {
        for my $i (0 .. 9) {
            my $ord = $zero_ord + $i;
            return unless chr($ord) =~ /\d/;
            my $numeric = $NUMERIC{$ord};
            return unless defined $numeric;
            return unless $numeric == $i;
        }
    }

    for my $i (1 .. $length -1) {

        # Here we know either by verifying, or by fact of the first character
        # being a \d in Unicode 6.0 or later, that any character between the
        # character that means 0, and 9 positions above it must be \d, and
        # must have its value correspond to its offset from the zero.  Any
        # characters outside these 10 do not form a legal number for this
        # function.
        my $ord = ord(substr($string, $i, 1));
        my $digit = $ord - $zero_ord;
        return unless $digit >= 0 && $digit <= 9;
        $value = $value * 10 + $digit;
    }

    return $value;
}



our %string_property_loose_to_name;
our %ambiguous_names;
our %loose_perlprop_to_name;
our %prop_aliases;

sub prop_aliases ($) {
    my $prop = $_[0];
    return unless defined $prop;

    require "unicore/UCD.pl";
    require "unicore/Heavy.pl";
    require "utf8_heavy.pl";

    # The property name may be loosely or strictly matched; we don't know yet.
    # But both types use lower-case.
    $prop = lc $prop;

    # It is loosely matched if its lower case isn't known to be strict.
    my $list_ref;
    if (! exists $utf8::stricter_to_file_of{$prop}) {
        my $loose = utf8::_loose_name($prop);

        # There is a hash that converts from any loose name to its standard
        # form, mapping all synonyms for a  name to one name that can be used
        # as a key into another hash.  The whole concept is for memory
        # savings, as the second hash doesn't have to have all the
        # combinations.  Actually, there are two hashes that do the
        # converstion.  One is used in utf8_heavy.pl (stored in Heavy.pl) for
        # looking up properties matchable in regexes.  This function needs to
        # access string properties, which aren't available in regexes, so a
        # second conversion hash is made for them (stored in UCD.pl).  Look in
        # the string one now, as the rest can have an optional 'is' prefix,
        # which these don't.
        if (exists $string_property_loose_to_name{$loose}) {

            # Convert to its standard loose name.
            $prop = $string_property_loose_to_name{$loose};
        }
        else {
            my $retrying = 0;   # bool.  ? Has an initial 'is' been stripped
        RETRY:
            if (exists $utf8::loose_property_name_of{$loose}
                && (! $retrying
                    || ! exists $ambiguous_names{$loose}))
            {
                # Found an entry giving the standard form.  We don't get here
                # (in the test above) when we've stripped off an
                # 'is' and the result is an ambiguous name.  That is because
                # these are official Unicode properties (though Perl can have
                # an optional 'is' prefix meaning the official property), and
                # all ambiguous cases involve a Perl single-form extension
                # for the gc, script, or block properties, and the stripped
                # 'is' means that they mean one of those, and not one of
                # these
                $prop = $utf8::loose_property_name_of{$loose};
            }
            elsif (exists $loose_perlprop_to_name{$loose}) {

                # This hash is specifically for this function to list Perl
                # extensions that aren't in the earlier hashes.  If there is
                # only one element, the short and long names are identical.
                # Otherwise the form is already in the same form as
                # %prop_aliases, which is handled at the end of the function.
                $list_ref = $loose_perlprop_to_name{$loose};
                if (@$list_ref == 1) {
                    my @list = ($list_ref->[0], $list_ref->[0]);
                    $list_ref = \@list;
                }
            }
            elsif (! exists $utf8::loose_to_file_of{$loose}) {

                # loose_to_file_of is a complete list of loose names.  If not
                # there, the input is unknown.
                return;
            }
            elsif ($loose =~ / [:=] /x) {

                # Here we found the name but not its aliases, so it has to
                # exist.  Exclude property-value combinations.  (This shows up
                # for something like ccc=vr which matches loosely, but is a
                # synonym for ccc=9 which matches only strictly.
                return;
            }
            else {

                # Here it has to exist, and isn't a property-value
                # combination.  This means it must be one of the Perl
                # single-form extensions.  First see if it is for a
                # property-value combination in one of the following
                # properties.
                my @list;
                foreach my $property ("gc", "script") {
                    @list = prop_value_aliases($property, $loose);
                    last if @list;
                }
                if (@list) {

                    # Here, it is one of those property-value combination
                    # single-form synonyms.  There are ambiguities with some
                    # of these.  Check against the list for these, and adjust
                    # if necessary.
                    for my $i (0 .. @list -1) {
                        if (exists $ambiguous_names
                                   {utf8::_loose_name(lc $list[$i])})
                        {
                            # The ambiguity is resolved by toggling whether or
                            # not it has an 'is' prefix
                            $list[$i] =~ s/^Is_// or $list[$i] =~ s/^/Is_/;
                        }
                    }
                    return @list;
                }

                # Here, it wasn't one of the gc or script single-form
                # extensions.  It could be a block property single-form
                # extension.  An 'in' prefix definitely means that, and should
                # be looked up without the prefix.  However, starting in
                # Unicode 6.1, we have to special case 'indic...', as there
                # is a property that begins with that name.   We shouldn't
                # strip the 'in' from that.   I'm (khw) generalizing this to
                # 'indic' instead of the single property, because I suspect
                # that others of this class may come along in the future.
                # However, this could backfire and a block created whose name
                # begins with 'dic...', and we would want to strip the 'in'.
                # At which point this would have to be tweaked.
                my $began_with_in = $loose =~ s/^in(?!dic)//;
                @list = prop_value_aliases("block", $loose);
                if (@list) {
                    map { $_ =~ s/^/In_/ } @list;
                    return @list;
                }

                # Here still haven't found it.  The last opportunity for it
                # being valid is only if it began with 'is'.  We retry without
                # the 'is', setting a flag to that effect so that we don't
                # accept things that begin with 'isis...'
                if (! $retrying && ! $began_with_in && $loose =~ s/^is//) {
                    $retrying = 1;
                    goto RETRY;
                }

                # Here, didn't find it.  Since it was in %loose_to_file_of, we
                # should have been able to find it.
                carp __PACKAGE__, "::prop_aliases: Unexpectedly could not find '$prop'.  Send bug report to perlbug\@perl.org";
                return;
            }
        }
    }

    if (! $list_ref) {
        # Here, we have set $prop to a standard form name of the input.  Look
        # it up in the structure created by mktables for this purpose, which
        # contains both strict and loosely matched properties.  Avoid
        # autovivifying.
        $list_ref = $prop_aliases{$prop} if exists $prop_aliases{$prop};
        return unless $list_ref;
    }

    # The full name is in element 1.
    return $list_ref->[1] unless wantarray;

    return @{_dclone $list_ref};
}


our %loose_to_standard_value;
our %prop_value_aliases;

sub prop_value_aliases ($$) {
    my ($prop, $value) = @_;
    return unless defined $prop && defined $value;

    require "unicore/UCD.pl";
    require "utf8_heavy.pl";

    # Find the property name synonym that's used as the key in other hashes,
    # which is element 0 in the returned list.
    ($prop) = prop_aliases($prop);
    return if ! $prop;
    $prop = utf8::_loose_name(lc $prop);

    # Here is a legal property, but the hash below (created by mktables for
    # this purpose) only knows about the properties that have a very finite
    # number of potential values, that is not ones whose value could be
    # anything, like most (if not all) string properties.  These don't have
    # synonyms anyway.  Simply return the input.  For example, there is no
    # synonym for ('Uppercase_Mapping', A').
    return $value if ! exists $prop_value_aliases{$prop};

    # The value name may be loosely or strictly matched; we don't know yet.
    # But both types use lower-case.
    $value = lc $value;

    # If the name isn't found under loose matching, it certainly won't be
    # found under strict
    my $loose_value = utf8::_loose_name($value);
    return unless exists $loose_to_standard_value{"$prop=$loose_value"};

    # Similarly if the combination under loose matching doesn't exist, it
    # won't exist under strict.
    my $standard_value = $loose_to_standard_value{"$prop=$loose_value"};
    return unless exists $prop_value_aliases{$prop}{$standard_value};

    # Here we did find a combination under loose matching rules.  But it could
    # be that is a strict property match that shouldn't have matched.
    # %prop_value_aliases is set up so that the strict matches will appear as
    # if they were in loose form.  Thus, if the non-loose version is legal,
    # we're ok, can skip the further check.
    if (! exists $utf8::stricter_to_file_of{"$prop=$value"}

        # We're also ok and skip the further check if value loosely matches.
        # mktables has verified that no strict name under loose rules maps to
        # an existing loose name.  This code relies on the very limited
        # circumstances that strict names can be here.  Strict name matching
        # happens under two conditions:
        # 1) when the name begins with an underscore.  But this function
        #    doesn't accept those, and %prop_value_aliases doesn't have
        #    them.
        # 2) When the values are numeric, in which case we need to look
        #    further, but their squeezed-out loose values will be in
        #    %stricter_to_file_of
        && exists $utf8::stricter_to_file_of{"$prop=$loose_value"})
    {
        # The only thing that's legal loosely under strict is that can have an
        # underscore between digit pairs XXX
        while ($value =~ s/(\d)_(\d)/$1$2/g) {}
        return unless exists $utf8::stricter_to_file_of{"$prop=$value"};
    }

    # Here, we know that the combination exists.  Return it.
    my $list_ref = $prop_value_aliases{$prop}{$standard_value};
    if (@$list_ref > 1) {
        # The full name is in element 1.
        return $list_ref->[1] unless wantarray;

        return @{_dclone $list_ref};
    }

    return $list_ref->[0] unless wantarray;

    # Only 1 element means that it repeats
    return ( $list_ref->[0], $list_ref->[0] );
}

$Unicode::UCD::MAX_CP = ~0;



our %loose_defaults;
our $MAX_UNICODE_CODEPOINT;

sub prop_invlist ($;$) {
    my $prop = $_[0];

    # Undocumented way to get at Perl internal properties
    my $internal_ok = defined $_[1] && $_[1] eq '_perl_core_internal_ok';

    return if ! defined $prop;

    require "utf8_heavy.pl";

    # Warnings for these are only for regexes, so not applicable to us
    no warnings 'deprecated';

    # Get the swash definition of the property-value.
    my $swash = utf8::SWASHNEW(__PACKAGE__, $prop, undef, 1, 0);

    # Fail if not found, or isn't a boolean property-value, or is a
    # user-defined property, or is internal-only.
    return if ! $swash
              || ref $swash eq ""
              || $swash->{'BITS'} != 1
              || $swash->{'USER_DEFINED'}
              || (! $internal_ok && $prop =~ /^\s*_/);

    if ($swash->{'EXTRAS'}) {
        carp __PACKAGE__, "::prop_invlist: swash returned for $prop unexpectedly has EXTRAS magic";
        return;
    }
    if ($swash->{'SPECIALS'}) {
        carp __PACKAGE__, "::prop_invlist: swash returned for $prop unexpectedly has SPECIALS magic";
        return;
    }

    my @invlist;

    if ($swash->{'LIST'} =~ /^V/) {

        # A 'V' as the first character marks the input as already an inversion
        # list, in which case, all we need to do is put the remaining lines
        # into our array.
        @invlist = split "\n", $swash->{'LIST'} =~ s/ \s* (?: \# .* )? $ //xmgr;
        shift @invlist;
    }
    else {
        # The input lines look like:
        # 0041\t005A   # [26]
        # 005F

        # Split into lines, stripped of trailing comments
        foreach my $range (split "\n",
                              $swash->{'LIST'} =~ s/ \s* (?: \# .* )? $ //xmgr)
        {
            # And find the beginning and end of the range on the line
            my ($hex_begin, $hex_end) = split "\t", $range;
            my $begin = hex $hex_begin;

            # If the new range merely extends the old, we remove the marker
            # created the last time through the loop for the old's end, which
            # causes the new one's end to be used instead.
            if (@invlist && $begin == $invlist[-1]) {
                pop @invlist;
            }
            else {
                # Add the beginning of the range
                push @invlist, $begin;
            }

            if (defined $hex_end) { # The next item starts with the code point 1
                                    # beyond the end of the range.
                no warnings 'portable';
                my $end = hex $hex_end;
                last if $end == $Unicode::UCD::MAX_CP;
                push @invlist, $end + 1;
            }
            else {  # No end of range, is a single code point.
                push @invlist, $begin + 1;
            }
        }
    }

    # Could need to be inverted: add or subtract a 0 at the beginning of the
    # list.
    if ($swash->{'INVERT_IT'}) {
        if (@invlist && $invlist[0] == 0) {
            shift @invlist;
        }
        else {
            unshift @invlist, 0;
        }
    }

    return @invlist;
}




our @algorithmic_named_code_points;
our $HANGUL_BEGIN;
our $HANGUL_COUNT;

sub prop_invmap ($) {

    croak __PACKAGE__, "::prop_invmap: must be called in list context" unless wantarray;

    my $prop = $_[0];
    return unless defined $prop;

    # Fail internal properties
    return if $prop =~ /^_/;

    # The values returned by this function.
    my (@invlist, @invmap, $format, $missing);

    # The swash has two components we look at, the base list, and a hash,
    # named 'SPECIALS', containing any additional members whose mappings don't
    # fit into the base list scheme of things.  These generally 'override'
    # any value in the base list for the same code point.
    my $overrides;

    require "utf8_heavy.pl";
    require "unicore/UCD.pl";

RETRY:

    # If there are multiple entries for a single code point
    my $has_multiples = 0;

    # Try to get the map swash for the property.  They have 'To' prepended to
    # the property name, and 32 means we will accept 32 bit return values.
    # The 0 means we aren't calling this from tr///.
    my $swash = utf8::SWASHNEW(__PACKAGE__, "To$prop", undef, 32, 0);

    # If didn't find it, could be because needs a proxy.  And if was the
    # 'Block' or 'Name' property, use a proxy even if did find it.  Finding it
    # in these cases would be the result of the installation changing mktables
    # to output the Block or Name tables.  The Block table gives block names
    # in the new-style, and this routine is supposed to return old-style block
    # names.  The Name table is valid, but we need to execute the special code
    # below to add in the algorithmic-defined name entries.
    # And NFKCCF needs conversion, so handle that here too.
    if (ref $swash eq ""
        || $swash->{'TYPE'} =~ / ^ To (?: Blk | Na | NFKCCF ) $ /x)
    {

        # Get the short name of the input property, in standard form
        my ($second_try) = prop_aliases($prop);
        return unless $second_try;
        $second_try = utf8::_loose_name(lc $second_try);

        if ($second_try eq "in") {

            # This property is identical to age for inversion map purposes
            $prop = "age";
            goto RETRY;
        }
        elsif ($second_try =~ / ^ s ( cf | fc | [ltu] c ) $ /x) {

            # These properties use just the LIST part of the full mapping,
            # which includes the simple maps that are otherwise overridden by
            # the SPECIALS.  So all we need do is to not look at the SPECIALS;
            # set $overrides to indicate that
            $overrides = -1;

            # The full name is the simple name stripped of its initial 's'
            $prop = $1;

            # .. except for this case
            $prop = 'cf' if $prop eq 'fc';

            goto RETRY;
        }
        elsif ($second_try eq "blk") {

            # We use the old block names.  Just create a fake swash from its
            # data.
            _charblocks();
            my %blocks;
            $blocks{'LIST'} = "";
            $blocks{'TYPE'} = "ToBlk";
            $utf8::SwashInfo{ToBlk}{'missing'} = "No_Block";
            $utf8::SwashInfo{ToBlk}{'format'} = "s";

            foreach my $block (@BLOCKS) {
                $blocks{'LIST'} .= sprintf "%x\t%x\t%s\n",
                                           $block->[0],
                                           $block->[1],
                                           $block->[2];
            }
            $swash = \%blocks;
        }
        elsif ($second_try eq "na") {

            # Use the combo file that has all the Name-type properties in it,
            # extracting just the ones that are for the actual 'Name'
            # property.  And create a fake swash from it.
            my %names;
            $names{'LIST'} = "";
            my $original = do "unicore/Name.pl";
            my $algorithm_names = \@algorithmic_named_code_points;

            # We need to remove the names from it that are aliases.  For that
            # we need to also read in that table.  Create a hash with the keys
            # being the code points, and the values being a list of the
            # aliases for the code point key.
            my ($aliases_code_points, $aliases_maps, undef, undef) =
                                                &prop_invmap('Name_Alias');
            my %aliases;
            for (my $i = 0; $i < @$aliases_code_points; $i++) {
                my $code_point = $aliases_code_points->[$i];
                $aliases{$code_point} = $aliases_maps->[$i];

                # If not already a list, make it into one, so that later we
                # can treat things uniformly
                if (! ref $aliases{$code_point}) {
                    $aliases{$code_point} = [ $aliases{$code_point} ];
                }

                # Remove the alias type from the entry, retaining just the
                # name.
                map { s/:.*// } @{$aliases{$code_point}};
            }

            my $i = 0;
            foreach my $line (split "\n", $original) {
                my ($hex_code_point, $name) = split "\t", $line;

                # Weeds out all comments, blank lines, and named sequences
                next if $hex_code_point =~ /[^[:xdigit:]]/a;

                my $code_point = hex $hex_code_point;

                # The name of all controls is the default: the empty string.
                # The set of controls is immutable
                next if chr($code_point) =~ /[[:cntrl:]]/u;

                # If this is a name_alias, it isn't a name
                next if grep { $_ eq $name } @{$aliases{$code_point}};

                # If we are beyond where one of the special lines needs to
                # be inserted ...
                while ($i < @$algorithm_names
                    && $code_point > $algorithm_names->[$i]->{'low'})
                {

                    # ... then insert it, ahead of what we were about to
                    # output
                    $names{'LIST'} .= sprintf "%x\t%x\t%s\n",
                                            $algorithm_names->[$i]->{'low'},
                                            $algorithm_names->[$i]->{'high'},
                                            $algorithm_names->[$i]->{'name'};

                    # Done with this range.
                    $i++;

                    # We loop until all special lines that precede the next
                    # regular one are output.
                }

                # Here, is a normal name.
                $names{'LIST'} .= sprintf "%x\t\t%s\n", $code_point, $name;
            } # End of loop through all the names

            $names{'TYPE'} = "ToNa";
            $utf8::SwashInfo{ToNa}{'missing'} = "";
            $utf8::SwashInfo{ToNa}{'format'} = "n";
            $swash = \%names;
        }
        elsif ($second_try =~ / ^ ( d [mt] ) $ /x) {

            # The file is a combination of dt and dm properties.  Create a
            # fake swash from the portion that we want.
            my $original = do "unicore/Decomposition.pl";
            my %decomps;

            if ($second_try eq 'dt') {
                $decomps{'TYPE'} = "ToDt";
                $utf8::SwashInfo{'ToDt'}{'missing'} = "None";
                $utf8::SwashInfo{'ToDt'}{'format'} = "s";
            }   # 'dm' is handled below, with 'nfkccf'

            $decomps{'LIST'} = "";

            # This property has one special range not in the file: for the
            # hangul syllables.  But not in Unicode version 1.
            UnicodeVersion() unless defined $v_unicode_version;
            my $done_hangul = ($v_unicode_version lt v2.0.0)
                              ? 1
                              : 0;    # Have we done the hangul range ?
            foreach my $line (split "\n", $original) {
                my ($hex_lower, $hex_upper, $type_and_map) = split "\t", $line;
                my $code_point = hex $hex_lower;
                my $value;
                my $redo = 0;

                # The type, enclosed in <...>, precedes the mapping separated
                # by blanks
                if ($type_and_map =~ / ^ < ( .* ) > \s+ (.*) $ /x) {
                    $value = ($second_try eq 'dt') ? $1 : $2
                }
                else {  # If there is no type specified, it's canonical
                    $value = ($second_try eq 'dt')
                             ? "Canonical" :
                             $type_and_map;
                }

                # Insert the hangul range at the appropriate spot.
                if (! $done_hangul && $code_point > $HANGUL_BEGIN) {
                    $done_hangul = 1;
                    $decomps{'LIST'} .=
                                sprintf "%x\t%x\t%s\n",
                                        $HANGUL_BEGIN,
                                        $HANGUL_BEGIN + $HANGUL_COUNT - 1,
                                        ($second_try eq 'dt')
                                        ? "Canonical"
                                        : "<hangul syllable>";
                }

                if ($value =~ / / && $hex_upper ne "" && $hex_upper ne $hex_lower) {
                    $line = sprintf("%04X\t%s\t%s", hex($hex_lower) + 1, $hex_upper, $value);
                    $hex_upper = "";
                    $redo = 1;
                }

                # And append this to our constructed LIST.
                $decomps{'LIST'} .= "$hex_lower\t$hex_upper\t$value\n";

                redo if $redo;
            }
            $swash = \%decomps;
        }
        elsif ($second_try ne 'nfkccf') { # Don't know this property. Fail.
            return;
        }

        if ($second_try eq 'nfkccf' || $second_try eq 'dm') {

            # The 'nfkccf' property is stored in the old format for backwards
            # compatibility for any applications that has read its file
            # directly before prop_invmap() existed.
            # And the code above has extracted the 'dm' property from its file
            # yielding the same format.  So here we convert them to adjusted
            # format for compatibility with the other properties similar to
            # them.
            my %revised_swash;

            # We construct a new converted list.
            my $list = "";

            my @ranges = split "\n", $swash->{'LIST'};
            for (my $i = 0; $i < @ranges; $i++) {
                my ($hex_begin, $hex_end, $map) = split "\t", $ranges[$i];

                # The dm property has maps that are space separated sequences
                # of code points, as well as the special entry "<hangul
                # syllable>, which also contains a blank.
                my @map = split " ", $map;
                if (@map > 1) {

                    # If it's just the special entry, append as-is.
                    if ($map eq '<hangul syllable>') {
                        $list .= "$ranges[$i]\n";
                    }
                    else {

                        # These should all be single-element ranges.
                        croak __PACKAGE__, "::prop_invmap: Not expecting a mapping with multiple code points in a multi-element range, $ranges[$i]" if $hex_end ne "" && $hex_end ne $hex_begin;

                        # Convert them to decimal, as that's what's expected.
                        $list .= "$hex_begin\t\t"
                            . join(" ", map { hex } @map)
                            . "\n";
                    }
                    next;
                }

                # Here, the mapping doesn't have a blank, is for a single code
                # point.
                my $begin = hex $hex_begin;
                my $end = (defined $hex_end && $hex_end ne "")
                        ? hex $hex_end
                        : $begin;

                # Again, the output is to be in decimal.
                my $decimal_map = hex $map;

                # We know that multi-element ranges with the same mapping
                # should not be adjusted, as after the adjustment
                # multi-element ranges are for consecutive increasing code
                # points.  Further, the final element in the list won't be
                # adjusted, as there is nothing after it to include in the
                # adjustment
                if ($begin != $end || $i == @ranges -1) {

                    # So just convert these to single-element ranges
                    foreach my $code_point ($begin .. $end) {
                        $list .= sprintf("%04X\t\t%d\n",
                                        $code_point, $decimal_map);
                    }
                }
                else {

                    # Here, we have a candidate for adjusting.  What we do is
                    # look through the subsequent adjacent elements in the
                    # input.  If the map to the next one differs by 1 from the
                    # one before, then we combine into a larger range with the
                    # initial map.  Loop doing this until we find one that
                    # can't be combined.

                    my $offset = 0;     # How far away are we from the initial
                                        # map
                    my $squished = 0;   # ? Did we squish at least two
                                        # elements together into one range
                    for ( ; $i < @ranges; $i++) {
                        my ($next_hex_begin, $next_hex_end, $next_map)
                                                = split "\t", $ranges[$i+1];

                        # In the case of 'dm', the map may be a sequence of
                        # multiple code points, which are never combined with
                        # another range
                        last if $next_map =~ / /;

                        $offset++;
                        my $next_decimal_map = hex $next_map;

                        # If the next map is not next in sequence, it
                        # shouldn't be combined.
                        last if $next_decimal_map != $decimal_map + $offset;

                        my $next_begin = hex $next_hex_begin;

                        # Likewise, if the next element isn't adjacent to the
                        # previous one, it shouldn't be combined.
                        last if $next_begin != $begin + $offset;

                        my $next_end = (defined $next_hex_end
                                        && $next_hex_end ne "")
                                            ? hex $next_hex_end
                                            : $next_begin;

                        # And finally, if the next element is a multi-element
                        # range, it shouldn't be combined.
                        last if $next_end != $next_begin;

                        # Here, we will combine.  Loop to see if we should
                        # combine the next element too.
                        $squished = 1;
                    }

                    if ($squished) {

                        # Here, 'i' is the element number of the last element to
                        # be combined, and the range is single-element, or we
                        # wouldn't be combining.  Get it's code point.
                        my ($hex_end, undef, undef) = split "\t", $ranges[$i];
                        $list .= "$hex_begin\t$hex_end\t$decimal_map\n";
                    } else {

                        # Here, no combining done.  Just append the initial
                        # (and current) values.
                        $list .= "$hex_begin\t\t$decimal_map\n";
                    }
                }
            } # End of loop constructing the converted list

            # Finish up the data structure for our converted swash
            my $type = ($second_try eq 'nfkccf') ? 'ToNFKCCF' : 'ToDm';
            $revised_swash{'LIST'} = $list;
            $revised_swash{'TYPE'} = $type;
            $revised_swash{'SPECIALS'} = $swash->{'SPECIALS'};
            $swash = \%revised_swash;

            $utf8::SwashInfo{$type}{'missing'} = 0;
            $utf8::SwashInfo{$type}{'format'} = 'a';
        }
    }

    if ($swash->{'EXTRAS'}) {
        carp __PACKAGE__, "::prop_invmap: swash returned for $prop unexpectedly has EXTRAS magic";
        return;
    }

    # Here, have a valid swash return.  Examine it.
    my $returned_prop = $swash->{'TYPE'};

    # All properties but binary ones should have 'missing' and 'format'
    # entries
    $missing = $utf8::SwashInfo{$returned_prop}{'missing'};
    $missing = 'N' unless defined $missing;

    $format = $utf8::SwashInfo{$returned_prop}{'format'};
    $format = 'b' unless defined $format;

    my $requires_adjustment = $format =~ /^a/;

    if ($swash->{'LIST'} =~ /^V/) {
        @invlist = split "\n", $swash->{'LIST'} =~ s/ \s* (?: \# .* )? $ //xmgr;
        shift @invlist;
        foreach my $i (0 .. @invlist - 1) {
            $invmap[$i] = ($i % 2 == 0) ? 'Y' : 'N'
        }

        # The map includes lines for all code points; add one for the range
        # from 0 to the first Y.
        if ($invlist[0] != 0) {
            unshift @invlist, 0;
            unshift @invmap, 'N';
        }
    }
    else {
        # The LIST input lines look like:
        # ...
        # 0374\t\tCommon
        # 0375\t0377\tGreek   # [3]
        # 037A\t037D\tGreek   # [4]
        # 037E\t\tCommon
        # 0384\t\tGreek
        # ...
        #
        # Convert them to like
        # 0374 => Common
        # 0375 => Greek
        # 0378 => $missing
        # 037A => Greek
        # 037E => Common
        # 037F => $missing
        # 0384 => Greek
        #
        # For binary properties, the final non-comment column is absent, and
        # assumed to be 'Y'.

        foreach my $range (split "\n", $swash->{'LIST'}) {
            $range =~ s/ \s* (?: \# .* )? $ //xg; # rmv trailing space, comments

            # Find the beginning and end of the range on the line
            my ($hex_begin, $hex_end, $map) = split "\t", $range;
            my $begin = hex $hex_begin;
            no warnings 'portable';
            my $end = (defined $hex_end && $hex_end ne "")
                    ? hex $hex_end
                    : $begin;

            # Each time through the loop (after the first):
            # $invlist[-2] contains the beginning of the previous range processed
            # $invlist[-1] contains the end+1 of the previous range processed
            # $invmap[-2] contains the value of the previous range processed
            # $invmap[-1] contains the default value for missing ranges
            #                                                       ($missing)
            #
            # Thus, things are set up for the typical case of a new
            # non-adjacent range of non-missings to be added.  But, if the new
            # range is adjacent, it needs to replace the [-1] element; and if
            # the new range is a multiple value of the previous one, it needs
            # to be added to the [-2] map element.

            # The first time through, everything will be empty.  If the
            # property doesn't have a range that begins at 0, add one that
            # maps to $missing
            if (! @invlist) {
                if ($begin != 0) {
                    push @invlist, 0;
                    push @invmap, $missing;
                }
            }
            elsif (@invlist > 1 && $invlist[-2] == $begin) {

                # Here we handle the case where the input has multiple entries
                # for each code point.  mktables should have made sure that
                # each such range contains only one code point.  At this
                # point, $invlist[-1] is the $missing that was added at the
                # end of the last loop iteration, and [-2] is the last real
                # input code point, and that code point is the same as the one
                # we are adding now, making the new one a multiple entry.  Add
                # it to the existing entry, either by pushing it to the
                # existing list of multiple entries, or converting the single
                # current entry into a list with both on it.  This is all we
                # need do for this iteration.

                if ($end != $begin) {
                    croak __PACKAGE__, ":prop_invmap: Multiple maps per code point in '$prop' require single-element ranges: begin=$begin, end=$end, map=$map";
                }
                if (! ref $invmap[-2]) {
                    $invmap[-2] = [ $invmap[-2], $map ];
                }
                else {
                    push @{$invmap[-2]}, $map;
                }
                $has_multiples = 1;
                next;
            }
            elsif ($invlist[-1] == $begin) {

                # If the input isn't in the most compact form, so that there
                # are two adjacent ranges that map to the same thing, they
                # should be combined (EXCEPT where the arrays require
                # adjustments, in which case everything is already set up
                # correctly).  This happens in our constructed dt mapping, as
                # Element [-2] is the map for the latest range so far
                # processed.  Just set the beginning point of the map to
                # $missing (in invlist[-1]) to 1 beyond where this range ends.
                # For example, in
                # 12\t13\tXYZ
                # 14\t17\tXYZ
                # we have set it up so that it looks like
                # 12 => XYZ
                # 14 => $missing
                #
                # We now see that it should be
                # 12 => XYZ
                # 18 => $missing
                if (! $requires_adjustment && @invlist > 1 && ( (defined $map)
                                    ? $invmap[-2] eq $map
                                    : $invmap[-2] eq 'Y'))
                {
                    $invlist[-1] = $end + 1;
                    next;
                }

                # Here, the range started in the previous iteration that maps
                # to $missing starts at the same code point as this range.
                # That means there is no gap to fill that that range was
                # intended for, so we just pop it off the parallel arrays.
                pop @invlist;
                pop @invmap;
            }

            # Add the range beginning, and the range's map.
            push @invlist, $begin;
            if ($returned_prop eq 'ToDm') {

                # The decomposition maps are either a line like <hangul
                # syllable> which are to be taken as is; or a sequence of code
                # points in hex and separated by blanks.  Convert them to
                # decimal, and if there is more than one, use an anonymous
                # array as the map.
                if ($map =~ /^ < /x) {
                    push @invmap, $map;
                }
                else {
                    my @map = split " ", $map;
                    if (@map == 1) {
                        push @invmap, $map[0];
                    }
                    else {
                        push @invmap, \@map;
                    }
                }
            }
            else {

                # Otherwise, convert hex formatted list entries to decimal;
                # add a 'Y' map for the missing value in binary properties, or
                # otherwise, use the input map unchanged.
                $map = ($format eq 'x' || $format eq 'ax')
                    ? hex $map
                    : $format eq 'b'
                    ? 'Y'
                    : $map;
                push @invmap, $map;
            }

            # We just started a range.  It ends with $end.  The gap between it
            # and the next element in the list must be filled with a range
            # that maps to the default value.  If there is no gap, the next
            # iteration will pop this, unless there is no next iteration, and
            # we have filled all of the Unicode code space, so check for that
            # and skip.
            if ($end < $Unicode::UCD::MAX_CP) {
                push @invlist, $end + 1;
                push @invmap, $missing;
            }
        }
    }

    # If the property is empty, make all code points use the value for missing
    # ones.
    if (! @invlist) {
        push @invlist, 0;
        push @invmap, $missing;
    }

    # The final element is always for just the above-Unicode code points.  If
    # not already there, add it.  It merely splits the current final range
    # that extends to infinity into two elements, each with the same map.
    # (This is to conform with the API that says the final element is for
    # $MAX_UNICODE_CODEPOINT + 1 .. INFINITY.)
    if ($invlist[-1] != $MAX_UNICODE_CODEPOINT + 1) {
        push @invmap, $invmap[-1];
        push @invlist, $MAX_UNICODE_CODEPOINT + 1;
    }

    # The second component of the map are those values that require
    # non-standard specification, stored in SPECIALS.  These override any
    # duplicate code points in LIST.  If we are using a proxy, we may have
    # already set $overrides based on the proxy.
    $overrides = $swash->{'SPECIALS'} unless defined $overrides;
    if ($overrides) {

        # A negative $overrides implies that the SPECIALS should be ignored,
        # and a simple 'a' list is the value.
        if ($overrides < 0) {
            $format = 'a';
        }
        else {

            # Currently, all overrides are for properties that normally map to
            # single code points, but now some will map to lists of code
            # points (but there is an exception case handled below).
            $format = 'al';

            # Look through the overrides.
            foreach my $cp_maybe_utf8 (keys %$overrides) {
                my $cp;
                my @map;

                # If the overrides came from SPECIALS, the code point keys are
                # packed UTF-8.
                if ($overrides == $swash->{'SPECIALS'}) {
                    $cp = unpack("C0U", $cp_maybe_utf8);
                    @map = unpack "U0U*", $swash->{'SPECIALS'}{$cp_maybe_utf8};

                    # The empty string will show up unpacked as an empty
                    # array.
                    $format = 'ale' if @map == 0;
                }
                else {

                    # But if we generated the overrides, we didn't bother to
                    # pack them, and we, so far, do this only for properties
                    # that are 'a' ones.
                    $cp = $cp_maybe_utf8;
                    @map = hex $overrides->{$cp};
                    $format = 'a';
                }

                # Find the range that the override applies to.
                my $i = search_invlist(\@invlist, $cp);
                if ($cp < $invlist[$i] || $cp >= $invlist[$i + 1]) {
                    croak __PACKAGE__, "::prop_invmap: wrong_range, cp=$cp; i=$i, current=$invlist[$i]; next=$invlist[$i + 1]"
                }

                # And what that range currently maps to
                my $cur_map = $invmap[$i];

                # If there is a gap between the next range and the code point
                # we are overriding, we have to add elements to both arrays to
                # fill that gap, using the map that applies to it, which is
                # $cur_map, since it is part of the current range.
                if ($invlist[$i + 1] > $cp + 1) {
                    #use feature 'say';
                    #say "Before splice:";
                    #say 'i-2=[', $i-2, ']', sprintf("%04X maps to %s", $invlist[$i-2], $invmap[$i-2]) if $i >= 2;
                    #say 'i-1=[', $i-1, ']', sprintf("%04X maps to %s", $invlist[$i-1], $invmap[$i-1]) if $i >= 1;
                    #say 'i  =[', $i, ']', sprintf("%04X maps to %s", $invlist[$i], $invmap[$i]);
                    #say 'i+1=[', $i+1, ']', sprintf("%04X maps to %s", $invlist[$i+1], $invmap[$i+1]) if $i < @invlist + 1;
                    #say 'i+2=[', $i+2, ']', sprintf("%04X maps to %s", $invlist[$i+2], $invmap[$i+2]) if $i < @invlist + 2;

                    splice @invlist, $i + 1, 0, $cp + 1;
                    splice @invmap, $i + 1, 0, $cur_map;

                    #say "After splice:";
                    #say 'i-2=[', $i-2, ']', sprintf("%04X maps to %s", $invlist[$i-2], $invmap[$i-2]) if $i >= 2;
                    #say 'i-1=[', $i-1, ']', sprintf("%04X maps to %s", $invlist[$i-1], $invmap[$i-1]) if $i >= 1;
                    #say 'i  =[', $i, ']', sprintf("%04X maps to %s", $invlist[$i], $invmap[$i]);
                    #say 'i+1=[', $i+1, ']', sprintf("%04X maps to %s", $invlist[$i+1], $invmap[$i+1]) if $i < @invlist + 1;
                    #say 'i+2=[', $i+2, ']', sprintf("%04X maps to %s", $invlist[$i+2], $invmap[$i+2]) if $i < @invlist + 2;
                }

                # If the remaining portion of the range is multiple code
                # points (ending with the one we are replacing, guaranteed by
                # the earlier splice).  We must split it into two
                if ($invlist[$i] < $cp) {
                    $i++;   # Compensate for the new element

                    #use feature 'say';
                    #say "Before splice:";
                    #say 'i-2=[', $i-2, ']', sprintf("%04X maps to %s", $invlist[$i-2], $invmap[$i-2]) if $i >= 2;
                    #say 'i-1=[', $i-1, ']', sprintf("%04X maps to %s", $invlist[$i-1], $invmap[$i-1]) if $i >= 1;
                    #say 'i  =[', $i, ']', sprintf("%04X maps to %s", $invlist[$i], $invmap[$i]);
                    #say 'i+1=[', $i+1, ']', sprintf("%04X maps to %s", $invlist[$i+1], $invmap[$i+1]) if $i < @invlist + 1;
                    #say 'i+2=[', $i+2, ']', sprintf("%04X maps to %s", $invlist[$i+2], $invmap[$i+2]) if $i < @invlist + 2;

                    splice @invlist, $i, 0, $cp;
                    splice @invmap, $i, 0, 'dummy';

                    #say "After splice:";
                    #say 'i-2=[', $i-2, ']', sprintf("%04X maps to %s", $invlist[$i-2], $invmap[$i-2]) if $i >= 2;
                    #say 'i-1=[', $i-1, ']', sprintf("%04X maps to %s", $invlist[$i-1], $invmap[$i-1]) if $i >= 1;
                    #say 'i  =[', $i, ']', sprintf("%04X maps to %s", $invlist[$i], $invmap[$i]);
                    #say 'i+1=[', $i+1, ']', sprintf("%04X maps to %s", $invlist[$i+1], $invmap[$i+1]) if $i < @invlist + 1;
                    #say 'i+2=[', $i+2, ']', sprintf("%04X maps to %s", $invlist[$i+2], $invmap[$i+2]) if $i < @invlist + 2;
                }

                # Here, the range we are overriding contains a single code
                # point.  The result could be the empty string, a single
                # value, or a list.  If the last case, we use an anonymous
                # array.
                $invmap[$i] = (scalar @map == 0)
                               ? ""
                               : (scalar @map > 1)
                                  ? \@map
                                  : $map[0];
            }
        }
    }
    elsif ($format eq 'x') {

        # All hex-valued properties are really to code points, and have been
        # converted to decimal.
        $format = 's';
    }
    elsif ($returned_prop eq 'ToDm') {
        $format = 'ad';
    }
    elsif ($format eq 'sw') { # blank-separated elements to form a list.
        map { $_ = [ split " ", $_  ] if $_ =~ / / } @invmap;
        $format = 'sl';
    }
    elsif ($returned_prop eq 'ToNameAlias') {

        # This property currently doesn't have any lists, but theoretically
        # could
        $format = 'sl';
    }
    elsif ($returned_prop eq 'ToPerlDecimalDigit') {
        $format = 'ae';
    }
    elsif ($returned_prop eq 'ToNv') {

        # The one property that has this format is stored as a delta, so needs
        # to indicate that need to add code point to it.
        $format = 'ar';
    }
    elsif ($format ne 'n' && $format ne 'a') {

        # All others are simple scalars
        $format = 's';
    }
    if ($has_multiples &&  $format !~ /l/) {
	croak __PACKAGE__, "::prop_invmap: Wrong format '$format' for prop_invmap('$prop'); should indicate has lists";
    }

    return (\@invlist, \@invmap, $format, $missing);
}

sub search_invlist {



    my $list_ref = shift;
    my $input_code_point = shift;
    my $code_point = _getcode($input_code_point);

    if (! defined $code_point) {
        carp __PACKAGE__, "::search_invlist: unknown code '$input_code_point'";
        return;
    }

    my $max_element = @$list_ref - 1;

    # Return undef if list is empty or requested item is before the first element.
    return if $max_element < 0;
    return if $code_point < $list_ref->[0];

    # Short cut something at the far-end of the table.  This also allows us to
    # refer to element [$i+1] without fear of being out-of-bounds in the loop
    # below.
    return $max_element if $code_point >= $list_ref->[$max_element];

    use integer;        # want integer division

    my $i = $max_element / 2;

    my $lower = 0;
    my $upper = $max_element;
    while (1) {

        if ($code_point >= $list_ref->[$i]) {

            # Here we have met the lower constraint.  We can quit if we
            # also meet the upper one.
            last if $code_point < $list_ref->[$i+1];

            $lower = $i;        # Still too low.

        }
        else {

            # Here, $code_point < $list_ref[$i], so look lower down.
            $upper = $i;
        }

        # Split search domain in half to try again.
        my $temp = ($upper + $lower) / 2;

        # No point in continuing unless $i changes for next time
        # in the loop.
        return $i if $temp == $i;
        $i = $temp;
    } # End of while loop

    # Here we have found the offset
    return $i;
}


my $UNICODEVERSION;

sub UnicodeVersion {
    unless (defined $UNICODEVERSION) {
	openunicode(\$VERSIONFH, "version");
	local $/ = "\n";
	chomp($UNICODEVERSION = <$VERSIONFH>);
	close($VERSIONFH);
	croak __PACKAGE__, "::VERSION: strange version '$UNICODEVERSION'"
	    unless $UNICODEVERSION =~ /^\d+(?:\.\d+)+$/;
    }
    $v_unicode_version = pack "C*", split /\./, $UNICODEVERSION;
    return $UNICODEVERSION;
}


1;
