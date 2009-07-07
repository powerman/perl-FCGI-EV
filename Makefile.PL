use inc::Module::Install;

name     'FCGI-EV';
all_from 'lib/FCGI/EV.pm';
author   'Alex Efros <powerman-asdf@ya.ru>';
license  'perl';

requires 'EV';
requires 'IO::Stream';

build_requires 'Test::More';

auto_install;

WriteAll;

