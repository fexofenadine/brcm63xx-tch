use strict;
package CPAN;
$CPAN::VERSION = '2.05';
$CPAN::VERSION =~ s/_//;

use File::Spec ();
BEGIN {
    if (File::Spec->can("rel2abs")) {
        for my $inc (@INC) {
            $inc = File::Spec->rel2abs($inc) unless ref $inc;
        }
    }
}
use CPAN::Author;
use CPAN::HandleConfig;
use CPAN::Version;
use CPAN::Bundle;
use CPAN::CacheMgr;
use CPAN::Complete;
use CPAN::Debug;
use CPAN::Distribution;
use CPAN::Distrostatus;
use CPAN::FTP;
use CPAN::Index 1.93; # https://rt.cpan.org/Ticket/Display.html?id=43349
use CPAN::InfoObj;
use CPAN::Module;
use CPAN::Prompt;
use CPAN::URL;
use CPAN::Queue;
use CPAN::Tarzip;
use CPAN::DeferredCode;
use CPAN::Shell;
use CPAN::LWP::UserAgent;
use CPAN::Exception::RecursiveDependency;
use CPAN::Exception::yaml_not_installed;
use CPAN::Exception::yaml_process_error;

use Carp ();
use Config ();
use Cwd qw(chdir);
use DirHandle ();
use Exporter ();
use ExtUtils::MakeMaker qw(prompt); # for some unknown reason,
                                    # 5.005_04 does not work without
                                    # this
use File::Basename ();
use File::Copy ();
use File::Find;
use File::Path ();
use FileHandle ();
use Fcntl qw(:flock);
use Safe ();
use Sys::Hostname qw(hostname);
use Text::ParseWords ();
use Text::Wrap ();

sub find_perl ();
sub anycwd ();
sub _uniq;

no lib ".";

require Mac::BuildTools if $^O eq 'MacOS';
if ($ENV{PERL5_CPAN_IS_RUNNING} && $$ != $ENV{PERL5_CPAN_IS_RUNNING}) {
    $ENV{PERL5_CPAN_IS_RUNNING_IN_RECURSION} ||= $ENV{PERL5_CPAN_IS_RUNNING};
    my @rec = _uniq split(/,/, $ENV{PERL5_CPAN_IS_RUNNING_IN_RECURSION}), $$;
    $ENV{PERL5_CPAN_IS_RUNNING_IN_RECURSION} = join ",", @rec;
    # warn "# Note: Recursive call of CPAN.pm detected\n";
    my $w = sprintf "# Note: CPAN.pm is running in process %d now", pop @rec;
    my %sleep = (
                 5 => 30,
                 6 => 60,
                 7 => 120,
                );
    my $sleep = @rec > 7 ? 300 : ($sleep{scalar @rec}||0);
    my $verbose = @rec >= 4;
    while (@rec) {
        $w .= sprintf " which has been called by process %d", pop @rec;
    }
    if ($sleep) {
        $w .= ".\n\n# Sleeping $sleep seconds to protect other processes\n";
    }
    if ($verbose) {
        warn $w;
    }
    local $| = 1;
    while ($sleep > 0) {
        printf "\r#%5d", --$sleep;
        sleep 1;
    }
    print "\n";
}
$ENV{PERL5_CPAN_IS_RUNNING}=$$;
$ENV{PERL5_CPANPLUS_IS_RUNNING}=$$; # https://rt.cpan.org/Ticket/Display.html?id=23735

END { $CPAN::End++; &cleanup; }

$CPAN::Signal ||= 0;
$CPAN::Frontend ||= "CPAN::Shell";
unless (@CPAN::Defaultsites) {
    @CPAN::Defaultsites = map {
        CPAN::URL->new(TEXT => $_, FROM => "DEF")
    }
        "http://www.perl.org/CPAN/",
        "ftp://ftp.perl.org/pub/CPAN/";
}
$CPAN::iCwd ||= CPAN::anycwd();
$CPAN::Perl ||= CPAN::find_perl();
$CPAN::Defaultdocs ||= "http://search.cpan.org/perldoc?";
$CPAN::Defaultrecent ||= "http://search.cpan.org/uploads.rdf";
$CPAN::Defaultrecent ||= "http://cpan.uwinnipeg.ca/htdocs/cpan.xml";

use vars qw(
            $AUTOLOAD
            $Be_Silent
            $CONFIG_DIRTY
            $Defaultdocs
            $Echo_readline
            $Frontend
            $GOTOSHELL
            $HAS_USABLE
            $Have_warned
            $MAX_RECURSION
            $META
            $RUN_DEGRADED
            $Signal
            $SQLite
            $Suppress_readline
            $VERSION
            $autoload_recursion
            $term
            @Defaultsites
            @EXPORT
           );

$MAX_RECURSION = 32;

@CPAN::ISA = qw(CPAN::Debug Exporter);

@EXPORT = qw(
             autobundle
             bundle
             clean
             cvs_import
             expand
             force
             fforce
             get
             install
             install_tested
             is_tested
             make
             mkmyconfig
             notest
             perldoc
             readme
             recent
             recompile
             report
             shell
             smoke
             test
             upgrade
            );

sub soft_chdir_with_alternatives ($);

{
    $autoload_recursion ||= 0;

    #-> sub CPAN::AUTOLOAD ;
    sub AUTOLOAD { ## no critic
        $autoload_recursion++;
        my($l) = $AUTOLOAD;
        $l =~ s/.*:://;
        if ($CPAN::Signal) {
            warn "Refusing to autoload '$l' while signal pending";
            $autoload_recursion--;
            return;
        }
        if ($autoload_recursion > 1) {
            my $fullcommand = join " ", map { "'$_'" } $l, @_;
            warn "Refusing to autoload $fullcommand in recursion\n";
            $autoload_recursion--;
            return;
        }
        my(%export);
        @export{@EXPORT} = '';
        CPAN::HandleConfig->load unless $CPAN::Config_loaded++;
        if (exists $export{$l}) {
            CPAN::Shell->$l(@_);
        } else {
            die(qq{Unknown CPAN command "$AUTOLOAD". }.
                qq{Type ? for help.\n});
        }
        $autoload_recursion--;
    }
}

