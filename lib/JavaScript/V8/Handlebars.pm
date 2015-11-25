package JavaScript::V8::Handlebars;

use strict;
use warnings;

our $VERSION = '0.03';

use File::Slurp qw/slurp/;
use File::Spec;
use File::Find ();
use JavaScript::V8;
use File::ShareDir ();

# Get Handlebars library path once to make it possible
# for users to use their own libraries.
our @LIBRARY_PATH = do {
	my $module_dir = File::ShareDir::module_dir( __PACKAGE__ );
	my ( $lib ) = glob "$module_dir/handlebars*.js"; # list context avoids global state
	$lib;
};

sub new {
	my( $class, @opts ) = @_;
	my $self = bless {}, $class;
	$self->_build_context;
	return $self;
}

my $HB_SERIAL = 1;
sub new_isolated_environment {
	# see http://handlebarsjs.com/reference.html, section 'Handlebars.create()'
	my( $class, @opts ) = @_;
	my $self = bless {}, $class;
	my $environment = sprintf( 'JV_HB_OBJECT_%d', $HB_SERIAL++ );
	$self->_build_context( $environment );
	return $self;
}

sub _build_context {
	my( $self, $environment ) = @_;

	my $c = $self->{c} = JavaScript::V8::Context->new;

	for my $lib ( @LIBRARY_PATH ){
		$self->eval( scalar slurp( $lib ), $lib ); # setting origin for nicer error messages
	}

	my $hb = 'Handlebars';
	if ( $environment ) {
		# initialize an isolated Handlebars environment
		$hb = $environment;
		$self->eval( "var $hb = Handlebars.create();" );
	}

	# Store subrefs for each javascript method
	for my $meth (qw/precompile registerHelper registerPartial template compile SafeString escapeExpression/ ) {
		# lots of Handlebars methods operate on 'this' so we have to bind our
		# function calls to the object in use
		$self->{$meth} = $self->eval( "$hb.$meth.bind( $hb )" );
	}
}

sub c {
	return $_[0]->{c};
}
sub eval {
	my $self = shift;
	my $ret = $self->{c}->eval(@_);
	die $@ if $@;
	return $ret;
}

sub escape_expression {
	my $self = shift;
	return $self->{escapeExpression}->(@_);
}

sub precompile {
	my( $self, $template, $opts ) = @_;

	return $self->{precompile}->($template, $opts);
}
sub precompile_file {
	return $_[0]->precompile( scalar slurp($_[1]), $_[2] );
}

sub compile {
	my( $self, $template, $opts ) = @_;

	return $self->{compile}->($template, $opts);
}
sub compile_file {
	return $_[0]->compile( scalar slurp($_[1]), $_[2] );
}


sub register_helper {
	my( $self, $name, $code, $origin ) = @_;

	if( ref $code eq 'CODE' ) {
		$self->{registerHelper}->( $name, $code );
	}
	elsif(ref $code eq '') {
		# There seems to be no good way to stay in javascript land here,
		# so we create a perl function from the helper and register it instead.
		# Parens force 'expression' context so the function reference is returned.
		my $fnct = $self->eval( "( $code )", $origin || [caller]->[1] );
		$self->{registerHelper}->( $name, $fnct );
	}
	else {
		die "Bad helper: should be CODEREF or JS source [$code]";
	}

	return 1;
}

sub register_partial {
	my( $self, $name, $tpl ) = @_;

	if( ref $tpl eq '' ) {
		$tpl = $self->compile( $tpl );
	}

	if( ref $tpl eq 'CODE') {
		$self->{registerPartial}->( $name, $tpl );
	}
	else {
		die "Bad partial template: should be CODEREF or template source [$tpl]";
	}

	return 1;
}

sub template {
	my( $self, $template ) = @_;

	if( ref $template eq '' ) {
		#Parens force 'expression' context
		return $self->{template}->($self->eval( "($template)" )); 
	}
	elsif( ref $template eq 'HASH' ) {
		return $self->{template}->( $template );
	}
	else { die "Bad arg [$template] (string or hash)" }
}

sub add_to_context {
	my( $self, $code ) = @_;

	$self->eval( $code );
	# This deliberately returns nothing.
	return;
}
sub add_to_context_file {
	$_[0]->add_to_context( scalar slurp $_[1] );
}

sub render_string {
	my( $self, $template, $env ) = @_;

	return $self->compile( $template )->( $env );
}


