package WebService::AppStoreAPI;
use strict;
use warnings;
use LWP::UserAgent;
use XML::XPath;
use Data::Dumper;
use Encode;

our $VERSION = '0.01';

our $USER_AGENT           = 'iTunes/9.1.1 (Macintosh; Intel Mac OS X 10.6.3';
our $BASE_URL             = 'http://ax.itunes.apple.com/WebObjects/MZStore.woa/wa/';
#our $XML_PREFERRED_PARSER = 'XML::SAX::PurePerl';
our $XML_PREFERRED_PARSER = 'XML::Parser';
#our $XML_PREFERRED_PARSER = 'XML::SAX::Expat';
#our $XML_PREFERRED_PARSER = 'XML::LibXML::SAX';

sub new {
    my $class = shift;
    my %args = @_;
    return bless \%args, $class;
}

sub ua {
    my $self = shift;
    unless ( $self->{ ua } ) {
        my $ua = LWP::UserAgent->new;
        $ua->timeout(30);
        $ua->env_proxy;
        $ua->agent( $USER_AGENT );
        $self->{ ua } = $ua;
    }
    return $self->{ ua };
}

sub app_info {
    my ( $self, $args ) = @_;
    my $base_info = $self->app_base_info( $args );
    my $ret = {};
    for my $app_id ( keys %$base_info ) {
        for my $country ( keys %{ $base_info->{ $app_id } } ) {
            my $info = $base_info->{ $app_id }->{ $country };
            my $genre_rank = $self->genre_rank(
                app_id => $app_id,
                info => $info
            );
            my $total_rank = $self->total_rank(
                app_id => $app_id,
                info   => $info
            );
            my $reviews = $self->app_reviews(
                app_id => $app_id,
                info   => $info
            );

            $ret->{ $app_id }->{ $country } = {
                %$info,
                genre_rank => $genre_rank,
                total_rank => $total_rank,
                reviews => $reviews,
                store_name => $self->countries( $country )->{ name },
            };
            sleep $self->{ wait } || 1; # 3secs
        }
    }
    $ret;
}

sub app_base_info {
    my ( $self, $args ) = @_;
    my $info;
    for my $app_id ( @{ $args->{ app_ids } } ) {
        for my $country ( @{ $args->{ countries } } ) {
            my $url = sprintf '%sviewSoftware?id=%s&mt=8', $BASE_URL, $app_id;
            my $xpath = $self->_get_xml( $url,
                                         $self->countries( $country )->{ code },
                                         $args->{ lang } );

            my $app_url = $xpath->find( '/plist/dict/dict/string[2]' )->string_value or return;
            $xpath = $self->_get_xml( $app_url,
                                      $self->countries( $country )->{ code },
                                      $args->{ lang } );

            my $app_name = Encode::encode( 'utf8',
                                           $xpath->find( '/Document/iTunes' )->string_value );
            next unless $app_name;

            my $info_tmp;
            $info_tmp->{ genre_id }   = $xpath->find( '/Document/@genreId' )->string_value;
            $info_tmp->{ artist_id }  = $xpath->find( '/Document/@artistId' )->string_value;
            ($info_tmp->{ app_name }  = $app_name) =~ s/^\s+(.*)\s+$/$1/;
            $info_tmp->{ genre_name } = Encode::encode( 'utf8',
                                                        $xpath->find(
                                                            '/Document/Path/PathElement[2]/@displayName'
                                                        )->string_value );

            # price
            (my $price = $xpath->find('//Buy/@buyParams')->string_value) =~ s/^.*price=(\d+).*$/$1/;
            $info_tmp->{ price } = $price;

            # current version star
            my ( $star_base_current ) = $xpath->find( '/Document/View/ScrollView/VBoxView/View/MatrixView/VBoxView/View/MatrixView/VBoxView/VBoxView[2]/View/View/View/VBoxView/Test[1]' )->get_nodelist;
            for my $i ( 0..4 ) {
                my $star_idx = 5 - $i;
                my $textview_idx = $i + 1;
                $info_tmp->{ stars }->{ current }->{ $star_idx } = $xpath->find(
                    "./VBoxView[2]/MatrixView/VBoxView[2]/TextView[$textview_idx]/SetFontStyle",
                    $star_base_current
                )->string_value;
            }

            # all version star
            my ( $star_base_all ) = $xpath->find( '/Document/View/ScrollView/VBoxView/View/MatrixView/VBoxView/View/MatrixView/VBoxView/VBoxView[2]/View/View/View/VBoxView/Test[2]' )->get_nodelist;
            for my $i ( 0..4 ) {
                my $star_idx = 5 - $i;
                my $textview_idx = $i + 1;
                $info_tmp->{ stars }->{ all }->{ $star_idx } = $xpath->find(
                    "./VBoxView/MatrixView/VBoxView[2]/TextView[$textview_idx]/SetFontStyle",
                    $star_base_current
                )->string_value;
            }

            $info->{ $app_id }->{ $country } = $info_tmp;
        }
    }
    return $info;
}


