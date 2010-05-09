package App::mobigen;
use LWP::Simple ();
use Digest::MD5 qw(md5_hex);
use HTML::TreeBuilder;
use IO::File;
use File::Basename;
use URI;
use File::Copy;
use File::Spec;
use File::Slurp qw(slurp);
use Data::Section::Simple qw(get_data_section);
use Text::MicroTemplate;

our $VERSION = '0.01';

sub new {
    my $class = shift;

    bless {
        home    => File::Spec->catfile( $ENV{HOME}, ".mobigen" ),
        verbose => undef,
        quiet   => undef,
        log     => undef,
        mirrors => [],
        perl    => $^X,
        argv    => [],
        hooks   => {},
        plugins => [],
        download_dir =>
            File::Spec->catfile( $ENV{HOME}, ".mobigen", "book" ),
        documents_dir =>
            File::Spec->catfile( '/', 'Volumes', 'Kindle', 'documents' ),
        @_,
    }, $class;
}

sub init {
    my $self = shift;
    $self->setup_home;
    $self->create_ebook_dir;
    $self->load_plugins;
}

sub setup_home {
    my $self = shift;

    mkdir $self->{home}, 0777 unless -e $self->{home};

    for my $dir (qw( plugins work )) {
        my $sub = File::Spec->catfile( $self->{home}, $dir );
        unless ( -e $sub ) {
            mkdir $sub, 0777 or die "$dir: $!";
        }
    }

    $self->{base}
        = File::Spec->catfile( $self->{home}, "work", time . ".$$" );
    mkdir $self->{base}, 0777 or die "$self->{base}: $!";

    $self->{log} = File::Spec->catfile( $self->{home}, "mobigen.log" );

    {
        my $log  = $self->{log};
        my $base = $self->{base};
        $self->{at_exit} = sub {
            File::Copy::copy( $log,
                File::Spec->catfile( $base, 'mobigen.log' ) );
        };
    }

    open my $out, ">$self->{log}" or die "$self->{log}: $!";
    print $out "mobigen (App::mobigen) $VERSION on perl $]\n";
    print $out "Work directory is $self->{base}\n";

    $self->{plugin_dir} = File::Spec->catfile( $self->{home}, "plugins" );
}

sub doit {
    my $self = shift;
    $self->init;
    my $html           = $self->download_html( $self->{url} );
    my $html_file_path = $self->generate_kindle_html($html);

    my $mobi_file_path
        = $self->generate_mobi( $html_file_path, $self->{url} );

    $self->copy_mobi_to_kindle($mobi_file_path);
    print "Congratulations! Converted a html to a mobi!\n";
}

sub generate_kindle_html {
    my ( $self, $html ) = @_;
    my $fixed_html = $self->fix_html( $html, $self->{url} );
    my $html_file_path = $self->html_file_path( $self->{url} );
    $self->write_file( $fixed_html, $html_file_path );
    $html_file_path;
}

sub generate_mobi {
    my ( $self, $html_file_path, $html_url ) = @_;
    my $toc_file_path = $self->generate_toc($html_url);
    my $opf_file_path = $self->generate_opf();

    $self->_generate_mobi($opf_file_path);
}

sub _generate_mobi {
    my ( $self, $opf_file_path ) = @_;
    print "Converting a html to mobi ...\n";
    my $mobi_file_name = Digest::MD5::md5_hex( $self->{url} ) . ".mobi";
    system("kindlegen -gif $opf_file_path -o $mobi_file_name");

    my $mobi_file_path
        = File::Spec->catfile( $self->{download_dir}, $mobi_file_name );
    $mobi_file_path;
}

