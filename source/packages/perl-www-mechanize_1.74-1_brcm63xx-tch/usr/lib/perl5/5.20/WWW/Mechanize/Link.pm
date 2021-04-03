package WWW::Mechanize::Link;

use strict;
use warnings;


sub new {
    my $class = shift;

    my $self;

    # The order of the first four must stay as they are for
    # compatibility with older code.
    if ( ref $_[0] eq 'HASH' ) {
        $self = [ @{$_[0]}{ qw( url text name tag base attrs ) } ];
    }
    else {
        $self = [ @_ ];
    }

    return bless $self, $class;
}


sub url   { return ($_[0])->[0]; }
sub text  { return ($_[0])->[1]; }
sub name  { return ($_[0])->[2]; }
sub tag   { return ($_[0])->[3]; }
sub base  { return ($_[0])->[4]; }
sub attrs { return ($_[0])->[5]; }


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
