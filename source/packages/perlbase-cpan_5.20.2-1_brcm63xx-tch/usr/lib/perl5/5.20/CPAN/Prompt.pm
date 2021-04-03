package CPAN::Prompt;
use overload '""' => "as_string";
use vars qw($prompt);
use vars qw(
            $VERSION
);
$VERSION = "5.5";


$prompt = "cpan> ";
$CPAN::CurrentCommandId ||= 0;
sub new {
    bless {}, shift;
}
sub as_string {
    my $word = "cpan";
    unless ($CPAN::META->{LOCK}) {
        $word = "nolock_cpan";
    }
    if ($CPAN::Config->{commandnumber_in_prompt}) {
        sprintf "$word\[%d]> ", $CPAN::CurrentCommandId;
    } else {
        "$word> ";
    }
}

1;