sub add_template {
	my( $self, $name, $template ) = @_;

	$self->{template_code}{$name} = $self->precompile( $template );

	return $self->{templates}{$name} = $self->compile( $template );
}

sub add_template_file {
	my( $self, $file, $base ) = @_;
	if( $base ) { $file = File::Spec->rel2abs( $file, $base ); }

	die "Failed to read $file $!" unless -e $file and -r $file;
	
	my $name = File::Spec->abs2rel( $file, $base );
		$name =~ s/\..*$//;

	$self->add_template( $name, scalar slurp $file );
}

sub add_template_dir {
	my( $self, $dir, $ext ) = @_;
	$ext ||= 'hbs';

	File::Find::find( { wanted => sub {
			return unless -f;
			return unless /\.$ext$/;
			warn "Can't read $_" unless -r;

			$self->add_template_file( File::Spec->rel2abs($_), $dir );
		},
		no_chdir => 1,
	}, $dir );

}

sub execute_template {
	my( $self, $name, $args ) = @_;

	return $self->{templates}{$name}->( $args );
}

sub precompiled {
	my( $self ) = @_;

	my $out = "var template = Handlebars.template, templates = Handlebars.templates = Handlebars.templates || {};\n";

	while( my( $name, $template ) = each %{ $self->{template_code} } ) {
		$out .= "templates['$name'] = template( $template );\n";
	}

	return $out;
}



1;

__END__

=head1 NAME

JavaScript::V8::Handlebars - Compile and execute Handlebars templates via the actual JS library

=head1 SYNOPSIS

	use JavaScript::V8::Handlebars

	my $hbjs = JavaScript::V8::Handlebars->new;

	print $hbjs->render_string( "Hello {{var}}", { var => "world" } );

	my $template = $hbjs->compile_file( "template.hbs" );
	print $template->({ var => "world" });

=head1 METHODS

For now the majority of these methods work as described in L<http://handlebarsjs.com/>

=over 4

=item $hbjs->new()

=item $hbjs->c()

Returns the internal JavaScript::V8 object, useful for executing javascript code in the context of the module.

=item $hbjs->eval($javascript_string)

Wrapper function for C<$hbjs->c->eval> that checks for errors and throws an exception.

=item $hbjs->add_to_context_file($javascript_filename)

=item $hbjs->add_to_context($javascript_string)

Shortcut for evaluating javascript intended to add global functions and objects to the current environment.

=item $hbjs->precompile_file($template_filename)

=item $hbjs->precompile($template_string)

Takes a template and translates it into the javascript code suitable for passing to the C<template> method.

=item $hbjs->compile_file($template_filename)

=item $hbjs->compile($template_string)

Takes a template and returns a subref that takes a hashref containing variables as an argument and returns the text of the executed template.

=item $hbjs->register_helper

TBD

=item $hbjs->template( $compiled_javascript_string | $compiled_perl_object )

Takes a precompiled template datastructure and returns a subref ready to be executed.

=item $hbjs->render_string( $template_string, \%context_vars )

Wrapper method for compiling and then executing a template passed as a string.

=item $hbjs->add_template_dir( $directory, [$extension] )

=item $hbjs->add_template_file( $filename, [$base_path] )

=item $hbjs->add_template( $name, $template_string )

Takes a template, compiles it and adds it to the internal store of cached templates for C<execute_template> to use.

=item $hbjs->execute_template( $name, \%context_vars )

Executes a cached template.

=item $hbjs->precompiled()

Returns a string of javascript consisting of all the templates in the cache ready for execution by the browser.

=item $hbjs->safeString($string)

Whatever the original Handlebar function does.

=item $hbjs->escapeString ($string)

Whatever the original Handlebar function does.

=item $hbjs->register_partial($name, $template_string)

Registers a partial named '$name' with the code in '$template_string' so later templates can access it.

=back

=head1 AUTHOR

Robert Grimes, C<< <rmzgrimes at gmail.com> >>

=head1 BUGS

Please report and bugs or feature requests through the interfaces at L<https://github.com/rmzg/JavaScript-V8-Handlebars>

=head1 SUPPORT

You can find documentation for this module with the perldoc command.

perldoc JavaScript::V8::Handlebars


=head1 LICENSE AND COPYRIGHT

Copyright 2015 Robert Grimes.

This library is free software; you can redistribute it and/or modify it under the same terms as Perl itself.


=head1 SEE ALSO

L<https://github.com/rmzg/JavaScript-V8-Handlebars>, L<http://handlebarsjs.com/>

=cut