sub generate_toc {
    my ( $self, $html_url ) = @_;
    print "Generating TOC ...\n";
    my $toc_items
        = $self->run_hooks( generate_toc => { html_url => $html_url } );
    my $toc           = {};
    my $new_toc_items = $self->numbering_toc_items($toc_items);
    $toc->{booktitle} = $self->{url};
    $toc->{items} = $new_toc_items;
    $toc->{html}  = Digest::MD5::md5_hex($html_url) . ".html";
    my $toc_content = $self->render_template( 'toc', { toc => $toc } );

    my $toc_file_path = $self->toc_file_path($html_url);
    $self->write_file( $toc_content, $toc_file_path );
    $toc_file_path;
}

sub numbering_toc_items {
    my ( $self, $toc_items ) = @_;
    die 'toc_items is required' unless $toc_items;
    my @new_toc_items = ();
    my $counter       = 1;
    foreach my $item ( @{ $toc_items || [] } ) {
        $item->{num} = $counter;
        $counter++;
        push @new_toc_items, $item;
    }
    return \@new_toc_items;
}

sub toc_file_path {
    my ( $self, $url ) = @_;
    my $file_path = File::Spec->catfile( $self->{download_dir},
        Digest::MD5::md5_hex($url) . ".ncx" );
    $file_path;
}

sub generate_opf {
    my $self = shift;
    print "Generating OPF ...\n";

    # TODO Implement me!
    my $book = $self->run_hooks(
        generate_bookinfo => { html_url => $self->{url}, } );

    # FIXME
    $book                ||= {};
    $book->{title}       ||= $self->{url};
    $book->{language}    ||= 'en-us';
    $book->{date}        ||= '2010';
    $book->{creator}     ||= 'dann';
    $book->{description} ||= 'description';
    $book->{toc}         ||= 'toc';
    $book->{start_page}  ||= 'Introduction';

    $book->{html} = Digest::MD5::md5_hex( $self->{url} ) . ".html";
    $book->{ncx}  = Digest::MD5::md5_hex( $self->{url} ) . ".ncx";

    my $opf_content = $self->render_template( 'opf', { book => $book } );
    my $opf_file_path = $self->opf_file_path($self->{url});
    $self->write_file( $opf_content, $opf_file_path );

    $opf_file_path;
}

sub opf_file_path {
    my ( $self, $url ) = @_;
    my $file_path = File::Spec->catfile( $self->{download_dir},
        Digest::MD5::md5_hex($url) . ".opf" );
    $file_path;
}

sub write_file {
    my ( $self, $content, $file_path ) = @_;
    my $io = IO::File->new( $file_path, 'w' );
    $io->print($content);
    $io->close;
}

sub create_ebook_dir {
    my $self = shift;
    if ( !-e $self->{download_dir} ) {
        mkdir $self->{download_dir}
            or die "cannot create $self->{download_dir} $!";
    }
}

sub html_file_path {
    my ( $self, $url ) = @_;
    my $html_file_path = File::Spec->catfile( $self->{download_dir},
        Digest::MD5::md5_hex($url) . ".html" );
    $html_file_path;
}

sub download_html {
    my ( $self, $url ) = @_;
    print "Downloading HTML ... $url\n";
    my $html = LWP::Simple::get($url);
    $html;
}

sub copy_mobi_to_kindle {
    my ( $self, $book_file_path ) = @_;
    if ( -d $self->{documents_dir} ) {
        print "Copying mobi to Kindle ...\n";
        File::Copy::copy( $book_file_path, $self->{documents_dir} );
    }
}

sub fix_html {
    my ( $self, $html, $html_url ) = @_;
    $self->get_images_and_fix_image_tags( $html, $html_url );
}

sub image_file_path {
    my ( $self, $url ) = @_;
    my $image_file_name = $self->image_file_name($url);
    my $image_file_path
        = File::Spec->catfile( $self->{download_dir}, $image_file_name );
    $image_file_path;
}

sub image_file_name {
    my ( $self, $url ) = @_;
    my ( undef, undef, $ext ) = fileparse( $url, qr"\..*" );
    my $image_file_name = Digest::MD5::md5_hex($url) . $ext;
    $image_file_name;
}

