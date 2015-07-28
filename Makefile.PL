use 5.006;
use strict;
use warnings;
use ExtUtils::MakeMaker;

use lib 'inc';
use File::ShareDir::Install;

install_share module => 'JavaScript::V8::Handlebars' => 'share';

WriteMakefile(
    NAME             => 'JavaScript::V8::Handlebars',
    AUTHOR           => q{Robert Grimes <rmzgrimes@gmail.com>},
    VERSION_FROM     => 'lib/JavaScript/V8/Handlebars.pm',
    ABSTRACT_FROM    => 'lib/JavaScript/V8/Handlebars.pm',
    LICENSE          => 'artistic_2',
    PL_FILES         => {},
    MIN_PERL_VERSION => 5.006,
    CONFIGURE_REQUIRES => {
        'ExtUtils::MakeMaker' => 0,
    },
    BUILD_REQUIRES => {
        'Test::More' => 0,
    },
    PREREQ_PM => {
        'JavaScript::V8'    => 0,
        #'Foo::Bar::Module' => 5.0401,
    },
    dist  => { COMPRESS => 'gzip -9f', SUFFIX => 'gz', },
    clean => { FILES => 'JavaScript-V8-Handlebars-*' },
);

package MY;
use File::ShareDir::Install qw/postamble/;
