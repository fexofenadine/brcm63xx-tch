package HTML::Form;

use strict;
use URI;
use Carp ();

use vars qw($VERSION $Encode_available);
$VERSION = "5.829";

eval { require Encode };
$Encode_available = !$@;

my %form_tags = map {$_ => 1} qw(input textarea button select option);

my %type2class = (
 text     => "TextInput",
 password => "TextInput",
 hidden   => "TextInput",
 textarea => "TextInput",

 "reset"  => "IgnoreInput",

 radio    => "ListInput",
 checkbox => "ListInput",
 option   => "ListInput",

 button   => "SubmitInput",
 submit   => "SubmitInput",
 image    => "ImageInput",
 file     => "FileInput",

 keygen   => "KeygenInput",
);


sub parse
{
    my $class = shift;
    my $html = shift;
    unshift(@_, "base") if @_ == 1;
    my %opt = @_;

    require HTML::TokeParser;
    my $p = HTML::TokeParser->new(ref($html) ? $html->decoded_content(ref => 1) : \$html);
    die "Failed to create HTML::TokeParser object" unless $p;

    my $base_uri = delete $opt{base};
    my $charset = delete $opt{charset};
    my $strict = delete $opt{strict};
    my $verbose = delete $opt{verbose};

    if ($^W) {
	Carp::carp("Unrecognized option $_ in HTML::Form->parse") for sort keys %opt;
    }

    unless (defined $base_uri) {
	if (ref($html)) {
	    $base_uri = $html->base;
	}
	else {
	    Carp::croak("HTML::Form::parse: No \$base_uri provided");
	}
    }
    unless (defined $charset) {
	if (ref($html) and $html->can("content_charset")) {
	    $charset = $html->content_charset;
	}
	unless ($charset) {
	    $charset = "UTF-8";
	}
    }

    my @forms;
    my $f;  # current form

    my %openselect; # index to the open instance of a select

    while (my $t = $p->get_tag) {
	my($tag,$attr) = @$t;
	if ($tag eq "form") {
	    my $action = delete $attr->{'action'};
	    $action = "" unless defined $action;
	    $action = URI->new_abs($action, $base_uri);
	    $f = $class->new($attr->{'method'},
			     $action,
			     $attr->{'enctype'});
            $f->accept_charset($attr->{'accept-charset'}) if $attr->{'accept-charset'};
	    $f->{default_charset} = $charset;
	    $f->{attr} = $attr;
	    $f->strict(1) if $strict;
            %openselect = ();
	    push(@forms, $f);
	    my(%labels, $current_label);
	    while (my $t = $p->get_tag) {
		my($tag, $attr) = @$t;
		last if $tag eq "/form";

		# if we are inside a label tag, then keep
		# appending any text to the current label
		if(defined $current_label) {
		    $current_label = join " ",
		        grep { defined and length }
		        $current_label,
		        $p->get_phrase;
		}

		if ($tag eq "input") {
		    $attr->{value_name} =
		        exists $attr->{id} && exists $labels{$attr->{id}} ? $labels{$attr->{id}} :
			defined $current_label                            ?  $current_label      :
		        $p->get_phrase;
		}

		if ($tag eq "label") {
		    $current_label = $p->get_phrase;
		    $labels{ $attr->{for} } = $current_label
		        if exists $attr->{for};
		}
		elsif ($tag eq "/label") {
		    $current_label = undef;
		}
		elsif ($tag eq "input") {
		    my $type = delete $attr->{type} || "text";
		    $f->push_input($type, $attr, $verbose);
		}
                elsif ($tag eq "button") {
                    my $type = delete $attr->{type} || "submit";
                    $f->push_input($type, $attr, $verbose);
                }
		elsif ($tag eq "textarea") {
		    $attr->{textarea_value} = $attr->{value}
		        if exists $attr->{value};
		    my $text = $p->get_text("/textarea");
		    $attr->{value} = $text;
		    $f->push_input("textarea", $attr, $verbose);
		}
		elsif ($tag eq "select") {
		    # rename attributes reserved to come for the option tag
		    for ("value", "value_name") {
			$attr->{"select_$_"} = delete $attr->{$_}
			    if exists $attr->{$_};
		    }
		    # count this new select option separately
		    my $name = $attr->{name};
		    $name = "" unless defined $name;
		    $openselect{$name}++;

		    while ($t = $p->get_tag) {
			my $tag = shift @$t;
			last if $tag eq "/select";
			next if $tag =~ m,/?optgroup,;
			next if $tag eq "/option";
			if ($tag eq "option") {
			    my %a = %{$t->[0]};
			    # rename keys so they don't clash with %attr
			    for (keys %a) {
				next if $_ eq "value";
				$a{"option_$_"} = delete $a{$_};
			    }
			    while (my($k,$v) = each %$attr) {
				$a{$k} = $v;
			    }
			    $a{value_name} = $p->get_trimmed_text;
			    $a{value} = delete $a{value_name}
				unless defined $a{value};
			    $a{idx} = $openselect{$name};
			    $f->push_input("option", \%a, $verbose);
			}
			else {
			    warn("Bad <select> tag '$tag' in $base_uri\n") if $verbose;
			    if ($tag eq "/form" ||
				$tag eq "input" ||
				$tag eq "textarea" ||
				$tag eq "select" ||
				$tag eq "keygen")
			    {
				# MSIE implictly terminate the <select> here, so we
				# try to do the same.  Actually the MSIE behaviour
				# appears really strange:  <input> and <textarea>
				# do implictly close, but not <select>, <keygen> or
				# </form>.
				my $type = ($tag =~ s,^/,,) ? "E" : "S";
				$p->unget_token([$type, $tag, @$t]);
				last;
			    }
			}
		    }
		}
		elsif ($tag eq "keygen") {
		    $f->push_input("keygen", $attr, $verbose);
		}
	    }
	}
	elsif ($form_tags{$tag}) {
	    warn("<$tag> outside <form> in $base_uri\n") if $verbose;
	}
    }
    for (@forms) {
	$_->fixup;
    }

    wantarray ? @forms : $forms[0];
}

