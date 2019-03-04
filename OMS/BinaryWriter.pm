package OMS::BinaryWriter;
use warnings;
use strict;

use Carp qw|cluck|;
use Data::Dumper;

sub new {
	my ($class) = @_;
	
	my $self = {
		buffer	=> ""
	};
	
	return bless $self => $class;
}

sub writeUtf {
	my ($self, $data) = @_;
	cluck "undefined data" if (!defined $data);
	return $self->writeShort(length($data))->writeString($data);
}

sub writeString {
	my ($self, $data) = @_;
	cluck "undefined data" if (!defined $data);
	$self->{buffer} .= $data;
	return $self;
}

sub writeChar {
	my ($self, $data) = @_;
	cluck "undefined data" if (!defined $data);
	$self->{buffer} .= substr($data, 0, 1);
	return $self;
}

sub writeByte {
	my ($self, $data) = @_;
	cluck "undefined data" if (!defined $data);
	return $self->writeUByte($data & 0xFF);
}

sub writeUByte {
	my ($self, $data) = @_;
	cluck "undefined data" if (!defined $data);
	$self->{buffer} .= chr($data & 0xFF);
	return $self;
}

sub writeShort {
	my ($self, $data) = @_;
	cluck "undefined data" if (!defined $data);
	return $self->writeUShort($data & 0xFFFF);
}

sub writeUShort {
	my ($self, $data) = @_;
	cluck "undefined data" if (!defined $data);
	$self->{buffer} .= chr(($data >> 8) & 0xFF).chr($data & 0xFF);
	return $self;
}

sub writeInt {
	my ($self, $data) = @_;
	cluck "undefined data" if (!defined $data);
	return $self->writeUShort($data & 0xFFFFFFFF);
}

sub writeUInt {
	my ($self, $data) = @_;
	cluck "undefined data" if (!defined $data);
	$self->{buffer} .= chr(($data >> 24) & 0xFF).chr(($data >> 16) & 0xFF).chr(($data >> 8) & 0xFF).chr($data & 0xFF);
	return $self;
}

sub data {
	my ($self) = @_;
	return $self->{buffer};
}

sub free {
	my ($self) = @_;
	$self->{buffer} = "";
	return $self;
}

1;
