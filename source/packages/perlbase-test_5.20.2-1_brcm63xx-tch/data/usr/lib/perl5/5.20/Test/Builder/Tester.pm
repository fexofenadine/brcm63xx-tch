package Test::Builder::Tester;

use strict;
our $VERSION = "1.23_002";

use Test::Builder 0.98;
use Symbol;
use Carp;



my $t = Test::Builder->new;


use Exporter;
our @ISA = qw(Exporter);

our @EXPORT = qw(test_out test_err test_fail test_diag test_test line_num);

sub import {
    my $class = shift;
    my(@plan) = @_;

    my $caller = caller;

    $t->exported_to($caller);
    $t->plan(@plan);

    my @imports = ();
    foreach my $idx ( 0 .. $#plan ) {
        if( $plan[$idx] eq 'import' ) {
            @imports = @{ $plan[ $idx + 1 ] };
            last;
        }
    }

    __PACKAGE__->export_to_level( 1, __PACKAGE__, @imports );
}


my $output_handle = gensym;
my $error_handle  = gensym;

my $out = tie *$output_handle, "Test::Builder::Tester::Tie", "STDOUT";
my $err = tie *$error_handle,  "Test::Builder::Tester::Tie", "STDERR";


my $testing = 0;
my $testing_num;
my $original_is_passing;

my $original_output_handle;
my $original_failure_handle;
my $original_todo_handle;

my $original_harness_env;

sub _start_testing {
    # even if we're running under Test::Harness pretend we're not
    # for now.  This needed so Test::Builder doesn't add extra spaces
    $original_harness_env = $ENV{HARNESS_ACTIVE} || 0;
    $ENV{HARNESS_ACTIVE} = 0;

    # remember what the handles were set to
    $original_output_handle  = $t->output();
    $original_failure_handle = $t->failure_output();
    $original_todo_handle    = $t->todo_output();

    # switch out to our own handles
    $t->output($output_handle);
    $t->failure_output($error_handle);
    $t->todo_output($output_handle);

    # clear the expected list
    $out->reset();
    $err->reset();

    # remember that we're testing
    $testing     = 1;
    $testing_num = $t->current_test;
    $t->current_test(0);
    $original_is_passing  = $t->is_passing;
    $t->is_passing(1);

    # look, we shouldn't do the ending stuff
    $t->no_ending(1);
}


sub test_out {
    # do we need to do any setup?
    _start_testing() unless $testing;

    $out->expect(@_);
}

sub test_err {
    # do we need to do any setup?
    _start_testing() unless $testing;

    $err->expect(@_);
}


sub test_fail {
    # do we need to do any setup?
    _start_testing() unless $testing;

    # work out what line we should be on
    my( $package, $filename, $line ) = caller;
    $line = $line + ( shift() || 0 );    # prevent warnings

    # expect that on stderr
    $err->expect("#     Failed test ($filename at line $line)");
}


sub test_diag {
    # do we need to do any setup?
    _start_testing() unless $testing;

    # expect the same thing, but prepended with "#     "
    local $_;
    $err->expect( map { "# $_" } @_ );
}


sub test_test {
    # decode the arguments as described in the pod
    my $mess;
    my %args;
    if( @_ == 1 ) {
        $mess = shift
    }
    else {
        %args = @_;
        $mess = $args{name} if exists( $args{name} );
        $mess = $args{title} if exists( $args{title} );
        $mess = $args{label} if exists( $args{label} );
    }

    # er, are we testing?
    croak "Not testing.  You must declare output with a test function first."
      unless $testing;

    # okay, reconnect the test suite back to the saved handles
    $t->output($original_output_handle);
    $t->failure_output($original_failure_handle);
    $t->todo_output($original_todo_handle);

    # restore the test no, etc, back to the original point
    $t->current_test($testing_num);
    $testing = 0;
    $t->is_passing($original_is_passing);

    # re-enable the original setting of the harness
    $ENV{HARNESS_ACTIVE} = $original_harness_env;

    # check the output we've stashed
    unless( $t->ok( ( $args{skip_out} || $out->check ) &&
                    ( $args{skip_err} || $err->check ), $mess ) 
    )
    {
        # print out the diagnostic information about why this
        # test failed

        local $_;

        $t->diag( map { "$_\n" } $out->complaint )
          unless $args{skip_out} || $out->check;

        $t->diag( map { "$_\n" } $err->complaint )
          unless $args{skip_err} || $err->check;
    }
}


