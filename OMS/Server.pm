package OMS::Server;
use warnings;
use strict;

use IO::Socket;
use IO::Select;
use Data::Dumper;

use OMS::Handler;

# Simple SCGI server

sub new {
	my ($class, $options) = @_;
	
	my $self = {};
	
	$self->{read_set} = new IO::Select();
	
	$self->{server} = new IO::Socket::INET (
		LocalHost		=> '127.0.0.1',
		LocalPort		=> '9999',
		Proto			=> 'tcp',
		Listen			=> 9999,
		ReuseAddr		=> 1, 
		Blocking		=> 0
	);
	
	$self->{read_set}->add($self->{server});
	
	return bless $self => $class;
}

sub run {
	my ($self) = @_;
	
	my $clients = {};
	
	my $close_client = sub {
		my ($rh, $fail) = @_;
		
		print "CLOSE[".$rh->fileno."] fail=".($fail ? 1 : 0)."\n";
		
		if ($fail) {
			# Send "bad Request"
			$rh->write("HTTP/1.0 400 Bad Request\r\n");
			$rh->write("Content-Length: 0\r\n");
			$rh->write("Content-Type: text/html\r\n\r\n");
		}
		
		if (exists $clients->{$rh->fileno}) {
			if ($clients->{$rh->fileno}->{handler}) {
				$clients->{$rh->fileno}->{handler}->close();
			}
			
			delete $clients->{$rh->fileno};
			$self->{read_set}->remove($rh);
		}
		
		$rh->close;
	};
	
	while (1) {
		my ($rh_set) = IO::Select->select($self->{read_set}, undef, undef);
		
		foreach my $rh (@$rh_set) {
			if ($rh->fileno == $self->{server}->fileno) {
				my $new = $rh->accept;
				if (defined $new) {
					if ($new->blocking(0)) {
						$self->{read_set}->add($new);
						$clients->{$new->fileno} = {
							buffer		=> ""
						};
					} else {
						warn "Socket set non-blocking error: $!";
						$close_client->($new, 1);
					}
				} else {
					warn "Socket accept error: $!";
				}
			} else {
				if ($rh->eof() || !exists $clients->{$rh->fileno}) {
					$close_client->($rh, 1);
				} else {
					my $client = $clients->{$rh->fileno};
					
					next if (!defined $client->{buffer});
					
					while (!$rh->eof()) {
						my $data;
						$rh->read($data, 4096);
						$client->{buffer} .= $data;
					}
					
					# SCGI header size
					if (!$client->{header_size} && $client->{buffer} =~ /^(\d+):/) {
						$client->{header_offset} = length($1) + 1;
						$client->{header_size} = int($1);
						
						if ($client->{header_size} < 24) {
							warn "Invalid SCGI header size (".$client->{header_size}.")";
							$close_client->($rh, 1);
							next;
						}
					}
					
					# Check if header read is done
					if ($client->{header_size} && !$client->{headers}) {
						if (length($client->{buffer}) >= $client->{header_offset} + $client->{header_size}) {
							# Parse SCGI headers
							$client->{headers} = {split(/\0/, substr($client->{buffer}, $client->{header_offset}, $client->{header_size}))};
							
							if (!exists $client->{headers}->{CONTENT_LENGTH} || !$client->{headers}->{SCGI}) {
								warn "Invalid SCGI header: ".Dumper($client->{headers})."\n";
								$close_client->($rh, 1);
								next;
							}
						}
					}
					
					# Check if body read is done
					if ($client->{headers}) {
						if (length($client->{buffer}) >= $client->{header_offset} + $client->{header_size} + $client->{headers}->{CONTENT_LENGTH} + 1) {
							my $body = substr($client->{buffer}, $client->{header_offset} + $client->{header_size} + 1, $client->{headers}->{CONTENT_LENGTH});
							
							delete $client->{buffer};
							
							$client->{handler} = OMS::Handler->new();
							$client->{handler}->on(response => sub {
								my $content = shift;
								$$rh->write($content);
								$close_client->($rh);
							});
							$client->{handler}->on(error => sub {
								$close_client->($rh, 1);
							});
							$client->{handler}->run({
								body		=> $body, 
								headers		=> $client->{headers}
							});
						}
					}
				}
			}
		}
	}

}

1;
