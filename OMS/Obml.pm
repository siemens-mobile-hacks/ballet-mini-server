package OMS::Obml;
use warnings;
use strict;

use Data::Dumper;
use Compress::Zlib;

use OMS::BinaryWriter;

my $STYLES = {
	ITALIC			=> 1 << 0, 
	BOLD			=> 1 << 1, 
	UNDERLINE		=> 1 << 2, 
	STRIKE			=> 1 << 3, 
	ALIGN_CENTER	=> 1 << 4, 
	ALIGN_RIGHT		=> 1 << 5, 
	MONOSPACE		=> 1 << 6
};

my $TAGS = {
	TEXT				=> 'T', 
	LINK_OPEN			=> 'L', 
	LINK_CLOSE			=> 'E', 
	PLACEHOLDER			=> 'J', 
	IMAGE				=> 'I', 
	UNCOMPRESSED_IMAGE	=> 'X', 
	IMAGE_REF			=> 'K', 
	IMAGE_REF2			=> 'O', 
	BACKGROUND			=> 'D', 
	STYLE				=> 'S', 
	STYLE_REF			=> 'y', 
	STYLE_REF2			=> 'Y', 
	BR					=> 'B', 
	PARAGRAPH			=> 'V', 
	PLUS				=> '+', 
	FOLD_OPEN			=> '(', 
	FOLD_CLOSE			=> ')', 
	DOLLAR				=> '$', 
	ANCHOR				=> 'A', 
	SUBMIT_FLAG			=> 'S', 
	PHONE_NUMBER		=> 'P', 
	HR					=> 'R', 
	
	UNKNOWN_F			=> 'F', 
	UNKNOWN_N			=> 'N', 
	UNKNOWN_t			=> 't', 
	
	FORM_PASSWORD		=> 'p', 
	FORM_TEXT			=> 'x', 
	FORM_CHECKBOX		=> 'c', 
	FORM_SELECT_OPEN	=> 's', 
	FORM_SELECT_CLOSE	=> 'l', 
	FORM_OPTION			=> 'o', 
	FORM_HIDDEN			=> 'h', 
	FORM_RESET			=> 'e', 
	FORM_IMAGE			=> 'i', 
	FORM_BUTTON			=> 'u', 
	FORM_UPLOAD			=> 'U', 
	FORM_RADIO			=> 'r', 
	FORM_SUBMIT_FLAG	=> "C", 
	
	LINE_FEED			=> 'v', 
	ALERT				=> 'M', 
	IDENT				=> 'z', 
	
	# WTF
	LINK_W				=> 'W', 
	LINK_m				=> 'm', 
	LINK_8				=> '\08', 
	LINK_9				=> '\09', 
	LINK_BIRD			=> '^', 
	KAWAI				=> '&', 
	
	DIRECT_IMAGE_LINK	=> 'Z', 
	DIRECT_FILE_LINK	=> '@', 
	
	AUTH				=> 'k', 
	
	END					=> 'Q'
};

sub new {
	my ($class, $options) = @_;
	
	my $self = {
		tags		=> [], 
		styles		=> [], 
		options		=> {
			version		=> 2, 
			url			=> "internal:", 
			part		=> 1, 
			parts_count	=> 1, 
			%$options
		}
	};
	
	return bless $self => $class;
}

sub getUrl {
	my ($self) = @_;
	return $self->{options}->{url};
}