sub new {
    my $class = shift;
    my $self = bless {}, $class;
    $self->{method} = uc(shift  || "GET");
    $self->{action} = shift  || Carp::croak("No action defined");
    $self->{enctype} = lc(shift || "application/x-www-form-urlencoded");
    $self->{accept_charset} = "UNKNOWN";
    $self->{default_charset} = "UTF-8";
    $self->{inputs} = [@_];
    $self;
}


sub push_input
{
    my($self, $type, $attr, $verbose) = @_;
    $type = lc $type;
    my $class = $type2class{$type};
    unless ($class) {
	Carp::carp("Unknown input type '$type'") if $verbose;
	$class = "TextInput";
    }
    $class = "HTML::Form::$class";
    my @extra;
    push(@extra, readonly => 1) if $type eq "hidden";
    push(@extra, strict => 1) if $self->{strict};
    if ($type eq "file" && exists $attr->{value}) {
	# it's not safe to trust the value set by the server
	# the user always need to explictly set the names of files to upload
	$attr->{orig_value} = delete $attr->{value};
    }
    delete $attr->{type}; # don't confuse the type argument
    my $input = $class->new(type => $type, %$attr, @extra);
    $input->add_to_form($self);
}



BEGIN {
    # Set up some accesor
    for (qw(method action enctype accept_charset)) {
	my $m = $_;
	no strict 'refs';
	*{$m} = sub {
	    my $self = shift;
	    my $old = $self->{$m};
	    $self->{$m} = shift if @_;
	    $old;
	};
    }
    *uri = \&action;  # alias
}


sub attr {
    my $self = shift;
    my $name = shift;
    return undef unless defined $name;

    my $old = $self->{attr}{$name};
    $self->{attr}{$name} = shift if @_;
    return $old;
}


sub strict {
    my $self = shift;
    my $old = $self->{strict};
    if (@_) {
	$self->{strict} = shift;
	for my $input (@{$self->{inputs}}) {
	    $input->strict($self->{strict});
	}
    }
    return $old;
}



sub inputs
{
    my $self = shift;
    @{$self->{'inputs'}};
}



