#XXX - make test for XAO::Web

package XAO::Web;
use strict;
use CGI;
use XAO::Utils;
use XAO::Projects;
use XAO::Objects;
use XAO::SimpleHash;
use XAO::PageSupport;
use XAO::Templates;
use XAO::Errors qw(XAO::Web);

###############################################################################
# XAO::Web version number. Hand changed with every release!
#
use vars qw($VERSION);
$VERSION='1.05';

###############################################################################

=head1 NAME

XAO::Web - XAO Web Developer, dynamic content building suite

=head1 SYNOPSIS

 use XAO::Web;

 my $web=XAO::Web->new(sitename => 'test');

 $web->execute(cgi => $cgi,
               path => '/index.html');

 my $config=$web->config;

 $config->clipboard->put(foo => 'bar');

=head1 DESCRIPTION

Please read L<XAO::Web::Intro> for general overview and setup
instructions.

XAO::Web module provides a frameworks for loading site configuration and
executing objects and templates in the site context. It is used in
scripts and in Apache web server handler to generate actual web pages
content.

Normally a developer does not need to use XAO::Web directly.

=head1 SITE INITIALIZATION

When XAO::Web creates a new site (for mod_perl that happens only once
during each instance on Apache lifetime) it first loads new 'Config'
object using XAO::Objects' new() method and site name it knows. If site
overrides Config - it loads site specific Config, if not - the systme
one.

After the object is created XAO::Web embeds two standard additional
configuration objects into it:

=over

=item hash

Hash object is primarily used to keep site configuration parameters. It
is just a XAO::SimpleHash object and most of its methods get embedded -
get, put, getref, delete, defined, exists, keys, values, contains.

=item web

Web configuration embeds methods that allow cookie, clipboard and
cgi manipulations -- add_cookie, cgi, clipboard, cookies, header,
header_args.

=back

After that XAO::Web calls init() method on the Config object which
is supposed to finish configuration set up and usually stuffs some
parameters into 'hash', then connects to a database and embeds database
configuration object into the Config object as well. Refer to
L<XAO::Web::Intro> for an example of site specific Config object and
init() method.

When object initialization is completed the Config object is placed into
XAO::Projects registry and is retrieved from there on next access to the
same site in case of mod_perl.

B<Note:> that means that if you are embedding a site specific version
of an object during initialisation you need to pass 'sitename' into
XAO::Objects' new() method.

=head1 METHODS

Methods of XAO::Web objects include:

=over

=cut

###############################################################################

sub analyze ($$;$);
sub clipboard ($);
sub config ($);
sub execute ($%);
sub new ($%);
sub set_current ($);
sub sitename ($);

###############################################################################

=item analyze ($)

Checks how to display the given path (scalar or split up array
reference). Always returns valid results or throws an error if that
can't be accomplished.

Returns hash reference:

 prefix   => longest matching prefix (directory in case of template found)
 path     => path to the page after the prefix
 fullpath => full path from original query
 objname  => object name that will serve this path
 objargs  => object args hash (may be empty)

=cut
 
