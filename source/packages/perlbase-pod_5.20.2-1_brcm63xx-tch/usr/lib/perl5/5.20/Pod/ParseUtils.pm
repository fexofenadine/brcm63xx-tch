
package Pod::ParseUtils;
use strict;

use vars qw($VERSION);
$VERSION = '1.62'; ## Current version of this package
require  5.005;    ## requires this Perl version or later



package Pod::List;

use Carp;


sub new {
    my $this = shift;
    my $class = ref($this) || $this;
    my %params = @_;
    my $self = {%params};
    bless $self, $class;
    $self->initialize();
    return $self;
}

sub initialize {
    my $self = shift;
    $self->{-file} ||= 'unknown';
    $self->{-start} ||= 'unknown';
    $self->{-indent} ||= 4; # perlpod: "should be the default"
    $self->{_items} = [];
    $self->{-type} ||= '';
}


sub file {
   return (@_ > 1) ? ($_[0]->{-file} = $_[1]) : $_[0]->{-file};
}


sub start {
   return (@_ > 1) ? ($_[0]->{-start} = $_[1]) : $_[0]->{-start};
}


sub indent {
   return (@_ > 1) ? ($_[0]->{-indent} = $_[1]) : $_[0]->{-indent};
}


sub type {
   return (@_ > 1) ? ($_[0]->{-type} = $_[1]) : $_[0]->{-type};
}


sub rx {
   return (@_ > 1) ? ($_[0]->{-rx} = $_[1]) : $_[0]->{-rx};
}


sub item {
    my ($self,$item) = @_;
    if(defined $item) {
        push(@{$self->{_items}}, $item);
        return $item;
    }
    else {
        return @{$self->{_items}};
    }
}


sub parent {
   return (@_ > 1) ? ($_[0]->{-parent} = $_[1]) : $_[0]->{-parent};
}


sub tag {
   return (@_ > 1) ? ($_[0]->{-tag} = $_[1]) : $_[0]->{-tag};
}


package Pod::Hyperlink;


use Carp;

sub new {
    my $this = shift;
    my $class = ref($this) || $this;
    my $self = +{};
    bless $self, $class;
    $self->initialize();
    if(defined $_[0]) {
        if(ref($_[0])) {
            # called with a list of parameters
            %$self = %{$_[0]};
            $self->_construct_text();
        }
        else {
            # called with L<> contents
            return unless($self->parse($_[0]));
        }
    }
    return $self;
}

sub initialize {
    my $self = shift;
    $self->{-line} ||= 'undef';
    $self->{-file} ||= 'undef';
    $self->{-page} ||= '';
    $self->{-node} ||= '';
    $self->{-alttext} ||= '';
    $self->{-type} ||= 'undef';
    $self->{_warnings} = [];
}