{
    my $x = *SAVEOUT; # avoid warning
    open($x,">&STDOUT") or die "dup failed";
    my $redir = 0;
    sub _redirect(@) {
        #die if $redir;
        local $_;
        push(@_,undef);
        while(defined($_=shift)) {
            if (s/^\s*>//){
                my ($m) = s/^>// ? ">" : "";
                s/\s+//;
                $_=shift unless length;
                die "no dest" unless defined;
                open(STDOUT,">$m$_") or die "open:$_:$!\n";
                $redir=1;
            } elsif ( s/^\s*\|\s*// ) {
                my $pipe="| $_";
                while(defined($_[0])){
                    $pipe .= ' ' . shift;
                }
                open(STDOUT,$pipe) or die "open:$pipe:$!\n";
                $redir=1;
            } else {
                push(@_,$_);
            }
        }
        return @_;
    }
    sub _unredirect {
        return unless $redir;
        $redir = 0;
        ## redirect: unredirect and propagate errors.  explicit close to wait for pipe.
        close(STDOUT);
        open(STDOUT,">&SAVEOUT");
        die "$@" if "$@";
        ## redirect: done
    }
}

sub _uniq {
    my(@list) = @_;
    my %seen;
    return grep { !$seen{$_}++ } @list;
}

sub shell {
    my($self) = @_;
    $Suppress_readline = ! -t STDIN unless defined $Suppress_readline;
    CPAN::HandleConfig->load unless $CPAN::Config_loaded++;

    my $oprompt = shift || CPAN::Prompt->new;
    my $prompt = $oprompt;
    my $commandline = shift || "";
    $CPAN::CurrentCommandId ||= 1;

    local($^W) = 1;
    unless ($Suppress_readline) {
        require Term::ReadLine;
        if (! $term
            or
            $term->ReadLine eq "Term::ReadLine::Stub"
           ) {
            $term = Term::ReadLine->new('CPAN Monitor');
        }
        if ($term->ReadLine eq "Term::ReadLine::Gnu") {
            my $attribs = $term->Attribs;
            $attribs->{attempted_completion_function} = sub {
                &CPAN::Complete::gnu_cpl;
            }
        } else {
            $readline::rl_completion_function =
                $readline::rl_completion_function = 'CPAN::Complete::cpl';
        }
        if (my $histfile = $CPAN::Config->{'histfile'}) {{
            unless ($term->can("AddHistory")) {
                $CPAN::Frontend->mywarn("Terminal does not support AddHistory.\n");
                last;
            }
            $META->readhist($term,$histfile);
        }}
        for ($CPAN::Config->{term_ornaments}) { # alias
            local $Term::ReadLine::termcap_nowarn = 1;
            $term->ornaments($_) if defined;
        }
        # $term->OUT is autoflushed anyway
        my $odef = select STDERR;
        $| = 1;
        select STDOUT;
        $| = 1;
        select $odef;
    }

    $META->checklock();
    my @cwd = grep { defined $_ and length $_ }
        CPAN::anycwd(),
              File::Spec->can("tmpdir") ? File::Spec->tmpdir() : (),
                    File::Spec->rootdir();
    my $try_detect_readline;
    $try_detect_readline = $term->ReadLine eq "Term::ReadLine::Stub" if $term;
    unless ($CPAN::Config->{inhibit_startup_message}) {
        my $rl_avail = $Suppress_readline ? "suppressed" :
            ($term->ReadLine ne "Term::ReadLine::Stub") ? "enabled" :
                "available (maybe install Bundle::CPAN or Bundle::CPANxxl?)";
        $CPAN::Frontend->myprint(
                                 sprintf qq{
cpan shell -- CPAN exploration and modules installation (v%s)
Enter 'h' for help.

},
                                 $CPAN::VERSION,
                                 $rl_avail
                                )
    }
    my($continuation) = "";
    my $last_term_ornaments;
  SHELLCOMMAND: while () {
        if ($Suppress_readline) {
            if ($Echo_readline) {
                $|=1;
            }
            print $prompt;
            last SHELLCOMMAND unless defined ($_ = <> );
            if ($Echo_readline) {
                # backdoor: I could not find a way to record sessions
                print $_;
            }
            chomp;
        } else {
            last SHELLCOMMAND unless
                defined ($_ = $term->readline($prompt, $commandline));
        }
        $_ = "$continuation$_" if $continuation;
        s/^\s+//;
        next SHELLCOMMAND if /^$/;
        s/^\s*\?\s*/help /;
        if (/^(?:q(?:uit)?|bye|exit)\s*$/i) {
            last SHELLCOMMAND;
        } elsif (s/\\$//s) {
            chomp;
            $continuation = $_;
            $prompt = "    > ";
        } elsif (/^\!/) {
            s/^\!//;
            my($eval) = $_;
            package
                CPAN::Eval; # hide from the indexer
            use strict;
            use vars qw($import_done);
            CPAN->import(':DEFAULT') unless $import_done++;
            CPAN->debug("eval[$eval]") if $CPAN::DEBUG;
            eval($eval);
            warn $@ if $@;
            $continuation = "";
            $prompt = $oprompt;
        } elsif (/./) {
            my(@line);
            eval { @line = Text::ParseWords::shellwords($_) };
            warn($@), next SHELLCOMMAND if $@;
            warn("Text::Parsewords could not parse the line [$_]"),
                next SHELLCOMMAND unless @line;
            $CPAN::META->debug("line[".join("|",@line)."]") if $CPAN::DEBUG;
            my $command = shift @line;
            eval {
                local (*STDOUT)=*STDOUT;
                @line = _redirect(@line);
                CPAN::Shell->$command(@line)
              };
            my $command_error = $@;
            _unredirect;
            my $reported_error;
            if ($command_error) {
                my $err = $command_error;
                if (ref $err and $err->isa('CPAN::Exception::blocked_urllist')) {
                    $CPAN::Frontend->mywarn("Client not fully configured, please proceed with configuring.$err");
                    $reported_error = ref $err;
                } else {
                    # I'd prefer never to arrive here and make all errors exception objects
                    if ($err =~ /\S/) {
                        require Carp;
                        require Dumpvalue;
                        my $dv = Dumpvalue->new(tick => '"');
                        Carp::cluck(sprintf "Catching error: %s", $dv->stringify($err));
                    }
                }
            }
            if ($command =~ /^(
                             # classic commands
                             make
                             |test
                             |install
                             |clean

                             # pragmas for classic commands
                             |ff?orce
                             |notest

                             # compounds
                             |report
                             |smoke
                             |upgrade
                            )$/x) {
                # only commands that tell us something about failed distros
                # eval necessary for people without an urllist
                eval {CPAN::Shell->failed($CPAN::CurrentCommandId,1);};
                if (my $err = $@) {
                    unless (ref $err and $reported_error eq ref $err) {
                        die $@;
                    }
                }
            }
            soft_chdir_with_alternatives(\@cwd);
            $CPAN::Frontend->myprint("\n");
            $continuation = "";
            $CPAN::CurrentCommandId++;
            $prompt = $oprompt;
        }
    } continue {
        $commandline = ""; # I do want to be able to pass a default to
                           # shell, but on the second command I see no
                           # use in that
        $Signal=0;
        CPAN::Queue->nullify_queue;
        if ($try_detect_readline) {
            if ($CPAN::META->has_inst("Term::ReadLine::Gnu")
                ||
                $CPAN::META->has_inst("Term::ReadLine::Perl")
            ) {
                delete $INC{"Term/ReadLine.pm"};
                my $redef = 0;
                local($SIG{__WARN__}) = CPAN::Shell::paintdots_onreload(\$redef);
                require Term::ReadLine;
                $CPAN::Frontend->myprint("\n$redef subroutines in ".
                                         "Term::ReadLine redefined\n");
                $GOTOSHELL = 1;
            }
        }
        if ($term and $term->can("ornaments")) {
            for ($CPAN::Config->{term_ornaments}) { # alias
                if (defined $_) {
                    if (not defined $last_term_ornaments
                        or $_ != $last_term_ornaments
                    ) {
                        local $Term::ReadLine::termcap_nowarn = 1;
                        $term->ornaments($_);
                        $last_term_ornaments = $_;
                    }
                } else {
                    undef $last_term_ornaments;
                }
            }
        }
        for my $class (qw(Module Distribution)) {
            # again unsafe meta access?
            for my $dm (keys %{$CPAN::META->{readwrite}{"CPAN::$class"}}) {
                next unless $CPAN::META->{readwrite}{"CPAN::$class"}{$dm}{incommandcolor};
                CPAN->debug("BUG: $class '$dm' was in command state, resetting");
                delete $CPAN::META->{readwrite}{"CPAN::$class"}{$dm}{incommandcolor};
            }
        }
        if ($GOTOSHELL) {
            $GOTOSHELL = 0; # not too often
            $META->savehist if $CPAN::term && $CPAN::term->can("GetHistory");
            @_ = ($oprompt,"");
            goto &shell;
        }
    }
    soft_chdir_with_alternatives(\@cwd);
}

