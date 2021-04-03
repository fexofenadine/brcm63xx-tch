package charnames;
use strict;
use warnings;
our $VERSION = '1.40';
use unicore::Name;    # mktables-generated algorithmically-defined names
use _charnames ();    # The submodule for this where most of the work gets done

use bytes ();          # for $bytes::hint_bits
use re "/aa";          # Everything in here should be ASCII


$Carp::Internal{ (__PACKAGE__) } = 1;

sub import
{
  shift; ## ignore class name
  _charnames->import(@_);
}

my %viacode;

sub viacode {
  return _charnames::viacode(@_);
}

sub vianame
{
  if (@_ != 1) {
    _charnames::carp "charnames::vianame() expects one name argument";
    return ()
  }

  # Looks up the character name and returns its ordinal if
  # found, undef otherwise.

  my $arg = shift;

  if ($arg =~ /^U\+([0-9a-fA-F]+)$/) {

    # khw claims that this is poor interface design.  The function should
    # return either a an ord or a chr for all inputs; not be bipolar.  But
    # can't change it because of backward compatibility.  New code can use
    # string_vianame() instead.
    my $ord = CORE::hex $1;
    return chr $ord if $ord <= 255 || ! ((caller 0)[8] & $bytes::hint_bits);
    _charnames::carp _charnames::not_legal_use_bytes_msg($arg, chr $ord);
    return;
  }

  # The first 1 arg means wants an ord returned; the second that we are in
  # runtime, and this is the first level routine called from the user
  return _charnames::lookup_name($arg, 1, 1);
} # vianame

sub string_vianame {

  # Looks up the character name and returns its string representation if
  # found, undef otherwise.

  if (@_ != 1) {
    _charnames::carp "charnames::string_vianame() expects one name argument";
    return;
  }

  my $arg = shift;

  if ($arg =~ /^U\+([0-9a-fA-F]+)$/) {

    my $ord = CORE::hex $1;
    return chr $ord if $ord <= 255 || ! ((caller 0)[8] & $bytes::hint_bits);

    _charnames::carp _charnames::not_legal_use_bytes_msg($arg, chr $ord);
    return;
  }

  # The 0 arg means wants a string returned; the 1 arg means that we are in
  # runtime, and this is the first level routine called from the user
  return _charnames::lookup_name($arg, 0, 1);
} # string_vianame

1;
__END__