sub download_image {
    my ( $self, $url ) = @_;
    print "Downloading image ... $url\n";
    my $image_file_path = $self->image_file_path($url);
    my $status = LWP::Simple::mirror( $url, $image_file_path );
    $image_file_path;
}

sub get_images_and_fix_image_tags {
    my ( $self, $html, $html_url ) = @_;
    my $root  = HTML::TreeBuilder->new_from_content($html);
    my @imges = $root->find("img");
    foreach my $img (@imges) {
        my $image_url       = URI->new_abs( $img->attr('src'), $html_url );
        my $image_file_path = $self->download_image($image_url);
        my $image_file_name = $self->image_file_name($image_url);
        $img->attr( "src", $image_file_name );
    }
    $root->as_HTML;
}

sub load_plugins {
    my $self = shift;

    $self->_load_plugins;

    for my $hook ( keys %{ $self->{hooks} } ) {
        $self->{hooks}->{$hook}
            = [ sort { $a->[0] <=> $b->[0] } @{ $self->{hooks}->{$hook} } ];
    }

    $self->run_hooks( init => {} );
}

sub _load_plugins {
    my $self = shift;
    return if $self->{disable_plugins};
    return unless $self->{plugin_dir} && -e $self->{plugin_dir};

    opendir my $dh, $self->{plugin_dir} or return;
    my @plugins;
    while ( my $e = readdir $dh ) {
        my $f = File::Spec->catfile( $self->{plugin_dir}, $e );
        next unless -f $f && $e =~ /^[A-Za-z0-9_]+$/ && $e ne 'README';
        push @plugins, [ $f, $e ];
    }

    for my $plugin ( sort { $a->[1] <=> $b->[1] } @plugins ) {
        $self->load_plugin(@$plugin);
    }
}

sub load_plugin {
    my ( $self, $file, $name ) = @_;

    my $plugin = { name => $name, file => $file };
    my @attr   = qw( name description author version synopsis );
    my $dsl    = join "\n", map "sub $_ { \$plugin->{$_} = shift }", @attr;

    ( my $package = $file ) =~ s/[^a-zA-Z0-9_]/_/g;
    my $code = do { open my $io, "<$file"; local $/; <$io> };

    my @hooks;
    eval "package App::mobigen::plugin::$package;\n"
        . "use strict;\n$dsl\n" . "\n"
        . "sub hook { push \@hooks, [\@_] };\n$code";

    if ($@) {
        $self->diag(
            "! Loading $name plugin failed. See $self->{log} for details.\n");
        $self->chat($@);
        return;
    }

    for my $hook (@hooks) {
        $self->hook( $plugin->{name}, @$hook );
    }

    push @{ $self->{plugins} }, $plugin;
}

sub hook {
    my $cb = pop;
    my ( $self, $name, $hook, $order ) = @_;
    $order = 50 unless defined $order;
    push @{ $self->{hooks}->{$hook} }, [ $order, $cb, $name ];
}

sub run_hook {
    my ( $self, $hook, $args ) = @_;
    $self->run_hooks( $hook, $args, 1 );
}

sub run_hooks {
    my ( $self, $hook, $args, $first ) = @_;
    $args->{app} = $self;
    my $res;
    for my $plugin ( @{ $self->{hooks}->{$hook} || [] } ) {
        $res = eval { $plugin->[1]->($args) };
        $self->chat("Running hook '$plugin->[2]' error: $@") if $@;
        last if $res && $first;
    }
    return $res;
}

sub diag {
    my $self = shift;
    print STDERR @_ if $self->{verbose} or !$self->{quiet};
    $self->log(@_);
}

sub chat {
    my $self = shift;
    print STDERR @_ if $self->{verbose};
    $self->log(@_);
}

sub log {
    my $self = shift;
    open my $out, ">>$self->{log}";
    print $out @_;
}

