package WWW::Mechanize::Image;

use strict;
use warnings;


sub new {
    my $class = shift;
    my $parms = shift || {};

    my $self = bless {}, $class;

    for my $parm ( qw( url base tag height width alt name ) ) {
        # Check for what we passed in, not whether it's defined
        $self->{$parm} = $parms->{$parm} if exists $parms->{$parm};
    }

    # url and tag are always required
    for ( qw( url tag ) ) {
        exists $self->{$_} or die "WWW::Mechanize::Image->new must have a $_ argument";
    }

    return $self;
}


sub url     { return ($_[0])->{url}; }
sub base    { return ($_[0])->{base}; }
sub name    { return ($_[0])->{name}; }
sub tag     { return ($_[0])->{tag}; }
sub height  { return ($_[0])->{height}; }
sub width   { return ($_[0])->{width}; }
sub alt     { return ($_[0])->{alt}; }


sub URI {
    my $self = shift;

    require URI::URL;
    my $URI = URI::URL->new( $self->url, $self->base );

    return $URI;
}


sub url_abs {
    my $self = shift;

    return $self->URI->abs;
}


1;
