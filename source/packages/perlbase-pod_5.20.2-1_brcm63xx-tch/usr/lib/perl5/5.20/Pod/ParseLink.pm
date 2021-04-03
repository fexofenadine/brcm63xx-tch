

package Pod::ParseLink;

require 5.004;

use strict;
use vars qw(@EXPORT @ISA $VERSION);

use Exporter;
@ISA    = qw(Exporter);
@EXPORT = qw(parselink);

$VERSION = '1.10';


sub _parse_section {
    my ($link) = @_;
    $link =~ s/^\s+//;
    $link =~ s/\s+$//;

    # If the whole link is enclosed in quotes, interpret it all as a section
    # even if it contains a slash.
    return (undef, $1) if ($link =~ /^"\s*(.*?)\s*"$/);

    # Split into page and section on slash, and then clean up quoting in the
    # section.  If there is no section and the name contains spaces, also
    # guess that it's an old section link.
    my ($page, $section) = split (/\s*\/\s*/, $link, 2);
    $section =~ s/^"\s*(.*?)\s*"$/$1/ if $section;
    if ($page && $page =~ / / && !defined ($section)) {
        $section = $page;
        $page = undef;
    } else {
        $page = undef unless $page;
        $section = undef unless $section;
    }
    return ($page, $section);
}

sub _infer_text {
    my ($page, $section) = @_;
    my $inferred;
    if ($page && !$section) {
        $inferred = $page;
    } elsif (!$page && $section) {
        $inferred = '"' . $section . '"';
    } elsif ($page && $section) {
        $inferred = '"' . $section . '" in ' . $page;
    }
    return $inferred;
}

sub parselink {
    my ($link) = @_;
    $link =~ s/\s+/ /g;
    my $text;
    if ($link =~ /\|/) {
        ($text, $link) = split (/\|/, $link, 2);
    }
    if ($link =~ /\A\w+:[^:\s]\S*\Z/) {
        my $inferred;
        if (defined ($text) && length ($text) > 0) {
            return ($text, $text, $link, undef, 'url');
        } else {
            return ($text, $link, $link, undef, 'url');
        }
    } else {
        my ($name, $section) = _parse_section ($link);
        my $inferred;
        if (defined ($text) && length ($text) > 0) {
            $inferred = $text;
        } else {
            $inferred = _infer_text ($name, $section);
        }
        my $type = ($name && $name =~ /\(\S*\)/) ? 'man' : 'pod';
        return ($text, $inferred, $name, $section, $type);
    }
}


1;
__END__