sub analyze ($$;$) {
    my ($self,$patharr,$sitename)=@_;

    $patharr=[ split(/\/+/,$patharr) ] unless ref $patharr;

    shift @$patharr while @$patharr && !length($patharr->[0]);
    unshift(@$patharr,'');
    my $path=join('/',@$patharr);

    ##
    # Looking for the object matching the path.
    #
    my $siteconfig=$self->config;
    my $table=$siteconfig->get('path_mapping_table');
    if($table) {
        for(my $i=@$patharr; $i>=0; $i--) {
            my $dir=$i ? join('/',@{$patharr}[0..$i-1]) : '';

            my $od=$table->{$dir} ||
                   $table->{'/'.$dir} ||
                   $table->{$dir.'/'} ||
                   $table->{'/'.$dir.'/'};
            next unless defined $od;

            ##
            # If $od is an empty string or an empty array reference --
            # that means that we need to fall back to default handler
            # for that path.
            #
            my $rhash;
            if(ref($od) eq 'HASH') {
                $rhash=merge_refs($od);
            }
            elsif(ref($od) eq 'ARRAY') {
                last unless @$od;
                my %args;
                if(scalar(@{$od})%2 == 1) {
                    %args=@{$od}[1..$#{$od}];
                }
                else {
                    throw XAO::E::Web "analyze - odd number of arguments in the mapping table, dir=$dir, objname=$od->[0]";
                }
                $rhash={
                    type        => 'xaoweb',
                    objname     => $od->[0],
                    objargs     => \%args,
                };
            }
            else {
                last unless length($od);
                $rhash={
                    type        => 'xaoweb',
                    objname     => $od,
                    objargs     => { },
                };
            }

            $rhash->{path}=join('/',@{$patharr}[$i..$#$patharr]);
            $rhash->{prefix}=$dir;
            $rhash->{fullpath}=$path;

            return $rhash;
        }
    }

    ##
    # Now looking for exactly matching template and returning Page
    # object if found.
    #
    my $filename=XAO::Templates::filename($path,$sitename);
    if($filename) {
        return {
            type        => 'xaoweb',
            objname     => 'Page',
            objargs     => { },
            path        => $path,
            fullpath    => $path,
            prefix      => join('/',@{$patharr}[0..($#$patharr-1)]),
            filename    => $filename,
        };
    }

    ##
    # Nothing was found, returning Default object
    #
    return {
        type        => 'notfound',
        objname     => 'Default',
        path        => $path,
        fullpath    => $path,
        prefix      => ''
    };
}

###############################################################################

=item clipboard ()

Returns site clipboard object.

=cut

sub clipboard ($) {
    my $self=shift;
    return $self->config->clipboard;
}

###############################################################################

=item config ()

Returns site configuration object reference.

=cut

sub config ($) {
    my $self=shift;
    return $self->{siteconfig} ||
        throw XAO::E::Web "config - no configuration object";
}

###############################################################################

=item execute (%)

Executes given `path' using given `cgi' environment. Prints results to
standard output and uses CGI object methods to send header.

B<Note:> Execute() is not re-entry safe currently! Meaning that if you
create a XAO::Web object in any method called inside of execute() loop
and then call execute() on that newly created XAO::Web object the system
will fail and no useful results will be produced.

=cut

sub execute ($%) {
    my $self=shift;
    my $args=get_args(\@_);

    my ($pagetext,$header)=$self->expand($args);

    ##
    # If we get the header then it was not printed before and we are
    # expected to print out the page. This is almost always true except
    # when page includes something like Redirect object.
    #
    if(defined($header)) {
        if(my $r=$args->{apache}) {
            my $h=$self->config->header_args;
            while(my ($n,$v)=each %$h) {
                $r->header_out($n => $v);
                $r->err_header_out($n => $v);
            }
            $r->send_http_header;
            $r->print($pagetext) unless $r->header_only;
        }
        else {
            print $header,
                  $pagetext;
        }
    }
}

###############################################################################

=item expand (%)

Expands given `path' using given `cgi' or 'apache' environment. Returns
just the text of the page in scalar context and page content plus header
content in array context.

This is normally used in scripts to execute only a particular template
and get results of execution.

`Objargs' argument may refer to a hash of additional parameters to be
passed to the template being executed.

Example:

 my $report=$web->expand(cgi     => CGI->new,
                         path    => '/bits/stat-report',
                         objargs => {
                             CUSTOMER_ID => '123X234Z',
                             MIN_TIME    => time - 86400 * 7,
                         });

See also lower level process() method.

=cut

sub expand ($%) {
    my $self=shift;
    my $args=get_args(\@_);

    ##
    # Processing the page and getting its text
    #
    my $pagetext=$self->process($args);

    ##
    # In scalar context (normal cases) we return only the resulting page
    # text. In array context (compatibility) we return header as well.
    #
    my $siteconfig=$self->config;
    if(wantarray) {
        my $header=$siteconfig->header;
        $siteconfig->cleanup;
        return ($pagetext,$header);
    }
    else {
        $siteconfig->cleanup;
        return $pagetext;
    }
}

###############################################################################

=item process (%)

Takes the same arguments as the expand() method returning expanded page
text. Does not clean the site context and should not be called directly
-- for normal situations either expand() or execute() methods should be
called.

=cut

sub process ($%) {
    my $self=shift;
    my $args=get_args(\@_);

    my $siteconfig=$self->config;
    my $sitename=$self->sitename;

    ##
    # Making sure path starts from a slash
    #
    my $path=$args->{path} || throw XAO::E::Web "expand - no 'path' given";
    $path='/' . $path;
    $path=~s/\/{2,}/\//g;

    ##
    # Setting the current project context to our site.
    #
    $self->set_current();

    ##
    # Resetting page text stack in case it was terminated abnormally
    # before and we're in the same process/memory.
    #
    XAO::PageSupport::reset();

    ##
    # Figuring out current active URL. It might be the same as base_url
    # and in most cases it is, but it just as well might be different.
    #
    # The URL should be full path to the start point -
    # http://host.com in case of rewrite and something like
    # http://host.com/cgi-bin/xao-apache.pl/sitename in case of plain
    # CGI usage.
    #
    my $active_url;
    my $apache=$args->{apache};
    my $cgi=$args->{cgi} || CGI->new;
    if($apache) {
        $active_url="http://" . $apache->hostname;
    }
    else {
        if(defined($CGI::VERSION) && $CGI::VERSION>=2.80) {
            $active_url=$cgi->url(-base => 1, -full => 0);
            my $pinfo=$ENV{PATH_INFO} || '';
            my $uri=$ENV{REQUEST_URI} || '';
            $uri=~s/^(.*?)\?.*$/$1/;
            if($pinfo =~ /^\/\Q$sitename\E(\/.+)?\Q$uri\E/) {
                # mod_rewrite
            }
            elsif($pinfo && $uri =~ /^(.*)\Q$pinfo\E$/) {
                # cgi
                $active_url.=$1;
            }
            # dprint ">2.8 $active_url";
        }
        else {
            $active_url=$cgi->url(-full => 1, -path_info => 0);
            $active_url=$1 if $active_url=~/^(.*)(\Q$path\E)$/;
            # dprint "<2.8 $active_url";
        }

        ##
        # Trying to understand if rewrite module was used or not. If not
        # - adding sitename to the end of guessed URL.
        #
        if($active_url =~ /cgi-bin/ || $active_url =~ /xao-[\w-]+\.pl/) {
            $active_url.="/$sitename";
        }
    }

    ##
    # Eating extra slashes
    #
    chop($active_url) while $active_url =~ /\/$/;
    $active_url=~s/(?<!:)\/\//\//g;

    ##
    # Figuring out secure URL
    #
    my $active_url_secure;
    if($active_url =~ /^http:(\/\/.*)$/) {
        $active_url_secure='https:' . $1;
    }
    elsif($active_url =~ /^https:(\/\/.*)$/) {
        $active_url_secure=$active_url;
        $active_url='http:' . $1;
    }
    else {
        dprint "Wrong active URL ($active_url)";
        $active_url_secure=$active_url;
    }

    ##
    # Storing active URLs
    #
    $siteconfig->clipboard->put(active_url => $active_url);
    $siteconfig->clipboard->put(active_url_secure => $active_url_secure);

    ##
    # Checking if we have base_url, assuming active_url if not.
    # Ensuring that URL does not end with '/'.
    #
    if($siteconfig->defined("base_url")) {
        my $url=$siteconfig->get('base_url');
        $url=~/^http:/i ||
            throw XAO::E::Web "expand - bad base_url ($url) for sitename=$sitename";
        my $nu=$url;
        chop($nu) while $nu =~ /\/$/;
        $siteconfig->put(base_url => $nu) if $nu ne $url;

        $url=$siteconfig->get('base_url_secure');
        if(!$url) {
            $url=$siteconfig->get('base_url');
            $url=~s/^http:/https:/i;
        }
        $nu=$url;
        chop($nu) while $nu =~ /\/$/;
        $siteconfig->put(base_url_secure => $nu);
    }
    else {
        $siteconfig->put(base_url => $active_url);
        $siteconfig->put(base_url_secure => $active_url_secure);
        dprint "No base_url for sitename '$sitename'; assuming base_url=$active_url, base_url_secure=$active_url_secure";
    }
  
    ##
    # Checking if we're running under mod_perl
    #
    my $mod_perl=($apache || $ENV{MOD_PERL}) ? 1 : 0;
    $siteconfig->clipboard->put(mod_perl => $mod_perl);

    ##
    # Putting CGI object into site configuration
    #
    $siteconfig->embedded('web')->enable_special_access;
    $siteconfig->cgi($cgi);
    $siteconfig->embedded('web')->disable_special_access;

    ##
    # Checking for directory index url without trailing slash and
    # redirecting with appended slash if this is the case.
    #
    my @path=split(/\//,$path);
    push(@path,"") unless @path;
    push(@path,"index.html") if $path =~ /\/$/;
    if($path[-1] !~ /\.\w+$/) {
        my $pd=$self->analyze([ @path,'index.html' ]);
        #use Data::Dumper; dprint "pd=",Dumper($pd);
        if($pd->{objname} ne 'Default') {
            my $newpath=$siteconfig->get('base_url') . $path . '/';
            dprint "Redirecting $path to $newpath";
            $siteconfig->header_args(
                -Location   => $newpath,
                -Status     => 302,
            );
            return "Directory index redirection\n";
        }
    }

    ##
    # Checking existence of the page.
    #
    my $pd=$args->{pagedesc} || $self->analyze(\@path);

    ##
    # Separator for the error_log :)
    #
    my @d=localtime;
    my $date=sprintf("%02u:%02u:%02u %u/%02u/%04u",$d[2],$d[1],$d[0],$d[4]+1,$d[3],$d[5]+1900);
    undef(@d);
    dprint "============ date=$date, mod_perl=$mod_perl",
                      ", path='",join('/',@path),"', translated='",$pd->{path},"'";

    ##
    # Putting path decription into the site clipboard
    #
    $siteconfig->clipboard->put(pagedesc => $pd);

    ##
    # We accumulate page content here
    #
    my $pagetext='';

    ##
    # Do we need to run any objects before executing? A good place to
    # turn on debug mode if required using Debug object.
    #
    my $autolist=$siteconfig->get('auto_before');
    if($autolist) {
        if(ref($autolist) eq 'ARRAY') {
            for(my $i=0; $i<@$autolist; $i+=2) {
                my ($objname,$objargs)=@{$autolist}[$i,$i+1];
                my $obj=XAO::Objects->new(objname => $objname);
                $pagetext.=$obj->expand($objargs);
            }
        }
        elsif(ref($autolist) eq 'HASH') {
            foreach my $objname (keys %{$autolist}) {
                my $obj=XAO::Objects->new(objname => $objname);
                $pagetext.=$obj->expand($autolist->{$objname});
            }
        }
        else {
            throw XAO::E::Web "process - don't know how to handle auto_before ($autolist)," .
                              " must be a hash or an array reference";
        }
    }

    ##
    # Preparing object arguments out of standard ones, object specific
    # once from template paths and supplied hash (in that order of
    # preference).
    #
    my $objargs={
        path => $pd->{path},
        fullpath => $pd->{fullpath},
        prefix => $pd->{prefix},
    };
    $objargs=merge_refs($objargs,$pd->{objargs},$args->{objargs});

    ##
    # Setting expiration time in the page header to immediate
    # expiration. If that's not what the page wants -- it can override
    # these.
    #
    $siteconfig->header_args(
        -expires        => 'now',
        -cache_control  => 'no-cache',
    );

    ##
    # Loading page displaying object and executing it.
    #
    my $obj=XAO::Objects->new(objname => 'Web::' . $pd->{objname});
    $pagetext.=$obj->expand($objargs);

    ##
    # Done!
    #
    return $pagetext;
}

###############################################################################

=item new (%)

Creates or loads a context for the named site. The only required
argument is 'sitename' which provides the name of the site.

Additionally `cgi' argument can point to a CGI object -- this is useful
mostly in test cases when one does not want to use execute(), but new()
comes handy.

=cut

sub new ($%) {
    my $proto=shift;
    my $args=get_args(\@_);

    ##
    # Getting site name
    #
    my $sitename=$args->{sitename} ||
        throw XAO::E::Web "new - required parameter missing (sitename)";

    ##
    # Loading or creating site configuration object.
    #
    my $siteconfig=XAO::Projects::get_project($sitename);
    if(!$siteconfig) {
        ##
        # Creating configuration.
        #
        $siteconfig=XAO::Objects->new(sitename => $sitename,
                                      objname => 'Config');

        ##
        # Always embedding at least web config and a hash
        #
        $siteconfig->embed(web => new XAO::Objects objname => 'Web::Config');
        $siteconfig->embed(hash => new XAO::SimpleHash);

        ##
        # Running initialization, this is where parameters are inserted and
        # normally FS::Config gets embedded.
        #
        $siteconfig->init();

        ##
        # Creating an entry in in-memory projects repository
        #
        XAO::Projects::create_project(name => $sitename,
                                      object => $siteconfig,
                                     );
    }

    ##
    # Cleaning up the configuration. Useful even if it was just created
    # as it will unlock tables in the database for instance.
    #
    $siteconfig->cleanup;

    ##
    # If we are given a CGI reference then putting it into the
    # configuration.
    #
    if($args->{cgi}) {
        $siteconfig->embedded('web')->enable_special_access;
        $siteconfig->cgi($args->{cgi});
        $siteconfig->embedded('web')->disable_special_access;
    }

    ##
    # Done
    #
    bless {
        sitename => $sitename,
        siteconfig => $siteconfig,
    }, ref($proto) || $proto;
}

###############################################################################

=item set_current ()

Sets the current site as the current project in the sense of XAO::Projects.

=cut

sub set_current ($) {
    my $self=shift;
    XAO::Projects::set_current_project($self->sitename);
}

###############################################################################

=item sitename ()

Returns site name.

=cut

sub sitename ($) {
    my $self=shift;
    $self->{sitename} || throw XAO::E::Web "sitename - no site name";
}

###############################################################################
1;
__END__

=back

=head1 EXPORTS

Nothing.

=head1 AUTHOR

Copyright (c) 2000-2001 XAO, Inc.

Andrew Maltsev <am@xao.com>.

=head1 SEE ALSO

Recommended reading:
L<XAO::Objects>,
L<XAO::Projects>,
L<XAO::DO::Config>.