#
# for rank
#

sub genre_rank {
    my $self = shift;
    $self->_get_rank( @_ );
}

sub total_rank {
    my $self = shift;
    $self->_get_rank( @_ );
}

sub _rank_uri {
    my ( $self, $price, $ident ) = @_;
    # iphone 30:27, ipad 47:44
    my $popId = $price ? 30 : 27;
    $popId += 17 if $ident eq 'ipad';
    my $url = $BASE_URL . 'viewTop?id=25209&popId='. $popId;
    $url;
}

sub _get_rank {
    my ( $self, $args ) = @_;
    my $caller = (caller(1))[3];

    my $info;
    if ( $args->{ info } ) {
        $info = $args->{ info };
    } else {
        my $base_info = $self->app_base_info( $args );
        $info = $base_info->{ $args->{ app_id } }->{ $args->{ store } };
    }

    my $url = $self->_rank_uri( $info->{ price }, $info->{ ident } );
    $url .= '&genreId=' . $info->{ genre_id } if $caller =~ /genre_rank$/;

    my $xpath = $self->_get_xml($url, $info->{ store_code }, $info->{ lang });
    (my $salableAdamId = $xpath->find('//Buy/@buyParams')->string_value)
        =~ s/^.*salableAdamId=(\d+).*$/$1/;

    return $salableAdamId;
}

#
# for reviews
#

sub app_reviews {
    my $self = shift;
    my @args = @_;

    my $args_ref = ref $args[0] eq 'HASH' ? $args[0] : {@args};
    my $ret = [];

    my $info;
    if ( $args_ref->{ info } ) {
        $info = $args_ref->{ info };
    } else {
        my $base_info = $self->app_base_info($args_ref);
        $info = $base_info->{ $args_ref->{ app } }->{ $args_ref->{ store } };
    }

    my $url = $info->{ review_url } || $BASE_URL . 'viewContentsUserReviews?pageNumber=0&type=Purple+Software&id=' . $args_ref->{ app } . '&sortOrdering=1';
    my $ref = $self->_get_xml($url, $info->{ store_code }, $info->{ lang });
    my $tree_tmp = $ref->{ View }->{ ScrollView }->{ VBoxView }->{ View }->{ MatrixView }->{ VBoxView }->[0]->{ VBoxView }->{ VBoxView };
    if ( ref $tree_tmp eq 'HASH' ) {
        my($date, $mes) = $self->_get_review_message( $tree_tmp );
        push @$ret, {
            message => $mes,
            date => $date,
        };
    } elsif ( ref $tree_tmp eq 'ARRAY' ) {
        for ( @$tree_tmp ) {
            my($date, $mes) = $self->_get_review_message( $_ );
            push @$ret, {
                message => $mes,
                date => $date,
            };
        }
    }

    $ret;
}

sub _get_review_message {
    my $self = shift;
    my $args = shift;

    my $mes = $args->{ TextView }->{ SetFontStyle }->{ content };
    my $tmp = $args->{ HBoxView }->[1]->{ TextView }->{ SetFontStyle }->{ content } || '';
    my $datetmp = ref $tmp eq 'ARRAY' ? $tmp->[scalar(@$tmp) -1] : $tmp;
    my $date;
    if ( $datetmp ) {
        chomp $datetmp;
        my @tmps =  split /\n\s+/, $datetmp;
        $date = pop @tmps;
    }
    if ( ref $mes eq 'ARRAY' ) {
        $mes = join "\n", @{$mes};
    }

    return ($date, $mes);
}

sub _get_xml {
    my $self = shift;
    my ( $url, $store, $lang ) = @_;

    $self->ua->default_header('X-Apple-Store-Front' => $store . '-' . $lang);
    my $res = $self->ua->get( $url );

    # Error Check
    unless ( $res->is_success ) {
        warn 'request failed: ', $url, ': ', $res->status_line;
        next;
    }
    unless ( $res->headers->header('Content-Type') =~ m|/xml| ) {
        warn 'content is not xml: ', $url, ': ', $res->headers->header('Content-Type');
        next;
    }
    return XML::XPath->new( xml => $res->content );
}

