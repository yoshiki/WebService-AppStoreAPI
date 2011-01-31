package WebService::AppStoreAPI;
use strict;
use warnings;
use LWP::UserAgent;
use XML::XPath;
use Data::Dumper;
use Encode ();

our $VERSION = '0.01';

our $USER_AGENT = 'iTunes/9.1.1 (Macintosh; Intel Mac OS X 10.6.3';
our $BASE_URL   = 'http://ax.itunes.apple.com/WebObjects/MZStore.woa/wa/';

sub new {
    my ( $class, $args ) = @_;
    return bless $args, $class;
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

sub _get_value {
    my ( $xp, $path, $node ) = @_;
    return _utf8_off( $xp->findvalue( $path, $node )->string_value );
}

sub _utf8_off {
    my $str = shift;
    Encode::_utf8_off( $str );
    return $str;
}

sub app_info {
    my $self = shift;
    return $self->{ _app_info } if $self->{ _app_info };

    my $app_id = $self->{ app_id };
    my $lang = $self->{ lang };
    my $country = $self->countries( $self->{ country } );
    my $code = $country->{ code };

    my $url = sprintf '%sviewSoftware?id=%s&mt=8', $BASE_URL, $app_id;
    my $xp = $self->_get_xml( $url, $code, $lang );

    my $app_url = _get_value( $xp, '/plist/dict/dict/string[2]' ) or return;
    $xp = $self->_get_xml( $app_url, $code, $lang );

    my ( $node ) = $xp->find( '/Document' )->get_nodelist;

    # app name
    my $app_name = _get_value( $xp, 'iTunes', $node );
    $app_name =~ s/^\s*([^\s]+)\s*$/$1/; # chomp space
    next unless $app_name;

    # genre
    my $genre_id = _get_value( $xp, '@genreId', $node );
    my $genre_name = _get_value( $xp, 'Path/PathElement[2]/@displayName', $node );

    # artist
    my $artist_id = _get_value( $xp, '@artistId', $node );

    # price
    my $buyParams = $xp->find('//Buy/@buyParams')->string_value;
    (my $price = $buyParams) =~ s/^.*price=(\d+).*$/$1/;

    # current version star
    my $current_star;
    my ( $current_star_node ) = $xp->find( '//Test[@id="1234"]' )->get_nodelist;
    for my $i ( 0..4 ) {
        my $star_idx = 5 - $i;
        my $textview_idx = $i + 1;
        $current_star->{ $star_idx } = _get_value(
            $xp,
            "VBoxView[2]/MatrixView/VBoxView[2]/TextView[$textview_idx]/SetFontStyle",
            $current_star_node,
        );
    }

    # all version star
    my $all_star;
    my ( $all_star_node ) = $xp->find( '//Test[@id="5678"]' )->get_nodelist;
    for my $i ( 0..4 ) {
        my $star_idx = 5 - $i;
        my $textview_idx = $i + 1;
        $all_star->{ $star_idx } = _get_value(
            $xp,
            "VBoxView[1]/MatrixView/VBoxView[2]/TextView[$textview_idx]/SetFontStyle",
            $all_star_node,
        );
    }

    $self->{ _app_info } = {
        app_id     => $app_id,
        app_name   => $app_name,
        lang       => $lang,
        price      => $price,
        genre_id   => $genre_id,
        genre_name => $genre_name,
        artist_id  => $artist_id,
        country    => $country,
        star       => { current => $current_star, all => $all_star },
    };

    return $self->{ _app_info };
}

sub genre_rank {
    my $self = shift;
    my $app_info = $self->app_info;
    my $url = $self->_rank_uri( $app_info->{ price },
                                $app_info->{ ident } || 'iphone' );
    $url .= '&genreId=' . $app_info->{ genre_id };
    my $xp = $self->_get_xml( $url );
    my ( $node ) = $xp->find( '/Document/View/ScrollView/VBoxView/View/MatrixView/VBoxView/HBoxView/VBoxView/VBoxView/View/VBoxView[2]/MatrixView/VBoxView/MatrixView' )->get_nodelist;
    for my $i ( 1..100 ) {
        my $buyParams = $xp->find( 'HBoxView[' . $i . ']/VBoxView/MatrixView/VBoxView/HBoxView/VBoxView[2]/HBoxView/VBoxView/Test/Test[2]/Buy/@buyParams', $node )->string_value;
        my ( $app_id ) = $buyParams =~ m/^.*salableAdamId=(\d+).*$/;
        return $i if $app_id == $app_info->{ app_id };
    }
}

sub total_rank {
    my $self = shift;
    my $app_info = $self->app_info;
    my $url = $self->_rank_uri( $app_info->{ price },
                                $app_info->{ ident } || 'iphone' );
    my $xp = $self->_get_xml( $url );
    my ( $node ) = $xp->find( '/Document/View/ScrollView/VBoxView/View/MatrixView/VBoxView/HBoxView/VBoxView/VBoxView/View/VBoxView[2]/MatrixView/VBoxView/MatrixView' )->get_nodelist;
    for my $i ( 1..100 ) {
        my $buyParams = $xp->find( 'HBoxView[' . $i . ']/VBoxView/MatrixView/VBoxView/HBoxView/VBoxView[2]/HBoxView/VBoxView/Test/Test[2]/Buy/@buyParams', $node )->string_value;
        my ( $app_id ) = $buyParams =~ m/^.*salableAdamId=(\d+).*$/;
        return $i if $app_id == $app_info->{ app_id };
    }
}

sub _rank_uri {
    my ( $self, $price, $ident ) = @_;
    # iphone 30:27, ipad 47:44
    my $popId = $price ? 30 : 27;
    $popId += 17 if $ident eq 'ipad';
    my $url = $BASE_URL . 'viewTop?id=25209&popId='. $popId;
    $url;
}

sub app_reviews {
    my $self = shift;
    my $app_info = $self->app_info;
    my $url = $BASE_URL
            . 'viewContentsUserReviews?pageNumber=0&type=Purple+Software&id='
            . $app_info->{ app_id }
            . '&sortOrdering=1';
    my $xp = $self->_get_xml( $url );
    my ( $review_root ) = $xp->find(
        '/Document/View/ScrollView/VBoxView/View/MatrixView/VBoxView[1]/VBoxView'
    )->get_nodelist;
    my @review_nodes = $review_root->find( './VBoxView' )->get_nodelist;
    my @reviews;
    for my $node ( @review_nodes ) {
        my $title = _get_value( $node, 'HBoxView[1]/TextView/SetFontStyle' );
        my $name = _get_value( $node, 'HBoxView[2]/TextView/SetFontStyle/GotoURL' );
        my $body  = _get_value( $node, 'TextView/SetFontStyle' );
        $name =~ s/^\s*([^\s]*)\s*$/$1/;
        push @reviews, {
            title => $title || undef,
            name  => $name  || undef,
            boddy => $body  || undef,
        };
    }
    return \@reviews;
}

sub _get_review_message {
    my $self = shift;

}

sub _get_xml {
    my ( $self, $url, $code, $lang ) = @_;
    if ( !$code || !$lang ) {
        $code = $self->app_info->{ country }->{ code };
        $lang = $self->app_info->{ lang };
    }
    $self->ua->default_header( 'X-Apple-Store-Front' => "${code}-${lang}" );
    my $res = $self->ua->get( $url );
    unless ( $res->is_success ) {
        die 'request failed: ', $url, ': ', $res->status_line;
    }
    unless ( $res->headers->header('Content-Type') =~ m|/xml| ) {
        die 'content is not xml: ', $url, ': ', $res->headers->header('Content-Type');
    }
    print $res->content;
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
  my $api = WebService::AppStoreAPI->new( {
      app_id  => 1,
      country => 'jp',
      lang    => 9,
      ident   => 'ipad', # or iphone
  } );
  $api->app_info;

=head1 DESCRIPTION

WebService::AppStoreAPI is

=head1 AUTHOR

Yoshiki Kurihara E<lt>kurihara at cpan.orgE<gt>

=head1 SEE ALSO

=head1 LICENSE

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut
