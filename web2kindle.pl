#!/usr/bin/env perl
use strict;
use warnings;
use LWP::Simple;
use Digest::MD5 qw(md5_hex);

our $DOWNLOAD_DIR = '/tmp/kindlebook';
our $KINDLE_DOCUMENTS_DIR = '/Volumes/Kindle/documents/';

my $url = shift;
die 'url is required' unless $url;

main();
exit;

sub main {
    create_download_dir();
    my $html_file_path = download($url);
    my $mobi_file_path = convert_to_mobi($html_file_path);
    copy_book_to_kindle($mobi_file_path);
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
    return $html_file_path;
}

sub download {
    my $url            = shift;
    my $html_file_path = html_file_path($url);
    LWP::Simple::mirror( $url, $html_file_path );
    return $html_file_path;
}

sub convert_to_mobi {
    my $html_file_path = shift;
    system("kindlegen $html_file_path");
    $html_file_path =~ s/\.html/\.mobi/;
    return $html_file_path;
}

sub copy_book_to_kindle {
    my $book_file_path = shift;
    if(-d $KINDLE_DOCUMENTS_DIR) {
        system("cp $book_file_path $KINDLE_DOCUMENTS_DIR");
    }
}

__END__
