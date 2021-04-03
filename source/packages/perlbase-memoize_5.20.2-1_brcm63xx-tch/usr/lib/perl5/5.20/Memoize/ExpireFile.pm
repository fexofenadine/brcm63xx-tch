package Memoize::ExpireFile;


$VERSION = '1.03';
use Carp;

my $Zero = pack("N", 0);

sub TIEHASH {
  my ($package, %args) = @_;
  my $cache = $args{HASH} || {};
  bless {ARGS => \%args, C => $cache} => $package;
}


sub STORE {
  my ($self, $key, $data) = @_;
  my $cache = $self->{C};
  my $cur_date = pack("N", (stat($key))[9]);
  $cache->{"C$key"} = $data;
  $cache->{"T$key"} = $cur_date;
}

sub FETCH {
  my ($self, $key) = @_;
  $self->{C}{"C$key"};
}

sub EXISTS {
  my ($self, $key) = @_;
  my $cache_date = $self->{C}{"T$key"} || $Zero;
  my $file_date = pack("N", (stat($key))[9]);#
  my $res = $cache_date ge $file_date;
  $res;
}

1;
