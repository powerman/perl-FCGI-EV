use inc::Module::Install;

name     'FCGI-EV';
all_from 'lib/FCGI/EV.pm';
author   'Alex Efros <powerman-asdf@ya.ru>';
license  'perl';

requires	'version';
requires	'EV';
requires	'IO::Stream';

test_requires   'Test::More';

recommends      'Test::CheckManifest'   => '0.9';
recommends      'Test::Perl::Critic';
recommends      'Test::Pod::Coverage'   => '1.08';
recommends      'Pod::Coverage'         => '0.18';
recommends      'Test::Pod'             => '1.22';


auto_install;

WriteAll;

