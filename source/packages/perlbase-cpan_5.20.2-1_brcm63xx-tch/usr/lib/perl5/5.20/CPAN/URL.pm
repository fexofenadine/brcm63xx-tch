package CPAN::URL;
use overload '""' => "as_string", fallback => 1;

use vars qw(
            $VERSION
);
$VERSION = "5.5";

sub new {
    my($class,%args) = @_;
    bless {
           %args
          }, $class;
}
sub as_string {
    my($self) = @_;
    $self->text;
}
sub text {
    my($self,$set) = @_;
    if (defined $set) {
        $self->{TEXT} = $set;
    }
    $self->{TEXT};
}

1;
