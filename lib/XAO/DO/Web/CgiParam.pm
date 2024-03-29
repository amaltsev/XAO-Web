=head1 NAME

XAO::DO::Web::CgiParam - Retrieves parameter from CGI environment

=head1 SYNOPSIS

 <%CgiParam param="username" default="test"%>

=head1 DESCRIPTION

Displays CGI parameter. Arguments are:

 name => parameter name
 default => default text

=cut

###############################################################################
package XAO::DO::Web::CgiParam;
use strict;
use XAO::Utils;
use XAO::Errors qw(XAO::DO::Web::CgiParam);
use base XAO::Objects->load(objname => 'Web::Page');

our $VERSION='2.2';

sub display ($;%) {
    my $self=shift;
    my $args=get_args(\@_);

    my $name=$args->{'name'} || $args->{'param'} ||
        throw $self "- no 'param' and no 'name' given";

    my $text;
    $text=$self->cgi->param($name);
    $text=$args->{'default'} unless defined $text;

    return unless defined $text;

    # Preventing XSS attacks. Unless we have a 'dont_sanitize' parameter
    # angle brackets are removed from the output.
    #
    if(!$args->{'dont_sanitize'}) {
        $text=~s/[<>]/ /sg;
    }

    # Zero bytes trigger a strange bug in at least some combinations of
    # Apache and XAO::Web. Repeated requests that send something like
    # ?foo=bar%00 that use CgiParam sometimes result in Apache hanging
    # even though processing is done. There is almost never a real need
    # to send a zero byte as an inline CGI parameter, so filtering it
    # out.
    #
    if(!$args->{'keep_zeros'}) {
        $text=~s/\x00/ /sg;
    }

    # Trimming spaces
    #
    if(!$args->{'keep_spaces'}) {
        $text=~s/^\s*|\s*$//sg;
    }

    $self->textout($text);
}

###############################################################################
1;
__END__

=head1 METHODS

No publicly available methods except overriden display().

=head1 EXPORTS

Nothing.

=head1 AUTHOR

Copyright (c) 2005 Andrew Maltsev

Copyright (c) 2001-2004 Andrew Maltsev, XAO Inc.

<am@ejelta.com> -- http://ejelta.com/xao/

=head1 SEE ALSO

Recommended reading:
L<XAO::Web>,
L<XAO::DO::Web::Page>.
