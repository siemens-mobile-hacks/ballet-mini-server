package OMS::Handler;
use warnings;
use strict;

use Data::Dumper;
use HTML5::DOM;
use File::Slurp qw|read_file|;
use URI::Escape;

use OMS::Obml;
use OMS::CssRender;
use OMS::HtmlRender;

my $OM_MANGLE = {
	k			=> "imageType", 
	
	o			=> "browserType", # 280 - 2.x, 285 - 3.x
	'x-o'		=> "browserType", # 13 - 1.x
	
	u			=> "request", 
	'x-u'		=> "request", # 1.x
	
	q			=> "language", 
	'x-l'		=> "language", # 1.x
	
	v			=> "version", 
	'x-v'		=> "version", # 1.x
	
	i			=> "userAgent", 
	'x-ua'		=> "userAgent", # 1.x
	
	A			=> "cldc", 
	'x-m-c'		=> "cldc", # 1.x
	
	B			=> "midp", 
	'x-m-ps'	=> "midp", # 1.x
	
	C			=> "phone", 
	'x-m-pm'	=> "phone", # 1.x
	
	D			=> "deviceLanguage", 
	'x-m-l'		=> "deviceLanguage", # 1.x
	
	E			=> "encoding", 
	'x-m-e'		=> "encoding", # 1.x
	
	d			=> "options", 
	'x-dp'		=> "options", # 1.x
	
	b			=> "build", 
	'x-b'		=> "build", # 1.x
	
	y			=> "country", 
	'x-co'		=> "country", # 1.x
	
	h			=> "authPrefix", 
	c			=> "authCode", 
	
	'x-h'		=> "authPrefix", # 1.x
	'x-c'		=> "authCode", # 1.x
	
	f			=> "referer", 
	'x-rr'		=> "referer", # 1.x
	
	e			=> "compression", 
	'x-e'		=> "compression", # 1.x
	
	j			=> "post", 
	'x-var'		=> "post", # 1.x
	
	t			=> "showPhoneAsLinks", 
	
	w			=> "parts", 
	'x-sn'		=> "parts", # 1.x
	
	G			=> "defaultSearch"
};

my $OM_OPTIONS_MANGLE = {
	w	=> "width", 
	h	=> "height", 
	c	=> "colors", 
	m	=> "maxPageSize", 
	i	=> "images", 
	q	=> "imagesQuality"
};

sub new {
	my ($class) = @_;
	
	my $self = {
		events	=> {}
	};
	
	return bless $self => $class;
}