sub find_input
{
    my($self, $name, $type, $no) = @_;
    if (wantarray) {
	my @res;
	my $c;
	for (@{$self->{'inputs'}}) {
	    next if defined($name) && !$_->selected($name);
	    next if $type && $type ne $_->{type};
	    $c++;
	    next if $no && $no != $c;
	    push(@res, $_);
	}
	return @res;
	
    }
    else {
	$no ||= 1;
	for (@{$self->{'inputs'}}) {
	    next if defined($name) && !$_->selected($name);
	    next if $type && $type ne $_->{type};
	    next if --$no;
	    return $_;
	}
	return undef;
    }
}

sub fixup
{
    my $self = shift;
    for (@{$self->{'inputs'}}) {
	$_->fixup;
    }
}



sub value
{
    my $self = shift;
    my $key  = shift;
    my $input = $self->find_input($key);
    unless ($input) {
	Carp::croak("No such field '$key'") if $self->{strict};
	return undef unless @_;
	$input = $self->push_input("text", { name => $key, value => "" });
    }
    local $Carp::CarpLevel = 1;
    $input->value(@_);
}


sub param {
    my $self = shift;
    if (@_) {
        my $name = shift;
        my @inputs;
        for ($self->inputs) {
            my $n = $_->name;
            next if !defined($n) || $n ne $name;
            push(@inputs, $_);
        }

        if (@_) {
            # set
            die "No '$name' parameter exists" unless @inputs;
	    my @v = @_;
	    @v = @{$v[0]} if @v == 1 && ref($v[0]);
            while (@v) {
                my $v = shift @v;
                my $err;
                for my $i (0 .. @inputs-1) {
                    eval {
                        $inputs[$i]->value($v);
                    };
                    unless ($@) {
                        undef($err);
                        splice(@inputs, $i, 1);
                        last;
                    }
                    $err ||= $@;
                }
                die $err if $err;
            }

	    # the rest of the input should be cleared
	    for (@inputs) {
		$_->value(undef);
	    }
        }
        else {
            # get
            my @v;
            for (@inputs) {
		if (defined(my $v = $_->value)) {
		    push(@v, $v);
		}
            }
            return wantarray ? @v : $v[0];
        }
    }
    else {
        # list parameter names
        my @n;
        my %seen;
        for ($self->inputs) {
            my $n = $_->name;
            next if !defined($n) || $seen{$n}++;
            push(@n, $n);
        }
        return @n;
    }
}



sub try_others
{
    my($self, $cb) = @_;
    my @try;
    for (@{$self->{'inputs'}}) {
	my @not_tried_yet = $_->other_possible_values;
	next unless @not_tried_yet;
	push(@try, [\@not_tried_yet, $_]);
    }
    return unless @try;
    $self->_try($cb, \@try, 0);
}

sub _try
{
    my($self, $cb, $try, $i) = @_;
    for (@{$try->[$i][0]}) {
	$try->[$i][1]->value($_);
	&$cb($self);
	$self->_try($cb, $try, $i+1) if $i+1 < @$try;
    }
}



sub make_request
{
    my $self = shift;
    my $method  = uc $self->{'method'};
    my $uri     = $self->{'action'};
    my $enctype = $self->{'enctype'};
    my @form    = $self->form;

    my $charset = $self->accept_charset eq "UNKNOWN" ? $self->{default_charset} : $self->accept_charset;
    if ($Encode_available) {
        foreach my $fi (@form) {
            $fi = Encode::encode($charset, $fi) unless ref($fi);
        }
    }

    if ($method eq "GET") {
	require HTTP::Request;
	$uri = URI->new($uri, "http");
	$uri->query_form(@form);
	return HTTP::Request->new(GET => $uri);
    }
    elsif ($method eq "POST") {
	require HTTP::Request::Common;
	return HTTP::Request::Common::POST($uri, \@form,
					   Content_Type => $enctype);
    }
    else {
	Carp::croak("Unknown method '$method'");
    }
}



sub click
{
    my $self = shift;
    my $name;
    $name = shift if (@_ % 2) == 1;  # odd number of arguments

    # try to find first submit button to activate
    for (@{$self->{'inputs'}}) {
        next unless $_->can("click");
        next if $name && !$_->selected($name);
	next if $_->disabled;
	return $_->click($self, @_);
    }
    Carp::croak("No clickable input with name $name") if $name;
    $self->make_request;
}



sub form
{
    my $self = shift;
    map { $_->form_name_value($self) } @{$self->{'inputs'}};
}



