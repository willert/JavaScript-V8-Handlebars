#!perl
use 5.006;
use strict;
use warnings;
use Test::More;

plan tests => 18;

#BEGIN {
    use_ok( 'JavaScript::V8::Handlebars' ) || print "Bail out!\n";
#}

my $hb = JavaScript::V8::Handlebars->new;
isa_ok( $hb, 'JavaScript::V8::Handlebars' );

is( $hb->render_string("hello {{name}}", {name=>"bob"}), "hello bob" );

is( $hb->render_string("hello {{#if name}}{{name}}{{/if}}",{name=>"bob"}), "hello bob" );

ok( $hb->registerHelper("helper1",sub{return "helper1 done"}) );

is( $hb->render_string( "test {{helper1}}" ), "test helper1 done" );

ok( $hb->registerHelper("helper2","function(){return 'helper2 done'}") );

is( $hb->render_string( "test {{helper2}}" ), "test helper2 done" );


is( $hb->render_string( "test {{#each list}}{{var}}{{/each}}", {list=>[{var=>1},{var=>2},{var=>3}]} ),
	"test 123"
);


is( $hb->compile("test {{foo}}")->({foo=>42}), "test 42" );

my $precompile = $hb->precompile("test {{bar}}");
ok( $precompile );

ok( my $template = $hb->template( $precompile ) );

is( $template->({bar=>43}), "test 43" );


my $c = $hb->c; #Get a JS context with Handlebars preloaded

ok( $hb->add_template( "precompiletest", "hello this is {{var}}" ) );
my $code = $hb->precompiled;
ok( $code );
ok( $c->eval( $code ) );

is( $c->eval( "Handlebars.templates.precompiletest({var:'precompiled'})" ), "hello this is precompiled" );
ok( not defined $@ );