sub run {
	my ($self, $request) = @_;
	
	# Response for CORS
	if ($request->{headers}->{REQUEST_METHOD} eq 'HEAD' || $request->{headers}->{REQUEST_METHOD} eq 'OPTIONS') {
		my $response = [
			"HTTP/1.1 200 OK", 
			"Content-Length: 0", 
			"", 
			""
		];
		$self->trigger('response', join("\r\n", @$response));
		return;
	}
	
	my $req_type = substr($request->{body}, 0, 2);
	if ($req_type eq "\0\0") { # unencrypted 3.x
		$request->{body} = substr($request->{body}, 2);
	} elsif ($req_type eq "\0\1") { # encrypted 3.x
		warn "Secure protocol in 3.x not supported.";
		my $response = [
			"HTTP/1.1 403 Forbidden", 
			"Content-Length: 0", 
			"", 
			""
		];
		$self->trigger('response', join("\r\n", @$response));
		return;
	}
	
	# Parse Ballet Mini Request
	$self->{params} = {
		request			=> "about:blank", 
		compression		=> "none", 
		browserType		=> 280
	};
	for my $pair (split("\0", $request->{body})) {
		my ($name, $value) = split(/=/, $pair, 2);
		$self->{params}->{$OM_MANGLE->{$name} || "unk_$name"} = defined $value ? $value : "";
	}
	
	# Parse Ballet Mini Options
	if ($self->{params}->{options}) {
		for my $pair (split(";", $self->{params}->{options})) {
			my ($name, $value) = split(/:/, $pair, 2);
			$self->{params}->{$OM_OPTIONS_MANGLE->{$name} || "unk_opt_$name"} = defined $value ? int($value) : 0;
		}
	}
	delete $self->{params}->{options};
	
	# Detect by "browserType"
	$self->{params}->{browserVersion} = 1;
	
	if ($self->{params}->{browserType} == 285 || $self->{params}->{browserType} == 29) {
		$self->{params}->{browserVersion} = 3;
	} elsif ($self->{params}->{browserType} == 280) {
		$self->{params}->{browserVersion} = 2;
	}
	
	# Detect by UA
	if ($self->{params}->{version} && $self->{params}->{version} =~ /^([^\/]+)\/(\d+)/) {
		my $v = int($2);
		$self->{params}->{browserVersion} = $v
			if ($v >= 0 && $v <= 3);
	}
	
	# 0.x == 1.x
	$self->{params}->{browserVersion} = 1
		if ($self->{params}->{browserVersion} < 1);
	
	$self->{request_part} = 1;
	$self->{request_url} = "about:blank";
	
	if ($self->{params}->{request} =~ /^\/obml\/(\d+)\/(.*?)$/) {
		$self->{request_part} = int($1);
		$self->{request_url} = $2;
	} elsif ($self->{params}->{request} =~ /^\/obml\/(.*?)$/) {
		$self->{request_url} = $1;
	} else {
		warn "Unknown URI: ".$self->{params}->{request};
	}
	
	print Dumper($self->{params});
	
	print "REQUEST: ".$self->{request_url}."\n";
	
	my $page;
	my $form;
	
	if ($self->{params}->{post} ne '') {
		$form = {
			id		=> 0, 
			method	=> "GET", 
			action	=> $self->{request_url}, 
			fields	=> []
		};
		for my $pair (split(/&/, $self->{params}->{post})) {
			my ($k, $v) = split(/=/, $pair, 2);
			
			$v = uri_unescape($v);
			
			if ($k =~ /^(\d+)_(.*?)$/) {
				$form->{id} = $1;
				$form->{method} = $2;
				$form->{action} = $v;
			} elsif ($k =~ /^(\d+)-(.*?)$/) {
				push @{$form->{fields}}, [$2, $v];
			}
		}
		
		print Dumper($form);
	}
	
	if ($self->{request_url} eq 'server:test' || $self->{request_url} eq 'server:t0') {
		$page = OMS::Obml->new({
			url		=> $self->{request_url}, 
			version	=> $self->{params}->{browserVersion}
		});
		$page
			->style({bold => 1, pad => 2})
			->plus()
			->text($self->{request_url})
			->plus()
			->background(0xFFFFFF)
			->style()
			->text("OK")
			->end();
		
		# force disable compression
		$self->{params}->{compression} = "none";
	} elsif ($self->{request_url} eq 'about:test') {
		$page = OMS::Obml->new({
			url		=> $self->{request_url}, 
			version	=> $self->{params}->{browserVersion}
		});
		$page
			->style({bold => 1, pad => 2})
			->plus()
			->text($self->{request_url})
			->plus()
			->background(0xFFFFFF)
			->style()
			->text("FORM")
			->formHidden("opf", "1")
			->formHidden("http://wfewefew", "1")
			->formText("name", "ololo", 0)
			->formButton("btn23", "Form button")
			->tag('$')
			->formButton("btn2", "Form button")
			->end();
	} else {
		my $dom = HTML5::DOM->new({
			scripts		=> 0
		});
		my $tree = $dom->parse(scalar(read_file("test.html")));

		my $css_text = scalar(read_file("data/user-agent.css"));
		$tree->find('style')->each(sub {
			my $el = shift;
			$css_text .= $el->text.";";
		});

		my $css_render = OMS::CssRender->new($tree);
		$css_render->addCss($css_text);
		$css_render->render();

		$page = OMS::Obml->new({
			url		=> $self->{request_url}, 
			version	=> $self->{params}->{browserVersion}
		});
		OMS::HtmlRender::render($css_render, $tree, $page);
		
		$page->end();
	}
	
=pod
	$page
		->style({bold => 1, pad => 2}) # 0x20 00 00 02
		->plus()
		->text("Xuj xuj xuj")
		->plus()
		->background(0xF0F0F0)
		->style({color => 0x00FF00, monospace => 1})
		->text("Xuj xuj xuj body???")
		->plus()
		->text("Xuj xuj xuj body???")
		->plus()
		->text("Xuj xuj xuj body???")
		->plus()
		->text("Xuj xuj xuj body???")
		
		->authPrefix("host42")
		->authCode("wefwefwefwefwefefwefwefwe")
		
		->text("input password: ")
		->formPassword("password", "122434343")
		->br()
		
		->text("input text: ")
		->formText("text", "122434343", 0)
		->br()
		
		->text("input textarea: ")
		->formText("textarea", "122434343", 1)
		->br()
		
		->text("input radio: ")->br()
		->formRadio("radio", "1", 0)->text("varian1")->br()
		->formRadio("radio", "2", 1)->text("varian2")->br()
		->formRadio("radio", "3", 0)->text("varian3")->br()
		->br()
		
		->text("input checkbox: ")->br()
		->formCheckbox("cb", "1", 1)->text("varian1")->br()
		->formCheckbox("cb", "2", 0)->text("varian2")->br()
		->formCheckbox("cb", "3", 1)->text("varian3")->br()
		->br()
		
		->formReset("btn1", "Reset button")
		
		->formButton("btn2", "Form button")
		
		->formImage("btn3", "Image button")
		
		->formSelect("xuj", 0, [
			{title => 'option1', value => '2', checked => 0}, 
			{title => 'option2', value => '2', checked => 1}, 
			{title => 'option3', value => '2', checked => 0}
		])
		
		->formSelect("xuj", 1, [
			{title => 'option1', value => '2', checked => 0}, 
			{title => 'option2', value => '2', checked => 1}, 
			{title => 'option3', value => '2', checked => 1}
		])
		
		->formSelectOpen("xuj", 1, 3)
			->formSelectOption("xuj0", "pizda0", 0)
			->formSelectOption("xuj1", "pizda1", 0)
			->formSelectOption("xuj2", "pizda2", 1)
		->formSelectClose()
		
		->plus()
	#	->alert("xuj", "pizda")
		->phoneNumber('+7384334334334')
		->end();
=cut
	
	my $obml;
	
	if ($self->{params}->{compression} eq 'gzip') {
		$obml = $page->pack("gzip");
	} elsif ($self->{params}->{compression} eq 'def') {
		$obml = $page->pack("deflate");
	} else {
		$obml = $page->pack("none");
	}
	
	$self->send($obml);
}

sub send {
	my ($self, $obml) = @_;
	
	open F, ">/tmp/2.oms";
	binmode F;
	print F $obml;
	close F;
	
	my $response = [
		"HTTP/1.1 200 OK", 
		"Content-Length: ".length($obml), 
		"Content-Type: application/octet-stream", 
		"", 
		$obml
	];
	
	return $self->trigger('response', join("\r\n", @$response));
}

sub on {
	my ($self, $event, $handler) = @_;
	$self->{events}->{$event} = $handler;
	return $self;
}

sub trigger {
	my ($self, $event, @args) = @_;
	$self->{events}->{$event}->(@args)
		if (ref($self->{events}->{$event}) eq 'CODE');
	return $self;
}

sub close {
	print "OM handler close\n";
}

1;
