package encoding;
our $VERSION = sprintf "%d.%02d", q$Revision: 2.12 $ =~ /(\d+)/g;

use Encode;
use strict;
use warnings;

use constant DEBUG => !!$ENV{PERL_ENCODE_DEBUG};

BEGIN {
    if ( ord("A") == 193 ) {
        require Carp;
        Carp::croak("encoding: pragma does not support EBCDIC platforms");
    }
}

our $HAS_PERLIO = 0;
eval { require PerlIO::encoding };
unless ($@) {
    $HAS_PERLIO = ( PerlIO::encoding->VERSION >= 0.02 );
}

sub _exception {
    my $name = shift;
    $] > 5.008 and return 0;    # 5.8.1 or higher then no
    my %utfs = map { $_ => 1 }
      qw(utf8 UCS-2BE UCS-2LE UTF-16 UTF-16BE UTF-16LE
      UTF-32 UTF-32BE UTF-32LE);
    $utfs{$name} or return 0;    # UTFs or no
    require Config;
    Config->import();
    our %Config;
    return $Config{perl_patchlevel} ? 0 : 1    # maintperl then no
}

sub in_locale { $^H & ( $locale::hint_bits || 0 ) }

sub _get_locale_encoding {
    my $locale_encoding;

    # I18N::Langinfo isn't available everywhere
    eval {
        require I18N::Langinfo;
        I18N::Langinfo->import(qw(langinfo CODESET));
        $locale_encoding = langinfo( CODESET() );
    };

    my $country_language;

    no warnings 'uninitialized';

    if ( (not $locale_encoding) && in_locale() ) {
        if ( $ENV{LC_ALL} =~ /^([^.]+)\.([^.@]+)(@.*)?$/ ) {
            ( $country_language, $locale_encoding ) = ( $1, $2 );
        }
        elsif ( $ENV{LANG} =~ /^([^.]+)\.([^.@]+)(@.*)?$/ ) {
            ( $country_language, $locale_encoding ) = ( $1, $2 );
        }

        # LANGUAGE affects only LC_MESSAGES only on glibc
    }
    elsif ( not $locale_encoding ) {
        if (   $ENV{LC_ALL} =~ /\butf-?8\b/i
            || $ENV{LANG} =~ /\butf-?8\b/i )
        {
            $locale_encoding = 'utf8';
        }

        # Could do more heuristics based on the country and language
        # parts of LC_ALL and LANG (the parts before the dot (if any)),
        # since we have Locale::Country and Locale::Language available.
        # TODO: get a database of Language -> Encoding mappings
        # (the Estonian database at http://www.eki.ee/letter/
        # would be excellent!) --jhi
    }
    if (   defined $locale_encoding
        && lc($locale_encoding) eq 'euc'
        && defined $country_language )
    {
        if ( $country_language =~ /^ja_JP|japan(?:ese)?$/i ) {
            $locale_encoding = 'euc-jp';
        }
        elsif ( $country_language =~ /^ko_KR|korean?$/i ) {
            $locale_encoding = 'euc-kr';
        }
        elsif ( $country_language =~ /^zh_CN|chin(?:a|ese)$/i ) {
            $locale_encoding = 'euc-cn';
        }
        elsif ( $country_language =~ /^zh_TW|taiwan(?:ese)?$/i ) {
            $locale_encoding = 'euc-tw';
        }
        else {
            require Carp;
            Carp::croak(
                "encoding: Locale encoding '$locale_encoding' too ambiguous"
            );
        }
    }

    return $locale_encoding;
}

sub import {
    if ($] >= 5.017) {
	warnings::warnif("deprecated",
			 "Use of the encoding pragma is deprecated")
    }
    my $class = shift;
    my $name  = shift;
    if (!$name){
	require Carp;
        Carp::croak("encoding: no encoding specified.");
    }
    if ( $name eq ':_get_locale_encoding' ) {    # used by lib/open.pm
        my $caller = caller();
        {
            no strict 'refs';
            *{"${caller}::_get_locale_encoding"} = \&_get_locale_encoding;
        }
        return;
    }
    $name = _get_locale_encoding() if $name eq ':locale';
    my %arg = @_;
    $name = $ENV{PERL_ENCODING} unless defined $name;
    my $enc = find_encoding($name);
    unless ( defined $enc ) {
        require Carp;
        Carp::croak("encoding: Unknown encoding '$name'");
    }
    $name = $enc->name;    # canonize
    unless ( $arg{Filter} ) {
        DEBUG and warn "_exception($name) = ", _exception($name);
        _exception($name) or ${^ENCODING} = $enc;
        $HAS_PERLIO or return 1;
    }
    else {
        defined( ${^ENCODING} ) and undef ${^ENCODING};

        # implicitly 'use utf8'
        require utf8;      # to fetch $utf8::hint_bits;
        $^H |= $utf8::hint_bits;
        eval {
            require Filter::Util::Call;
            Filter::Util::Call->import;
            filter_add(
                sub {
                    my $status = filter_read();
                    if ( $status > 0 ) {
                        $_ = $enc->decode( $_, 1 );
                        DEBUG and warn $_;
                    }
                    $status;
                }
            );
        };
        $@ eq '' and DEBUG and warn "Filter installed";
    }
    defined ${^UNICODE} and ${^UNICODE} != 0 and return 1;
    for my $h (qw(STDIN STDOUT)) {
        if ( $arg{$h} ) {
            unless ( defined find_encoding( $arg{$h} ) ) {
                require Carp;
                Carp::croak(
                    "encoding: Unknown encoding for $h, '$arg{$h}'");
            }
            eval { binmode( $h, ":raw :encoding($arg{$h})" ) };
        }
        else {
            unless ( exists $arg{$h} ) {
                eval {
                    no warnings 'uninitialized';
                    binmode( $h, ":raw :encoding($name)" );
                };
            }
        }
        if ($@) {
            require Carp;
            Carp::croak($@);
        }
    }
    return 1;    # I doubt if we need it, though
}

sub unimport {
    no warnings;
    undef ${^ENCODING};
    if ($HAS_PERLIO) {
        binmode( STDIN,  ":raw" );
        binmode( STDOUT, ":raw" );
    }
    else {
        binmode(STDIN);
        binmode(STDOUT);
    }
    if ( $INC{"Filter/Util/Call.pm"} ) {
        eval { filter_del() };
    }
}

1;
__END__

