package OMS::HtmlRender;
use warnings;
use strict;

=pod
TODO:
1. support white-space
...
=cut

use Encode;
use Data::Dumper;
use HTML5::DOM;

my $LAST_TOK = {
	CONTENT		=> 0, 
	SPACE		=> 1, 
	BR			=> 2, 
	BLOCK		=> 3
};

sub render {
	my ($css, $tree, $page) = @_;
	
	my $context = {
		background		=> 0xFFFFFF, 
		style			=> {
			color			=> 0, 
			monospace		=> 0, 
			bold			=> 0, 
			italic			=> 0, 
			underline		=> 0, 
			align			=> "left", 
		}
	};
	
	my $state = {
		css				=> $css, 
		tree			=> $tree, 
		page			=> $page, 
		context			=> $context, 
		context_stack	=> [$context], 
		value			=> "", 
		last_tok		=> $LAST_TOK->{BLOCK}, 
		form_id			=> 0
	};
	
	$state->{base} = _parseUri($page->getUrl());
	
	# Get <base>, if exists
	my $base = $tree->at('base[href]');
	$state->{base} = _parseUri($base->attr("href")) if ($base);
	
	# Get title
	my $title = $tree->at('title');
	$title = $title ? $title->text : $title;
	$title =~ s/\s+/ /g;
	$title =~ s/^\s+|\s+$//g;
	
	$state->{page}
		->style({bold => 1, pad => 2})
		->plus()
		->text($title || $page->getUrl())
		->plus()
		->background(0xFFFFFF)
		->style();
	
	_walkTree($tree->root, $state);
}

sub _formInputName {
	my ($node, $state) = @_;
	my $name = defined $node->{name} ? $node->{name} : "";
	return $state->{form_id}."-".$name;
}

