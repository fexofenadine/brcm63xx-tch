package HTML::Filter;

use strict;
use vars qw(@ISA $VERSION);

require HTML::Parser;
@ISA=qw(HTML::Parser);

$VERSION = "3.57";

sub declaration { $_[0]->output("<!$_[1]>")     }
sub process     { $_[0]->output($_[2])          }
sub comment     { $_[0]->output("<!--$_[1]-->") }
sub start       { $_[0]->output($_[4])          }
sub end         { $_[0]->output($_[2])          }
sub text        { $_[0]->output($_[1])          }

sub output      { print $_[1] }

1;

__END__

