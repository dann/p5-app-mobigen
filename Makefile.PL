use inc::Module::Install;
name 'App-mobigen';
all_from 'lib/App/mobigen.pm';

requires(
    'LWP::Simple'           => 0,
    'Digest::MD5'           => 0,
    'HTML::TreeBuilder'     => 0,
    'IO::File'              => 0,
    'File::Basename'        => 0,
    'URI'                   => 0,
    'File::Copy'            => 0,
    'File::Spec'            => 0,
    'File::Slurp'           => 0,
    'Data::Section::Simple' => 0,
    'Text::MicroTemplate'   => 0,
);

test_requires( 'Test::More' => 0, );
use_test_base;
auto_include;
WriteAll;