sub _walkTree {
	my ($node, $state) = @_;
	
	if ($node->nodeType == $node->TEXT_NODE) {
		if (!$state->{hidden_content}) {
			my $parent_styles = $state->{css}->getNodeStyle($node->parent());
			my $text = $node->text();
			
			# collapse whitespaces
			$text =~ s/\s+/ /g;
			
			# ltrim
			if ($state->{last_tok}) {
				$text =~ s/^\s+//g;
			}
			
			if (length($text)) {
				$text = " $text"
					if ($state->{last_tok} == $LAST_TOK->{SPACE});
				
				if ($text =~ /\s$/) {
					$state->{last_tok} = $LAST_TOK->{SPACE};
					$text =~ s/\s+$//g;
				} else {
					$state->{last_tok} = $LAST_TOK->{CONTENT};
				}
				
				if ($parent_styles->{"text-transform"} eq "uppercase") {
					eval {
						Encode::_utf8_on($text);
						$text = uc($text);
					};
					Encode::_utf8_off($text);
				} elsif ($parent_styles->{"text-transform"} eq "lowercase") {
					eval {
						Encode::_utf8_on($text);
						$text = lc($text);
					};
					Encode::_utf8_off($text);
				} elsif ($parent_styles->{"text-transform"} eq "capitalize") {
					eval {
						Encode::_utf8_on($text);
						$text =~ s/([\w_-])([\w_-]*)/uc($1).$2/gie;
					};
					Encode::_utf8_off($text);
				}
				
				$state->{page}->text($text);
			}
		}
	} elsif ($node->nodeType == $node->ELEMENT_NODE) {
		my $styles = $state->{css}->getNodeStyle($node);
		
		# hidden
		if ($styles->{display} eq 'none' || $styles->{visibility} eq 'hidden') {
			$state->{hidden_content} = 1;
		}
		
		if ($node->tagId == HTML5::DOM->TAG_BR) {
			if (!$state->{hidden_content}) {
				$state->{last_tok} = $LAST_TOK->{BR};
				$state->{page}->br();
			}
		} else {
			my $bg_changed = 0;
			my $style_changed = 0;
			
			if (!$state->{hidden_content} && !_skipStyle($node)) {
				my $new_background = _blendColors($state->{context}->{background}, $styles->{"background-color"});
				if ($new_background != $state->{context}->{background}) {
					$state->{page}->background($new_background);
					$bg_changed = 1;
				}
				
				my $new_style = {
					color			=> _blendColors($new_background, $styles->{color}), 
					monospace		=> $styles->{"font-family"} =~ /monospace/ ? 1 : 0, 
					bold			=> $styles->{"font-weight"} >= 700, 
					italic			=> $styles->{"font-style"} eq "italic" || $styles->{"font-style"} eq "oblique", 
					underline		=> $styles->{"text-decoration-line"}->{"underline"}, 
					strike			=> $styles->{"text-decoration-line"}->{"line-through"}, 
					align			=> $styles->{"text-align"}, 
				};
				
				if (_compareStyle($new_style, $state->{context}->{style})) {
					$state->{page}->style($new_style);
					$style_changed = 1;
				}
				
				if ($bg_changed || $style_changed) {
					my $new_context = {
						background		=> $new_background, 
						style			=> $new_style
					};
					push @{$state->{context_stack}}, $state->{context};
					$state->{context} = $new_context;
				}
			}
			
			# url start
			if ($node->tagId == HTML5::DOM->TAG_A) {
				my $uri = _parseUri($node->{href} || "");
				_mergeUri($uri, $state->{base});
				$state->{page}->link(_serializeUri($uri));
			}
			
			# form start
			if ($node->tagId == HTML5::DOM->TAG_FORM) {
				++$state->{form_id};
				
				my $method = uc($node->{method} || "");
				$method = "GET" if ($method !~ /^POST|GET$/);
				$state->{page}->formHidden($state->{form_id}."_".$method, $node->{action});
			}
			
			# form select
			if ($node->tagId == HTML5::DOM->TAG_SELECT) {
				my $multiple = defined $node->{multiple};
				my $options = $node->find('option');
				
				my $selected_option = $node->at('option[selected]');
				$selected_option = $node->at('option:first-child') if (!$selected_option);
				
				if (!$state->{hidden_content}) {
					$state->{page}->formSelectOpen(_formInputName($node, $state), $multiple ? 1 : 0, $options->length);
				}
				
				$options->each(sub {
					my $option = shift;
					
					my $value = $option->{value};
					my $is_selected = $selected_option && $selected_option->isSameNode($option);
					
					my $title = $option->text();
					$title =~ s/^\s+$/ /g;
					$title =~ s/^\s+|\s+$//g;
					
					$value = $title if (!defined $value);
					
					if ($state->{hidden_content}) {
						$state->{page}->formHidden(_formInputName($node, $state), $value)
							if (defined $option->{checked});
					} else {
						$state->{page}->formSelectOption($title, $value, $is_selected ? 1 : 0);
					}
				});
				
				if (!$state->{hidden_content}) {
					$state->{page}->formSelectClose();
				}
			}
			
			# form input
			if ($node->tagId == HTML5::DOM->TAG_INPUT || $node->tagId == HTML5::DOM->TAG_BUTTON) {
				my $name = _formInputName($node, $state);
				my $value = $node->{value} || "";
				my $type = lc($node->{type} || "text");
				
				if ($node->tagId == HTML5::DOM->TAG_BUTTON) {
					$type = 'button' if ($type !~ /^(button|reset|submit)$/);
				}
				
				if ($type eq "password") {
					if ($state->{hidden_content}) {
						$state->{page}->formHidden($name, $value);
					} else {
						$state->{page}->formPassword($name, $value);
					}
				} elsif ($type eq "hidden") {
					$state->{page}->formHidden($name, $value);
				} elsif ($type eq "submit" || $type eq "button") {
					$value =~ s/\s+/ /g;
					$value =~ s/^\s+|\s+$//g;
					
					if (!$state->{hidden_content}) {
						$state->{page}->formButton($name, $value || "Submit");
						$state->{page}->tag("\$");
					}
				} elsif ($type eq "reset") {
					$value =~ s/\s+/ /g;
					$value =~ s/^\s+|\s+$//g;
					
					if (!$state->{hidden_content}) {
						$state->{page}->formButton($name, $value || "Reset");
						$state->{page}->tag("\$");
					}
				} elsif ($type eq "checkbox") {
					if ($state->{hidden_content}) {
						$state->{page}->formHidden($name, $value)
							if (defined $node->{checked});
					} else {
						$state->{page}->formCheckbox($name, $value, defined $node->{checked} ? 1 : 0);
					}
				} elsif ($type eq "radio") {
					if ($state->{hidden_content}) {
						$state->{page}->formHidden($name, $value)
							if (defined $node->{checked});
					} else {
						$state->{page}->formRadio($name, $value, defined $node->{checked} ? 1 : 0);
					}
				} else {
					$state->{page}->formText($name, $value, 0);
				}
			}
			
			if ($node->tagId == HTML5::DOM->TAG_HR) {
				$state->{page}->hr($state->{context}->{style}->{color});
			}
			
			if (!$node->void() && $node->tagId != HTML5::DOM->TAG_SELECT) {
				$node->childrenNode->each(sub {
					my $child = shift;
					_walkTree($child, $state);
				});
			}
			
			if ($node->tagId == HTML5::DOM->TAG_FORM) {
				--$state->{form_id};
			}
			
			if ($node->tagId == HTML5::DOM->TAG_A) {
				$state->{page}->linkEnd();
			}
			
			if (!$state->{hidden_content}) {
				if ($styles->{display} =~ /^block|table|table-caption$/) {
					if ($state->{last_tok} != $LAST_TOK->{BLOCK} && $state->{last_tok} != $LAST_TOK->{BR}) {
						$state->{page}->br();
						$state->{last_tok} = $LAST_TOK->{BLOCK};
					}
				} else {
					$state->{last_tok} = $LAST_TOK->{CONTENT};
				}
				
				if ($bg_changed || $style_changed) {
					$state->{context} = pop @{$state->{context_stack}};
				}
				
				if ($bg_changed) {
					$state->{page}->background($state->{context}->{background});
				}
				
				if ($style_changed) {
					$state->{page}->style($state->{context}->{style});
				}
			}
		}
		
		$state->{hidden_content} = 0;
	}
}

