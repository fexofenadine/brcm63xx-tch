package WWW::Mechanize;


our $VERSION = '1.74';


use strict;
use warnings;

use HTTP::Request 1.30;
use LWP::UserAgent 5.827;
use HTML::Form 1.00;
use HTML::TokeParser;

use base 'LWP::UserAgent';

our $HAS_ZLIB;
BEGIN {
    $HAS_ZLIB = eval 'use Compress::Zlib (); 1;';
}


sub new {
    my $class = shift;

    my %parent_parms = (
        agent       => "WWW-Mechanize/$VERSION",
        cookie_jar  => {},
    );

    my %mech_parms = (
        autocheck   => ($class eq 'WWW::Mechanize' ? 1 : 0),
        onwarn      => \&WWW::Mechanize::_warn,
        onerror     => \&WWW::Mechanize::_die,
        quiet       => 0,
        stack_depth => 8675309,     # Arbitrarily humongous stack
        headers     => {},
        noproxy     => 0,
    );

    my %passed_parms = @_;

    # Keep the mech-specific parms before creating the object.
    while ( my($key,$value) = each %passed_parms ) {
        if ( exists $mech_parms{$key} ) {
            $mech_parms{$key} = $value;
        }
        else {
            $parent_parms{$key} = $value;
        }
    }

    my $self = $class->SUPER::new( %parent_parms );
    bless $self, $class;

    # Use the mech parms now that we have a mech object.
    for my $parm ( keys %mech_parms ) {
        $self->{$parm} = $mech_parms{$parm};
    }
    $self->{page_stack} = [];
    $self->env_proxy() unless $mech_parms{noproxy};

    # libwww-perl 5.800 (and before, I assume) has a problem where
    # $ua->{proxy} can be undef and clone() doesn't handle it.
    $self->{proxy} = {} unless defined $self->{proxy};
    push( @{$self->requests_redirectable}, 'POST' );

    $self->_reset_page();

    return $self;
}


my %known_agents = (
    'Windows IE 6'      => 'Mozilla/4.0 (compatible; MSIE 6.0; Windows NT 5.1)',
    'Windows Mozilla'   => 'Mozilla/5.0 (Windows; U; Windows NT 5.0; en-US; rv:1.4b) Gecko/20030516 Mozilla Firebird/0.6',
    'Mac Safari'        => 'Mozilla/5.0 (Macintosh; U; PPC Mac OS X; en-us) AppleWebKit/85 (KHTML, like Gecko) Safari/85',
    'Mac Mozilla'       => 'Mozilla/5.0 (Macintosh; U; PPC Mac OS X Mach-O; en-US; rv:1.4a) Gecko/20030401',
    'Linux Mozilla'     => 'Mozilla/5.0 (X11; U; Linux i686; en-US; rv:1.4) Gecko/20030624',
    'Linux Konqueror'   => 'Mozilla/5.0 (compatible; Konqueror/3; Linux)',
);

sub agent_alias {
    my $self = shift;
    my $alias = shift;

    if ( defined $known_agents{$alias} ) {
        return $self->agent( $known_agents{$alias} );
    }
    else {
        $self->warn( qq{Unknown agent alias "$alias"} );
        return $self->agent();
    }
}


sub known_agent_aliases {
    return sort keys %known_agents;
}


sub get {
    my $self = shift;
    my $uri = shift;

    $uri = $uri->url if ref($uri) eq 'WWW::Mechanize::Link';

    $uri = $self->base
            ? URI->new_abs( $uri, $self->base )
            : URI->new( $uri );

    # It appears we are returning a super-class method,
    # but it in turn calls the request() method here in Mechanize
    return $self->SUPER::get( $uri->as_string, @_ );
}


sub put {
    my $self = shift;
    my $uri = shift;

    $uri = $uri->url if ref($uri) eq 'WWW::Mechanize::Link';

    $uri = $self->base
            ? URI->new_abs( $uri, $self->base )
            : URI->new( $uri );

    # It appears we are returning a super-class method,
    # but it in turn calls the request() method here in Mechanize
    return $self->_SUPER_put( $uri->as_string, @_ );
}


sub _SUPER_put {
    require HTTP::Request::Common;
    my($self, @parameters) = @_;
    my @suff = $self->_process_colonic_headers(\@parameters,1);
    return $self->request( HTTP::Request::Common::PUT( @parameters ), @suff );
}


sub reload {
    my $self = shift;

    return unless my $req = $self->{req};

    return $self->_update_page( $req, $self->_make_request( $req, @_ ) );
}


