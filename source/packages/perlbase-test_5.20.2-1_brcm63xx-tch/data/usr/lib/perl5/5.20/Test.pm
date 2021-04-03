
require 5.004;
package Test;

use strict;

use Carp;
use vars (qw($VERSION @ISA @EXPORT @EXPORT_OK $ntest $TestLevel), #public-ish
          qw($TESTOUT $TESTERR %Program_Lines $told_about_diff
             $ONFAIL %todo %history $planned @FAILDETAIL) #private-ish
         );

sub _reset_globals {
    %todo       = ();
    %history    = ();
    @FAILDETAIL = ();
    $ntest      = 1;
    $TestLevel  = 0;		# how many extra stack frames to skip
    $planned    = 0;
}

$VERSION = '1.26';
require Exporter;
@ISA=('Exporter');

@EXPORT    = qw(&plan &ok &skip);
@EXPORT_OK = qw($ntest $TESTOUT $TESTERR);

$|=1;
$TESTOUT = *STDOUT{IO};
$TESTERR = *STDERR{IO};

$ENV{REGRESSION_TEST} = $0;



sub plan {
    croak "Test::plan(%args): odd number of arguments" if @_ & 1;
    croak "Test::plan(): should not be called more than once" if $planned;

    local($\, $,);   # guard against -l and other things that screw with
                     # print

    _reset_globals();

    _read_program( (caller)[1] );

    my $max=0;
    while (@_) {
	my ($k,$v) = splice(@_, 0, 2);
	if ($k =~ /^test(s)?$/) { $max = $v; }
	elsif ($k eq 'todo' or
	       $k eq 'failok') { for (@$v) { $todo{$_}=1; }; }
	elsif ($k eq 'onfail') {
	    ref $v eq 'CODE' or croak "Test::plan(onfail => $v): must be CODE";
	    $ONFAIL = $v;
	}
	else { carp "Test::plan(): skipping unrecognized directive '$k'" }
    }
    my @todo = sort { $a <=> $b } keys %todo;
    if (@todo) {
	print $TESTOUT "1..$max todo ".join(' ', @todo).";\n";
    } else {
	print $TESTOUT "1..$max\n";
    }
    ++$planned;
    print $TESTOUT "# Running under perl version $] for $^O",
      (chr(65) eq 'A') ? "\n" : " in a non-ASCII world\n";

    print $TESTOUT "# Win32::BuildNumber ", &Win32::BuildNumber(), "\n"
      if defined(&Win32::BuildNumber) and defined &Win32::BuildNumber();

    print $TESTOUT "# MacPerl version $MacPerl::Version\n"
      if defined $MacPerl::Version;

    printf $TESTOUT
      "# Current time local: %s\n# Current time GMT:   %s\n",
      scalar(localtime($^T)), scalar(gmtime($^T));

    print $TESTOUT "# Using Test.pm version $VERSION\n";

    # Retval never used:
    return undef;
}

sub _read_program {
  my($file) = shift;
  return unless defined $file and length $file
    and -e $file and -f _ and -r _;
  open(SOURCEFILE, "<$file") || return;
  $Program_Lines{$file} = [<SOURCEFILE>];
  close(SOURCEFILE);

  foreach my $x (@{$Program_Lines{$file}})
   { $x =~ tr/\cm\cj\n\r//d }

  unshift @{$Program_Lines{$file}}, '';
  return 1;
}


sub _to_value {
    my ($v) = @_;
    return ref $v eq 'CODE' ? $v->() : $v;
}

sub _quote {
    my $str = $_[0];
    return "<UNDEF>" unless defined $str;
    $str =~ s/\\/\\\\/g;
    $str =~ s/"/\\"/g;
    $str =~ s/\a/\\a/g;
    $str =~ s/[\b]/\\b/g;
    $str =~ s/\e/\\e/g;
    $str =~ s/\f/\\f/g;
    $str =~ s/\n/\\n/g;
    $str =~ s/\r/\\r/g;
    $str =~ s/\t/\\t/g;
    $str =~ s/([\0-\037])(?!\d)/sprintf('\\%o',ord($1))/eg;
    $str =~ s/([\0-\037\177-\377])/sprintf('\\x%02X',ord($1))/eg;
    $str =~ s/([^\0-\176])/sprintf('\\x{%X}',ord($1))/eg;
    #if( $_[1] ) {
    #  substr( $str , 218-3 ) = "..."
    #   if length($str) >= 218 and !$ENV{PERL_TEST_NO_TRUNC};
    #}
    return qq("$str");
}




sub ok ($;$$) {
    croak "ok: plan before you test!" if !$planned;

    local($\,$,);   # guard against -l and other things that screw with
                    # print

    my ($pkg,$file,$line) = caller($TestLevel);
    my $repetition = ++$history{"$file:$line"};
    my $context = ("$file at line $line".
		   ($repetition > 1 ? " fail \#$repetition" : ''));

    # Are we comparing two values?
    my $compare = 0;

    my $ok=0;
    my $result = _to_value(shift);
    my ($expected, $isregex, $regex);
    if (@_ == 0) {
	$ok = $result;
    } else {
        $compare = 1;
	$expected = _to_value(shift);
	if (!defined $expected) {
	    $ok = !defined $result;
	} elsif (!defined $result) {
	    $ok = 0;
	} elsif (ref($expected) eq 'Regexp') {
	    $ok = $result =~ /$expected/;
            $regex = $expected;
	} elsif (($regex) = ($expected =~ m,^ / (.+) / $,sx) or
	    (undef, $regex) = ($expected =~ m,^ m([^\w\s]) (.+) \1 $,sx)) {
	    $ok = $result =~ /$regex/;
	} else {
	    $ok = $result eq $expected;
	}
    }
    my $todo = $todo{$ntest};
    if ($todo and $ok) {
	$context .= ' TODO?!' if $todo;
	print $TESTOUT "ok $ntest # ($context)\n";
    } else {
        # Issuing two seperate prints() causes problems on VMS.
        if (!$ok) {
            print $TESTOUT "not ok $ntest\n";
        }
	else {
            print $TESTOUT "ok $ntest\n";
        }

        $ok or _complain($result, $expected,
        {
          'repetition' => $repetition, 'package' => $pkg,
          'result' => $result, 'todo' => $todo,
          'file' => $file, 'line' => $line,
          'context' => $context, 'compare' => $compare,
          @_ ? ('diagnostic' =>  _to_value(shift)) : (),
        });

    }
    ++ $ntest;
    $ok;
}


sub _complain {
    my($result, $expected, $detail) = @_;
    $$detail{expected} = $expected if defined $expected;

    # Get the user's diagnostic, protecting against multi-line
    # diagnostics.
    my $diag = $$detail{diagnostic};
    $diag =~ s/\n/\n#/g if defined $diag;

    $$detail{context} .= ' *TODO*' if $$detail{todo};
    if (!$$detail{compare}) {
        if (!$diag) {
            print $TESTERR "# Failed test $ntest in $$detail{context}\n";
        } else {
            print $TESTERR "# Failed test $ntest in $$detail{context}: $diag\n";
        }
    } else {
        my $prefix = "Test $ntest";

        print $TESTERR "# $prefix got: " . _quote($result) .
                       " ($$detail{context})\n";
        $prefix = ' ' x (length($prefix) - 5);
        my $expected_quoted = (defined $$detail{regex})
         ?  'qr{'.($$detail{regex}).'}'  :  _quote($expected);

        print $TESTERR "# $prefix Expected: $expected_quoted",
           $diag ? " ($diag)" : (), "\n";

        _diff_complain( $result, $expected, $detail, $prefix )
          if defined($expected) and 2 < ($expected =~ tr/\n//);
    }

    if(defined $Program_Lines{ $$detail{file} }[ $$detail{line} ]) {
        print $TESTERR
          "#  $$detail{file} line $$detail{line} is: $Program_Lines{ $$detail{file} }[ $$detail{line} ]\n"
         if $Program_Lines{ $$detail{file} }[ $$detail{line} ]
          =~ m/[^\s\#\(\)\{\}\[\]\;]/;  # Otherwise it's uninformative

        undef $Program_Lines{ $$detail{file} }[ $$detail{line} ];
         # So we won't repeat it.
    }

    push @FAILDETAIL, $detail;
    return;
}



sub _diff_complain {
    my($result, $expected, $detail, $prefix) = @_;
    return _diff_complain_external(@_) if $ENV{PERL_TEST_DIFF};
    return _diff_complain_algdiff(@_)
     if eval { require Algorithm::Diff; Algorithm::Diff->VERSION(1.15); 1; };

    $told_about_diff++ or print $TESTERR <<"EOT";
EOT
    ;
    return;
}



sub _diff_complain_external {
    my($result, $expected, $detail, $prefix) = @_;
    my $diff = $ENV{PERL_TEST_DIFF} || die "WHAAAA?";

    require File::Temp;
    my($got_fh, $got_filename) = File::Temp::tempfile("test-got-XXXXX");
    my($exp_fh, $exp_filename) = File::Temp::tempfile("test-exp-XXXXX");
    unless ($got_fh && $exp_fh) {
      warn "Can't get tempfiles";
      return;
    }

    print $got_fh $result;
    print $exp_fh $expected;
    if (close($got_fh) && close($exp_fh)) {
        my $diff_cmd = "$diff $exp_filename $got_filename";
        print $TESTERR "#\n# $prefix $diff_cmd\n";
        if (open(DIFF, "$diff_cmd |")) {
            local $_;
            while (<DIFF>) {
                print $TESTERR "# $prefix $_";
            }
            close(DIFF);
        }
        else {
            warn "Can't run diff: $!";
        }
    } else {
        warn "Can't write to tempfiles: $!";
    }
    unlink($got_filename);
    unlink($exp_filename);
    return;
}



sub _diff_complain_algdiff {
    my($result, $expected, $detail, $prefix) = @_;

    my @got = split(/^/, $result);
    my @exp = split(/^/, $expected);

    my $diff_kind;
    my @diff_lines;

    my $diff_flush = sub {
        return unless $diff_kind;

        my $count_lines = @diff_lines;
        my $s = $count_lines == 1 ? "" : "s";
        my $first_line = $diff_lines[0][0] + 1;

        print $TESTERR "# $prefix ";
        if ($diff_kind eq "GOT") {
            print $TESTERR "Got $count_lines extra line$s at line $first_line:\n";
            for my $i (@diff_lines) {
                print $TESTERR "# $prefix  + " . _quote($got[$i->[0]]) . "\n";
            }
        } elsif ($diff_kind eq "EXP") {
            if ($count_lines > 1) {
                my $last_line = $diff_lines[-1][0] + 1;
                print $TESTERR "Lines $first_line-$last_line are";
            }
            else {
                print $TESTERR "Line $first_line is";
            }
            print $TESTERR " missing:\n";
            for my $i (@diff_lines) {
                print $TESTERR "# $prefix  - " . _quote($exp[$i->[1]]) . "\n";
            }
        } elsif ($diff_kind eq "CH") {
            if ($count_lines > 1) {
                my $last_line = $diff_lines[-1][0] + 1;
                print $TESTERR "Lines $first_line-$last_line are";
            }
            else {
                print $TESTERR "Line $first_line is";
            }
            print $TESTERR " changed:\n";
            for my $i (@diff_lines) {
                print $TESTERR "# $prefix  - " . _quote($exp[$i->[1]]) . "\n";
                print $TESTERR "# $prefix  + " . _quote($got[$i->[0]]) . "\n";
            }
        }

        # reset
        $diff_kind = undef;
        @diff_lines = ();
    };

    my $diff_collect = sub {
        my $kind = shift;
        &$diff_flush() if $diff_kind && $diff_kind ne $kind;
        $diff_kind = $kind;
        push(@diff_lines, [@_]);
    };


    Algorithm::Diff::traverse_balanced(
        \@got, \@exp,
        {
            DISCARD_A => sub { &$diff_collect("GOT", @_) },
            DISCARD_B => sub { &$diff_collect("EXP", @_) },
            CHANGE    => sub { &$diff_collect("CH",  @_) },
            MATCH     => sub { &$diff_flush() },
        },
    );
    &$diff_flush();

    return;
}







sub skip ($;$$$) {
    local($\, $,);   # guard against -l and other things that screw with
                     # print

    my $whyskip = _to_value(shift);
    if (!@_ or $whyskip) {
	$whyskip = '' if $whyskip =~ m/^\d+$/;
        $whyskip =~ s/^[Ss]kip(?:\s+|$)//;  # backwards compatibility, old
                                            # versions required the reason
                                            # to start with 'skip'
        # We print in one shot for VMSy reasons.
        my $ok = "ok $ntest # skip";
        $ok .= " $whyskip" if length $whyskip;
        $ok .= "\n";
        print $TESTOUT $ok;
        ++ $ntest;
        return 1;
    } else {
        # backwards compatibility (I think).  skip() used to be
        # called like ok(), which is weird.  I haven't decided what to do with
        # this yet.

	local($TestLevel) = $TestLevel+1;  #to ignore this stack frame
        return &ok(@_);
    }
}


END {
    $ONFAIL->(\@FAILDETAIL) if @FAILDETAIL && $ONFAIL;
}

1;
__END__