sub parse {
    my $self = shift;
    local($_) = $_[0];
    # syntax check the link and extract destination
    my ($alttext,$page,$node,$type,$quoted) = (undef,'','','',0);

    $self->{_warnings} = [];

    # collapse newlines with whitespace
    s/\s*\n+\s*/ /g;

    # strip leading/trailing whitespace
    if(s/^[\s\n]+//) {
        $self->warning('ignoring leading whitespace in link');
    }
    if(s/[\s\n]+$//) {
        $self->warning('ignoring trailing whitespace in link');
    }
    unless(length($_)) {
        _invalid_link('empty link');
        return;
    }

    ## Check for different possibilities. This is tedious and error-prone
    # we match all possibilities (alttext, page, section/item)
    #warn "DEBUG: link=$_\n";

    # only page
    # problem: a lot of people use (), or (1) or the like to indicate
    # man page sections. But this collides with L<func()> that is supposed
    # to point to an internal function...
    my $page_rx = '[\w.-]+(?:::[\w.-]+)*(?:[(](?:\d\w*|)[)]|)';
    # page name only
    if(/^($page_rx)$/o) {
        $page = $1;
        $type = 'page';
    }
    # alttext, page and "section"
    elsif(m{^(.*?)\s*[|]\s*($page_rx)\s*/\s*"(.+)"$}o) {
        ($alttext, $page, $node) = ($1, $2, $3);
        $type = 'section';
        $quoted = 1; #... therefore | and / are allowed
    }
    # alttext and page
    elsif(/^(.*?)\s*[|]\s*($page_rx)$/o) {
        ($alttext, $page) = ($1, $2);
        $type = 'page';
    }
    # alttext and "section"
    elsif(m{^(.*?)\s*[|]\s*(?:/\s*|)"(.+)"$}) {
        ($alttext, $node) = ($1,$2);
        $type = 'section';
        $quoted = 1;
    }
    # page and "section"
    elsif(m{^($page_rx)\s*/\s*"(.+)"$}o) {
        ($page, $node) = ($1, $2);
        $type = 'section';
        $quoted = 1;
    }
    # page and item
    elsif(m{^($page_rx)\s*/\s*(.+)$}o) {
        ($page, $node) = ($1, $2);
        $type = 'item';
    }
    # only "section"
    elsif(m{^/?"(.+)"$}) {
        $node = $1;
        $type = 'section';
        $quoted = 1;
    }
    # only item
    elsif(m{^\s*/(.+)$}) {
        $node = $1;
        $type = 'item';
    }

    # non-standard: Hyperlink with alt-text - doesn't remove protocol prefix, maybe it should?
    elsif(/^ \s* (.*?) \s* [|] \s* (\w+:[^:\s] [^\s|]*?) \s* $/ix) {
      ($alttext,$node) = ($1,$2);
      $type = 'hyperlink';
    }

    # non-standard: Hyperlink
    elsif(/^(\w+:[^:\s]\S*)$/i) {
        $node = $1;
        $type = 'hyperlink';
    }
    # alttext, page and item
    elsif(m{^(.*?)\s*[|]\s*($page_rx)\s*/\s*(.+)$}o) {
        ($alttext, $page, $node) = ($1, $2, $3);
        $type = 'item';
    }
    # alttext and item
    elsif(m{^(.*?)\s*[|]\s*/(.+)$}) {
        ($alttext, $node) = ($1,$2);
    }
    # must be an item or a "malformed" section (without "")
    else {
        $node = $_;
        $type = 'item';
    }
    # collapse whitespace in nodes
    $node =~ s/\s+/ /gs;

    # empty alternative text expands to node name
    if(defined $alttext) {
        if(!length($alttext)) {
          $alttext = $node || $page;
        }
    }
    else {
        $alttext = '';
    }

    if($page =~ /[(]\w*[)]$/) {
        $self->warning("(section) in '$page' deprecated");
    }
    if(!$quoted && $node =~ m{[|/]} && $type ne 'hyperlink') {
        $self->warning("node '$node' contains non-escaped | or /");
    }
    if($alttext =~ m{[|/]}) {
        $self->warning("alternative text '$node' contains non-escaped | or /");
    }
    $self->{-page} = $page;
    $self->{-node} = $node;
    $self->{-alttext} = $alttext;
    #warn "DEBUG: page=$page section=$section item=$item alttext=$alttext\n";
    $self->{-type} = $type;
    $self->_construct_text();
    1;
}

sub _construct_text {
    my $self = shift;
    my $alttext = $self->alttext();
    my $type = $self->type();
    my $section = $self->node();
    my $page = $self->page();
    my $page_ext = '';
    $page =~ s/([(]\w*[)])$// && ($page_ext = $1);
    if($alttext) {
        $self->{_text} = $alttext;
    }
    elsif($type eq 'hyperlink') {
        $self->{_text} = $section;
    }
    else {
        $self->{_text} = ($section || '') .
            (($page && $section) ? ' in ' : '') .
            "$page$page_ext";
    }
    # for being marked up later
    # use the non-standard markers P<> and Q<>, so that the resulting
    # text can be parsed by the translators. It's their job to put
    # the correct hypertext around the linktext
    if($alttext) {
        $self->{_markup} = "Q<$alttext>";
    }
    elsif($type eq 'hyperlink') {
        $self->{_markup} = "Q<$section>";
    }
    else {
        $self->{_markup} = (!$section ? '' : "Q<$section>") .
            ($page ? ($section ? ' in ':'') . "P<$page>$page_ext" : '');
    }
}


#' retrieve/set markuped text
sub markup {
    return (@_ > 1) ? ($_[0]->{_markup} = $_[1]) : $_[0]->{_markup};
}


