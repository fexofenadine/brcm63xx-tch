
package Pod::Simple::XHTML;
use strict;
use vars qw( $VERSION @ISA $HAS_HTML_ENTITIES );
$VERSION = '3.28';
use Pod::Simple::Methody ();
@ISA = ('Pod::Simple::Methody');

BEGIN {
  $HAS_HTML_ENTITIES = eval "require HTML::Entities; 1";
}

my %entities = (
  q{>} => 'gt',
  q{<} => 'lt',
  q{'} => '#39',
  q{"} => 'quot',
  q{&} => 'amp',
);

sub encode_entities {
  my $self = shift;
  my $ents = $self->html_encode_chars;
  return HTML::Entities::encode_entities( $_[0], $ents ) if $HAS_HTML_ENTITIES;
  if (defined $ents) {
      $ents =~ s,(?<!\\)([]/]),\\$1,g;
      $ents =~ s,(?<!\\)\\\z,\\\\,;
  } else {
      $ents = join '', keys %entities;
  }
  my $str = $_[0];
  $str =~ s/([$ents])/'&' . ($entities{$1} || sprintf '#x%X', ord $1) . ';'/ge;
  return $str;
}



__PACKAGE__->_accessorize(
 'perldoc_url_prefix',
 'perldoc_url_postfix',
 'man_url_prefix',
 'man_url_postfix',
 'title_prefix',  'title_postfix',
 'html_css',
 'html_javascript',
 'html_doctype',
 'html_charset',
 'html_encode_chars',
 'html_h_level',
 'title', # Used internally for the title extracted from the content
 'default_title',
 'force_title',
 'html_header',
 'html_footer',
 'index',
 'anchor_items',
 'backlink',
 'batch_mode', # whether we're in batch mode
 'batch_mode_current_level',
    # When in batch mode, how deep the current module is: 1 for "LWP",
    #  2 for "LWP::Procotol", 3 for "LWP::Protocol::GHTTP", etc
);



sub new {
  my $self = shift;
  my $new = $self->SUPER::new(@_);
  $new->{'output_fh'} ||= *STDOUT{IO};
  $new->perldoc_url_prefix('http://search.cpan.org/perldoc?');
  $new->man_url_prefix('http://man.he.net/man');
  $new->html_charset('ISO-8859-1');
  $new->nix_X_codes(1);
  $new->{'scratch'} = '';
  $new->{'to_index'} = [];
  $new->{'output'} = [];
  $new->{'saved'} = [];
  $new->{'ids'} = { '_podtop_' => 1 }; # used in <body>
  $new->{'in_li'} = [];

  $new->{'__region_targets'}  = [];
  $new->{'__literal_targets'} = {};
  $new->accept_targets_as_html( 'html', 'HTML' );

  return $new;
}

sub html_header_tags {
    my $self = shift;
    return $self->{html_header_tags} = shift if @_;
    return $self->{html_header_tags}
        ||= '<meta http-equiv="Content-Type" content="text/html; charset='
            . $self->html_charset . '" />';
}



sub __in_literal_xhtml_region {
    return unless @{ $_[0]{__region_targets} };
    my $target = $_[0]{__region_targets}[-1];
    return $_[0]{__literal_targets}{ $target };
}

sub accept_targets_as_html {
    my ($self, @targets) = @_;
    $self->accept_targets(@targets);
    $self->{__literal_targets}{$_} = 1 for @targets;
}

sub handle_text {
    # escape special characters in HTML (<, >, &, etc)
    my $text = $_[0]->__in_literal_xhtml_region
        ? $_[1]
        : $_[0]->encode_entities( $_[1] );

    if ($_[0]{'in_code'} && @{$_[0]{'in_code'}}) {
        # Intentionally use the raw text in $_[1], even if we're not in a
        # literal xhtml region, since handle_code calls encode_entities.
        $_[0]->handle_code( $_[1], $_[0]{'in_code'}[-1] );
    } else {
        $_[0]{'scratch'} .= $text;
    }

    $_[0]{htext} .= $text if $_[0]{'in_head'};
}

sub start_code {
    $_[0]{'scratch'} .= '<code>';
}

sub end_code {
    $_[0]{'scratch'} .= '</code>';
}

sub handle_code {
    $_[0]{'scratch'} .= $_[0]->encode_entities( $_[1] );
}

sub start_Para {
    $_[0]{'scratch'} = '<p>';
}

sub start_Verbatim {
    $_[0]{'scratch'} = '<pre>';
    push(@{$_[0]{'in_code'}}, 'Verbatim');
    $_[0]->start_code($_[0]{'in_code'}[-1]);
}

sub start_head1 {  $_[0]{'in_head'} = 1; $_[0]{htext} = ''; }
sub start_head2 {  $_[0]{'in_head'} = 2; $_[0]{htext} = ''; }
sub start_head3 {  $_[0]{'in_head'} = 3; $_[0]{htext} = ''; }
sub start_head4 {  $_[0]{'in_head'} = 4; $_[0]{htext} = ''; }

sub start_item_number {
    $_[0]{'scratch'} = "</li>\n" if ($_[0]{'in_li'}->[-1] && pop @{$_[0]{'in_li'}});
    $_[0]{'scratch'} .= '<li><p>';
    push @{$_[0]{'in_li'}}, 1;
}

sub start_item_bullet {
    $_[0]{'scratch'} = "</li>\n" if ($_[0]{'in_li'}->[-1] && pop @{$_[0]{'in_li'}});
    $_[0]{'scratch'} .= '<li><p>';
    push @{$_[0]{'in_li'}}, 1;
}

sub start_item_text   {
    # see end_item_text
}

sub start_over_bullet { $_[0]{'scratch'} = '<ul>'; push @{$_[0]{'in_li'}}, 0; $_[0]->emit }
sub start_over_block  { $_[0]{'scratch'} = '<ul>'; $_[0]->emit }
sub start_over_number { $_[0]{'scratch'} = '<ol>'; push @{$_[0]{'in_li'}}, 0; $_[0]->emit }
sub start_over_text   {
    $_[0]{'scratch'} = '<dl>';
    $_[0]{'dl_level'}++;
    $_[0]{'in_dd'} ||= [];
    $_[0]->emit
}

sub end_over_block  { $_[0]{'scratch'} .= '</ul>'; $_[0]->emit }

sub end_over_number   {
    $_[0]{'scratch'} = "</li>\n" if ( pop @{$_[0]{'in_li'}} );
    $_[0]{'scratch'} .= '</ol>';
    pop @{$_[0]{'in_li'}};
    $_[0]->emit;
}

sub end_over_bullet   {
    $_[0]{'scratch'} = "</li>\n" if ( pop @{$_[0]{'in_li'}} );
    $_[0]{'scratch'} .= '</ul>';
    pop @{$_[0]{'in_li'}};
    $_[0]->emit;
}

sub end_over_text   {
    if ($_[0]{'in_dd'}[ $_[0]{'dl_level'} ]) {
        $_[0]{'scratch'} = "</dd>\n";
        $_[0]{'in_dd'}[ $_[0]{'dl_level'} ] = 0;
    }
    $_[0]{'scratch'} .= '</dl>';
    $_[0]{'dl_level'}--;
    $_[0]->emit;
}


sub end_Para     { $_[0]{'scratch'} .= '</p>'; $_[0]->emit }
sub end_Verbatim {
    $_[0]->end_code(pop(@{$_[0]->{'in_code'}}));
    $_[0]{'scratch'} .= '</pre>';
    $_[0]->emit;
}

sub _end_head {
    my $h = delete $_[0]{in_head};

    my $add = $_[0]->html_h_level;
    $add = 1 unless defined $add;
    $h += $add - 1;

    my $id = $_[0]->idify($_[0]{htext});
    my $text = $_[0]{scratch};
    $_[0]{'scratch'} = $_[0]->backlink && ($h - $add == 0)
                         # backlinks enabled && =head1
                         ? qq{<a href="#_podtop_"><h$h id="$id">$text</h$h></a>}
                         : qq{<h$h id="$id">$text</h$h>};
    $_[0]->emit;
    push @{ $_[0]{'to_index'} }, [$h, $id, delete $_[0]{'htext'}];
}

sub end_head1       { shift->_end_head(@_); }
sub end_head2       { shift->_end_head(@_); }
sub end_head3       { shift->_end_head(@_); }
sub end_head4       { shift->_end_head(@_); }

sub end_item_bullet { $_[0]{'scratch'} .= '</p>'; $_[0]->emit }
sub end_item_number { $_[0]{'scratch'} .= '</p>'; $_[0]->emit }

sub end_item_text   {
    # idify and anchor =item content if wanted
    my $dt_id = $_[0]{'anchor_items'} 
                 ? ' id="'. $_[0]->idify($_[0]{'scratch'}) .'"'
                 : '';

    # reset scratch
    my $text = $_[0]{scratch};
    $_[0]{'scratch'} = '';

    if ($_[0]{'in_dd'}[ $_[0]{'dl_level'} ]) {
        $_[0]{'scratch'} = "</dd>\n";
        $_[0]{'in_dd'}[ $_[0]{'dl_level'} ] = 0;
    }

    $_[0]{'scratch'} .= qq{<dt$dt_id>$text</dt>\n<dd>};
    $_[0]{'in_dd'}[ $_[0]{'dl_level'} ] = 1;
    $_[0]->emit;
}

sub start_for {
  my ($self, $flags) = @_;

  push @{ $self->{__region_targets} }, $flags->{target_matching};

  unless ($self->__in_literal_xhtml_region) {
    $self->{scratch} .= '<div';
    $self->{scratch} .= qq( class="$flags->{target}") if $flags->{target};
    $self->{scratch} .= '>';
  }

  $self->emit;

}
sub end_for {
  my ($self) = @_;

  $self->{'scratch'} .= '</div>' unless $self->__in_literal_xhtml_region;

  pop @{ $self->{__region_targets} };
  $self->emit;
}

sub start_Document {
  my ($self) = @_;
  if (defined $self->html_header) {
    $self->{'scratch'} .= $self->html_header;
    $self->emit unless $self->html_header eq "";
  } else {
    my ($doctype, $title, $metatags, $bodyid);
    $doctype = $self->html_doctype || '';
    $title = $self->force_title || $self->title || $self->default_title || '';
    $metatags = $self->html_header_tags || '';
    if (my $css = $self->html_css) {
        $metatags .= $css;
        if ($css !~ /<link/) {
            # this is required to be compatible with Pod::Simple::BatchHTML
            $metatags .= '<link rel="stylesheet" href="'
                . $self->encode_entities($css) . '" type="text/css" />';
        }
    }
    if ($self->html_javascript) {
      $metatags .= qq{\n<script type="text/javascript" src="} .
                    $self->html_javascript . "'></script>";
    }
    $bodyid = $self->backlink ? ' id="_podtop_"' : '';
    $self->{'scratch'} .= <<"HTML";
$doctype
<html>
<head>
<title>$title</title>
$metatags
</head>
<body$bodyid>
HTML
    $self->emit;
  }
}

sub end_Document   {
  my ($self) = @_;
  my $to_index = $self->{'to_index'};
  if ($self->index && @{ $to_index } ) {
      my @out;
      my $level  = 0;
      my $indent = -1;
      my $space  = '';
      my $id     = ' id="index"';

      for my $h (@{ $to_index }, [0]) {
          my $target_level = $h->[0];
          # Get to target_level by opening or closing ULs
          if ($level == $target_level) {
              $out[-1] .= '</li>';
          } elsif ($level > $target_level) {
              $out[-1] .= '</li>' if $out[-1] =~ /^\s+<li>/;
              while ($level > $target_level) {
                  --$level;
                  push @out, ('  ' x --$indent) . '</li>' if @out && $out[-1] =~ m{^\s+<\/ul};
                  push @out, ('  ' x --$indent) . '</ul>';
              }
              push @out, ('  ' x --$indent) . '</li>' if $level;
          } else {
              while ($level < $target_level) {
                  ++$level;
                  push @out, ('  ' x ++$indent) . '<li>' if @out && $out[-1]=~ /^\s*<ul/;
                  push @out, ('  ' x ++$indent) . "<ul$id>";
                  $id = '';
              }
              ++$indent;
          }

          next unless $level;
          $space = '  '  x $indent;
          push @out, sprintf '%s<li><a href="#%s">%s</a>',
              $space, $h->[1], $h->[2];
      }
      # Splice the index in between the HTML headers and the first element.
      my $offset = defined $self->html_header ? $self->html_header eq '' ? 0 : 1 : 1;
      splice @{ $self->{'output'} }, $offset, 0, join "\n", @out;
  }

  if (defined $self->html_footer) {
    $self->{'scratch'} .= $self->html_footer;
    $self->emit unless $self->html_footer eq "";
  } else {
    $self->{'scratch'} .= "</body>\n</html>";
    $self->emit;
  }

  if ($self->index) {
      print {$self->{'output_fh'}} join ("\n\n", @{ $self->{'output'} }), "\n\n";
      @{$self->{'output'}} = ();
  }

}

sub start_B { $_[0]{'scratch'} .= '<b>' }
sub end_B   { $_[0]{'scratch'} .= '</b>' }

sub start_C { push(@{$_[0]{'in_code'}}, 'C'); $_[0]->start_code($_[0]{'in_code'}[-1]); }
sub end_C   { $_[0]->end_code(pop(@{$_[0]{'in_code'}})); }

sub start_F { $_[0]{'scratch'} .= '<i>' }
sub end_F   { $_[0]{'scratch'} .= '</i>' }

sub start_I { $_[0]{'scratch'} .= '<i>' }
sub end_I   { $_[0]{'scratch'} .= '</i>' }

sub start_L {
  my ($self, $flags) = @_;
    my ($type, $to, $section) = @{$flags}{'type', 'to', 'section'};
    my $url = $self->encode_entities(
        $type eq 'url' ? $to
            : $type eq 'pod' ? $self->resolve_pod_page_link($to, $section)
            : $type eq 'man' ? $self->resolve_man_page_link($to, $section)
            :                  undef
    );

    # If it's an unknown type, use an attribute-less <a> like HTML.pm.
    $self->{'scratch'} .= '<a' . ($url ? ' href="'. $url . '">' : '>');
}

sub end_L   { $_[0]{'scratch'} .= '</a>' }

sub start_S { $_[0]{'scratch'} .= '<span style="white-space: nowrap;">' }
sub end_S   { $_[0]{'scratch'} .= '</span>' }

sub emit {
  my($self) = @_;
  if ($self->index) {
      push @{ $self->{'output'} }, $self->{'scratch'};
  } else {
      print {$self->{'output_fh'}} $self->{'scratch'}, "\n\n";
  }
  $self->{'scratch'} = '';
  return;
}


sub resolve_pod_page_link {
    my ($self, $to, $section) = @_;
    return undef unless defined $to || defined $section;
    if (defined $section) {
        $section = '#' . $self->idify($self->encode_entities($section), 1);
        return $section unless defined $to;
    } else {
        $section = ''
    }

    return ($self->perldoc_url_prefix || '')
        . $self->encode_entities($to) . $section
        . ($self->perldoc_url_postfix || '');
}


sub resolve_man_page_link {
    my ($self, $to, $section) = @_;
    return undef unless defined $to;
    my ($page, $part) = $to =~ /^([^(]+)(?:[(](\d+)[)])?$/;
    return undef unless $page;
    return ($self->man_url_prefix || '')
        . ($part || 1) . "/" . $self->encode_entities($page)
        . ($self->man_url_postfix || '');

}


sub idify {
    my ($self, $t, $not_unique) = @_;
    for ($t) {
        s/<[^>]+>//g;            # Strip HTML.
        s/&[^;]+;//g;            # Strip entities.
        s/^\s+//; s/\s+$//;      # Strip white space.
        s/^([^a-zA-Z]+)$/pod$1/; # Prepend "pod" if no valid chars.
        s/^[^a-zA-Z]+//;         # First char must be a letter.
        s/[^-a-zA-Z0-9_:.]+/-/g; # All other chars must be valid.
        s/[-:.]+$//;             # Strip trailing punctuation.
    }
    return $t if $not_unique;
    my $i = '';
    $i++ while $self->{ids}{"$t$i"}++;
    return "$t$i";
}


sub batch_mode_page_object_init {
  my ($self, $batchconvobj, $module, $infile, $outfile, $depth) = @_;
  $self->batch_mode(1);
  $self->batch_mode_current_level($depth);
  return $self;
}

sub html_header_after_title {
}


1;

__END__

