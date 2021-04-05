package HTML::LinkExtor;

require HTML::Parser;
@ISA = qw(HTML::Parser);
$VERSION = "3.69";


use strict;
use HTML::Tagset ();

use vars qw(%LINK_ELEMENT);
*LINK_ELEMENT = \%HTML::Tagset::linkElements;


sub new
{
    my($class, $cb, $base) = @_;
    my $self = $class->SUPER::new(
                    start_h => ["_start_tag", "self,tagname,attr"],
		    report_tags => [keys %HTML::Tagset::linkElements],
	       );
    $self->{extractlink_cb} = $cb;
    if ($base) {
	require URI;
	$self->{extractlink_base} = URI->new($base);
    }
    $self;
}

sub _start_tag
{
    my($self, $tag, $attr) = @_;

    my $base = $self->{extractlink_base};
    my $links = $HTML::Tagset::linkElements{$tag};
    $links = [$links] unless ref $links;

    my @links;
    my $a;
    for $a (@$links) {
	next unless exists $attr->{$a};
	(my $link = $attr->{$a}) =~ s/^\s+//; $link =~ s/\s+$//; # HTML5
	push(@links, $a, $base ? URI->new($link, $base)->abs($base) : $link);
    }
    return unless @links;
    $self->_found_link($tag, @links);
}

sub _found_link
{
    my $self = shift;
    my $cb = $self->{extractlink_cb};
    if ($cb) {
	&$cb(@_);
    } else {
	push(@{$self->{'links'}}, [@_]);
    }
}


sub links
{
    my $self = shift;
    exists($self->{'links'}) ? @{delete $self->{'links'}} : ();
}

sub parse_file
{
    my $self = shift;
    delete $self->{'links'};
    $self->SUPER::parse_file(@_);
}


1;
