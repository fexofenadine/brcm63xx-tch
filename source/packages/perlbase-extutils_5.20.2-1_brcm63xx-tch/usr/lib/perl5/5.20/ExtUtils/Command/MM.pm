package ExtUtils::Command::MM;

require 5.006;

use strict;
use warnings;

require Exporter;
our @ISA = qw(Exporter);

our @EXPORT  = qw(test_harness pod2man perllocal_install uninstall
                  warn_if_old_packlist test_s cp_nonempty);
our $VERSION = '6.98';

my $Is_VMS = $^O eq 'VMS';

eval {  require Time::HiRes; die unless Time::HiRes->can("stat"); };
*mtime = $@ ?
 sub { [             stat($_[0])]->[9] } :
 sub { [Time::HiRes::stat($_[0])]->[9] } ;


sub test_harness {
    require Test::Harness;
    require File::Spec;

    $Test::Harness::verbose = shift;

    # Because Windows doesn't do this for us and listing all the *.t files
    # out on the command line can blow over its exec limit.
    require ExtUtils::Command;
    my @argv = ExtUtils::Command::expand_wildcards(@ARGV);

    local @INC = @INC;
    unshift @INC, map { File::Spec->rel2abs($_) } @_;
    Test::Harness::runtests(sort { lc $a cmp lc $b } @argv);
}




sub pod2man {
    local @ARGV = @_ ? @_ : @ARGV;

    {
        local $@;
        if( !eval { require Pod::Man } ) {
            warn "Pod::Man is not available: $@".
                 "Man pages will not be generated during this install.\n";
            return 0;
        }
    }
    require Getopt::Long;

    # We will cheat and just use Getopt::Long.  We fool it by putting
    # our arguments into @ARGV.  Should be safe.
    my %options = ();
    Getopt::Long::config ('bundling_override');
    Getopt::Long::GetOptions (\%options,
                'section|s=s', 'release|r=s', 'center|c=s',
                'date|d=s', 'fixed=s', 'fixedbold=s', 'fixeditalic=s',
                'fixedbolditalic=s', 'official|o', 'quotes|q=s', 'lax|l',
                'name|n=s', 'perm_rw=i'
    );

    # If there's no files, don't bother going further.
    return 0 unless @ARGV;

    # Official sets --center, but don't override things explicitly set.
    if ($options{official} && !defined $options{center}) {
        $options{center} = q[Perl Programmer's Reference Guide];
    }

    # This isn't a valid Pod::Man option and is only accepted for backwards
    # compatibility.
    delete $options{lax};

    do {{  # so 'next' works
        my ($pod, $man) = splice(@ARGV, 0, 2);

        next if ((-e $man) &&
                 (mtime($man) > mtime($pod)) &&
                 (mtime($man) > mtime("Makefile")));

        print "Manifying $man\n";

        my $parser = Pod::Man->new(%options);
        $parser->parse_from_file($pod, $man)
          or do { warn("Could not install $man\n");  next };

        if (exists $options{perm_rw}) {
            chmod(oct($options{perm_rw}), $man)
              or do { warn("chmod $options{perm_rw} $man: $!\n"); next };
        }
    }} while @ARGV;

    return 1;
}



sub warn_if_old_packlist {
    my $packlist = $ARGV[0];

    return unless -f $packlist;
    print <<"PACKLIST_WARNING";
WARNING: I have found an old package in
    $packlist.
Please make sure the two installations are not conflicting
PACKLIST_WARNING

}



sub perllocal_install {
    my($type, $name) = splice(@ARGV, 0, 2);

    # VMS feeds args as a piped file on STDIN since it usually can't
    # fit all the args on a single command line.
    my @mod_info = $Is_VMS ? split /\|/, <STDIN>
                           : @ARGV;

    my $pod;
    $pod = sprintf <<POD, scalar localtime;
 =head2 %s: C<$type> L<$name|$name>

 =over 4

POD

    do {
        my($key, $val) = splice(@mod_info, 0, 2);

        $pod .= <<POD
 =item *

 C<$key: $val>

POD

    } while(@mod_info);

    $pod .= "=back\n\n";
    $pod =~ s/^ //mg;
    print $pod;

    return 1;
}


sub uninstall {
    my($packlist) = shift @ARGV;

    require ExtUtils::Install;

    print <<'WARNING';

Uninstall is unsafe and deprecated, the uninstallation was not performed.
We will show what would have been done.

WARNING

    ExtUtils::Install::uninstall($packlist, 1, 1);

    print <<'WARNING';

Uninstall is unsafe and deprecated, the uninstallation was not performed.
Please check the list above carefully, there may be errors.
Remove the appropriate files manually.
Sorry for the inconvenience.

WARNING

}


sub test_s {
  exit(-s $ARGV[0] ? 0 : 1);
}


sub cp_nonempty {
  my @args = @ARGV;
  return 0 unless -s $args[0];
  require ExtUtils::Command;
  {
    local @ARGV = @args[0,1];
    ExtUtils::Command::cp(@ARGV);
  }
  {
    local @ARGV = @args[2,1];
    ExtUtils::Command::chmod(@ARGV);
  }
}


1;