sub back {
    my $self = shift;

    my $stack = $self->{page_stack};
    return unless $stack && @{$stack};

    my $popped = pop @{$self->{page_stack}};
    my $req    = $popped->{req};
    my $res    = $popped->{res};

    $self->_update_page( $req, $res );

    return 1;
}


sub success {
    my $self = shift;

    return $self->res && $self->res->is_success;
}



sub uri {
    my $self = shift;
    return $self->response->request->uri;
}

sub res {           my $self = shift; return $self->{res}; }
sub response {      my $self = shift; return $self->{res}; }
sub status {        my $self = shift; return $self->{status}; }
sub ct {            my $self = shift; return $self->{ct}; }
sub content_type {  my $self = shift; return $self->{ct}; }
sub base {          my $self = shift; return $self->{base}; }
sub is_html {
    my $self = shift;
    return defined $self->ct &&
        ($self->ct eq 'text/html' || $self->ct eq 'application/xhtml+xml');
}


sub title {
    my $self = shift;

    return unless $self->is_html;

    if ( not defined $self->{title} ) {
        require HTML::HeadParser;
        my $p = HTML::HeadParser->new;
        $p->parse($self->content);
        $self->{title} = $p->header('Title');
    }
    return $self->{title};
}


sub content {
    my $self = shift;
    my %parms = @_;

    my $content = $self->{content};
    if (delete $parms{raw}) {
        $content = $self->response()->content();
    }
    elsif (delete $parms{decoded_by_headers}) {
        $content = $self->response()->decoded_content(charset => 'none');
    }
    elsif (my $charset = delete $parms{charset}) {
        $content = $self->response()->decoded_content(charset => $charset);
    }
    elsif ( $self->is_html ) {
        if ( exists $parms{base_href} ) {
            my $base_href = (delete $parms{base_href}) || $self->base;
            $content=~s/<head>/<head>\n<base href="$base_href">/i;
        }

        if ( my $format = delete $parms{format} ) {
            if ( $format eq 'text' ) {
                $content = $self->text;
            }
            else {
                $self->die( qq{Unknown "format" parameter "$format"} );
            }
        }

        $self->_check_unhandled_parms( %parms );
    }

    return $content;
}


sub text {
    my $self = shift;

    if ( not defined $self->{text} ) {
        require HTML::TreeBuilder;
        my $tree = HTML::TreeBuilder->new();
        $tree->parse( $self->content );
        $tree->eof();
        $tree->elementify(); # just for safety
        $self->{text} = $tree->as_text();
        $tree->delete;
    }

    return $self->{text};
}

sub _check_unhandled_parms {
    my $self  = shift;
    my %parms = @_;

    for my $cmd ( sort keys %parms ) {
        $self->die( qq{Unknown named argument "$cmd"} );
    }
}


sub links {
    my $self = shift;

    $self->_extract_links() unless $self->{links};

    return @{$self->{links}} if wantarray;
    return $self->{links};
}


sub follow_link {
    my $self = shift;
    $self->die( qq{Needs to get key-value pairs of parameters.} ) if @_ % 2;
    my %parms = ( n=>1, @_ );

    if ( $parms{n} eq 'all' ) {
        delete $parms{n};
        $self->warn( q{follow_link(n=>"all") is not valid} );
    }

    my $link = $self->find_link(%parms);
    if ( $link ) {
        return $self->get( $link->url );
    }

    if ( $self->{autocheck} ) {
        $self->die( 'Link not found' );
    }

    return;
}


sub find_link {
    my $self = shift;
    my %parms = ( n=>1, @_ );

    my $wantall = ( $parms{n} eq 'all' );

    $self->_clean_keys( \%parms, qr/^(n|(text|url|url_abs|name|tag|id|class)(_regex)?)$/ );

    my @links = $self->links or return;

    my $nmatches = 0;
    my @matches;
    for my $link ( @links ) {
        if ( _match_any_link_parms($link,\%parms) ) {
            if ( $wantall ) {
                push( @matches, $link );
            }
            else {
                ++$nmatches;
                return $link if $nmatches >= $parms{n};
            }
        }
    } # for @links

    if ( $wantall ) {
        return @matches if wantarray;
        return \@matches;
    }

    return;
} # find_link

