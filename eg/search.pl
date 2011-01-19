#!/usr/local/bin/perl

use strict;
use warnings;
use Data::Dumper;
use WebService::AppStoreAPI;

my $app_ids = [ split /\s/, $ARGV[0] ];
my $api = WebService::AppStoreAPI->new;
warn Dumper $api->app_info( {
    app_ids   => $app_ids,
    countries => [ qw( jp ) ],
    lang      => 9,
    ident     => 'iphone',
} );
