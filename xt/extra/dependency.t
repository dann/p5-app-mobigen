use Test::Dependencies
    exclude => [qw/Test::Dependencies Test::Base Test::Perl::Critic App::kindlegen/],
    style   => 'light';
ok_dependencies();