sub _match_any_link_parms {
    my $link = shift;
    my $p = shift;

    # No conditions, anything matches
    return 1 unless keys %$p;

    return if defined $p->{url}           && !($link->url eq $p->{url} );
    return if defined $p->{url_regex}     && !($link->url =~ $p->{url_regex} );
    return if defined $p->{url_abs}       && !($link->url_abs eq $p->{url_abs} );
    return if defined $p->{url_abs_regex} && !($link->url_abs =~ $p->{url_abs_regex} );
    return if defined $p->{text}          && !(defined($link->text) && $link->text eq $p->{text} );
    return if defined $p->{text_regex}    && !(defined($link->text) && $link->text =~ $p->{text_regex} );
    return if defined $p->{name}          && !(defined($link->name) && $link->name eq $p->{name} );
    return if defined $p->{name_regex}    && !(defined($link->name) && $link->name =~ $p->{name_regex} );
    return if defined $p->{tag}           && !($link->tag && $link->tag eq $p->{tag} );
    return if defined $p->{tag_regex}     && !($link->tag && $link->tag =~ $p->{tag_regex} );

    return if defined $p->{id}            && !($link->attrs->{id} && $link->attrs->{id} eq $p->{id} );
    return if defined $p->{id_regex}      && !($link->attrs->{id} && $link->attrs->{id} =~ $p->{id_regex} );
    return if defined $p->{class}         && !($link->attrs->{class} && $link->attrs->{class} eq $p->{class} );
    return if defined $p->{class_regex}   && !($link->attrs->{class} && $link->attrs->{class} =~ $p->{class_regex} );

    # Success: everything that was defined passed.
    return 1;

}

sub _clean_keys {
    my $self = shift;
    my $parms = shift;
    my $rx_keyname = shift;

    for my $key ( keys %$parms ) {
        my $val = $parms->{$key};
        if ( $key !~ qr/$rx_keyname/ ) {
            $self->warn( qq{Unknown link-finding parameter "$key"} );
            delete $parms->{$key};
            next;
        }

        my $key_regex = ( $key =~ /_regex$/ );
        my $val_regex = ( ref($val) eq 'Regexp' );

        if ( $key_regex ) {
            if ( !$val_regex ) {
                $self->warn( qq{$val passed as $key is not a regex} );
                delete $parms->{$key};
                next;
            }
        }
        else {
            if ( $val_regex ) {
                $self->warn( qq{$val passed as '$key' is a regex} );
                delete $parms->{$key};
                next;
            }
            if ( $val =~ /^\s|\s$/ ) {
                $self->warn( qq{'$val' is space-padded and cannot succeed} );
                delete $parms->{$key};
                next;
            }
        }
    } # for keys %parms

    return;
} # _clean_keys()



sub find_all_links {
    my $self = shift;
    return $self->find_link( @_, n=>'all' );
}