our $Countries;
sub countries {
    my ( $self, $code ) = @_;
    unless ( defined $Countries ) {
        $Countries = {
            jp => {
                name => 'Japan',
                code => 143462,
            },
            us => {
                name => 'United States',
                code => 143441,
            },
            ar => {
                name => 'Argentine',
                code => 143505,
            },
            au => {
                name => 'Autstralia',
                code => 143460,
            },
            be => {
                name => 'Belgium',
                code => 143446,
            },
            br => {
                name => 'Brazil',
                code => 143503,
            },
            ca => {
                name => 'Canada',
                code => 143455,
            },
            cl => {
                name => 'Chile',
                code => 143483,
            },
            cn => {
                name => 'China',
                code => 143465,
            },
            co => {
                name => 'Colombia',
                code => 143501,
            },
            cr => {
                name => 'Costa Rica',
                code => 143495,
            },
            hr => {
                name => 'Croatia',
                code => 143494,
            },
            cz => {
                name => 'Czech Republic',
                code => 143489,
            },
            dk => {
                name => 'Denmark',
                code => 143458,
            },
            de => {
                name => 'Germany',
                code => 143443,
            },
            sv => {
                name => 'El Salvador',
                code => 143506,
            },
            es => {
                name => 'Spain',
                code => 143454,
            },
            fi => {
                name => 'Finland',
                code => 143447,
            },
            fr => {
                name => 'France',
                code => 143442,
            },
            gr => {
                name => 'Greece',
                code => 143448,
            },
            gt => {
                name => 'Guatemala',
                code => 143504,
            },
            hk => {
                name => 'Hong Kong',
                code => 143463,
            },
            hu => {
                name => 'Hungary',
                code => 143482,
            },
            in => {
                name => 'India',
                code => 143467,
            },
            id => {
                name => 'Indonesia',
                code => 143476,
            },
            ie => {
                name => 'Ireland',
                code => 143449,
            },
            il => {
                name => 'Israel',
                code => 143491,
            },
            it => {
                name => 'Italia',
                code => 143450,
            },
            kr => {
                name => 'Korea',
                code => 143466,
            },
            kw => {
                name => 'Kuwait',
                code => 143493,
            },
            lb => {
                name => 'Lebanon',
                code => 143497,
            },
            lu => {
                name => 'Luxembourg',
                code => 143451,
            },
            my => {
                name => 'Malaysia',
                code => 143473,
            },
            mx => {
                name => 'Mexico',
                code => 143468,
            },
            nl => {
                name => 'Nederland',
                code => 143452,
            },
            nu => {
                name => 'New Zealand',
                code => 143461,
            },
            no => {
                name => 'Norway',
                code => 143457,
            },
            at => {
                name => 'Osterreich',
                code => 143445,
            },
            pk => {
                name => 'Pakistan',
                code => 143477,
            },
            pa => {
                name => 'Panama',
                code => 143485,
            },
            pe => {
                name => 'Peru',
                code => 143507,
            },
            ph => {
                name => 'Phillipines',
                code => 143474,
            },
            pl => {
                name => 'Poland',
                code => 143478,
            },
            pt => {
                name => 'Portugal',
                code => 143453,
            },
            qa => {
                name => 'Qatar',
                code => 143498,
            },
            ro => {
                name => 'Romania',
                code => 143487,
            },
            ru => {
                name => 'Russia',
                code => 143469,
            },
            sa => {
                name => 'Saudi Arabia',
                code => 143479,
            },
            ch => {
                name => 'Switzerland',
                code => 143459,
            },
            sg => {
                name => 'Singapore',
                code => 143464,
            },
            sk => {
                name => 'Slovakia',
                code => 143496,
            },
            si => {
                name => 'Slovenia',
                code => 143499,
            },
            za => {
                name => 'South Africa',
                code => 143472,
            },
            lk => {
                name => 'Sri Lanka',
                code => 143486,
            },
            se => {
                name => 'Sweden',
                code => 143456,
            },
            tw => {
                name => 'Taiwan',
                code => 143470,
            },
            th => {
                name => 'Thailand',
                code => 143475,
            },
            tr => {
                name => 'Turkey',
                code => 143480,
            },
            ae => {
                name => 'United Arab Emirates',
                code => 143481,
            },
            uk => {
                name => 'United Kingdom',
                code => 143444,
            },
            ve => {
                name => 'Venezuela',
                code => 143502,
            },
            vn => {
                name => 'Vietnam',
                code => 143471,
            },
        };
    }
    return $Countries->{ $code };
}

1;
__END__

=head1 NAME

WebService::AppStoreAPI -

=head1 SYNOPSIS

  use WebService::AppStoreAPI;
  my $api = WebService::AppStoreAPI->new;
  $api->app_info( {
      app_ids   => [ qw( 1 2 3 ) ],
      countries => [ qw( jp us ) ],
      lang      => 9,
      ident     => 'ipad', # or iphone
  } );

=head1 DESCRIPTION

WebService::AppStoreAPI is

=head1 AUTHOR

Yoshiki Kurihara E<lt>kurihara at cpan.orgE<gt>

=head1 SEE ALSO

=head1 LICENSE

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut
