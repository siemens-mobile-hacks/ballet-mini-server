package OMS::CssRender;
use warnings;
use strict;

use Data::Dumper;
use HTML5::DOM;

use OMS::CssRender::Colors;

# Inherit if not specified
my $CSS_PROPS_INHERIT = {
	"color"				=> 1, 
	"font-weight"		=> 1, 
	"white-space"		=> 1, 
	"text-align"		=> 1, 
	"font-style"		=> 1, 
	"font-family"		=> 1, 
	"visibility"		=> 1, 
	"text-transform"	=> 1
};

# Allowed css props with default values
my $CSS_PROPS = {
	"color"					=> {type => 'rgb', value => 0, alpha => 1}, 
	"background-color"		=> {type => 'rgb', value => 0, alpha => 0}, 
	"font-weight"			=> 400, 
	"display"				=> "inline", 
	"text-decoration-line"	=> {"underline" => 0, "line-through" => 0, "overline" => 0}, 
	"white-space"			=> "normal", 
	"text-align"			=> "start", 
	"text-transform"		=> "none", 
	"font-style"			=> "normal", 
	"font-family"			=> "Arial", 
	"visibility"			=> "visible", 
	
	"width"					=> "auto", 
	"min-width"				=> "auto", 
	"max-width"				=> "none", 
	
	"height"				=> "auto", 
	"min-height"			=> "auto", 
	"max-height"			=> "v", 
	
	"opacity"				=> "1", 
	"all"					=> ""
};

sub new {
	my ($class, $tree) = @_;
	
	my $self = {
		tree			=> $tree, 
		css				=> HTML5::DOM::CSS->new, 
		stylesheets		=> [], 
		styles			=> {}
	};
	
	return bless $self => $class;
}

sub addCss {
	my ($self, $css_text) = @_;
	push @{$self->{stylesheets}}, {
		rules	=> $self->_parseCss($css_text), 
		index	=> scalar(@{$self->{stylesheets}})
	};
	return $self;
}

# get computed style with inheritance
sub getNodeStyle {
	my ($self, $el) = @_;
	
	my $el_styles = $self->{styles}->{$el->hash};
	
	return $el_styles if ($el_styles->{_cached});
	
	my $parent_styles = ref($el->parent) eq 'HTML5::DOM::Element' ? $self->getNodeStyle($el->parent) : $CSS_PROPS;
	
	# manual inherit
	for my $k (keys %$el_styles) {
		my $value = $el_styles->{$k};
		if (!ref($value) && $value eq 'inherit') {
			$el_styles->{$k} = $parent_styles->{$k};
		}
	}
	
	# auto inherit if not specified
	for my $k (keys %$CSS_PROPS_INHERIT) {
		if (!exists $el_styles->{$k}) {
			$el_styles->{$k} = $parent_styles->{$k};
		}
	}
	
	# fill initial
	for my $k (keys %$CSS_PROPS) {
		if (!exists $el_styles->{$k} && !exists $CSS_PROPS_INHERIT->{$k}) {
			$el_styles->{$k} = $CSS_PROPS->{$k};
		}
	}
	
	# resolve font-weight lighter/bolder
	if ($el_styles->{"font-weight"} =~ /^(lighter|bolder)$/) {
		my $name2val = {
			lighter		=> 100, 
			bolder		=> 700
		};
		
		my $parent_font_weight = $name2val->{$parent_styles->{"font-weight"}} || $parent_styles->{"font-weight"};
		
		my $font_sizes = [
			[900, 900, 700], 
			[800, 900, 700], 
			[700, 900, 400], 
			[600, 900, 400], 
			[500, 700, 100], 
			[400, 700, 100], 
			[300, 400, 100], 
			[200, 400, 100], 
			[100, 400, 100], 
			[0, 400, 100], 
		];
		
		for my $fh (@$font_sizes) {
			if (!$fh->[0] || $fh->[0] <= $parent_font_weight) {
				$el_styles->{"font-weight"} = $fh->[1] if ($el_styles->{"font-weight"} eq 'bolder');
				$el_styles->{"font-weight"} = $fh->[2] if ($el_styles->{"font-weight"} eq 'lighter');
				last;
			}
		}
	}
	
	$el_styles->{_cached} = 1;
	
	return $el_styles;
}