sub build {
	my ($self) = @_;
	
	my $obml = OMS::BinaryWriter->new;
	
	my $special_response = "";
	
	if ($self->{options}->{url} eq "server:test") {
		# OM 1.x - 2.x network test ACK
		$special_response = "server:test";
	} elsif ($self->{options}->{url} eq "server:t0") {
		# OM 3.x network test ACK
		$special_response = "\x00\x00\x00\x20".("\xFF" x 0x20); # unknown
		$obml->writeUtf($special_response);
		return $obml->data();
	}
	
	$obml->writeUtf($special_response);
	$obml->writeString("\0" x (16 - length($special_response)))
		if (length($special_response) < 16);
	
	$obml
		# tags count
		->writeUShort(scalar(@{$self->{tags}}))
		
		# current part
		->writeUShort($self->{options}->{part})
		
		# parts count
		->writeUShort($self->{options}->{parts_count})
		
		# unk2
		->writeUShort(0)
		
		# styles count
		->writeUShort(scalar(@{$self->{styles}}))
		
		# unk3
		->writeUShort(0)->writeByte(0)
		
		# cacheable
		->writeUShort(0xFFFF);
	
	# unk4
	if ($self->{options}->{version} >= 2) {
		$obml->writeUShort(0);
	}
	
	# page url
	$obml->writeUtf($self->{options}->{part}.'/'.$self->{options}->{url});
	
	for my $tag (@{$self->{tags}}) {
		if ($tag->{id} eq $TAGS->{AUTH}) {
			$obml
				->writeChar($tag->{id})
				->writeByte($tag->{data}->{type})
				->writeUtf($tag->{data}->{value});
		} elsif (
			$tag->{id} eq $TAGS->{FORM_PASSWORD} || $tag->{id} eq $TAGS->{FORM_HIDDEN} || 
			$tag->{id} eq $TAGS->{FORM_IMAGE} || $tag->{id} eq $TAGS->{FORM_BUTTON} || 
			$tag->{id} eq $TAGS->{FORM_RESET} || $tag->{id} eq $TAGS->{FORM_HIDDEN}
		) {
			$obml
				->writeChar($tag->{id})
				->writeUtf($tag->{data}->{name})
				->writeUtf($tag->{data}->{value});
		} elsif ($tag->{id} eq $TAGS->{FORM_CHECKBOX} || $tag->{id} eq $TAGS->{FORM_RADIO}) {
			$obml
				->writeChar($tag->{id})
				->writeUtf($tag->{data}->{name})
				->writeUtf($tag->{data}->{value})
				->writeByte($tag->{data}->{checked} ? 1 : 0);
		} elsif ($tag->{id} eq $TAGS->{FORM_TEXT}) {
			if ($self->{options}->{version} > 1) {
				$obml
					->writeChar($tag->{id})
					->writeByte($tag->{data}->{multiline} ? 1 : 0)
					->writeUtf($tag->{data}->{name})
					->writeUtf($tag->{data}->{value});
			} else {
				$obml
					->writeChar($tag->{id})
					->writeUtf($tag->{data}->{name})
					->writeUtf($tag->{data}->{value});
			}
		} elsif ($tag->{id} eq $TAGS->{FORM_UPLOAD}) {
			$obml
				->writeChar($tag->{id})
				->writeUtf($tag->{data}->{name});
		} elsif ($tag->{id} eq $TAGS->{FORM_SELECT_OPEN}) {
			$obml
				->writeChar($tag->{id})
				->writeUtf($tag->{data}->{name})
				->writeByte($tag->{data}->{multiline} ? 1 : 0)
				->writeShort($tag->{data}->{count});
		} elsif ($tag->{id} eq $TAGS->{FORM_OPTION}) {
			$obml
				->writeChar($tag->{id})
				->writeUtf($tag->{data}->{title})
				->writeUtf($tag->{data}->{value})
				->writeByte($tag->{data}->{checked} ? 1 : 0);
		} elsif ($tag->{id} eq $TAGS->{ALERT}) {
			$obml
				->writeChar($tag->{id})
				->writeUtf($tag->{data}->{title})
				->writeUtf($tag->{data}->{message});
		} elsif (
			$tag->{id} eq $TAGS->{TEXT} || $tag->{id} eq $TAGS->{PHONE_NUMBER} || 
			$tag->{id} eq $TAGS->{LINK_OPEN}
		) {
			$obml
				->writeChar($tag->{id})
				->writeUtf($tag->{data});
		} elsif ($tag->{id} eq $TAGS->{BACKGROUND} || $tag->{id} eq $TAGS->{HR}) {
			if ($self->{options}->{version} >= 3) {
				$obml
					->writeChar($tag->{id})
					->writeUInt($tag->{data});
			} else {
				$obml
					->writeChar($tag->{id})
					->writeUShort(_rgb24to565($tag->{data}));
			}
		} elsif ($tag->{id} eq $TAGS->{STYLE}) {
			my $style = 0;
			
			$style |= $STYLES->{ALIGN_CENTER} if ($tag->{data}->{align} eq "center");
			
			$style |= $STYLES->{ALIGN_RIGHT} if ($tag->{data}->{align} eq "right");
			
			$style |= $STYLES->{BOLD} if ($tag->{data}->{bold});
			
			$style |= $STYLES->{UNDERLINE} if ($tag->{data}->{underline});
			
			$style |= $STYLES->{MONOSPACE} if ($tag->{data}->{monospace});
			
			$style |= $STYLES->{ITALIC} if ($tag->{data}->{italic});
			
			$style |= $STYLES->{STRIKE} if ($tag->{data}->{strike});
			
			if ($self->{options}->{version} >= 3) {
				$obml
					->writeChar($tag->{id})
					->writeByte($style)
					->writeUInt($tag->{data}->{color})
					->writeByte($tag->{data}->{pad});
			} else {
				$obml
					->writeChar($tag->{id})
					->writeByte($style)
					->writeUShort(_rgb24to565($tag->{data}->{color}))
					->writeByte($tag->{data}->{pad});
			}
		} else {
			$obml->writeChar($tag->{id});
		}
	}
	
	return $obml->data();
}