sub dump
{
    my $self = shift;
    my $method  = $self->{'method'};
    my $uri     = $self->{'action'};
    my $enctype = $self->{'enctype'};
    my $dump = "$method $uri";
    $dump .= " ($enctype)"
	if $enctype ne "application/x-www-form-urlencoded";
    $dump .= " [$self->{attr}{name}]"
    	if exists $self->{attr}{name};
    $dump .= "\n";
    for ($self->inputs) {
	$dump .= "  " . $_->dump . "\n";
    }
    print STDERR $dump unless defined wantarray;
    $dump;
}


package HTML::Form::Input;


sub new
{
    my $class = shift;
    my $self = bless {@_}, $class;
    $self;
}

sub add_to_form
{
    my($self, $form) = @_;
    push(@{$form->{'inputs'}}, $self);
    $self;
}

sub strict {
    my $self = shift;
    my $old = $self->{strict};
    if (@_) {
	$self->{strict} = shift;
    }
    $old;
}

sub fixup {}



sub type
{
    shift->{type};
}


sub name
{
    my $self = shift;
    my $old = $self->{name};
    $self->{name} = shift if @_;
    $old;
}

sub id
{
    my $self = shift;
    my $old = $self->{id};
    $self->{id} = shift if @_;
    $old;
}

sub class
{
    my $self = shift;
    my $old = $self->{class};
    $self->{class} = shift if @_;
    $old;
}

sub selected {
    my($self, $sel) = @_;
    return undef unless defined $sel;
    my $attr =
        $sel =~ s/^\^// ? "name"  :
        $sel =~ s/^#//  ? "id"    :
        $sel =~ s/^\.// ? "class" :
	                  "name";
    return 0 unless defined $self->{$attr};
    return $self->{$attr} eq $sel;
}

sub value
{
    my $self = shift;
    my $old = $self->{value};
    $self->{value} = shift if @_;
    $old;
}


sub possible_values
{
    return;
}


sub other_possible_values
{
    return;
}


sub value_names {
    return
}


sub readonly {
    my $self = shift;
    my $old = $self->{readonly};
    $self->{readonly} = shift if @_;
    $old;
}


sub disabled {
    my $self = shift;
    my $old = $self->{disabled};
    $self->{disabled} = shift if @_;
    $old;
}


sub form_name_value
{
    my $self = shift;
    my $name = $self->{'name'};
    return unless defined $name;
    return if $self->disabled;
    my $value = $self->value;
    return unless defined $value;
    return ($name => $value);
}

sub dump
{
    my $self = shift;
    my $name = $self->name;
    $name = "<NONAME>" unless defined $name;
    my $value = $self->value;
    $value = "<UNDEF>" unless defined $value;
    my $dump = "$name=$value";

    my $type = $self->type;

    $type .= " disabled" if $self->disabled;
    $type .= " readonly" if $self->readonly;
    return sprintf "%-30s %s", $dump, "($type)" unless $self->{menu};

    my @menu;
    my $i = 0;
    for (@{$self->{menu}}) {
	my $opt = $_->{value};
	$opt = "<UNDEF>" unless defined $opt;
	$opt .= "/$_->{name}"
	    if defined $_->{name} && length $_->{name} && $_->{name} ne $opt;
	substr($opt,0,0) = "-" if $_->{disabled};
	if (exists $self->{current} && $self->{current} == $i) {
	    substr($opt,0,0) = "!" unless $_->{seen};
	    substr($opt,0,0) = "*";
	}
	else {
	    substr($opt,0,0) = ":" if $_->{seen};
	}
	push(@menu, $opt);
	$i++;
    }

    return sprintf "%-30s %-10s %s", $dump, "($type)", "[" . join("|", @menu) . "]";
}


package HTML::Form::TextInput;
@HTML::Form::TextInput::ISA=qw(HTML::Form::Input);


sub value
{
    my $self = shift;
    my $old = $self->{value};
    $old = "" unless defined $old;
    if (@_) {
        Carp::croak("Input '$self->{name}' is readonly")
	    if $self->{strict} && $self->{readonly};
        my $new = shift;
        my $n = exists $self->{maxlength} ? $self->{maxlength} : undef;
        Carp::croak("Input '$self->{name}' has maxlength '$n'")
	    if $self->{strict} && defined($n) && defined($new) && length($new) > $n;
	$self->{value} = $new;
    }
    $old;
}