# Map CSS to DOM
sub render {
	my ($self) = @_;
	
	my @nodes;
	my @pseudos;
	my $nodes_data = {};
	
	my $tree = $self->{tree};
	
	# Style entry for inline styles
	push @{$self->{stylesheets}}, {
		rules	=> [], 
		inline	=> 1, 
		index	=> scalar(@{$self->{stylesheets}})
	};
	
	# Parse inline styles (style="" attr)
	for my $el (@{$tree->findAttr("style")}) {
		my $style = $self->_parseInlineCss($el->attr("style"));
		if ($style) {
			if (!exists $nodes_data->{$el->hash}) {
				push @nodes, $el;
			}
			
			my $style_id = scalar(@{$self->{stylesheets}->[-1]->{rules}});
			push @{$self->{stylesheets}->[-1]->{rules}}, $style;
			push @{$nodes_data->{$el->hash}}, [$self->{stylesheets}->[-1]->{index}, $style_id, 0];
		}
	}
	
	# Link CSS selectors to nodes
	for my $stylesheet (@{$self->{stylesheets}}) {
		next if ($stylesheet->{inline});
		
		for my $rule (@{$stylesheet->{rules}}) {
			my $l = $rule->{selector}->length;
			for (my $i = 0; $i < $l; ++$i) {
				my $selector = $rule->{selector}->entry($i);
				my $pseudo = $selector->pseudoElement;
				if (!$pseudo) { # skip pseudos
					for my $el (@{$tree->find($selector)}) {
						push @nodes, $el if (!exists $nodes_data->{$el->hash});
						push @{$nodes_data->{$el->hash}}, [$stylesheet->{index}, $rule->{index}, $i];
					}
				}
			}
		}
	}
	
	# Merge styles
	my $inline_spec = [0, 0, 0];
	for my $el (@nodes) {
		my $props = {};
		my $props_specificity = {};
		
		for my $style (@{$nodes_data->{$el->hash}}) {
			my $stylesheet = $self->{stylesheets}->[$style->[0]];
			my $rule = $stylesheet->{rules}->[$style->[1]];
			my $selector = $rule->{selector} && $rule->{selector}->entry($style->[2]);
			
			my $property_index = 0;
			for my $v (@{$rule->{values}}) {
				my $spec = $selector ? $selector->specificityArray : $inline_spec;
				
				my $specificity = [
					# default						= 0
					# default + inline				= 1
					# default + important			= 2
					# default + inline + important	= 3
					($stylesheet->{inline} ? 1 : 0) + ($v->[2] ? 2 : 0), 
					# ids
					$spec->[0], 
					# classes, attributes, pseudo-classes
					$spec->[1], 
					# elements, pseudo-elements
					$spec->[2], 
					# stylesheet index
					$stylesheet->{index}, 
					# rule index in stylesheet
					$rule->{index}, 
					# property index in rule
					$property_index, 
				];
				
				my $specificity_cmp = exists $props_specificity->{$v->[0]} ? 
					$self->_compareSpecificity($specificity, $props_specificity->{$v->[0]}) : 0;
				
				if (!exists $props_specificity->{$v->[0]} || $specificity_cmp > 0) {
					$props_specificity->{$v->[0]} = $specificity;
					$props->{$v->[0]} = $v->[1];
				}
				
				++$property_index;
			}
		}
		
		$self->{styles}->{$el->hash} = $props;
	}
}

sub _parseInlineCss {
	my ($self, $text, $rules) = @_;
	
	return if (!defined $text);
	
	my @values = ();
	while ($text =~ /^\s*([\w\d_-]+)\s*:\s*(.*?)\s*(;|$)$/gio) {
		my ($k, $v) = ($1, $2);
		_parseCssProp(\@values, $k, $v);
	}
	
	if (scalar(@values)) {
		return {
			inline	=> 1, 
			values	=> \@values
		};
	}
	
	return;
}

sub _compareSpecificity {
	my ($self, $a, $b) = @_;
	my $l = scalar(@$a);
	for (my $i = 0; $i < $l; ++$i) {
		return 1 if ($a->[$i] > $b->[$i]);
		return -1 if ($a->[$i] < $b->[$i]);
	}
	return 0;
}