sub line_num {
    my( $package, $filename, $line ) = caller;
    return $line + ( shift() || 0 );    # prevent warnings
}


my $color;

sub color {
    $color = shift if @_;
    $color;
}


1;


package Test::Builder::Tester::Tie;


sub expect {
    my $self = shift;

    my @checks = @_;
    foreach my $check (@checks) {
        $check = $self->_account_for_subtest($check);
        $check = $self->_translate_Failed_check($check);
        push @{ $self->{wanted} }, ref $check ? $check : "$check\n";
    }
}

sub _account_for_subtest {
    my( $self, $check ) = @_;

    # Since we ship with Test::Builder, calling a private method is safe...ish.
    return ref($check) ? $check : $t->_indent . $check;
}

sub _translate_Failed_check {
    my( $self, $check ) = @_;

    if( $check =~ /\A(.*)#     (Failed .*test) \((.*?) at line (\d+)\)\Z(?!\n)/ ) {
        $check = "/\Q$1\E#\\s+\Q$2\E.*?\\n?.*?\Qat $3\E line \Q$4\E.*\\n?/";
    }

    return $check;
}


sub check {
    my $self = shift;

    # turn off warnings as these might be undef
    local $^W = 0;

    my @checks = @{ $self->{wanted} };
    my $got    = $self->{got};
    foreach my $check (@checks) {
        $check = "\Q$check\E" unless( $check =~ s,^/(.*)/$,$1, or ref $check );
        return 0 unless $got =~ s/^$check//;
    }

    return length $got == 0;
}


sub complaint {
    my $self   = shift;
    my $type   = $self->type;
    my $got    = $self->got;
    my $wanted = join '', @{ $self->wanted };

    # are we running in colour mode?
    if(Test::Builder::Tester::color) {
        # get color
        eval { require Term::ANSIColor };
        unless($@) {
            # colours

            my $green = Term::ANSIColor::color("black") . Term::ANSIColor::color("on_green");
            my $red   = Term::ANSIColor::color("black") . Term::ANSIColor::color("on_red");
            my $reset = Term::ANSIColor::color("reset");

            # work out where the two strings start to differ
            my $char = 0;
            $char++ while substr( $got, $char, 1 ) eq substr( $wanted, $char, 1 );

            # get the start string and the two end strings
            my $start = $green . substr( $wanted, 0, $char );
            my $gotend    = $red . substr( $got,    $char ) . $reset;
            my $wantedend = $red . substr( $wanted, $char ) . $reset;

            # make the start turn green on and off
            $start =~ s/\n/$reset\n$green/g;

            # make the ends turn red on and off
            $gotend    =~ s/\n/$reset\n$red/g;
            $wantedend =~ s/\n/$reset\n$red/g;

            # rebuild the strings
            $got    = $start . $gotend;
            $wanted = $start . $wantedend;
        }
    }

    return "$type is:\n" . "$got\nnot:\n$wanted\nas expected";
}


sub reset {
    my $self = shift;
    %$self = (
        type   => $self->{type},
        got    => '',
        wanted => [],
    );
}

sub got {
    my $self = shift;
    return $self->{got};
}

sub wanted {
    my $self = shift;
    return $self->{wanted};
}

sub type {
    my $self = shift;
    return $self->{type};
}


sub PRINT {
    my $self = shift;
    $self->{got} .= join '', @_;
}

sub TIEHANDLE {
    my( $class, $type ) = @_;

    my $self = bless { type => $type }, $class;

    $self->reset;

    return $self;
}

sub READ     { }
sub READLINE { }
sub GETC     { }
sub FILENO   { }

1;