sub pack {
	my ($self, $compression) = @_;
	
	$compression = $compression || "none";
	
	my $magic = {
		1	=> 0x0d, 
		2	=> 0x18, 
		3	=> 0x1a
	};
	
	my $compression_types = {
		"none"		=> 0x33, 
		"deflate"	=> 0x32, 
		"gzip"		=> 0x31
	};
	
	my $obml;
	if ($compression eq "deflate") {
		my ($d, $status) = deflateInit(
			-Level			=> Z_DEFAULT_COMPRESSION, 
			-Method			=> Z_DEFLATED, 
			-WindowBits		=> -MAX_WBITS, 
			-Strategy		=> Z_DEFAULT_STRATEGY, 
			-memLevel		=> 8
		);
		
		if ($status == Z_OK) {
			($obml, $status) = $d->deflate($self->build());
			if ($status == Z_OK) {
				($obml, $status) = $d->flush();
				if ($status != Z_OK) {
					warn "Zlib::flush err (status=$status)";
					$compression = 'none';
					$obml = $self->build();
				}
			} else {
				warn "Zlib::deflate err (status=$status)";
				$compression = 'none';
				$obml = $self->build();
			}
		} else {
			warn "Zlib::deflateInit err (status=$status)";
			$compression = 'none';
			$obml = $self->build();
		}
	} elsif ($compression eq "gzip") {
		$obml = Compress::Zlib::memGzip($self->build());
		if (!$obml) {
			warn "Zlib::memGzip err (gzerrno=$gzerrno)";
			$compression = 'none';
			$obml = $self->build();
		}
	} else {
		$obml = $self->build();
	}
	
	my $header = OMS::BinaryWriter->new;
	$header
		->writeUByte($magic->{$self->{options}->{version}}) # obml version
		->writeUByte($compression_types->{$compression}) # compression type
		->writeUInt(length($obml) + 6); # obml length
	return $header->data().$obml;
}

sub tag {
	my ($self, $tag, $data) = @_;
	push @{$self->{tags}}, {id => $tag, data => $data};
	return $self;
}

sub plus {
	my ($self) = @_;
	return $self->tag($TAGS->{PLUS});
}

sub alert {
	my ($self, $title, $message) = @_;
	return $self->tag($TAGS->{ALERT}, {title => $title, message => $message});
}

sub text {
	my ($self, $text) = @_;
	print "TEXT: $text\n";
	return $self->tag($TAGS->{TEXT}, $text);
}

sub phoneNumber {
	my ($self, $text) = @_;
	return $self->tag($TAGS->{PHONE_NUMBER}, $text);
}

sub link {
	my ($self, $text) = @_;
	return $self->tag($TAGS->{LINK_OPEN}, $text);
}

sub linkEnd {
	my ($self) = @_;
	return $self->tag($TAGS->{LINK_CLOSE});
}

sub placeholder {
	my ($self, $w, $h) = @_;
	return $self->tag($TAGS->{PLACEHOLDER}, [$w, $h]);
}

sub formPassword {
	my ($self, $name, $value) = @_;
	print "<formPassword($name, $value)>\n";
	return $self->tag($TAGS->{FORM_PASSWORD}, {name => $name, value => $value});
}

sub formText {
	my ($self, $name, $value, $multiline) = @_;
	print "<formText($name, $value, $multiline)>\n";
	return $self->tag($TAGS->{FORM_TEXT}, {name => $name, value => $value, multiline => $multiline});
}