sub find_all_inputs {
    my $self = shift;
    my %criteria = @_;

    my $form = $self->current_form() or return;

    my @found;
    foreach my $input ( $form->inputs ) { # check every pattern for a match on the current hash
        my $matched = 1;
        foreach my $criterion ( sort keys %criteria ) { # Sort so we're deterministic
            my $field = $criterion;
            my $is_regex = ( $field =~ s/(?:_regex)$// );
            my $what = $input->{$field};
            $matched = defined($what) && (
                $is_regex
                    ? ( $what =~ $criteria{$criterion} )
                    : ( $what eq $criteria{$criterion} )
                );
            last if !$matched;
        }
        push @found, $input if $matched;
    }
    return @found;
}


sub find_all_submits {
    my $self = shift;

    return $self->find_all_inputs( @_, type_regex => qr/^(submit|image)$/ );
}



sub images {
    my $self = shift;

    $self->_extract_images() unless $self->{images};

    return @{$self->{images}} if wantarray;
    return $self->{images};
}


sub find_image {
    my $self = shift;
    my %parms = ( n=>1, @_ );

    my $wantall = ( $parms{n} eq 'all' );

    $self->_clean_keys( \%parms, qr/^(n|(alt|url|url_abs|tag)(_regex)?)$/ );

    my @images = $self->images or return;

    my $nmatches = 0;
    my @matches;
    for my $image ( @images ) {
        if ( _match_any_image_parms($image,\%parms) ) {
            if ( $wantall ) {
                push( @matches, $image );
            }
            else {
                ++$nmatches;
                return $image if $nmatches >= $parms{n};
            }
        }
    } # for @images

    if ( $wantall ) {
        return @matches if wantarray;
        return \@matches;
    }

    return;
}

sub _match_any_image_parms {
    my $image = shift;
    my $p = shift;

    # No conditions, anything matches
    return 1 unless keys %$p;

    return if defined $p->{url}           && !($image->url eq $p->{url} );
    return if defined $p->{url_regex}     && !($image->url =~ $p->{url_regex} );
    return if defined $p->{url_abs}       && !($image->url_abs eq $p->{url_abs} );
    return if defined $p->{url_abs_regex} && !($image->url_abs =~ $p->{url_abs_regex} );
    return if defined $p->{alt}           && !(defined($image->alt) && $image->alt eq $p->{alt} );
    return if defined $p->{alt_regex}     && !(defined($image->alt) && $image->alt =~ $p->{alt_regex} );
    return if defined $p->{tag}           && !($image->tag && $image->tag eq $p->{tag} );
    return if defined $p->{tag_regex}     && !($image->tag && $image->tag =~ $p->{tag_regex} );

    # Success: everything that was defined passed.
    return 1;
}



sub find_all_images {
    my $self = shift;
    return $self->find_image( @_, n=>'all' );
}


sub forms {
    my $self = shift;

    $self->_extract_forms() unless $self->{forms};

    return @{$self->{forms}} if wantarray;
    return $self->{forms};
}

sub current_form {
    my $self = shift;

    if ( !$self->{current_form} ) {
        $self->form_number(1);
    }

    return $self->{current_form};
}


sub form_number {
    my ($self, $form) = @_;
    # XXX Should we die if no $form is defined? Same question for form_name()

    my $forms = $self->forms;
    if ( $forms->[$form-1] ) {
        $self->{current_form} = $forms->[$form-1];
        return $self->{current_form};
    }

    return;
}


sub form_name {
    my ($self, $form) = @_;

    my $temp;
    my @matches = grep {defined($temp = $_->attr('name')) and ($temp eq $form) } $self->forms;

    my $nmatches = @matches;
    if ( $nmatches > 0 ) {
        if ( $nmatches > 1 ) {
            $self->warn( "There are $nmatches forms named $form.  The first one was used." )
        }
        return $self->{current_form} = $matches[0];
    }

    return;
}


sub form_id {
    my ($self, $formid) = @_;

    my $temp;
    my @matches = grep { defined($temp = $_->attr('id')) and ($temp eq $formid) } $self->forms;
    if ( @matches ) {
        $self->warn( 'There are ', scalar @matches, " forms with ID $formid.  The first one was used." )
            if @matches > 1;
        return $self->{current_form} = $matches[0];
    }
    else {
        $self->warn( qq{ There is no form with ID "$formid"} );
        return undef;
    }
}



sub form_with_fields {
    my ($self, @fields) = @_;
    die 'no fields provided' unless scalar @fields;

    my @matches;
    FORMS: for my $form (@{ $self->forms }) {
        my @fields_in_form = $form->param();
        for my $field (@fields) {
            next FORMS unless grep { $_ eq $field } @fields_in_form;
        }
        push @matches, $form;
    }

    my $nmatches = @matches;
    if ( $nmatches > 0 ) {
        if ( $nmatches > 1 ) {
            $self->warn( "There are $nmatches forms with the named fields.  The first one was used." )
        }
        return $self->{current_form} = $matches[0];
    }
    else {
        $self->warn( qq{There is no form with the requested fields} );
        return undef;
    }
}


sub field {
    my ($self, $name, $value, $number) = @_;
    $number ||= 1;

    my $form = $self->current_form();
    if ($number > 1) {
        $form->find_input($name, undef, $number)->value($value);
    }
    else {
        if ( ref($value) eq 'ARRAY' ) {
            $form->param($name, $value);
        }
        else {
            $form->value($name => $value);
        }
    }
}


sub select {
    my ($self, $name, $value) = @_;

    my $form = $self->current_form();

    my $input = $form->find_input($name);
    if (!$input) {
        $self->warn( qq{Input "$name" not found} );
        return;
    }

    if ($input->type ne 'option') {
        $self->warn( qq{Input "$name" is not type "select"} );
        return;
    }

    # For $mech->select($name, {n => 3}) or $mech->select($name, {n => [2,4]}),
    # transform the 'n' number(s) into value(s) and put it in $value.
    if (ref($value) eq 'HASH') {
        for (keys %$value) {
            $self->warn(qq{Unknown select value parameter "$_"})
              unless $_ eq 'n';
        }

        if (defined($value->{n})) {
            my @inputs = $form->find_input($name, 'option');
            my @values = ();
            # distinguish between multiple and non-multiple selects
            # (see INPUTS section of `perldoc HTML::Form`)
            if (@inputs == 1) {
                @values = $inputs[0]->possible_values();
            }
            else {
                foreach my $input (@inputs) {
                    my @possible = $input->possible_values();
                    push @values, pop @possible;
                }
            }

            my $n = $value->{n};
            if (ref($n) eq 'ARRAY') {
                $value = [];
                for (@$n) {
                    unless (/^\d+$/) {
                        $self->warn(qq{"n" value "$_" is not a positive integer});
                        return;
                    }
                    push @$value, $values[$_ - 1];  # might be undef
                }
            }
            elsif (!ref($n) && $n =~ /^\d+$/) {
                $value = $values[$n - 1];           # might be undef
            }
            else {
                $self->warn('"n" value is not a positive integer or an array ref');
                return;
            }
        }
        else {
            $self->warn('Hash value is invalid');
            return;
        }
    } # hashref

    if (ref($value) eq 'ARRAY') {
        $form->param($name, $value);
        return 1;
    }

    $form->value($name => $value);
    return 1;
}


sub set_fields {
    my $self = shift;
    my %fields = @_;

    my $form = $self->current_form or $self->die( 'No form defined' );

    while ( my ( $field, $value ) = each %fields ) {
        if ( ref $value eq 'ARRAY' ) {
            $form->find_input( $field, undef,
                         $value->[1])->value($value->[0] );
        }
        else {
            $form->value($field => $value);
        }
    } # while
} # set_fields()


sub set_visible {
    my $self = shift;

    my $form = $self->current_form;
    my @inputs = $form->inputs;

    my $num_set = 0;
    for my $value ( @_ ) {
        # Handle type/value pairs an arrayref
        if ( ref $value eq 'ARRAY' ) {
            my ( $type, $value ) = @$value;
            while ( my $input = shift @inputs ) {
                next if $input->type eq 'hidden';
                if ( $input->type eq $type ) {
                    $input->value( $value );
                    $num_set++;
                    last;
                }
            } # while
        }
        # by default, it's a value
        else {
            while ( my $input = shift @inputs ) {
                next if $input->type eq 'hidden';
                $input->value( $value );
                $num_set++;
                last;
            } # while
        }
    } # for

    return $num_set;
} # set_visible()


sub tick {
    my $self = shift;
    my $name = shift;
    my $value = shift;
    my $set = @_ ? shift : 1;  # default to 1 if not passed

    # loop though all the inputs
    my $index = 0;
    while ( my $input = $self->current_form->find_input( $name, 'checkbox', $index ) ) {
        # Can't guarantee that the first element will be undef and the second
        # element will be the right name
        foreach my $val ($input->possible_values()) {
            next unless defined $val;
            if ($val eq $value) {
                $input->value($set ? $value : undef);
                return;
            }
        }

        # move onto the next input
        $index++;
    } # while

    # got self far?  Didn't find anything
    $self->warn( qq{No checkbox "$name" for value "$value" in form} );
} # tick()


sub untick {
    shift->tick(shift,shift,undef);
}


sub value {
    my $self = shift;
    my $name = shift;
    my $number = shift || 1;

    my $form = $self->current_form;
    if ( $number > 1 ) {
        return $form->find_input( $name, undef, $number )->value();
    }
    else {
        return $form->value( $name );
    }
} # value


sub click {
    my ($self, $button, $x, $y) = @_;
    for ($x, $y) { $_ = 1 unless defined; }
    my $request = $self->current_form->click($button, $x, $y);
    return $self->request( $request );
}


sub click_button {
    my $self = shift;
    my %args = @_;

    for ( keys %args ) {
        if ( !/^(number|name|value|input|x|y)$/ ) {
            $self->warn( qq{Unknown click_button parameter "$_"} );
        }
    }

    for ($args{x}, $args{y}) {
        $_ = 1 unless defined;
    }

    my $form = $self->current_form or $self->die( 'click_button: No form has been selected' );

    my $request;
    if ( $args{name} ) {
        $request = $form->click( $args{name}, $args{x}, $args{y} );
    }
    elsif ( $args{number} ) {
        my $input = $form->find_input( undef, 'submit', $args{number} );
        $request = $input->click( $form, $args{x}, $args{y} );
    }
    elsif ( $args{input} ) {
        $request = $args{input}->click( $form, $args{x}, $args{y} );
    }
    elsif ( $args{value} ) {
        my $i = 1;
        while ( my $input = $form->find_input(undef, 'submit', $i) ) {
            if ( $args{value} && ($args{value} eq $input->value) ) {
                $request = $input->click( $form, $args{x}, $args{y} );
                last;
            }
            $i++;
        } # while
    } # $args{value}

    return $self->request( $request );
}


sub submit {
    my $self = shift;

    my $request = $self->current_form->make_request;
    return $self->request( $request );
}


sub submit_form {
    my( $self, %args ) = @_;

    for ( keys %args ) {
        if ( !/^(form_(number|name|fields|id)|(with_)?fields|button|x|y)$/ ) {
            # XXX Why not die here?
            $self->warn( qq{Unknown submit_form parameter "$_"} );
        }
    }

    my $fields;
    for (qw/with_fields fields/) {
        if ($args{$_}) {
            if ( ref $args{$_} eq 'HASH' ) {
                $fields = $args{$_};
            }
            else {
                die "$_ arg to submit_form must be a hashref";
            }
            last;
        }
    }

    if ( $args{with_fields} ) {
        $fields || die q{must submit some 'fields' with with_fields};
        $self->form_with_fields(keys %{$fields}) or die "There is no form with the requested fields";
    }
    elsif ( my $form_number = $args{form_number} ) {
        $self->form_number( $form_number ) or die "There is no form numbered $form_number";
    }
    elsif ( my $form_name = $args{form_name} ) {
        $self->form_name( $form_name ) or die qq{There is no form named "$form_name"};
    }
    elsif ( my $form_id = $args{form_id} ) {
        $self->form_id( $form_id ) or die qq{There is no form with ID "$form_id"};
    }
    else {
        # No form selector was used.
        # Maybe a form was set separately, or we'll default to the first form.
    }

    $self->set_fields( %{$fields} ) if $fields;

    my $response;
    if ( $args{button} ) {
        $response = $self->click( $args{button}, $args{x} || 0, $args{y} || 0 );
    }
    else {
        $response = $self->submit();
    }

    return $response;
}


sub add_header {
    my $self = shift;
    my $npairs = 0;

    while ( @_ ) {
        my $key = shift;
        my $value = shift;
        ++$npairs;

        $self->{headers}{$key} = $value;
    }

    return $npairs;
}


sub delete_header {
    my $self = shift;

    while ( @_ ) {
        my $key = shift;

        delete $self->{headers}{$key};
    }

    return;
}



sub quiet {
    my $self = shift;

    $self->{quiet} = $_[0] if @_;

    return $self->{quiet};
}


sub stack_depth {
    my $self = shift;
    $self->{stack_depth} = shift if @_;
    return $self->{stack_depth};
}


sub save_content {
    my $self = shift;
    my $filename = shift;
    my %opts = @_;
    if (delete $opts{binary}) {
        $opts{binmode} = ':raw';
        $opts{decoded_by_headers} = 1;
    }

    open( my $fh, '>', $filename ) or $self->die( "Unable to create $filename: $!" );
    if ((my $binmode = delete($opts{binmode}) || '') || ($self->content_type() !~ m{^text/})) {
        if (length($binmode) && (substr($binmode, 0, 1) eq ':')) {
            binmode $fh, $binmode;
        }
        else {
            binmode $fh;
        }
    }
    print {$fh} $self->content(%opts) or $self->die( "Unable to write to $filename: $!" );
    close $fh or $self->die( "Unable to close $filename: $!" );

    return;
}



sub _get_fh_default_stdout {
    my $self = shift;
    my $p = shift || '';
    if ( !$p ) {
        return \*STDOUT;
    } elsif ( !ref($p) ) {
        open my $fh, '>', $p or $self->die( "Unable to write to $p: $!" );;
        return $fh;
    } else {
        return $p;
    }
}

sub dump_headers {
    my $self = shift;
    my $fh   = $self->_get_fh_default_stdout(shift);

    print {$fh} $self->response->headers_as_string;

    return;
}



sub dump_links {
    my $self = shift;
    my $fh = shift || \*STDOUT;
    my $absolute = shift;

    for my $link ( $self->links ) {
        my $url = $absolute ? $link->url_abs : $link->url;
        $url = '' if not defined $url;
        print {$fh} $url, "\n";
    }
    return;
}


sub dump_images {
    my $self = shift;
    my $fh = shift || \*STDOUT;
    my $absolute = shift;

    for my $image ( $self->images ) {
        my $url = $absolute ? $image->url_abs : $image->url;
        $url = '' if not defined $url;
        print {$fh} $url, "\n";
    }
    return;
}


sub dump_forms {
    my $self = shift;
    my $fh = shift || \*STDOUT;

    for my $form ( $self->forms ) {
        print {$fh} $form->dump, "\n";
    }
    return;
}


sub dump_text {
    my $self = shift;
    my $fh = shift || \*STDOUT;
    my $absolute = shift;

    print {$fh} $self->text, "\n";

    return;
}



sub clone {
    my $self  = shift;
    my $clone = $self->SUPER::clone();

    $clone->cookie_jar( $self->cookie_jar );

    return $clone;
}



sub redirect_ok {
    my $self = shift;
    my $prospective_request = shift;
    my $response = shift;

    my $ok = $self->SUPER::redirect_ok( $prospective_request, $response );
    if ( $ok ) {
        $self->{redirected_uri} = $prospective_request->uri;
    }

    return $ok;
}



sub request {
    my $self = shift;
    my $request = shift;

    $request = $self->_modify_request( $request );

    if ( $request->method eq 'GET' || $request->method eq 'POST' ) {
        $self->_push_page_stack();
    }

    return $self->_update_page($request, $self->_make_request( $request, @_ ));
}


sub update_html {
    my $self = shift;
    my $html = shift;

    $self->_reset_page;
    $self->{ct} = 'text/html';
    $self->{content} = $html;

    return;
}


sub credentials {
    my $self = shift;

    # The latest LWP::UserAgent also supports 2 arguments,
    # in which case the first is host:port
    if (@_ == 4 || (@_ == 2 && $_[0] =~ /:\d+$/)) {
        return $self->SUPER::credentials(@_);
    }

    @_ == 2
        or $self->die( 'Invalid # of args for overridden credentials()' );

    return @$self{qw( __username __password )} = @_;
}


sub get_basic_credentials {
    my $self = shift;
    my @cred = grep { defined } @$self{qw( __username __password )};
    return @cred if @cred == 2;
    return $self->SUPER::get_basic_credentials(@_);
}


sub clear_credentials {
    my $self = shift;
    delete @$self{qw( __username __password )};
}


sub _update_page {
    my ($self, $request, $res) = @_;

    $self->{req} = $request;
    $self->{redirected_uri} = $request->uri->as_string;

    $self->{res} = $res;

    $self->{status}  = $res->code;
    $self->{base}    = $res->base;
    $self->{ct}      = $res->content_type || '';

    if ( $res->is_success ) {
        $self->{uri} = $self->{redirected_uri};
        $self->{last_uri} = $self->{uri};
    }

    if ( $res->is_error ) {
        if ( $self->{autocheck} ) {
            $self->die( 'Error ', $request->method, 'ing ', $request->uri, ': ', $res->message );
        }
    }

    $self->_reset_page;

    # Try to decode the content. Undef will be returned if there's nothing to decompress.
    # See docs in HTTP::Message for details. Do we need to expose the options there?
    my $content = $res->decoded_content();
    $content = $res->content if (not defined $content);

    $content .= _taintedness();

    if ($self->is_html) {
        $self->update_html($content);
    }
    else {
        $self->{content} = $content;
    }

    return $res;
} # _update_page

our $_taintbrush;

sub _taintedness {
    return $_taintbrush if defined $_taintbrush;

    # Somehow we need to get some taintedness into our $_taintbrush.
    # Let's try the easy way first. Either of these should be
    # tainted, unless somebody has untainted them, so this
    # will almost always work on the first try.
    # (Unless, of course, taint checking has been turned off!)
    $_taintbrush = substr("$0$^X", 0, 0);
    return $_taintbrush if _is_tainted( $_taintbrush );

    # Let's try again. Maybe somebody cleaned those.
    $_taintbrush = substr(join('', grep { defined } @ARGV, %ENV), 0, 0);
    return $_taintbrush if _is_tainted( $_taintbrush );

    # If those don't work, go try to open some file from some unsafe
    # source and get data from them.  That data is tainted.
    # (Yes, even reading from /dev/null works!)
    for my $filename ( qw(/dev/null / . ..), values %INC, $0, $^X ) {
        if ( open my $fh, '<', $filename ) {
            my $data;
            if ( defined sysread $fh, $data, 1 ) {
                $_taintbrush = substr( $data, 0, 0 );
                last if _is_tainted( $_taintbrush );
            }
        }
    }

    # Sanity check
    die "Our taintbrush should have zero length!" if length $_taintbrush;

    return $_taintbrush;
}

sub _is_tainted {
    no warnings qw(void uninitialized);

    return !eval { join('', shift), kill 0; 1 };
} # _is_tainted



sub _modify_request {
    my $self = shift;
    my $req = shift;

    # add correct Accept-Encoding header to restore compliance with
    # http://www.freesoft.org/CIE/RFC/2068/158.htm
    # http://use.perl.org/~rhesa/journal/25952
    if (not $req->header( 'Accept-Encoding' ) ) {
        # "identity" means "please! unencoded content only!"
        $req->header( 'Accept-Encoding', $HAS_ZLIB ? 'gzip' : 'identity' );
    }

    my $last = $self->{last_uri};
    if ( $last ) {
        $last = $last->as_string if ref($last);
        $req->header( Referer => $last );
    }
    while ( my($key,$value) = each %{$self->{headers}} ) {
        if ( defined $value ) {
            $req->header( $key => $value );
        }
        else {
            $req->remove_header( $key );
        }
    }

    return $req;
}



sub _make_request {
    my $self = shift;
    return $self->SUPER::request(@_);
}


sub _reset_page {
    my $self = shift;

    $self->{links}        = undef;
    $self->{images}       = undef;
    $self->{forms}        = undef;
    $self->{current_form} = undef;
    $self->{title}        = undef;
    $self->{text}         = undef;

    return;
}


my %link_tags = (
    a      => 'href',
    area   => 'href',
    frame  => 'src',
    iframe => 'src',
    link   => 'href',
    meta   => 'content',
);

sub _extract_links {
    my $self = shift;


    $self->{links} = [];
    if ( defined $self->{content} ) {
        my $parser = HTML::TokeParser->new(\$self->{content});
        while ( my $token = $parser->get_tag( keys %link_tags ) ) {
            my $link = $self->_link_from_token( $token, $parser );
            push( @{$self->{links}}, $link ) if $link;
        } # while
    }

    return;
}


my %image_tags = (
    img   => 'src',
    input => 'src',
);

sub _extract_images {
    my $self = shift;

    $self->{images} = [];

    if ( defined $self->{content} ) {
        my $parser = HTML::TokeParser->new(\$self->{content});
        while ( my $token = $parser->get_tag( keys %image_tags ) ) {
            my $image = $self->_image_from_token( $token, $parser );
            push( @{$self->{images}}, $image ) if $image;
        } # while
    }

    return;
}

sub _image_from_token {
    my $self = shift;
    my $token = shift;
    my $parser = shift;

    my $tag = $token->[0];
    my $attrs = $token->[1];

    if ( $tag eq 'input' ) {
        my $type = $attrs->{type} or return;
        return unless $type eq 'image';
    }

    require WWW::Mechanize::Image;
    return
        WWW::Mechanize::Image->new({
            tag     => $tag,
            base    => $self->base,
            url     => $attrs->{src},
            name    => $attrs->{name},
            height  => $attrs->{height},
            width   => $attrs->{width},
            alt     => $attrs->{alt},
        });
}

sub _link_from_token {
    my $self = shift;
    my $token = shift;
    my $parser = shift;

    my $tag = $token->[0];
    my $attrs = $token->[1];
    my $url = $attrs->{$link_tags{$tag}};

    my $text;
    my $name;
    if ( $tag eq 'a' ) {
        $text = $parser->get_trimmed_text("/$tag");
        $text = '' unless defined $text;

        my $onClick = $attrs->{onclick};
        if ( $onClick && ($onClick =~ /^window\.open\(\s*'([^']+)'/) ) {
            $url = $1;
        }
    } # a

    # Of the tags we extract from, only 'AREA' has an alt tag
    # The rest should have a 'name' attribute.
    # ... but we don't do anything with that bit of wisdom now.

    $name = $attrs->{name};

    if ( $tag eq 'meta' ) {
        my $equiv = $attrs->{'http-equiv'};
        my $content = $attrs->{'content'};
        return unless $equiv && (lc $equiv eq 'refresh') && defined $content;

        if ( $content =~ /^\d+\s*;\s*url\s*=\s*(\S+)/i ) {
            $url = $1;
            $url =~ s/^"(.+)"$/$1/ or $url =~ s/^'(.+)'$/$1/;
        }
        else {
            undef $url;
        }
    } # meta

    return unless defined $url;   # probably just a name link or <AREA NOHREF...>

    require WWW::Mechanize::Link;
    return
        WWW::Mechanize::Link->new({
            url  => $url,
            text => $text,
            name => $name,
            tag  => $tag,
            base => $self->base,
            attrs => $attrs,
        });
} # _link_from_token


sub _extract_forms {
    my $self = shift;

    my @forms = HTML::Form->parse( $self->content, $self->base );
    $self->{forms} = \@forms;
    for my $form ( @forms ) {
        for my $input ($form->inputs) {
             if ($input->type eq 'file') {
                 $input->value( undef );
             }
        }
    }

    return;
}


sub _push_page_stack {
    my $self = shift;

    my $req = $self->{req};
    my $res = $self->{res};

    return unless $req && $res && $self->stack_depth;

    # Don't push anything if it's a virgin object
    my $stack = $self->{page_stack} ||= [];
    if ( @{$stack} >= $self->stack_depth ) {
        shift @{$stack};
    }
    push( @{$stack}, { req => $req, res => $res } );

    return 1;
}


sub warn {
    my $self = shift;

    return unless my $handler = $self->{onwarn};

    return if $self->quiet;

    return $handler->(@_);
}


sub die {
    my $self = shift;

    return unless my $handler = $self->{onerror};

    return $handler->(@_);
}


sub _warn {
    require Carp;
    return &Carp::carp; ## no critic
}

sub _die {
    require Carp;
    return &Carp::croak; ## no critic
}

1; # End of module

__END__

