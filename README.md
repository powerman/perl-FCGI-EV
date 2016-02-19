[![Build Status](https://travis-ci.org/powerman/perl-FCGI-EV.svg?branch=master)](https://travis-ci.org/powerman/perl-FCGI-EV)
[![Coverage Status](https://coveralls.io/repos/powerman/perl-FCGI-EV/badge.svg?branch=master)](https://coveralls.io/r/powerman/perl-FCGI-EV?branch=master)

# NAME

FCGI::EV - Implement FastCGI protocol for use in EV-based applications

# VERSION

This document describes FCGI::EV version v1.0.9

# SYNOPSIS

    use FCGI::EV;
    use Some::FCGI::EV::Handler;

    # while in EV::loop, accept incoming connection from web server into
    # $sock, then start handling FastCGI protocol on that connection,
    # using Some::FCGI::EV::Handler for processing CGI requests:
    FCGI::EV->new($sock, 'Some::FCGI::EV::Handler');


    #
    # EXAMPLE: complete FastCGI server (without error handling code)
    #          use FCGI::EV::Std handler (download separately from CPAN)
    #

    use Socket;
    use Fcntl;
    use EV;
    use FCGI::EV;
    use FCGI::EV::Std;

    my $path = '/tmp/fastcgi.sock';

    socket my $srvsock, AF_UNIX, SOCK_STREAM, 0;
    unlink $path;
    my $umask = umask 0;   # ensure 0777 perms for unix socket
    bind $srvsock, sockaddr_un($path);
    umask $umask;
    listen $srvsock, SOMAXCONN;
    fcntl $srvsock, F_SETFL, O_NONBLOCK;

    my $w = EV::io $srvsock, EV::READ, sub {
       accept my($sock), $srvsock;
       fcntl $sock, F_SETFL, O_NONBLOCK;
       FCGI::EV->new($sock, 'FCGI::EV::Std');
    };

    EV::loop;

# DESCRIPTION

This module implement FastCGI protocol for use in EV-based applications.
(That mean you have to run EV::loop in your application or this module
will not work.)

It receive and parse data from web server, pack and send data to web
server, but it doesn't process CGI requests received from web server -
instead it delegate this work to another module called 'handler'. For
one example of such handler, see [FCGI::EV::Std](https://metacpan.org/pod/FCGI::EV::Std).

FCGI::EV work using non-blocking sockets and initially was designed to use
in event-based CGI applications (which able to handle multiple parallel
CGI requests in single process without threads/fork). This require from
CGI to avoid any operations which may block, like using SQL database -
instead CGI should delegate all such tasks to remote services and talk to
these services in non-blocking mode.

It also possible to use it to run usual CGI.pm-based applications. If you
will do this using FCGI::EV::Std handler, then only one CGI request will
be executed at a time (which is probably not what you expect from
FastCGI!), because FCGI::EV::Std doesn't implement any process-manager.
But it's possible to develop another handlers for FCGI::EV, which will
support process-management and so will handle multiple CGI request in
parallel.

This module doesn't require from user to use CGI.pm - any module for
parsing CGI params can be used in general (details depends on used
FCGI::EV handler module).

# INTERFACE 

- new( $sock, $class )

    Start talking FastCGI protocol on $sock (which should be socket open to
    just-connected web server), and use $class to handle received CGI requests.

    Module $class should implement "FCGI::EV handler" interface. You can use
    either [FCGI::EV::Std](https://metacpan.org/pod/FCGI::EV::Std) from CPAN or develop your own.

    Return nothing. (Created FCGI::EV object will work in background and will
    be automatically destroyed after finishing I/O with web server.)

# HANDLER CLASS INTERFACE

Handler class (which name provided in $class parameter to FCGI::EV->new())
must implement this interface:

- new( $server, \\%env )

    When FCGI::EV object receive initial part of CGI request (environment
    variables) it will call $handler\_class->new() to create handler object
    which should process that CGI request.

    Parameter $server is FCGI::EV object itself. It's required to send CGI
    reply. WARNING! Handler may keep only weaken() reference to $server!

    After calling new() FCGI::EV object ($server) will continue receiving
    STDIN content from web server and will call $handler->stdin() each time it
    get next part of STDIN.

- stdin( $data, $is\_eof )

    The $data is next chunk of STDIN received from web server. Flag $is\_eof will
    be true if $data was last part of STDIN.

    Usually handler shouldn't begin processing CGI request until all content
    of STDIN will be received.

- DESTROY

    This method is optional. It will be called when connection to web server is
    closed and FCGI::EV object going to die (but it's still exists when DESTROY
    is called - except if DESTROY was called while global destruction stage).

    Handler object may use DESTROY to interrupt current CGI request if web server
    close connection before CGI send it reply.

## SENDING CGI REPLY

After handler got %env (in new()) and complete STDIN (in one or more calls
of stdin()) it may start handling this CGI request and prepare reply to send
to web server. To send this data it should use method $server->stdout(),
where $server is object given to new() while creating handler object
(it should keep weak reference to $server inside to be able to reply).

- stdout( $data, $is\_eof )

    CGI may send reply in one or more parts. Last part should have $is\_eof set
    to true. DESTROY method of handler object will be called shortly after
    handler object will do $server->stdout( $data, 1 ).

## HANDLER EXAMPLE

This handler will process CGI requests one-by-one (i.e. in blocking mode).
On request function main::main() will be executed. That function may use
standard CGI.pm module to get request parameters and send it reply using
usual print to STDOUT.

There no error-handling code in this example, see [FCGI::EV::Std](https://metacpan.org/pod/FCGI::EV::Std) for
more details.

    package FCGI::EV::ExampleHandler;

    use Scalar::Util qw( weaken );
    use CGI::Stateless; # needed to re-init CGI.pm state between requests

    sub new {
       my ($class, $server, $env) = @_;
       my $self = bless {
           server  => $server,
           env     => $env,
           stdin   => q{},
       }, $class;
       weaken($self->{server});
       return $self;
    }

    sub stdin {
       my ($self, $stdin, $is_eof) = @_;
       $self->{stdin} .= $stdin;
       if ($is_eof) {
           local *STDIN;
           open STDIN, '<', \$self->{stdin};
           local %ENV = %{ $self->{env} };
           local $CGI::Q = CGI::Stateless->new();
           local *STDOUT;
           my $reply = q{};
           open STDOUT, '>', \$reply;
           main::main();
           $self->{server}->stdout($reply, 1);
       }
       return;
    }

# DIAGNOSTICS

There no errors returned in any way by this module, but there few warning
messages may be printed:

- `FCGI::EV: IO: %s`

    While doing I/O with web server error %s happened and connection was closed.

- `FCGI::EV: %s`

    While parsing data from web server error %s happened and connection was closed.
    (That error probably mean bug either in web server or this module.)

# SUPPORT

## Bugs / Feature Requests

Please report any bugs or feature requests through the issue tracker
at [https://github.com/powerman/perl-FCGI-EV/issues](https://github.com/powerman/perl-FCGI-EV/issues).
You will be notified automatically of any progress on your issue.

## Source Code

This is open source software. The code repository is available for
public review and contribution under the terms of the license.
Feel free to fork the repository and submit pull requests.

[https://github.com/powerman/perl-FCGI-EV](https://github.com/powerman/perl-FCGI-EV)

    git clone https://github.com/powerman/perl-FCGI-EV.git

## Resources

- MetaCPAN Search

    [https://metacpan.org/search?q=FCGI-EV](https://metacpan.org/search?q=FCGI-EV)

- CPAN Ratings

    [http://cpanratings.perl.org/dist/FCGI-EV](http://cpanratings.perl.org/dist/FCGI-EV)

- AnnoCPAN: Annotated CPAN documentation

    [http://annocpan.org/dist/FCGI-EV](http://annocpan.org/dist/FCGI-EV)

- CPAN Testers Matrix

    [http://matrix.cpantesters.org/?dist=FCGI-EV](http://matrix.cpantesters.org/?dist=FCGI-EV)

- CPANTS: A CPAN Testing Service (Kwalitee)

    [http://cpants.cpanauthors.org/dist/FCGI-EV](http://cpants.cpanauthors.org/dist/FCGI-EV)

# AUTHOR

Alex Efros &lt;powerman@cpan.org>

# COPYRIGHT AND LICENSE

This software is Copyright (c) 2009 by Alex Efros &lt;powerman@cpan.org>.

This is free software, licensed under:

    The MIT (X11) License