sub text {
    return $_[0]->{_text};
}


sub warning {
    my $self = shift;
    if(@_) {
        push(@{$self->{_warnings}}, @_);
        return @_;
    }
    return @{$self->{_warnings}};
}


sub line {
    return (@_ > 1) ? ($_[0]->{-line} = $_[1]) : $_[0]->{-line};
}

sub file {
    return (@_ > 1) ? ($_[0]->{-file} = $_[1]) : $_[0]->{-file};
}


sub page {
    if (@_ > 1) {
        $_[0]->{-page} = $_[1];
        $_[0]->_construct_text();
    }
    return $_[0]->{-page};
}


sub node {
    if (@_ > 1) {
        $_[0]->{-node} = $_[1];
        $_[0]->_construct_text();
    }
    return $_[0]->{-node};
}


sub alttext {
    if (@_ > 1) {
        $_[0]->{-alttext} = $_[1];
        $_[0]->_construct_text();
    }
    return $_[0]->{-alttext};
}


sub type {
    return (@_ > 1) ? ($_[0]->{-type} = $_[1]) : $_[0]->{-type};
}


sub link {
    my $self = shift;
    my $link = $self->page() || '';
    if($self->node()) {
        my $node = $self->node();
        $node =~ s/\|/E<verbar>/g;
        $node =~ s{/}{E<sol>}g;
        if($self->type() eq 'section') {
            $link .= ($link ? '/' : '') . '"' . $node . '"';
        }
        elsif($self->type() eq 'hyperlink') {
            $link = $self->node();
        }
        else { # item
            $link .= '/' . $node;
        }
    }
    if($self->alttext()) {
        my $text = $self->alttext();
        $text =~ s/\|/E<verbar>/g;
        $text =~ s{/}{E<sol>}g;
        $link = "$text|$link";
    }
    return $link;
}

sub _invalid_link {
    my ($msg) = @_;
    # this sets @_
    #eval { die "$msg\n" };
    #chomp $@;
    $@ = $msg; # this seems to work, too!
    return;
}


package Pod::Cache;


sub new {
    my $this = shift;
    my $class = ref($this) || $this;
    my $self = [];
    bless $self, $class;
    return $self;
}


sub item {
    my ($self,%param) = @_;
    if(%param) {
        my $item = Pod::Cache::Item->new(%param);
        push(@$self, $item);
        return $item;
    }
    else {
        return @{$self};
    }
}


sub find_page {
    my ($self,$page) = @_;
    foreach(@$self) {
        if($_->page() eq $page) {
            return $_;
        }
    }
    return;
}

package Pod::Cache::Item;


sub new {
    my $this = shift;
    my $class = ref($this) || $this;
    my %params = @_;
    my $self = {%params};
    bless $self, $class;
    $self->initialize();
    return $self;
}

sub initialize {
    my $self = shift;
    $self->{-nodes} = [] unless(defined $self->{-nodes});
}


sub page {
   return (@_ > 1) ? ($_[0]->{-page} = $_[1]) : $_[0]->{-page};
}


sub description {
   return (@_ > 1) ? ($_[0]->{-description} = $_[1]) : $_[0]->{-description};
}


sub path {
   return (@_ > 1) ? ($_[0]->{-path} = $_[1]) : $_[0]->{-path};
}


sub file {
   return (@_ > 1) ? ($_[0]->{-file} = $_[1]) : $_[0]->{-file};
}


sub nodes {
    my ($self,@nodes) = @_;
    if(@nodes) {
        push(@{$self->{-nodes}}, @nodes);
        return @nodes;
    }
    else {
        return @{$self->{-nodes}};
    }
}


sub find_node {
    my ($self,$node) = @_;
    my @search;
    push(@search, @{$self->{-nodes}}) if($self->{-nodes});
    push(@search, @{$self->{-idx}}) if($self->{-idx});
    foreach(@search) {
        if($_->[0] eq $node) {
            return $_->[1]; # id
        }
    }
    return;
}


sub idx {
    my ($self,@idx) = @_;
    if(@idx) {
        push(@{$self->{-idx}}, @idx);
        return @idx;
    }
    else {
        return @{$self->{-idx}};
    }
}


1;
