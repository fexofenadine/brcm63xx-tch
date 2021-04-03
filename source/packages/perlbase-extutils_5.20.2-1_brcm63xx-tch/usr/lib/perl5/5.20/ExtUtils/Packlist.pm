package ExtUtils::Packlist;

use 5.00503;
use strict;
use Carp qw();
use Config;
use vars qw($VERSION $Relocations);
$VERSION = '1.48';
$VERSION = eval $VERSION;

my $fhname = "FH1";


sub mkfh()
{
no strict;
local $^W;
my $fh = \*{$fhname++};
use strict;
return($fh);
}


sub __find_relocations
{
    my %paths;
    while (my ($raw_key, $raw_val) = each %Config) {
	my $exp_key = $raw_key . "exp";
	next unless exists $Config{$exp_key};
	next unless $raw_val =~ m!\.\.\./!;
	$paths{$Config{$exp_key}}++;
    }
    # Longest prefixes go first in the alternatives
    my $alternations = join "|", map {quotemeta $_}
    sort {length $b <=> length $a} keys %paths;
    qr/^($alternations)/o;
}

sub new($$)
{
my ($class, $packfile) = @_;
$class = ref($class) || $class;
my %self;
tie(%self, $class, $packfile);
return(bless(\%self, $class));
}

sub TIEHASH
{
my ($class, $packfile) = @_;
my $self = { packfile => $packfile };
bless($self, $class);
$self->read($packfile) if (defined($packfile) && -f $packfile);
return($self);
}

sub STORE
{
$_[0]->{data}->{$_[1]} = $_[2];
}

sub FETCH
{
return($_[0]->{data}->{$_[1]});
}

sub FIRSTKEY
{
my $reset = scalar(keys(%{$_[0]->{data}}));
return(each(%{$_[0]->{data}}));
}

sub NEXTKEY
{
return(each(%{$_[0]->{data}}));
}

sub EXISTS
{
return(exists($_[0]->{data}->{$_[1]}));
}

sub DELETE
{
return(delete($_[0]->{data}->{$_[1]}));
}

sub CLEAR
{
%{$_[0]->{data}} = ();
}

sub DESTROY
{
}

sub read($;$)
{
my ($self, $packfile) = @_;
$self = tied(%$self) || $self;

if (defined($packfile)) { $self->{packfile} = $packfile; }
else { $packfile = $self->{packfile}; }
Carp::croak("No packlist filename specified") if (! defined($packfile));
my $fh = mkfh();
open($fh, "<$packfile") || Carp::croak("Can't open file $packfile: $!");
$self->{data} = {};
my ($line);
while (defined($line = <$fh>))
   {
   chomp $line;
   my ($key, $data) = $line;
   if ($key =~ /^(.*?)( \w+=.*)$/)
      {
      $key = $1;
      $data = { map { split('=', $_) } split(' ', $2)};

      if ($Config{userelocatableinc} && $data->{relocate_as})
      {
	  require File::Spec;
	  require Cwd;
	  my ($vol, $dir) = File::Spec->splitpath($packfile);
	  my $newpath = File::Spec->catpath($vol, $dir, $data->{relocate_as});
	  $key = Cwd::realpath($newpath);
      }
         }
   $key =~ s!/\./!/!g;   # Some .packlists have spurious '/./' bits in the paths
      $self->{data}->{$key} = $data;
      }
close($fh);
}

sub write($;$)
{
my ($self, $packfile) = @_;
$self = tied(%$self) || $self;
if (defined($packfile)) { $self->{packfile} = $packfile; }
else { $packfile = $self->{packfile}; }
Carp::croak("No packlist filename specified") if (! defined($packfile));
my $fh = mkfh();
open($fh, ">$packfile") || Carp::croak("Can't open file $packfile: $!");
foreach my $key (sort(keys(%{$self->{data}})))
   {
       my $data = $self->{data}->{$key};
       if ($Config{userelocatableinc}) {
	   $Relocations ||= __find_relocations();
	   if ($packfile =~ $Relocations) {
	       # We are writing into a subdirectory of a run-time relocated
	       # path. Figure out if the this file is also within a subdir.
	       my $prefix = $1;
	       if (File::Spec->no_upwards(File::Spec->abs2rel($key, $prefix)))
	       {
		   # The relocated path is within the found prefix
		   my $packfile_prefix;
		   (undef, $packfile_prefix)
		       = File::Spec->splitpath($packfile);

		   my $relocate_as
		       = File::Spec->abs2rel($key, $packfile_prefix);

		   if (!ref $data) {
		       $data = {};
		   }
		   $data->{relocate_as} = $relocate_as;
	       }
	   }
       }
   print $fh ("$key");
   if (ref($data))
      {
      foreach my $k (sort(keys(%$data)))
         {
         print $fh (" $k=$data->{$k}");
         }
      }
   print $fh ("\n");
   }
close($fh);
}

sub validate($;$)
{
my ($self, $remove) = @_;
$self = tied(%$self) || $self;
my @missing;
foreach my $key (sort(keys(%{$self->{data}})))
   {
   if (! -e $key)
      {
      push(@missing, $key);
      delete($self->{data}{$key}) if ($remove);
      }
   }
return(@missing);
}

sub packlist_file($)
{
my ($self) = @_;
$self = tied(%$self) || $self;
return($self->{packfile});
}

1;

__END__