# Lightweight css parser
sub _parseCss {
	my ($self, $str) = @_;
	
	my $rules = [];
	my $last_pos = 0;
	my $state = 0;
	my $escape;
	
	# Parent block types
	my $TYPE_STYLESHEET		= 0;
	my $TYPE_GROUP			= 1;
	my $TYPE_SELECTOR		= 2;
	my $TYPE_UNKNOWN_GROUP	= 3;
	
	my @value;
	my @parents;
	my $parent = $TYPE_STYLESHEET;
	my $selector;
	
	my $fetch_value = sub {
		my $pos = pos($str) - ($_[0] || 0);
		my $val = substr($str, $last_pos, $pos - $last_pos);
		push @value, $val if (length($val));
		$last_pos = pos($str);
	};
	
	while (1) {
		my $tok;
		if ($state == 0) {
			last unless ($str =~ /([{};"']|\/\*|$)/gcos);
			$tok = $1;
		} elsif ($state == 1) {
			last unless ($str =~ /(\*\/|$)/gcos);
			$tok = $1;
		} elsif ($state == 2) {
			last unless ($str =~ /([\\\n"]|$)/gcos);
			$tok = $1;
		} elsif ($state == 3) {
			last unless ($str =~ /([\\\n']|$)/gcos);
			$tok = $1;
		}
		
		# idle
		if ($state == 0) {
			if (!$tok || index("{};", $tok) >= 0) {
				$fetch_value->($tok ? 1 : 0);
				my $v = join("", @value);
				@value = ();
				
				if ($parent == $TYPE_SELECTOR) {
					# We in selector, do parse css properties
					if ($selector && (!$tok || index("};", $tok) >= 0)) {
						if ($v =~ /^\s*([\w\d_-]+)\s*:\s*(.*?)\s*$/io) {
							my ($k, $v) = ($1, $2);
							_parseCssProp($selector->{values}, $k, $v);
						}
					}
				} elsif ($v =~ /^\s*\@([\w\d_-]+)/io) {
					if ($tok eq "{") {
						# CSS block (@media, @supports, @keyframes...)
						push @parents, $parent;
						$parent = $TYPE_UNKNOWN_GROUP; # skip
					}
				} elsif ($parent == $TYPE_GROUP || $parent == $TYPE_STYLESHEET) {
					# We in styles group, do parse selectors
					if ($tok eq "{") {
						push @parents, $parent;
						$parent = $TYPE_SELECTOR;
						
						my $query = $self->{css}->parseSelector($v);
						if ($query->valid) {
							$selector = {
								selector	=> $query, 
								index		=> scalar(@$rules), 
								values		=> []
							};
						} else {
						#	print "INVALID SELECTOR: $v\n";
						}
					}
				}
				
				if ($tok eq "}" && scalar(@parents) > 0) {
					if ($parent == $TYPE_SELECTOR && $selector) {
						push @$rules, $selector if (@{$selector->{values}});
						$selector = undef;
					}
					$parent = pop @parents;
				}
			} elsif ($tok eq '"') {
				$state = 2;
			} elsif ($tok eq "'") {
				$state = 3;
			} elsif ($tok eq '/*') {
				$state = 1;
				$fetch_value->(2);
			}
		}
		# comment
		elsif ($state == 1) {
			$state = 0;
			$last_pos = pos($str);
			$fetch_value->();
		}
		# string
		elsif ($state == 2 || $state == 3) {
			if ($escape) {
				$escape = 0;
			} elsif ($tok eq '\\') {
				$escape = 1;
			} else {
				$state = 0;
			}
		}
	}
	
	return $rules;
}

sub _parseCssProp {
	my ($parsed_values, $k, $v) = @_;
	
	my $important = $v =~ /!important/io;
	
	# normalize
	$v = lc($v);
	$v =~ s/!important//gi;
	$v =~ s/\s+/ /g;
	$v =~ s/^\s+|\s+$//g;
	
	# unwrap text-decoration
	if ($k eq 'text-decoration') {
		my @values = split(/\s+/, $v);
		
		return _parseCssProp($parsed_values, 'text-decoration-line', $values[0].($important ? ' !important' : ''))
			if (exists $values[0]);
	}
	
	# unwrap font
	if ($k eq 'font') {
		my $re = qx//;
		
		# magic
		my @result = $v =~ /^\s*
			(?:
				# [ <'font-style'> || <font-variant-css21> || <'font-weight'> || <'font-stretch'> ]?
				((?:
					(?:
						normal|small-caps|italic|oblique|bold|lighter|bolder|
						(?:[\d\.e+-]+)|
						ultra-condensed|extra-condensed|condensed|semi-condensed|semi-expanded|expanded|extra-expanded|
						ultra-expanded|(?:[\d\.e+-]+)%
					)\s
				){0,})
				
				(
					# <'font-size'>
					(?:xx-small|x-small|small|medium|large|x-large|xx-large|smaller|larger|(?:[\d\.e+-]+(?:cap|ch|em|ex|ic|lh|rem|rlh|vh|vw|vi|vb|vmin|vmax|px|cm|mm|q|in|pc|pt|%)))
					
					# [ \/ <'line-height'> ]?
					(?:\s*\/\s*(?:normal|(?:[\d\.e+-]+(?:cap|ch|em|ex|ic|lh|rem|rlh|vh|vw|vi|vb|vmin|vmax|px|cm|mm|q|in|pc|pt|%|)))\s)?
				)
				
				# <'font-family'>
				(.+?)
			)?
			
			# System font values
			((?:caption|icon|menu|message-box|small-caption|status-bar)(?:\s|$)){0,}
		$/gx;
		
		if (@result) {
			my ($font_style, $font_size, $font_family, $sys_font) = @result;
			
			my $font_props = {};
			
			if (defined $font_family) {
				# magic
				my @font_family_valid = $font_family =~ /^
					(\s*
						# escaped font name
						(?:
							(?:[^\s'"]+) | ((["'])((?:.*?)[^\\]\3|\3))
						)
						
						# separator
						(?:\s*,\s*|\s*$)
					){0,}
				$/gx;
				
				if (@font_family_valid) {
					$font_props->{"font-family"} = $font_family;
				} else {
					warn "Can't parse font-family: '$font_family'";
					return;
				}
			}
			
			if (defined $font_style) {
				for my $v (split(/\s+/, $font_style)) {
					my $k;
					
					if ($v =~ /^(italic|oblique)$/) {
						$k = "font-style";
						$font_props->{$k} = exists $font_props->{$k} ? $font_props->{$k}." ".$v : $v;
					}
					
					if ($v =~ /^(bold|lighter|bolder|[\d\.e+-]+)$/) {
						$k = "font-weight";
						$font_props->{$k} = $v;
					}
				}
			}
			
			for my $k (keys %$font_props) {
				_parseCssProp($parsed_values, $k, $font_props->{$k}.($important ? ' !important' : ''))
			}
		} else {
			warn "Can't parse font: '$v'";
			return;
		}
		
		# skip, if not parsed any props
		return;
	}
	
	# get 'background-color' from 'background'
	if ($k eq 'background') {
		while ($v =~ /([\!\w\d#_%\/-]+)(\()?/gc) {
			my $pos = pos($v);
			
			my $name = $1;
			my $is_func = $2;
			
			if ($is_func) {
				my $quote;
				my $state = 0;
				my $escape = 0;
				my $brace_level = 1;
				my $start = $pos;
				
				for (; $pos < length($v); ++$pos) {
					my $c = substr($v, $pos, 1);
					if ($escape) {
						$escape = 0;
						next;
					}
					
					if ($c eq '\\') {
						$escape = 1;
						next;
					}
					
					if ($state == 1) {
						$state = 0 if ($c eq $quote);
					} else {
						if ($c eq '"' || $c eq '\'') {
							$state = 1;
							$quote = $c;
						} elsif ($c eq '(') {
							++$brace_level;
						} elsif ($c eq ')') {
							--$brace_level;
							last if ($brace_level == 0);
						}
					}
				}
				
				if ($name =~ /^rgb|rgba|hsl|hsla$/i) {
					my $func_body = substr($v, $start, $pos - $start);
					return _parseCssProp($parsed_values, 'background-color', "$name($func_body)".($important ? ' !important' : ''));
				}
				
				pos($v) = $pos;
			} else {
				my $lc_name = lc($name);
				if (exists $OMS::CssRender::CSS_COLORS{$lc_name} || $lc_name eq 'currentcolor' || $lc_name eq 'transparent') {
					return _parseCssProp($parsed_values, 'background-color', $name.($important ? ' !important' : ''));
				} elsif ($name =~ /^#([a-f0-9]+)$/) {
					return _parseCssProp($parsed_values, 'background-color', $name.($important ? ' !important' : ''));
				}
			}
		}
		
		# skip, if not parsed any colors
		return;
	}
	
	return if (!exists $CSS_PROPS->{$k});
	
	# process initial
	if ($v eq 'initial') {
		push @$parsed_values, [$k, $CSS_PROPS->{$k}, $important ? 1 : 0];
		return;
	}
	
	# process inherit & unset
	if ($v eq 'inherit' || $v eq 'unset') {
		push @$parsed_values, [$k, $v, $important ? 1 : 0];
		return;
	}
	
	# process colors
	if ($k eq 'color' || $k eq 'background-color') {
		$v = _parseCssColor($v);
		
		# process currentcolor for fg color
		if ($k ne 'background-color' && $v->{type} eq 'currentcolor') {
			$v = 'inherit';
		}
	}
	
	$v = _normalizeCssProp($k, $v);
	
	push @$parsed_values, [$k, $v, $important ? 1 : 0] if (defined $v);
}

sub _normalizeCssProp {
	my ($k, $v) = @_;
	
	if ($k eq 'font-weight') {
		if ($v =~ /^normal|bold|lighter|bolder$/) {
			my $name2val = {
				"normal"		=> 400, 
				"bold"			=> 700
			};
			return $name2val->{$v} || $v;
		}
		
		if ($v =~ /^([\d\.e+-]+)$/) {
			my $value = int($1);
			return $value if ($value >= 0 && $value <= 1000);
		}
		
		return undef;
	}
	
	if ($k eq 'opacity') {
		if ($v =~ /^([\d\.e+-]+)$/) {
			my $value = int($1);
			return $value if ($value >= 0 && $value <= 1);
		}
		return undef;
	}
	
	if ($k eq 'display') {
		# <display-outside>
		return $v if ($v =~ /^block|inline$/);
		
		# <display-inside>
		return $v if ($v =~ /^flow|flow-root|table|flex|grid|ruby$/);
		
		# <display-listitem>
		return $v if ($v =~ /^list-item$/);
		
		# <display-internal>
		return $v if ($v =~ /^table-row-group|table-header-group|table-footer-group|table-row|table-cell|table-column-group|table-column|table-caption$/);
		return $v if ($v =~ /^ruby-base|ruby-text|ruby-base-container|ruby-text-container$/);
		
		# <display-box>
		return $v if ($v =~ /^contents|none$/);
		
		# <display-legacy>
		return $v if ($v =~ /^inline-block|inline-table|inline-flex|inline-grid$/);
		
		return undef;
	}
	
	if ($k eq 'all') {
		return $v if ($v =~ /^initial|inherit|unset/);
		return undef;
	}
	
	if ($k eq 'text-transform') {
		return $v if ($v =~ /^none|capitalize|uppercase|lowercase|full-width/);
		return undef;
	}
	
	if ($k eq 'text-decoration-line') {
		my $value = $CSS_PROPS->{$k};
		for my $vv (split(/\s+/, $v)) {
			next if ($vv eq 'none');
			return undef if (!exists $value->{$vv});
			$value->{$vv} = 1;
		}
		return $value;
	}
	
	if ($k eq 'white-space') {
		return $v if ($v =~ /^normal|nowrap|pre|pre-wrap|pre-line$/);
		return undef;
	}
	
	if ($k eq 'visibility') {
		return $v if ($v =~ /^visible|hidden|collapse$/);
		return undef;
	}
	
	if ($k eq 'font-style') {
		return $v if ($v =~ /^normal|italic|oblique$/);
		return undef;
	}
	
	if ($k eq 'text-align') {
		return $v if ($v =~ /^left|right|center$/);
		return 'center' if ($v =~ /^center|justify$/);
		
		# todo: handle direcion
		return 'left' if ($v eq 'start');
		return 'right' if ($v eq 'end');
		return 'inherit' if ($v eq 'match-parent');
		
		return undef;
	}
	
	return $v;
}

sub _parseCssColor {
	my $color = shift;
	
	# named color
	if (exists $OMS::CssRender::CSS_COLORS{$color}) {
		return {
			type	=> "rgb", 
			value	=> $OMS::CssRender::CSS_COLORS{$color}, 
			alpha	=> 1
		};
	}
	
	# hex color
	elsif ($color =~ /^#([a-f0-9]{3}[a-f0-9]?|[a-f0-9]{6}(?:[a-f0-9]{2})?)$/) {
		my $v = $1;
		
		# fff => ffffff
		$v =~ s/(.)/$1$1/g if (length($v) <= 4);
		
		my $a = 1;
		my $color_int = hex(substr($v, 0, 6));
		
		$a = hex(substr($v, 6, 2)) / 255
			if (length($v) == 8);
		
		my $r = ($color_int >> 16) & 0xFF;
		my $g = ($color_int >> 8) & 0xFF;
		my $b = $color_int & 0xFF;
		
		return {
			type	=> "rgb", 
			value	=> $color_int, 
			alpha	=> defined $a ? $a : 1
		};
	}
	
	# rgb color
	elsif ($color =~ /^(rgba|rgb)\(([+e\d\.]+%?)\s*(?:,|\s)\s*([+e\d\.]+%?)\s*(?:,|\s)\s*([+e\d\.]+%?)(?:\s*(?:,|\s|\/)\s*([+e\d\.]+%?))?\)$/) {
		my ($func, $r, $g, $b, $a) = ($1, $2, $3, $4, $5);
		
		$r = int(_parseCssColorValue($r, 255));
		$g = int(_parseCssColorValue($g, 255));
		$b = int(_parseCssColorValue($b, 255));
		$a = _parseCssColorValue($a, 1) if (defined $a);
		
		return {
			type	=> "rgb", 
			value	=> ($r << 16) | ($g << 8) | ($b), 
			alpha	=> defined $a ? $a : 1
		};
	}
	
	# hsl color
	elsif ($color =~ /^(hsl|hsla)\(([+e\d\.]+?(?:deg|grad|rad|turn|))\s*(?:,|\s)\s*([+e\d\.]+%)\s*(?:,|\s)\s*([+e\d\.]+%)(?:\s*(?:,|\s|\/)\s*([+e\d\.]+%?))?\)$/) {
		my ($func, $h, $s, $l, $a) = ($1, $2, $3, $4, $5);
		
		$s = _parseCssColorValue($s, 1);
		$l = _parseCssColorValue($l, 1);
		$a = _parseCssColorValue($a, 1) if (defined $a);
		
		if ($h =~ /^(\d+)(rad|deg|grad|turn)$/) {
			my ($hv, $ht) = ($1, $2);
			if ($ht eq 'deg') {
				$h = $hv;
			} elsif ($ht eq 'grad') {
				$h = $hv * 360 / 400 + 0.5;
			} elsif ($ht eq 'rad') {
				$h = $hv * 180 / 3.14159265359 + 0.5;
			} elsif ($ht eq 'turn') {
				$h = $hv * 360 + 0.5;
			}
		}
		
		# deg to 0..1 range
		$h = $h / 360;
		
		# circular values
		$h -= int($h) if ($h > 1);
		$h += -int($h) if ($h < 1);
		$h = 1 + $h if ($h < 0);
		
		my ($r, $g, $b) = _hslToRgb($h, $s, $l);
		
		return {
			type	=> "rgb", 
			value	=> ($r << 16) | ($g << 8) | ($b), 
			alpha	=> defined $a ? $a : 1
		};
	}
	
	# transparent
	elsif ($color eq 'transparent') {
		return {
			type	=> "rgb", 
			value	=> 0, 
			alpha	=> 0
		};
	}
	
	# special values
	elsif ($color =~ /^currentcolor$/) {
		return {
			type	=> $color
		};
	}
	
	# invalid color
	warn "INVALID COLOR: $color";
	
	return undef;
}

sub _hslToRgb {
	my ($h, $s, $l) = @_;
	
	my ($r, $g, $b);
	
	if ($s == 0) {
		$r = $g = $b = $l; # achromatic
	} else {
		my $q = $l < 0.5 ? $l * (1 + $s) : $l + $s - $l * $s;
		my $p = 2 * $l - $q;
		$r = _hueToRgb($p, $q, $h + 1 / 3);
		$g = _hueToRgb($p, $q, $h);
		$b = _hueToRgb($p, $q, $h - 1 / 3);
	}
	
	return (int($r * 255 + 0.5), int($g * 255 + 0.5), int($b * 255 + 0.5));
}

sub _hueToRgb {
	my ($p, $q, $t) = @_;
	
	$t += 1 if ($t < 0);
	$t -= 1 if ($t > 1);
	
	return $p + ($q - $p) * 6 * $t if ($t < 1 / 6);
	return $q if ($t < 1 / 2);
	return $p + ($q - $p) * (2 / 3 - $t) * 6 if ($t < 2 / 3);
	return $p;
}

sub _parseCssColorValue {
	my ($value, $max) = @_;
	if ($value =~ /%$/) {
		my $pct = substr($value, 0, length($value) - 1) + 0;
		
		$pct = 0 if ($pct < 0);
		$pct = 100 if ($pct > 100);
		
		return $max / 100 * $pct;
	}
	return $value + 0;
}

1;
