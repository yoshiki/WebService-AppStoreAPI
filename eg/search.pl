#!/usr/local/bin/perl

use strict;
use warnings;
use Data::Dumper;
use WebService::AppStoreAPI;

my $app_id = $ARGV[0];
my $country = $ARGV[1] || 'jp';
my $api = WebService::AppStoreAPI->new( {
    app_id  => $app_id,
    country => $country,
    lang    => 9,
    ident   => 'iphone',
} );
#warn Dumper $api->app_info;
warn Dumper $api->app_reviews;
#warn Dumper $api->genre_rank;
#warn Dumper $api->total_rank;
