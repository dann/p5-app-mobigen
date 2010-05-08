#!/usr/bin/env perl
use strict;
use warnings;
use LWP::Simple ();
use Digest::MD5 qw(md5_hex);
use HTML::TreeBuilder;
use IO::File;
use File::Basename;
use URI;

# settings
my $DOWNLOAD_DIR         = '/tmp/kindlebook';
my $KINDLE_DOCUMENTS_DIR = '/Volumes/Kindle/documents/';

# main
main();
exit;

sub main {
    my $url = $ARGV[0];
    die 'usage: kindlecreator.pl url' unless $url;

    create_download_dir();
    my $html           = download_html($url);
    my $fixed_html     = fix_html( $html, $url );
    my $html_file_path = html_file_path($url);
    write_file( $fixed_html, $html_file_path );
    my $mobi_file_path = convert_to_mobi($html_file_path);
    copy_mobi_to_kindle($mobi_file_path);

    print "Congratulations! Converted a html to a mobi!\n";
}

sub write_file {
    my ( $content, $file_path ) = @_;
    my $io = IO::File->new( $file_path, 'w' );
    $io->print($content);
    $io->close;
}

sub create_download_dir {
    if ( !-e $DOWNLOAD_DIR ) {
        mkdir $DOWNLOAD_DIR or die "cannot create $DOWNLOAD_DIR $!";
    }
}

sub html_file_path {
    my $url = shift;
    my $html_file_path
        = sprintf( "%s/%s.html", $DOWNLOAD_DIR, Digest::MD5::md5_hex($url) );
    $html_file_path;
}

sub download_html {
    my $url = shift;
    print "Downloading HTML ... $url\n";
    my $html = LWP::Simple::get($url);
    $html;
}

sub convert_to_mobi {
    my $html_file_path = shift;
    print "Converting a html to mobi ...\n";
    system("kindlegen -gif $html_file_path");
    $html_file_path =~ s/\.html/\.mobi/;
    $html_file_path;
}

sub copy_mobi_to_kindle {
    my $book_file_path = shift;
    if ( -d $KINDLE_DOCUMENTS_DIR ) {
        print "Copying mobi to Kindle ...\n";
        system("cp $book_file_path $KINDLE_DOCUMENTS_DIR");
    }
}

sub fix_html {
    my ( $html, $html_url ) = @_;
    get_images_and_fix_image_tags( $html, $html_url );
}

sub image_file_path {
    my $url             = shift;
    my $image_file_name = image_file_name($url);
    my $image_file_path = "$DOWNLOAD_DIR/$image_file_name";
    $image_file_path;
}

sub image_file_name {
    my $url = shift;
    my ( undef, undef, $ext ) = fileparse( $url, qr"\..*" );
    my $image_file_name = Digest::MD5::md5_hex($url) . $ext;
    $image_file_name;
}

sub download_image {
    my $url = shift;
    print "Downloading image ... $url\n";
    my $image_file_path = image_file_path($url);
    my $status = LWP::Simple::mirror( $url, $image_file_path );
    $image_file_path;
}

sub get_images_and_fix_image_tags {
    my ( $html, $html_url ) = @_;
    my $tree  = HTML::TreeBuilder->new_from_content($html);
    my @imges = $tree->find("img");
    foreach my $img (@imges) {
        my $image_url       = URI->new_abs( $img->attr('src'), $html_url );
        my $image_file_path = download_image($image_url);
        my $image_file_name = image_file_name($image_url);
        $img->attr( "src", $image_file_name );
    }
    $tree->as_HTML;
}

__END__