sub soft_chdir_with_alternatives ($) {
    my($cwd) = @_;
    unless (@$cwd) {
        my $root = File::Spec->rootdir();
        $CPAN::Frontend->mywarn(qq{Warning: no good directory to chdir to!
Trying '$root' as temporary haven.
});
        push @$cwd, $root;
    }
    while () {
        if (chdir $cwd->[0]) {
            return;
        } else {
            if (@$cwd>1) {
                $CPAN::Frontend->mywarn(qq{Could not chdir to "$cwd->[0]": $!
Trying to chdir to "$cwd->[1]" instead.
});
                shift @$cwd;
            } else {
                $CPAN::Frontend->mydie(qq{Could not chdir to "$cwd->[0]": $!});
            }
        }
    }
}

sub _flock {
    my($fh,$mode) = @_;
    if ( $Config::Config{d_flock} || $Config::Config{d_fcntl_can_lock} ) {
        return flock $fh, $mode;
    } elsif (!$Have_warned->{"d_flock"}++) {
        $CPAN::Frontend->mywarn("Your OS does not seem to support locking; continuing and ignoring all locking issues\n");
        $CPAN::Frontend->mysleep(5);
        return 1;
    } else {
        return 1;
    }
}

sub _yaml_module () {
    my $yaml_module = $CPAN::Config->{yaml_module} || "YAML";
    if (
        $yaml_module ne "YAML"
        &&
        !$CPAN::META->has_inst($yaml_module)
       ) {
        # $CPAN::Frontend->mywarn("'$yaml_module' not installed, falling back to 'YAML'\n");
        $yaml_module = "YAML";
    }
    if ($yaml_module eq "YAML"
        &&
        $CPAN::META->has_inst($yaml_module)
        &&
        $YAML::VERSION < 0.60
        &&
        !$Have_warned->{"YAML"}++
       ) {
        $CPAN::Frontend->mywarn("Warning: YAML version '$YAML::VERSION' is too low, please upgrade!\n".
                                "I'll continue but problems are *very* likely to happen.\n"
                               );
        $CPAN::Frontend->mysleep(5);
    }
    return $yaml_module;
}

sub _yaml_loadfile {
    my($self,$local_file) = @_;
    return +[] unless -s $local_file;
    my $yaml_module = _yaml_module;
    if ($CPAN::META->has_inst($yaml_module)) {
        # temporarily enable yaml code deserialisation
        no strict 'refs';
        # 5.6.2 could not do the local() with the reference
        # so we do it manually instead
        my $old_loadcode = ${"$yaml_module\::LoadCode"};
        ${ "$yaml_module\::LoadCode" } = $CPAN::Config->{yaml_load_code} || 0;

        my ($code, @yaml);
        if ($code = UNIVERSAL::can($yaml_module, "LoadFile")) {
            eval { @yaml = $code->($local_file); };
            if ($@) {
                # this shall not be done by the frontend
                die CPAN::Exception::yaml_process_error->new($yaml_module,$local_file,"parse",$@);
            }
        } elsif ($code = UNIVERSAL::can($yaml_module, "Load")) {
            local *FH;
            open FH, $local_file or die "Could not open '$local_file': $!";
            local $/;
            my $ystream = <FH>;
            eval { @yaml = $code->($ystream); };
            if ($@) {
                # this shall not be done by the frontend
                die CPAN::Exception::yaml_process_error->new($yaml_module,$local_file,"parse",$@);
            }
        }
        ${"$yaml_module\::LoadCode"} = $old_loadcode;
        return \@yaml;
    } else {
        # this shall not be done by the frontend
        die CPAN::Exception::yaml_not_installed->new($yaml_module, $local_file, "parse");
    }
    return +[];
}

sub _yaml_dumpfile {
    my($self,$local_file,@what) = @_;
    my $yaml_module = _yaml_module;
    if ($CPAN::META->has_inst($yaml_module)) {
        my $code;
        if (UNIVERSAL::isa($local_file, "FileHandle")) {
            $code = UNIVERSAL::can($yaml_module, "Dump");
            eval { print $local_file $code->(@what) };
        } elsif ($code = UNIVERSAL::can($yaml_module, "DumpFile")) {
            eval { $code->($local_file,@what); };
        } elsif ($code = UNIVERSAL::can($yaml_module, "Dump")) {
            local *FH;
            open FH, ">$local_file" or die "Could not open '$local_file': $!";
            print FH $code->(@what);
        }
        if ($@) {
            die CPAN::Exception::yaml_process_error->new($yaml_module,$local_file,"dump",$@);
        }
    } else {
        if (UNIVERSAL::isa($local_file, "FileHandle")) {
            # I think this case does not justify a warning at all
        } else {
            die CPAN::Exception::yaml_not_installed->new($yaml_module, $local_file, "dump");
        }
    }
}

sub _init_sqlite () {
    unless ($CPAN::META->has_inst("CPAN::SQLite")) {
        $CPAN::Frontend->mywarn(qq{CPAN::SQLite not installed, trying to work without\n})
            unless $Have_warned->{"CPAN::SQLite"}++;
        return;
    }
    require CPAN::SQLite::META; # not needed since CVS version of 2006-12-17
    $CPAN::SQLite ||= CPAN::SQLite::META->new($CPAN::META);
}

{
    my $negative_cache = {};
    sub _sqlite_running {
        if ($negative_cache->{time} && time < $negative_cache->{time} + 60) {
            # need to cache the result, otherwise too slow
            return $negative_cache->{fact};
        } else {
            $negative_cache = {}; # reset
        }
        my $ret = $CPAN::Config->{use_sqlite} && ($CPAN::SQLite || _init_sqlite());
        return $ret if $ret; # fast anyway
        $negative_cache->{time} = time;
        return $negative_cache->{fact} = $ret;
    }
}

$META ||= CPAN->new; # In case we re-eval ourselves we need the ||


sub _perl_fingerprint {
    my($self,$other_fingerprint) = @_;
    my $dll = eval {OS2::DLLname()};
    my $mtime_dll = 0;
    if (defined $dll) {
        $mtime_dll = (-f $dll ? (stat(_))[9] : '-1');
    }
    my $mtime_perl = (-f CPAN::find_perl ? (stat(_))[9] : '-1');
    my $this_fingerprint = {
                            '$^X' => CPAN::find_perl,
                            sitearchexp => $Config::Config{sitearchexp},
                            'mtime_$^X' => $mtime_perl,
                            'mtime_dll' => $mtime_dll,
                           };
    if ($other_fingerprint) {
        if (exists $other_fingerprint->{'stat($^X)'}) { # repair fp from rev. 1.88_57
            $other_fingerprint->{'mtime_$^X'} = $other_fingerprint->{'stat($^X)'}[9];
        }
        # mandatory keys since 1.88_57
        for my $key (qw($^X sitearchexp mtime_dll mtime_$^X)) {
            return unless $other_fingerprint->{$key} eq $this_fingerprint->{$key};
        }
        return 1;
    } else {
        return $this_fingerprint;
    }
}

sub suggest_myconfig () {
  SUGGEST_MYCONFIG: if(!$INC{'CPAN/MyConfig.pm'}) {
        $CPAN::Frontend->myprint("You don't seem to have a user ".
                                 "configuration (MyConfig.pm) yet.\n");
        my $new = CPAN::Shell::colorable_makemaker_prompt("Do you want to create a ".
                                              "user configuration now? (Y/n)",
                                              "yes");
        if($new =~ m{^y}i) {
            CPAN::Shell->mkmyconfig();
            return &checklock;
        } else {
            $CPAN::Frontend->mydie("OK, giving up.");
        }
    }
}

sub all_objects {
    my($mgr,$class) = @_;
    CPAN::HandleConfig->load unless $CPAN::Config_loaded++;
    CPAN->debug("mgr[$mgr] class[$class]") if $CPAN::DEBUG;
    CPAN::Index->reload;
    values %{ $META->{readwrite}{$class} }; # unsafe meta access, ok
}


