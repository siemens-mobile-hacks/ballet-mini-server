#!/usr/bin/perl
use warnings;
use strict;

$| = 1;

use File::Basename;
use lib dirname (__FILE__);

use OMS::Server;

my $server = OMS::Server->new();
$server->run();
