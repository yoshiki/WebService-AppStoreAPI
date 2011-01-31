#!/usr/local/bin/perl

use strict;
use warnings;
use Data::Dumper;
use WebService::AppStoreAPI;

my $app_id = $ARGV[0];
my $country = $ARGV[1] || 'jp';
my $lang = $ARGV[2] || 9;
my $api = WebService::AppStoreAPI->new( {
    app_id  => $app_id,
    country => $country,
    lang    => $lang,
    ident   => 'iphone',
} );
my $url = $api->app_info_url( $app_id );
print $api->fetch_xml( $url );