package HTML::Form::IgnoreInput;
@HTML::Form::IgnoreInput::ISA=qw(HTML::Form::Input);


sub value { return }


package HTML::Form::ListInput;
@HTML::Form::ListInput::ISA=qw(HTML::Form::Input);


sub new
{
    my $class = shift;
    my $self = $class->SUPER::new(@_);

    my $value = delete $self->{value};
    my $value_name = delete $self->{value_name};
    my $type = $self->{type};

    if ($type eq "checkbox") {
	$value = "on" unless defined $value;
	$self->{menu} = [
	    { value => undef, name => "off", },
            { value => $value, name => $value_name, },
        ];
	$self->{current} = (delete $self->{checked}) ? 1 : 0;
	;
    }
    else {
	$self->{option_disabled}++
	    if $type eq "radio" && delete $self->{disabled};
	$self->{menu} = [
            {value => $value, name => $value_name},
        ];
	my $checked = $self->{checked} || $self->{option_selected};
	delete $self->{checked};
	delete $self->{option_selected};
	if (exists $self->{multiple}) {
	    unshift(@{$self->{menu}}, { value => undef, name => "off"});
	    $self->{current} = $checked ? 1 : 0;
	}
	else {
	    $self->{current} = 0 if $checked;
	}
    }
    $self;
}

sub add_to_form
{
    my($self, $form) = @_;
    my $type = $self->type;

    return $self->SUPER::add_to_form($form)
	if $type eq "checkbox";

    if ($type eq "option" && exists $self->{multiple}) {
	$self->{disabled} ||= delete $self->{option_disabled};
	return $self->SUPER::add_to_form($form);
    }

    die "Assert" if @{$self->{menu}} != 1;
    my $m = $self->{menu}[0];
    $m->{disabled}++ if delete $self->{option_disabled};

    my $prev = $form->find_input($self->{name}, $self->{type}, $self->{idx});
    return $self->SUPER::add_to_form($form) unless $prev;

    # merge menues
    $prev->{current} = @{$prev->{menu}} if exists $self->{current};
    push(@{$prev->{menu}}, $m);
}

sub fixup
{
    my $self = shift;
    if ($self->{type} eq "option" && !(exists $self->{current})) {
	$self->{current} = 0;
    }
    $self->{menu}[$self->{current}]{seen}++ if exists $self->{current};
}

sub disabled
{
    my $self = shift;
    my $type = $self->type;

    my $old = $self->{disabled} || _menu_all_disabled(@{$self->{menu}});
    if (@_) {
	my $v = shift;
	$self->{disabled} = $v;
        for (@{$self->{menu}}) {
            $_->{disabled} = $v;
        }
    }
    return $old;
}

sub _menu_all_disabled {
    for (@_) {
	return 0 unless $_->{disabled};
    }
    return 1;
}

sub value
{
    my $self = shift;
    my $old;
    $old = $self->{menu}[$self->{current}]{value} if exists $self->{current};
    $old = $self->{value} if exists $self->{value};
    if (@_) {
	my $i = 0;
	my $val = shift;
	my $cur;
	my $disabled;
	for (@{$self->{menu}}) {
	    if ((defined($val) && defined($_->{value}) && $val eq $_->{value}) ||
		(!defined($val) && !defined($_->{value}))
	       )
	    {
		$cur = $i;
		$disabled = $_->{disabled};
		last unless $disabled;
	    }
	    $i++;
	}
	if (!(defined $cur) || $disabled) {
	    if (defined $val) {
		# try to search among the alternative names as well
		my $i = 0;
		my $cur_ignorecase;
		my $lc_val = lc($val);
		for (@{$self->{menu}}) {
		    if (defined $_->{name}) {
			if ($val eq $_->{name}) {
			    $disabled = $_->{disabled};
			    $cur = $i;
			    last unless $disabled;
			}
			if (!defined($cur_ignorecase) && $lc_val eq lc($_->{name})) {
			    $cur_ignorecase = $i;
			}
		    }
		    $i++;
		}
		unless (defined $cur) {
		    $cur = $cur_ignorecase;
		    if (defined $cur) {
			$disabled = $self->{menu}[$cur]{disabled};
		    }
		    elsif ($self->{strict}) {
			my $n = $self->name;
		        Carp::croak("Illegal value '$val' for field '$n'");
		    }
		}
	    }
	    elsif ($self->{strict}) {
		my $n = $self->name;
	        Carp::croak("The '$n' field can't be unchecked");
	    }
	}
	if ($self->{strict} && $disabled) {
	    my $n = $self->name;
	    Carp::croak("The value '$val' has been disabled for field '$n'");
	}
	if (defined $cur) {
	    $self->{current} = $cur;
	    $self->{menu}[$cur]{seen}++;
	    delete $self->{value};
	}
	else {
	    $self->{value} = $val;
	    delete $self->{current};
	}
    }
    $old;
}