sub _skipStyle {
	my $node = shift;
	
	return 1 if $node->tagId == HTML5::DOM->TAG_INPUT;
	return 1 if $node->tagId == HTML5::DOM->TAG_BUTTON;
	return 1 if $node->tagId == HTML5::DOM->TAG_TEXTAREA;
	return 1 if $node->tagId == HTML5::DOM->TAG_SELECT;
	
	return 0;
}

sub _parseUri {
	if ($_[0] =~ /^(([a-z0-9_.-]+\:)?(\/\/([^\/#\?\@:]+))?(:\d+)?)?([^\?#]+)?(\?[^#]*)?(#.*)?$/io) {
		# [scheme, domain, port, path, query, hash]
		return [$2, $4, $5, $6, $7, $8];
	}
	return;
}

sub _mergeUri {
	my $l = scalar(@{$_[0]});
	for (my $i = 0; $i < $l; ++$i) {
		if ($i == 3 && defined $_[0]->[$i] && $_[0]->[$i] !~ /^\// && $_[1]->[$i] =~ /\/$/) {
			$_[0]->[$i] = $_[1]->[$i].$_[0]->[$i];
		} else {
			last if (defined $_[0]->[$i]);
			$_[0]->[$i] = $_[1]->[$i];
		}
	}
}

sub _serializeUri {
	my $url = $_[0];
	
	my $out = "";
	
	# scheme
	$out .= $url->[0] if (defined $url->[0]);
	
	if (defined $url->[1] || defined $url->[2]) {
		$out .= "//";
		
		# domain
		$out .= $url->[1] if (defined $url->[1]);
		
		# port
		$out .= ":".$url->[2] if (defined $url->[2]);
	}
	
	# path
	if (defined $url->[3]) {
		$out .= "/" if (substr($url->[3], 0, 1) ne '/');
		$out .= $url->[3];
	}
	
	# query
	$out .= $url->[4] if (defined $url->[4]);
	
	# hash
	$out .= $url->[5] if (defined $url->[5]);
	
	return $out;
}
 
# TODO: use more efficient way
sub _compareStyle {
	my ($a, $b) = @_;
	return join("\0", sort(values(%$a))) ne join("\0", sort(values(%$b)));
}

sub _blendColors {
	my ($bg, $fg) = @_;
	
	return $fg->{value} if ($fg->{alpha} == 1);
	
	my $fg_r = ($fg->{value} >> 16) & 0xFF;
	my $fg_g = ($fg->{value} >> 8) & 0xFF;
	my $fg_b = $fg->{value} & 0xFF;
	
	my $bg_r = ($bg >> 16) & 0xFF;
	my $bg_g = ($bg >> 8) & 0xFF;
	my $bg_b = $bg & 0xFF;
	
	my $new_r = int(($fg_r * $fg->{alpha}) + ($bg_r * (1.0 - $fg->{alpha})));
	my $new_g = int(($fg_g * $fg->{alpha}) + ($bg_g * (1.0 - $fg->{alpha})));
	my $new_b = int(($fg_b * $fg->{alpha}) + ($bg_b * (1.0 - $fg->{alpha})));
	
	return ($new_r << 16) | ($new_g << 8) | $new_b;
}

1;