sub parse_options {
    my $self = shift;
    $self->{url} = $ARGV[0];
    die 'usage: mobigen url' unless $self->{url};
}

sub render_template {
    my ( $self, $name, $args ) = @_;
    $args ||= {};
    my $code        = $self->code($name);
    my $args_string = $self->args_string($args);

    local $@;
    my $renderer = eval << "..." or die $@;    ## no critic
sub {
    my \$args = shift; $args_string;
    $code->();
};
...

    $renderer->($args);
}

sub args_string {
    my ( $self, $args ) = @_;
    my $args_string = '';
    for my $key ( keys %{ $args || {} } ) {
        unless ( $key =~ /^[a-zA-Z_][a-zA-Z0-9_]*$/ ) {
            die qq{Invalid template args key name: "$key"};
        }
        if ( ref( $args->{$key} ) eq 'CODE' ) {
            $args_string .= qq{my \$$key = \$args->{$key}->();\n};
        }
        else {
            $args_string .= qq{my \$$key = \$args->{$key};\n};
        }
    }
    $args_string;
}

sub template {
    my $name     = shift;
    my $template = get_data_section($name);
    local $@;
    eval { $template = slurp($name) unless $template; };
    chomp $template if $template;
    return $template;
}

sub code {
    my ( $self, $name ) = @_;
    my $template = template($name) or return;
    my $mt = Text::MicroTemplate->new( template => $template );
    my $code = $mt->code;
    return $code;
}

1;

__DATA__

@@ opf
?= Text::MicroTemplate::encoded_string('<?xml version="1.0" encoding="UTF-8"?>')
<package unique-identifier="uid">
  <metadata>
    <dc-metadata xmlns:dc="http://purl.org/metadata/dublin_core"
    xmlns:oebpackage="http://openebook.org/namespaces/oeb-package/1.0/">

      <dc:Title><?= $book->{title} ?></dc:Title>
      <dc:Language><?= $book->{language} ?></dc:Language>
      <dc:Creator><?= $book->{creator} ?></dc:Creator>
      <dc:Description><?= $book->{description} ?></dc:Description>
      <dc:Date><?= $book->{date} ?></dc:Date>
    </dc-metadata>
    <x-metadata>
      <output encoding="utf-8" content-type="text/x-oeb1-document">
      </output>
    </x-metadata>
  </metadata>
  <manifest>
    <item id="item1" media-type="text/x-oeb1-document" href="<?= $book->{html} ?>"></item>
    <item id="toc" media-type="application/x-dtbncx+xml" href="<?= $book->{ncx} ?>"></item>
  </manifest>
  <spine toc="toc">
    <itemref idref="item1" />
  </spine>
  <tours></tours>
  <guide>
    <reference type="toc" title="Table of Contents" href="<?= $book->{html} ?>%23<?= $book->{toc} ?>"></reference>
    <reference type="start" title="Startup Page" href="<?= $book->{html} ?>%23<?= $book->{start_page} ?>"></reference>
  </guide>
</package>

@@ toc
?= Text::MicroTemplate::encoded_string('<?xml version="1.0" encoding="UTF-8"?>')
<!DOCTYPE ncx PUBLIC "-//NISO//DTD ncx 2005-1//EN" "http://www.daisy.org/z3986/2005/ncx-2005-1.dtd">

<ncx xmlns="http://www.daisy.org/z3986/2005/ncx/" version="2005-1">
  <docTitle>
    <text><?= $toc->{booktitle} ?></text>
  </docTitle>
  <navMap>
? for my $item (@{$toc->{items}|| []}) {
    <navPoint id="navPoint-<?= $item->{num} ?>" playOrder="<?= $item->{num} ?>">
      <navLabel><text><?= $item->{text} ?></text></navLabel><content src="<?= $toc->{html} ?><?= $item->{anchor} ?>"/>
    </navPoint>
? }
  </navMap>
</ncx>