sub check
{
    my $self = shift;
    $self->{current} = 1;
    $self->{menu}[1]{seen}++;
}

sub possible_values
{
    my $self = shift;
    map $_->{value}, grep !$_->{disabled}, @{$self->{menu}};
}

sub other_possible_values
{
    my $self = shift;
    map $_->{value}, grep !$_->{seen} && !$_->{disabled}, @{$self->{menu}};
}

sub value_names {
    my $self = shift;
    my @names;
    for (@{$self->{menu}}) {
	my $n = $_->{name};
	$n = $_->{value} unless defined $n;
	push(@names, $n);
    }
    @names;
}


package HTML::Form::SubmitInput;
@HTML::Form::SubmitInput::ISA=qw(HTML::Form::Input);



sub click
{
    my($self,$form,$x,$y) = @_;
    for ($x, $y) { $_ = 1 unless defined; }
    local($self->{clicked}) = [$x,$y];
    return $form->make_request;
}

sub form_name_value
{
    my $self = shift;
    return unless $self->{clicked};
    return $self->SUPER::form_name_value(@_);
}


package HTML::Form::ImageInput;
@HTML::Form::ImageInput::ISA=qw(HTML::Form::SubmitInput);

sub form_name_value
{
    my $self = shift;
    my $clicked = $self->{clicked};
    return unless $clicked;
    return if $self->{disabled};
    my $name = $self->{name};
    $name = (defined($name) && length($name)) ? "$name." : "";
    return ("${name}x" => $clicked->[0],
	    "${name}y" => $clicked->[1]
	   );
}

package HTML::Form::FileInput;
@HTML::Form::FileInput::ISA=qw(HTML::Form::TextInput);


sub file {
    my $self = shift;
    $self->value(@_);
}


sub filename {
    my $self = shift;
    my $old = $self->{filename};
    $self->{filename} = shift if @_;
    $old = $self->file unless defined $old;
    $old;
}


sub content {
    my $self = shift;
    my $old = $self->{content};
    $self->{content} = shift if @_;
    $old;
}


sub headers {
    my $self = shift;
    my $old = $self->{headers} || [];
    $self->{headers} = [@_] if @_;
    @$old;
}

sub form_name_value {
    my($self, $form) = @_;
    return $self->SUPER::form_name_value($form)
	if $form->method ne "POST" ||
	   $form->enctype ne "multipart/form-data";

    my $name = $self->name;
    return unless defined $name;
    return if $self->{disabled};

    my $file = $self->file;
    my $filename = $self->filename;
    my @headers = $self->headers;
    my $content = $self->content;
    if (defined $content) {
	$filename = $file unless defined $filename;
	$file = undef;
	unshift(@headers, "Content" => $content);
    }
    elsif (!defined($file) || length($file) == 0) {
	return;
    }

    # legacy (this used to be the way to do it)
    if (ref($file) eq "ARRAY") {
	my $f = shift @$file;
	my $fn = shift @$file;
	push(@headers, @$file);
	$file = $f;
	$filename = $fn unless defined $filename;
    }

    return ($name => [$file, $filename, @headers]);
}

package HTML::Form::KeygenInput;
@HTML::Form::KeygenInput::ISA=qw(HTML::Form::Input);

sub challenge {
    my $self = shift;
    return $self->{challenge};
}

sub keytype {
    my $self = shift;
    return lc($self->{keytype} || 'rsa');
}

1;

__END__