sub formCheckbox {
	my ($self, $name, $value, $checked) = @_;
	print "<formCheckbox($name, $value, $checked)>\n";
	return $self->tag($TAGS->{FORM_CHECKBOX}, {name => $name, value => $value, checked => $checked});
}

sub formRadio {
	my ($self, $name, $value, $checked) = @_;
	print "<formRadio($name, $value, $checked)>\n";
	return $self->tag($TAGS->{FORM_RADIO}, {name => $name, value => $value, checked => $checked});
}

sub formSelect {
	my ($self, $name, $multiple, $options) = @_;
	$self->formSelectOpen($name, $multiple, scalar(@$options));
	for my $opt (@$options) {
		$self->formSelectOption($opt->{title}, $opt->{value}, $opt->{checked});
	}
	return $self->formSelectClose();
}

sub formSelectOpen {
	my ($self, $name, $multiple, $count) = @_;
	print "<formSelectOpen($name, $multiple, $count)>\n";
	return $self->tag($TAGS->{FORM_SELECT_OPEN}, {name => $name, multiple => $multiple, count => $count});
}

sub formSelectOption {
	my ($self, $title, $value, $checked) = @_;
	print "<formSelectOption($title, $value, $checked)>\n";
	return $self->tag($TAGS->{FORM_OPTION}, {title => $title, value => $value, checked => $checked});
}

sub formSelectClose {
	my ($self) = @_;
	print "</formSelectClose>\n";
	return $self->tag($TAGS->{FORM_SELECT_CLOSE});
}

sub formHidden {
	my ($self, $name, $value) = @_;
	print "<formHidden($name, $value)>\n";
	return $self->tag($TAGS->{FORM_HIDDEN}, {name => $name, value => $value});
}

sub formReset {
	my ($self, $name, $value) = @_;
	print "<formReset($name, $value)>\n";
	return $self->tag($TAGS->{FORM_RESET}, {name => $name, value => $value});
}

sub formImage {
	my ($self, $name, $value) = @_;
	print "<formImage($name, $value)>\n";
	return $self->tag($TAGS->{FORM_IMAGE}, {name => $name, value => $value});
}

sub formButton {
	my ($self, $name, $value) = @_;
	print "<formButton($name, $value)>\n";
	return $self->tag($TAGS->{FORM_BUTTON}, {name => $name, value => $value});
}

sub formSubmitOnChange {
	my ($self) = @_;
	return $self->tag($TAGS->{FORM_SUBMIT_FLAG});
}

sub formUpload {
	my ($self, $name) = @_;
	return $self->tag($TAGS->{FORM_UPLOAD}, {name => $name});
}

sub style {
	my ($self, $style) = @_;
	
	$style = {} if (!ref($style));
	
	$style = {
		color			=> 0, 
		monospace		=> 0, 
		bold			=> 0, 
		italic			=> 0, 
		underline		=> 0, 
		align			=> "left", 
		pad				=> 2, 
		%$style
	};
	
	push @{$self->{styles}}, $style;
	
	print "<style ".sprintf("#%06X", $style->{color}).">\n";
	
	return $self->tag($TAGS->{STYLE}, $style);
}

sub background {
	my ($self, $color) = @_;
	print "<background ".sprintf("#%06X", $color).">\n";
	return $self->tag($TAGS->{BACKGROUND}, $color);
}

sub hr {
	my ($self, $color) = @_;
	print "<hr ".sprintf("#%06X", $color).">\n";
	return $self->tag($TAGS->{HR}, $color);
}

sub br {
	my ($self, $color) = @_;
	print "<br>\n";
	return $self->tag($TAGS->{BR});
}

sub end {
	my ($self, $color) = @_;
	print "</end>\n";
	return $self->tag($TAGS->{END});
}

sub paragraph {
	my ($self, $color) = @_;
	print "<p>\n";
	return $self->tag($TAGS->{PARAGRAPH});
}

sub authPrefix {
	my ($self, $value) = @_;
	return $self->tag($TAGS->{AUTH}, {type => 0, value => $value});
}

sub authCode {
	my ($self, $value) = @_;
	return $self->tag($TAGS->{AUTH}, {type => 1, value => $value});
}

sub _rgb24to565 {
	my $color = shift;
	my $red = ($color >> 16) & 0xFF;
	my $green = ($color >> 8) & 0xFF;
	my $blue = $color & 0xFF;
	return ($red >> 3) | (($green & 0xFC) << 3) | (($blue  & 0xF8) << 8);
}

1;