sub checklock {
    my($self) = @_;
    my $lockfile = File::Spec->catfile($CPAN::Config->{cpan_home},".lock");
    if (-f $lockfile && -M _ > 0) {
        my $fh = FileHandle->new($lockfile) or
            $CPAN::Frontend->mydie("Could not open lockfile '$lockfile': $!");
        my $otherpid  = <$fh>;
        my $otherhost = <$fh>;
        $fh->close;
        if (defined $otherpid && $otherpid) {
            chomp $otherpid;
        }
        if (defined $otherhost && $otherhost) {
            chomp $otherhost;
        }
        my $thishost  = hostname();
        if (defined $otherhost && defined $thishost &&
            $otherhost ne '' && $thishost ne '' &&
            $otherhost ne $thishost) {
            $CPAN::Frontend->mydie(sprintf("CPAN.pm panic: Lockfile '$lockfile'\n".
                                           "reports other host $otherhost and other ".
                                           "process $otherpid.\n".
                                           "Cannot proceed.\n"));
        } elsif ($RUN_DEGRADED) {
            $CPAN::Frontend->mywarn("Running in downgraded mode (experimental)\n");
        } elsif (defined $otherpid && $otherpid) {
            return if $$ == $otherpid; # should never happen
            $CPAN::Frontend->mywarn(
                                    qq{
There seems to be running another CPAN process (pid $otherpid).  Contacting...
});
            if (kill 0, $otherpid or $!{EPERM}) {
                $CPAN::Frontend->mywarn(qq{Other job is running.\n});
                my($ans) =
                    CPAN::Shell::colorable_makemaker_prompt
                        (qq{Shall I try to run in downgraded }.
                        qq{mode? (Y/n)},"y");
                if ($ans =~ /^y/i) {
                    $CPAN::Frontend->mywarn("Running in downgraded mode (experimental).
Please report if something unexpected happens\n");
                    $RUN_DEGRADED = 1;
                    for ($CPAN::Config) {
                        # XXX
                        # $_->{build_dir_reuse} = 0; # 2006-11-17 akoenig Why was that?
                        $_->{commandnumber_in_prompt} = 0; # visibility
                        $_->{histfile}       = "";  # who should win otherwise?
                        $_->{cache_metadata} = 0;   # better would be a lock?
                        $_->{use_sqlite}     = 0;   # better would be a write lock!
                        $_->{auto_commit}    = 0;   # we are violent, do not persist
                        $_->{test_report}    = 0;   # Oliver Paukstadt had sent wrong reports in degraded mode
                    }
                } else {
                    $CPAN::Frontend->mydie("
You may want to kill the other job and delete the lockfile. On UNIX try:
    kill $otherpid
    rm $lockfile
");
                }
            } elsif (-w $lockfile) {
                my($ans) =
                    CPAN::Shell::colorable_makemaker_prompt
                        (qq{Other job not responding. Shall I overwrite }.
                        qq{the lockfile '$lockfile'? (Y/n)},"y");
            $CPAN::Frontend->myexit("Ok, bye\n")
                unless $ans =~ /^y/i;
            } else {
                Carp::croak(
                    qq{Lockfile '$lockfile' not writable by you. }.
                    qq{Cannot proceed.\n}.
                    qq{    On UNIX try:\n}.
                    qq{    rm '$lockfile'\n}.
                    qq{  and then rerun us.\n}
                );
            }
        } else {
            $CPAN::Frontend->mydie(sprintf("CPAN.pm panic: Found invalid lockfile ".
                                           "'$lockfile', please remove. Cannot proceed.\n"));
        }
    }
    my $dotcpan = $CPAN::Config->{cpan_home};
    eval { File::Path::mkpath($dotcpan);};
    if ($@) {
        # A special case at least for Jarkko.
        my $firsterror = $@;
        my $seconderror;
        my $symlinkcpan;
        if (-l $dotcpan) {
            $symlinkcpan = readlink $dotcpan;
            die "readlink $dotcpan failed: $!" unless defined $symlinkcpan;
            eval { File::Path::mkpath($symlinkcpan); };
            if ($@) {
                $seconderror = $@;
            } else {
                $CPAN::Frontend->mywarn(qq{
Working directory $symlinkcpan created.
});
            }
        }
        unless (-d $dotcpan) {
            my $mess = qq{
Your configuration suggests "$dotcpan" as your
CPAN.pm working directory. I could not create this directory due
to this error: $firsterror\n};
            $mess .= qq{
As "$dotcpan" is a symlink to "$symlinkcpan",
I tried to create that, but I failed with this error: $seconderror
} if $seconderror;
            $mess .= qq{
Please make sure the directory exists and is writable.
};
            $CPAN::Frontend->mywarn($mess);
            return suggest_myconfig;
        }
    } # $@ after eval mkpath $dotcpan
    if (0) { # to test what happens when a race condition occurs
        for (reverse 1..10) {
            print $_, "\n";
            sleep 1;
        }
    }
    # locking
    if (!$RUN_DEGRADED && !$self->{LOCKFH}) {
        my $fh;
        unless ($fh = FileHandle->new("+>>$lockfile")) {
            $CPAN::Frontend->mywarn(qq{

Your configuration suggests that CPAN.pm should use a working
directory of
    $CPAN::Config->{cpan_home}
Unfortunately we could not create the lock file
    $lockfile
due to '$!'.

Please make sure that the configuration variable
    \$CPAN::Config->{cpan_home}
points to a directory where you can write a .lock file. You can set
this variable in either a CPAN/MyConfig.pm or a CPAN/Config.pm in your
\@INC path;
});
            return suggest_myconfig;
        }
        my $sleep = 1;
        while (!CPAN::_flock($fh, LOCK_EX|LOCK_NB)) {
            if ($sleep>10) {
                $CPAN::Frontend->mydie("Giving up\n");
            }
            $CPAN::Frontend->mysleep($sleep++);
            $CPAN::Frontend->mywarn("Could not lock lockfile with flock: $!; retrying\n");
        }

        seek $fh, 0, 0;
        truncate $fh, 0;
        $fh->autoflush(1);
        $fh->print($$, "\n");
        $fh->print(hostname(), "\n");
        $self->{LOCK} = $lockfile;
        $self->{LOCKFH} = $fh;
    }
    $SIG{TERM} = sub {
        my $sig = shift;
        &cleanup;
        $CPAN::Frontend->mydie("Got SIG$sig, leaving");
    };
    $SIG{INT} = sub {
      # no blocks!!!
        my $sig = shift;
        &cleanup if $Signal;
        die "Got yet another signal" if $Signal > 1;
        $CPAN::Frontend->mydie("Got another SIG$sig") if $Signal;
        $CPAN::Frontend->mywarn("Caught SIG$sig, trying to continue\n");
        $Signal++;
    };


    # global backstop to cleanup if we should really die
    $SIG{__DIE__} = \&cleanup;
    $self->debug("Signal handler set.") if $CPAN::DEBUG;
}

sub DESTROY {
    &cleanup; # need an eval?
}

sub anycwd () {
    my $getcwd;
    $getcwd = $CPAN::Config->{'getcwd'} || 'cwd';
    CPAN->$getcwd();
}

sub cwd {Cwd::cwd();}

sub getcwd {Cwd::getcwd();}

sub fastcwd {Cwd::fastcwd();}

sub backtickcwd {my $cwd = `cwd`; chomp $cwd; $cwd}

sub _perl_is_same {
  my ($perl) = @_;
  return MM->maybe_command($perl)
    && `$perl -MConfig=myconfig -e print -e myconfig` eq Config->myconfig;
}

sub find_perl () {
    if ( File::Spec->file_name_is_absolute($^X) ) {
        return $^X;
    }
    else {
        my $exe = $Config::Config{exe_ext};
        my @candidates = (
            File::Spec->catfile($CPAN::iCwd,$^X),
            $Config::Config{'perlpath'},
        );
        for my $perl_name ($^X, 'perl', 'perl5', "perl$]") {
            for my $path (File::Spec->path(), $Config::Config{'binexp'}) {
                if ( defined($path) && length $path && -d $path ) {
                    my $perl = File::Spec->catfile($path,$perl_name);
                    push @candidates, $perl;
                    # try with extension if not provided already
                    if ($^O eq 'VMS') {
                        # VMS might have a file version at the end
                        push @candidates, $perl . $exe
                            unless $perl =~ m/$exe(;\d+)?$/i;
                    } elsif (defined $exe && length $exe) {
                        push @candidates, $perl . $exe
                            unless $perl =~ m/$exe$/i;
                    }
                }
            }
        }
        for my $perl ( @candidates ) {
            if (MM->maybe_command($perl) && _perl_is_same($perl)) {
                $^X = $perl;
                return $perl;
            }
        }
    }
    return $^X; # default fall back
}

sub exists {
    my($mgr,$class,$id) = @_;
    CPAN::HandleConfig->load unless $CPAN::Config_loaded++;
    CPAN::Index->reload;
    ### Carp::croak "exists called without class argument" unless $class;
    $id ||= "";
    $id =~ s/:+/::/g if $class eq "CPAN::Module";
    my $exists;
    if (CPAN::_sqlite_running) {
        $exists = (exists $META->{readonly}{$class}{$id} or
                   $CPAN::SQLite->set($class, $id));
    } else {
        $exists =  exists $META->{readonly}{$class}{$id};
    }
    $exists ||= exists $META->{readwrite}{$class}{$id}; # unsafe meta access, ok
}

sub delete {
  my($mgr,$class,$id) = @_;
  delete $META->{readonly}{$class}{$id}; # unsafe meta access, ok
  delete $META->{readwrite}{$class}{$id}; # unsafe meta access, ok
}

sub has_usable {
    my($self,$mod,$message) = @_;
    return 1 if $HAS_USABLE->{$mod};
    my $has_inst = $self->has_inst($mod,$message);
    return unless $has_inst;
    my $usable;
    $usable = {

               #
               # these subroutines die if they believe the installed version is unusable;
               #
               'CPAN::Meta' => [
                            sub {
                                require CPAN::Meta;
                                unless (CPAN::Version->vge(CPAN::Meta->VERSION, 2.110350)) {
                                    for ("Will not use CPAN::Meta, need version 2.110350\n") {
                                        $CPAN::Frontend->mywarn($_);
                                        die $_;
                                    }
                                }
                            },
                           ],

               LWP => [ # we frequently had "Can't locate object
                        # method "new" via package "LWP::UserAgent" at
                        # (eval 69) line 2006
                       sub {require LWP},
                       sub {require LWP::UserAgent},
                       sub {require HTTP::Request},
                       sub {require URI::URL;
                            unless (CPAN::Version->vge(URI::URL::->VERSION,0.08)) {
                                for ("Will not use URI::URL, need 0.08\n") {
                                    $CPAN::Frontend->mywarn($_);
                                    die $_;
                                }
                            }
                       },
                      ],
               'Net::FTP' => [
                            sub {require Net::FTP},
                            sub {require Net::Config},
                           ],
               'HTTP::Tiny' => [
                            sub {
                                require HTTP::Tiny;
                                unless (CPAN::Version->vge(HTTP::Tiny->VERSION, 0.005)) {
                                    for ("Will not use HTTP::Tiny, need version 0.005\n") {
                                        $CPAN::Frontend->mywarn($_);
                                        die $_;
                                    }
                                }
                            },
                           ],
               'File::HomeDir' => [
                                   sub {require File::HomeDir;
                                        unless (CPAN::Version->vge(File::HomeDir::->VERSION, 0.52)) {
                                            for ("Will not use File::HomeDir, need 0.52\n") {
                                                $CPAN::Frontend->mywarn($_);
                                                die $_;
                                            }
                                        }
                                    },
                                  ],
               'Archive::Tar' => [
                                  sub {require Archive::Tar;
                                       my $demand = "1.50";
                                       unless (CPAN::Version->vge(Archive::Tar::->VERSION, $demand)) {
                                            my $atv = Archive::Tar->VERSION;
                                            for ("You have Archive::Tar $atv, but $demand or later is recommended. Please upgrade.\n") {
                                                $CPAN::Frontend->mywarn($_);
                                            # don't die, because we may need
                                            # Archive::Tar to upgrade
                                            }

                                       }
                                  },
                                 ],
               'File::Temp' => [
                                # XXX we should probably delete from
                                # %INC too so we can load after we
                                # installed a new enough version --
                                # I'm not sure.
                                sub {require File::Temp;
                                     unless (CPAN::Version->vge(File::Temp::->VERSION,0.16)) {
                                         for ("Will not use File::Temp, need 0.16\n") {
                                                $CPAN::Frontend->mywarn($_);
                                                die $_;
                                         }
                                     }
                                },
                               ]
              };
    if ($usable->{$mod}) {
        for my $c (0..$#{$usable->{$mod}}) {
            my $code = $usable->{$mod}[$c];
            my $ret = eval { &$code() };
            $ret = "" unless defined $ret;
            if ($@) {
                # warn "DEBUG: c[$c]\$\@[$@]ret[$ret]";
                return;
            }
        }
    }
    return $HAS_USABLE->{$mod} = 1;
}

sub has_inst {
    my($self,$mod,$message) = @_;
    Carp::croak("CPAN->has_inst() called without an argument")
        unless defined $mod;
    my %dont = map { $_ => 1 } keys %{$CPAN::META->{dontload_hash}||{}},
        keys %{$CPAN::Config->{dontload_hash}||{}},
            @{$CPAN::Config->{dontload_list}||[]};
    if (defined $message && $message eq "no"  # as far as I remember only used by Nox
        ||
        $dont{$mod}
       ) {
      $CPAN::META->{dontload_hash}{$mod}||=1; # unsafe meta access, ok
      return 0;
    }
    my $file = $mod;
    my $obj;
    $file =~ s|::|/|g;
    $file .= ".pm";
    if ($INC{$file}) {
        # checking %INC is wrong, because $INC{LWP} may be true
        # although $INC{"URI/URL.pm"} may have failed. But as
        # I really want to say "blah loaded OK", I have to somehow
        # cache results.
        ### warn "$file in %INC"; #debug
        return 1;
    } elsif (eval { require $file }) {
        # eval is good: if we haven't yet read the database it's
        # perfect and if we have installed the module in the meantime,
        # it tries again. The second require is only a NOOP returning
        # 1 if we had success, otherwise it's retrying

        my $mtime = (stat $INC{$file})[9];
        # privileged files loaded by has_inst; Note: we use $mtime
        # as a proxy for a checksum.
        $CPAN::Shell::reload->{$file} = $mtime;
        my $v = eval "\$$mod\::VERSION";
        $v = $v ? " (v$v)" : "";
        CPAN::Shell->optprint("load_module","CPAN: $mod loaded ok$v\n");
        if ($mod eq "CPAN::WAIT") {
            push @CPAN::Shell::ISA, 'CPAN::WAIT';
        }
        return 1;
    } elsif ($mod eq "Net::FTP") {
        $CPAN::Frontend->mywarn(qq{
  Please, install Net::FTP as soon as possible. CPAN.pm installs it for you
  if you just type
      install Bundle::libnet

}) unless $Have_warned->{"Net::FTP"}++;
        $CPAN::Frontend->mysleep(3);
    } elsif ($mod eq "Digest::SHA") {
        if ($Have_warned->{"Digest::SHA"}++) {
            $CPAN::Frontend->mywarn(qq{CPAN: checksum security checks disabled }.
                                     qq{because Digest::SHA not installed.\n});
        } else {
            $CPAN::Frontend->mywarn(qq{
  CPAN: checksum security checks disabled because Digest::SHA not installed.
  Please consider installing the Digest::SHA module.

});
            $CPAN::Frontend->mysleep(2);
        }
    } elsif ($mod eq "Module::Signature") {
        # NOT prefs_lookup, we are not a distro
        my $check_sigs = $CPAN::Config->{check_sigs};
        if (not $check_sigs) {
            # they do not want us:-(
        } elsif (not $Have_warned->{"Module::Signature"}++) {
            # No point in complaining unless the user can
            # reasonably install and use it.
            if (eval { require Crypt::OpenPGP; 1 } ||
                (
                 defined $CPAN::Config->{'gpg'}
                 &&
                 $CPAN::Config->{'gpg'} =~ /\S/
                )
               ) {
                $CPAN::Frontend->mywarn(qq{
  CPAN: Module::Signature security checks disabled because Module::Signature
  not installed.  Please consider installing the Module::Signature module.
  You may also need to be able to connect over the Internet to the public
  key servers like pool.sks-keyservers.net or pgp.mit.edu.

});
                $CPAN::Frontend->mysleep(2);
            }
        }
    } else {
        delete $INC{$file}; # if it inc'd LWP but failed during, say, URI
    }
    return 0;
}

sub instance {
    my($mgr,$class,$id) = @_;
    CPAN::Index->reload;
    $id ||= "";
    # unsafe meta access, ok?
    return $META->{readwrite}{$class}{$id} if exists $META->{readwrite}{$class}{$id};
    $META->{readwrite}{$class}{$id} ||= $class->new(ID => $id);
}

sub new {
    bless {}, shift;
}

sub _exit_messages {
    my ($self) = @_;
    $self->{exit_messages} ||= [];
}

sub cleanup {
  # warn "cleanup called with arg[@_] End[$CPAN::End] Signal[$Signal]";
  local $SIG{__DIE__} = '';
  my($message) = @_;
  my $i = 0;
  my $ineval = 0;
  my($subroutine);
  while ((undef,undef,undef,$subroutine) = caller(++$i)) {
      $ineval = 1, last if
        $subroutine eq '(eval)';
  }
  return if $ineval && !$CPAN::End;
  return unless defined $META->{LOCK};
  return unless -f $META->{LOCK};
  $META->savehist;
  $META->{cachemgr} ||= CPAN::CacheMgr->new('atexit');
  close $META->{LOCKFH};
  unlink $META->{LOCK};
  # require Carp;
  # Carp::cluck("DEBUGGING");
  if ( $CPAN::CONFIG_DIRTY ) {
      $CPAN::Frontend->mywarn("Warning: Configuration not saved.\n");
  }
  $CPAN::Frontend->myprint("Lockfile removed.\n");
  for my $msg ( @{ $META->_exit_messages } ) {
      $CPAN::Frontend->myprint($msg);
  }
}

sub readhist {
    my($self,$term,$histfile) = @_;
    my $histsize = $CPAN::Config->{'histsize'} || 100;
    $term->Attribs->{'MaxHistorySize'} = $histsize if (defined($term->Attribs->{'MaxHistorySize'}));
    my($fh) = FileHandle->new;
    open $fh, "<$histfile" or return;
    local $/ = "\n";
    while (<$fh>) {
        chomp;
        $term->AddHistory($_);
    }
    close $fh;
}

sub savehist {
    my($self) = @_;
    my($histfile,$histsize);
    unless ($histfile = $CPAN::Config->{'histfile'}) {
        $CPAN::Frontend->mywarn("No history written (no histfile specified).\n");
        return;
    }
    $histsize = $CPAN::Config->{'histsize'} || 100;
    if ($CPAN::term) {
        unless ($CPAN::term->can("GetHistory")) {
            $CPAN::Frontend->mywarn("Terminal does not support GetHistory.\n");
            return;
        }
    } else {
        return;
    }
    my @h = $CPAN::term->GetHistory;
    splice @h, 0, @h-$histsize if @h>$histsize;
    my($fh) = FileHandle->new;
    open $fh, ">$histfile" or $CPAN::Frontend->mydie("Couldn't open >$histfile: $!");
    local $\ = local $, = "\n";
    print $fh @h;
    close $fh;
}

sub is_tested {
    my($self,$what,$when) = @_;
    unless ($what) {
        Carp::cluck("DEBUG: empty what");
        return;
    }
    $self->{is_tested}{$what} = $when;
}

sub reset_tested {
    my ($self) = @_;
    $self->{is_tested} = {};
}

sub is_installed {
    my($self,$what) = @_;
    delete $self->{is_tested}{$what};
}

sub _list_sorted_descending_is_tested {
    my($self) = @_;
    my $foul = 0;
    my @sorted = sort
        { ($self->{is_tested}{$b}||0) <=> ($self->{is_tested}{$a}||0) }
            grep
                { if ($foul){ 0 } elsif (-e) { 1 } else { $foul = $_; 0 } }
                    keys %{$self->{is_tested}};
    if ($foul) {
        $CPAN::Frontend->mywarn("Lost build_dir detected ($foul), giving up all cached test results of currently running session.\n");
        for my $dbd (keys %{$self->{is_tested}}) { # distro-build-dir
        SEARCH: for my $d ($CPAN::META->all_objects("CPAN::Distribution")) {
                if ($d->{build_dir} && $d->{build_dir} eq $dbd) {
                    $CPAN::Frontend->mywarn(sprintf "Flushing cache for %s\n", $d->pretty_id);
                    $d->fforce("");
                    last SEARCH;
                }
            }
            delete $self->{is_tested}{$dbd};
        }
        return ();
    } else {
        return @sorted;
    }
}

{
my $fh;
sub set_perl5lib {
    my($self,$for) = @_;
    unless ($for) {
        (undef,undef,undef,$for) = caller(1);
        $for =~ s/.*://;
    }
    $self->{is_tested} ||= {};
    return unless %{$self->{is_tested}};
    my $env = $ENV{PERL5LIB};
    $env = $ENV{PERLLIB} unless defined $env;
    my @env;
    push @env, split /\Q$Config::Config{path_sep}\E/, $env if defined $env and length $env;
    #my @dirs = map {("$_/blib/arch", "$_/blib/lib")} keys %{$self->{is_tested}};
    #$CPAN::Frontend->myprint("Prepending @dirs to PERL5LIB.\n");

    my @dirs = map {("$_/blib/arch", "$_/blib/lib")} $self->_list_sorted_descending_is_tested;
    return if !@dirs;

    if (@dirs < 12) {
        $CPAN::Frontend->optprint('perl5lib', "Prepending @dirs to PERL5LIB for '$for'\n");
        $ENV{PERL5LIB} = join $Config::Config{path_sep}, @dirs, @env;
    } elsif (@dirs < 24 ) {
        my @d = map {my $cp = $_;
                     $cp =~ s/^\Q$CPAN::Config->{build_dir}\E/%BUILDDIR%/;
                     $cp
                 } @dirs;
        $CPAN::Frontend->optprint('perl5lib', "Prepending @d to PERL5LIB; ".
                                 "%BUILDDIR%=$CPAN::Config->{build_dir} ".
                                 "for '$for'\n"
                                );
        $ENV{PERL5LIB} = join $Config::Config{path_sep}, @dirs, @env;
    } else {
        my $cnt = keys %{$self->{is_tested}};
        $CPAN::Frontend->optprint('perl5lib', "Prepending blib/arch and blib/lib of ".
                                 "$cnt build dirs to PERL5LIB; ".
                                 "for '$for'\n"
                                );
        $ENV{PERL5LIB} = join $Config::Config{path_sep}, @dirs, @env;
    }
}}


1;


__END__

