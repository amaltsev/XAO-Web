=head1 NAME

XAO::DO::Web::FS - XAO::Web front end object for XAO::FS

=head1 SYNOPSIS

 <%FS uri="/Categories/123/description"%>

 <%FS mode="show-list"
      base.clipboard="cached-list"
      base.database="/Foo/test/Bars"
      fields="*"
      header.path="/bits/foo-list-header"
      path="/bits/foo-list-row"
 %>

 <%FS mode="search"
      uri="/Orders"
      index_1="status"
      value_1="submitted"
      compare_1="wq"
      expression="1"
      orderby="place_time"
      fields="*"
      header.path="/bits/admin/order/list-header"
      path="/bits/admin/order/list-row"
      footer.path="/bits/admin/order/list-footer"
 %>

=head1 DESCRIPTION

Web::FS allows web site developer to directly access XAO Foundation
Server from templates without implementing specific objects.

=head1 SEARCH MODE

Accepts the following arguments:

=over

=item uri => '/Customers'

Database object path.

=item index_1..N => 'first_name|last_name'

Name of database field(s) to perform search on.
Multiple field names are separated by | (pipe character)
and treated as a logical 'or'.

=item value_1..N => 'Ann|Lonnie'

Keywords you want to search for in field(s) of corresponding index.
Multiple sets of keywords are separated by | (pipe character)
and treated as a logical 'or'.

=item compare_1..N => 'ws'

Comparison operator to be used in matching index to value.
Supported comparison operators are:
    eq  True if equal.
    
    ge  True if greater or equal.
    
    gt  True if greater.
    
    le  True if less or equal.
    
    lt  True if less.

    ne  True if not equal.
    
    gtlt True if greater than             'a' and less than 'b'

    gtle True if greater than             'a' and less than or equal to 'b'

    gelt True if greater than or equal to 'a' and less than             'b'

    gele True if greater than or equal to 'a' and less than or equal to 'b'
    
    wq  (word equal)True if contains given word completely.
    
    ws  (word start) True if contains word that starts with the given string.

    cs  (contains string) True if contains string.

=item expression => [ [ 1 and 2 ] and [ 3 or 4] ]

Logical expression, as shown above, that indicates how to
combine index/value pairs.  Numbers are used to indicate
expressions specified by corresponding index/value pairs
and brackets are used so that only one logical operator
(and, or) is contained within a pair of brackets.

=item orderby => '+last_name|-first_name'

Optional field to use for sorting output. If field name is preceded
by - (minus sign), sorting will be done in descending order for that
field, otherwise it will be done in ascending order. For consistency
and clarity, a + (plus sign) may precede a field name to expicitly
indicate sorting in ascending order.  Multiple fields to sort by are
separated by | (pipe character) and are listed in order of priority.

=item distinct => 'first_name'

This eliminates duplicate matches on a given field, just like
SQL distinct.

=item start_item => 40

Number indicating the first query match to fetch.

=item items_per_page => 20

Number indicating the maximum number of query matches to fetch.

=back

Example:

 <%FS mode="search
      uri="/Customers"
      fields="*"

      index_1="first_name|last_name"
      value_1="Linda|Mary Ann|Steven"
      compare_1="wq"

      index_2="gender"
      value_2="female"
      compare_2="wq"

      index_3="age"
      value_3="21|30"
      compare_3="gelt"

      expression="[ [ 1 and 2 ] and 3 ]"
      orderby="age|first_name+desc"
      start_item="40"
      items_per_page="20"
 %>

=head2 CONFIGURATION VALUES SUPPORTED IN SEARCH MODE

=over

=item default_search_args

The value of this configuration value is a reference to a hash.
In this hash each key is a database (object) path (name) whose
corresponding value is a reference to a hash containing the
default arguments for searching on the specified of data.
These default arguments are added unless they are specified by
input arguments.

=back

=head1 METHODS

FS provides a useful base for other displayable object that work with
XAO::FS data.

=over

=cut

###############################################################################
package XAO::DO::Web::FS;
use strict;
use XAO::Utils;
use XAO::Errors qw(XAO::DO::Web::FS);
use base XAO::Objects->load(objname => 'Web::Action');

use vars qw($VERSION);
($VERSION)=(q$Id: FS.pm,v 1.9 2002/02/04 03:43:55 am Exp $ =~ /(\d+\.\d+)/);

###############################################################################

=item get_object (%)

Returns an object retrieved from either clipboard or the database.
Accepts the following arguments:

 base.clipboard     clipboard uri
 base.database      XAO::FS object uri
 uri                XAO::FS object URI relative to `base' object
                    or root if no base.* is given

If both base.clipboard and base.database are set then first attempt is
made to get object from the clipboard and then from the database. If the
object is retrieved from the database then it is stored in clipboard.
Next call with the same arguments will get the object from clipboard.

=cut

sub get_object ($%) {
    my $self=shift;
    my $args=get_args(\@_);

    my $object;

    my $cb_base=$args->{'base.clipboard'};
    my $db_base=$args->{'base.database'};

    $object=$self->clipboard->get($cb_base) if $cb_base;
    !$object || ref($object) ||
        throw XAO::E::DO::Web::FS "get_object - garbage in clipboard at '$cb_base'";
    my $got_from_cb=$object;
    $object=$self->odb->fetch($db_base) if $db_base && !$object;

    if($cb_base) {
        $db_base || $object ||
            throw XAO::E::DO::Web::FS "get_object - no object in clipboard and" .
                                      " no base.database to retrieve it";

        ##
        # Caching object in clipboard if we have both base.clipboard and
        # base.database.
        #
        if($object && !$got_from_cb) {
            $self->clipboard->put($cb_base => $object);
        }
    }

    my $uri=$args->{uri};
    if($object && $uri && $uri !~ /^\//) {
        
        ##
        # XXX - This should be done in FS
        #
        foreach my $name (split(/\/+/,$uri)) {
            $object=$object->get($name);
        }
    }
    elsif(defined($uri) && length($uri)) {
        $object=$self->odb->fetch($uri);
    }

    $cb_base || $db_base || $uri ||
        throw XAO::E::DO::Web::FS "get_object - at least one location parameter must present";

    $object;
}

###############################################################################

=back

Here is the list of accepted 'mode' arguments and corresponding method
names. The default mode is 'show-property'.

=over

=cut

###############################################################################

sub check_mode ($%) {
    my $self=shift;
    my $args=get_args(\@_);
    my $mode=$args->{mode} || 'show-property';

    if($mode eq 'search') {
        $self->search($args);
    }
    elsif($mode eq 'delete-property') {
        $self->delete_property($args);
    }
    elsif($mode eq 'show-hash') {
        $self->show_hash($args);
    }
    elsif($mode eq 'show-list') {
        $self->show_list($args);
    }
    elsif($mode eq 'show-property') {
        $self->show_property($args);
    }
    else {
        throw XAO::E::DO::Web::FS "check_mode - unknown mode '$mode'";
    }
}

###############################################################################

=item delete-property => delete_property (%)

Deletes an object or property pointed to by `name' argument.

Example of deleting an entry from Addresses list by ID:

 <%FS
   mode="delete-property"
   base.clipboard="/IdentifyUser/customer/object"
   uri="Addresses"
   name="<%ID/f%>"
 %>

=cut

sub delete_property ($%) {
    my $self=shift;
    my $args=get_args(\@_);

    my $name=$args->{name} ||
        throw XAO::E::DO::Web::FS "delete_property - no 'name'";
    $self->odb->_check_name($name) ||
        throw XAO::E::DO::Web::FS "delete_property - bad name '$name'";

    my $object=$self->get_object($args);

    $object->delete($name);
}

###############################################################################

=item show-hash => show_hash (%)

Displays a XAO::FS hash derived object. Object location is the same as
described in get_object() method. Additional arguments are:

 fields     comma or space separated list of fields that are
            to be retrieved from each object in the list and
            passed to the template. Field names are converted
            to all uppercase when passed to template. For
            convenience '*' means to pass all
            property names (lists be passed as empty strings).

 path       path to the template that gets displayed with the
            given fields passed in all uppercase.

Example:

 <%FS mode="show-hash" uri="/Customers/c123" fields="firstname,lastname"
      path="/bits/customer-name"%>

Where /bits/customer-name should be something like:

 Customer Name: <%FIRSTNAME/h%> <%LASTNAME/h%>

=cut

sub show_hash ($%) {
    my $self=shift;
    my $args=get_args(\@_);

    my $hash=$self->get_object($args);

    my @fields;
    if($args->{fields}) {
        if($args->{fields} eq '*') {
            @fields=$hash->keys;
        }
        else {
            @fields=split(/\W+/,$args->{fields});
            shift @fields unless length($fields[0]);
        }
    }

    my %data=(
        path        => $args->{path},
        ID          => $hash->container_key,
    );
    if(@fields) {
        my %t;
        @t{@fields}=$hash->get(@fields);
        foreach my $fn (@fields) {
            $data{uc($fn)}=defined($t{$fn}) ? $t{$fn} : '';
        }
    }
    $self->object->display(\%data);
}

###############################################################################

=item show-list => show_list (%)

Displays an index for XAO::FS list. List location is the same as
described in get_object() method. Additional arguments are:

 fields             comma or space separated list of fields that are
                    to be retrieved from each object in the list and
                    passed to the template. Field names are converted
                    to all uppercase when passed to template. For
                    convenience '*' means to pass all
                    property names (lists be passed as empty strings).
 header.path        header template path
 path               path that is displayed for each element of the list
 footer.path        footer template path

Show_list() supplies 'NUMBER' argument to header and footer containing
the number of elements in the list.

At least 'ID' and 'NUMBER' are supplied to the element template.
Additional arguments depend on 'field' content.

To help in displaying selection lists show_list() accepts 'current'
argument. If ID of a list element is the same as the value of 'current'
it will pass true value in IS_CURRENT parameter to the element
template. 'Current' argument will be passed through as CURRENT parameter
as well.

=cut

sub show_list ($%) {
    my $self=shift;
    my $args=get_args(\@_);

    my $list=$self->get_object($args);
    $list->objname eq 'FS::List' ||
        throw XAO::E::DO::Web::FS "show_list - not a list";

    my $current=$args->{current} || '';

    my @keys=$list->keys;
    my @fields;
    if($args->{fields}) {
        if($args->{fields} eq '*') {
            @fields=$list->get_new->keys;
        }
        else {
            @fields=split(/\W+/,$args->{fields});
            shift @fields unless length($fields[0]);
        }
    }

    my $page=$self->object;
    $page->display(merge_refs($args,{
        path        => $args->{'header.path'},
        template    => $args->{'header.template'},
        NUMBER      => scalar(@keys),
        CURRENT     => $current,
    })) if $args->{'header.path'} || $args->{'header.template'};

    foreach my $id (@keys) {
        my %data=(
            path        => $args->{path},
            ID          => $id,
            NUMBER      => scalar(@keys),
            CURRENT     => $current,
            IS_CURRENT  => $current && $current eq $id ? 1 : 0,
        );
        if(@fields) {
            my %t;
            @t{@fields}=$list->get($id)->get(@fields);
            foreach my $fn (@fields) {
                $data{uc($fn)}=defined($t{$fn}) ? $t{$fn} : '';
            }
        }
        $page->display(merge_refs($args,\%data));
    }

    $page->display(merge_refs($args,{
        path        => $args->{'footer.path'},
        template    => $args->{'footer.template'},
        NUMBER      => scalar(@keys),
        CURRENT     => $current,
    })) if $args->{'footer.path'} || $args->{'footer.template'};
}

###############################################################################

=item show-property => show_property (%)

Displays a property of the given object. Does not use any templates,
just displays the property using textout(). Example:

 <%FS uri="/project"%>

=cut

sub show_property ($%) {
    my $self=shift;
    my $args=get_args(\@_);

    my $value=$self->get_object($args);
    $value=$args->{default} unless defined $value;
    $value='' unless defined $value;

    $self->textout($value);
}

###############################################################################
sub search ($;%) {

    my $self=shift;

    my $args = get_args(\@_);
    my $rh_conf = $self->siteconfig;

    if ($args->{debug}) {
        &XAO::Utils::set_debug(1);
        #dprint "\n\n*** XAO::DO::Web::FS::search DEBUG MODE ***\n\n";
        #dprint '*** Original Arguments:';
        #foreach (sort keys %$args) { dprint " arg> $_: $args->{$_}\n"; }
        #dprint '';
    }

    #############
    #
    # PROCESS INPUT ARGUMENTS
    #
    #############

    #$args->{uri} = $args->{db_list} unless $args->{uri};

    #
    # Add default arguments as specified in configuration
    # unless there are input arguments to override them.
    #
    my $rh_defaults     = $rh_conf->{default_search_args};
    my $rh_default_args = $rh_defaults->{$args->{uri}};
    if (ref($rh_default_args) eq 'HASH') {
        foreach (keys %$rh_default_args) {
            next if defined $args->{$_};
            $args->{$_}  = $rh_default_args->{$_};
            #dprint "*** Add Default Argument: $_ = $rh_default_args->{$_}";
        }
    }

    if ($args->{debug}) {
        #dprint '*** Processed Parameters:';
        #foreach (sort keys %$args) { dprint " arg> $_: $args->{$_}"; }
        #dprint '';
    }

    #############
    #
    # DO SEARCH
    #
    #############

    my $list = $self->get_object($args);
    $list->objname eq 'FS::List' || throw XAO::E::DO::Web::FS "show_list - not a list";
    #dprint "*** LIST: $list";

    #dprint "*** Go Search...\n\n";

    my $ra_query   = $self->_create_query($args, $rh_conf);
    my $ra_all_ids = $list->search(@$ra_query);
    my $ra_ids     = $ra_all_ids;
    my $total      = $#{$ra_all_ids}+1;
    my $items_per_page = $args->{items_per_page} || 0;
    my $limit_reached  = $items_per_page && $total>$items_per_page;
    if ($args->{start_item} || $items_per_page) {
        my $start_item = int($args->{start_item}) > 1 ? $args->{start_item}-1 : 0;
        my $stop_item  = $total-1;
        if (int($items_per_page)) {
            my $max    = $items_per_page + $start_item;
            $stop_item = $max unless $max > $stop_item;
        }
        $ra_ids = [ @{$ra_all_ids}[$start_item..$stop_item] ];
    }

    #############
    #
    # DISPLAY ITEMS
    #
    #############

    my $page     = $self->object(objname => 'Page');
    my $basetype = '';

    #
    # Display header
    #

    my $header = '';
    if    ($args->{'header.template'}) {
        $basetype = 'template';
        $header   = $args->{'header.template'};
    }
    elsif ($args->{'header.path'}) {
        $basetype = 'path';
        $header   = $args->{'header.path'};
    }
    $page->display(
        $basetype      => $header,
        ITEMS_PER_PAGE => $items_per_page,
        LIMIT_REACHED  => $limit_reached,
        START_ITEM     => $args->{start_item},
        TOTAL_ITEMS    => $total,
    ) if $header;

    #
    # Display items
    #

    my @fields;
    if($args->{fields}) {
        if($args->{fields} eq '*') {
            @fields=$list->get_new->keys;
        }
        else {
            @fields=split(/\W+/,$args->{fields});
            shift @fields unless length($fields[0]);
        }
    }

    my $count = 1;
    $basetype = $args->{template} ? 'template' : 'path';
    #dprint "\n*** Search Results *" . scalar(@$ra_ids) . " matches*";
    #dprint "    (use $basetype: $args->{$basetype})" if $basetype eq 'path';
    foreach my $id (@$ra_ids) {
        #dprint "    $count> show $id";
        my %pass = (
            $basetype => $args->{$basetype},
            ID        => $id,
            COUNT     => $count,
        );
        if ($args->{fields}) {
            my $item = $list->get($id);
            foreach (@fields) {
                my $uckey = uc($_);
                $pass{$uckey} = $item->get($_) unless $pass{$uckey};
                $pass{$uckey} = '' unless defined $pass{$uckey};
            }
        }
        $page->display(\%pass);
        $count++;
    }

    #
    # Display footer
    #

    my $footer = '';
    if ($args->{'footer.template'}) {
        $basetype = 'template';
        $footer   = $args->{'footer.template'};
    }
    elsif ($args->{'footer.path'}) {
        $basetype = 'path';
        $footer   = $args->{'footer.path'};
    }
    $page->display(
        $basetype      => $footer,
        ITEMS_PER_PAGE => $items_per_page,
        LIMIT_REACHED  => $limit_reached,
        START_ITEM     => $args->{start_item},
        TOTAL_ITEMS    => $total,
    ) if $footer;
}   
###############################################################################
sub _create_query {

    my $self=shift;

    my ($args, $rh_conf) = @_;

    #dprint "*** _create_query START";

    my $i=1;
    my @expr_ra;
    while ($args->{"index_$i"}) {

        my $index      = $args->{"index_$i"};
        my $value      = $args->{"value_$i"};
        my $compare_op = $args->{"compare_$i"};

        #dprint "\n  ** $i **";
        #dprint "  ## index:            $index";
        #dprint "  ## value:            $value";
        #dprint "  ## compare operator: $compare_op";

        #
        # Create ref to array w/ object expression for index/value pair
        #
        my @indexes = split(/\|/, $index);
        if ($compare_op eq 'wq' || $compare_op eq 'ws') {
            if ($value =~ /\|/) {
                my @value_list = split(/\|/, $value);
                $value         = \@value_list;
            }
            $expr_ra[$i]   = $self->_create_expression(\@indexes, $compare_op, $value);
        }
        elsif ($compare_op =~ /^(g[et])(l[et])$/) {
            my ($lo, $hi) = split(/\|/, $value);
            foreach (@indexes) {
                my $ra_temp  = [ [$_, $1, $lo] and [$_, $2, $hi] ];
                $expr_ra[$i] = ref($expr_ra[$i]) eq 'ARRAY'
                             ? [$expr_ra[$i], 'or', $ra_temp] : $ra_temp;
            }
        }
        else {
            $expr_ra[$i] = $self->_create_expression(\@indexes, $compare_op, $value);
        }
        $i++;
    }

    #
    # At this point we have a bunch of expressions (1..N) in @expr_ra
    # that need to be put together as specified in the 'expression'
    # argument.  If the 'expression' argument does not match the
    # the format (described in documentation above) then the only
    # expression used will be the first one provided.
    #
    #dprint "\n    ## EXPRESSION: $args->{expression}";
    my $regex = '\[\s*(\d+)\s+(\w+)\s+(\d+)\s*\]';
    if ($args->{expression} && $args->{expression} =~ /$regex/) {
        $args->{expression} =~ s{$regex} {
                                  $self->_interpret_expression(
                                      \@expr_ra,
                                      $args->{expression},
                                      \$i, $1, $2, $3,
                                      $regex,
                                  );
                                }eg;
        $i--;
        ###########################################################################
        sub _interpret_expression {
            my $self = shift;
            my ($ra_expr_ra, $expression, $r_i, $i1, $i2, $i3, $regex) = @_;
            $ra_expr_ra->[$$r_i] = [ $ra_expr_ra->[$i1], $i2, $ra_expr_ra->[$i3] ];
            #dprint "  ## $$r_i = [ $i1 $i2 $i3 ]";
            $expression =~ s/\[\s*$i1\s+$i2\s+$i3\s*\]/$$r_i/;
            #dprint "  ## new expr = $expression";
            ${$r_i}++;
            $self->_interpret_expression($ra_expr_ra,
                                         $expression,
                                         $r_i, $1, $2, $3,
                                         $regex) if $expression =~ /$regex/;
        }
        ###########################################################################
    }
    else {
        $expr_ra[$i] = $expr_ra[1];
    }

    #
    # Add any extra search options
    #
    if ($args->{orderby} || $args->{distict}) {
        my $rh_options = {};

        #
        # Sort specifications
        #
        if ($args->{orderby}) {
            my $ra_orderby = [];
            foreach (split(/\|/, $args->{orderby})) {
                my $direction = /^-/ ? 'descend' : 'ascend';
                s/\W//g;
                push @$ra_orderby, ($direction => $_);
            }
            $rh_options->{orderby} = $ra_orderby;
        }

        #
        # Distinct searching
        #
        $rh_options->{distinct} = $args->{distict} if $args->{distict};

        push @{$expr_ra[$i]}, $rh_options;
    }

    #dprint "\n    ## QUERY START ##"
    #     . $self->_searcharray2str($expr_ra[$i], '')
    #     . "\n    ## QUERY STOP  ##\n"
    #     . "\n*** _create_query STOP\n\n";

    $expr_ra[$i];
}
###############################################################################
sub _create_expression {
    my $self=shift;
    my ($ra_indexes, $compare_op, $value) = @_;
    my $ra_expr;
    foreach my $index (@$ra_indexes) {
        my $ra_temp = [$index, $compare_op, $value];
        $ra_expr    = ref($ra_expr) eq 'ARRAY' ? [$ra_expr, 'or', $ra_temp] : $ra_temp;
    }
    $ra_expr;
}
###############################################################################
sub _searcharray2str() {
    my $self=shift;
    my ($ra, $indent) = @_;
    my $indent_new = $indent . ' ';
    my $i=0;
    my $innermost=1;
    my $str= "\n" . $indent . "[";
    foreach (@$ra) {
        $str .= ' ';
        if    (ref($_) eq 'ARRAY') {
            $str .=  $self->_searcharray2str($_, $indent_new);
        }
        elsif (ref($_) eq 'HASH') {
            $str .= '{ ';
            foreach my $key (keys %$_) { $str .= qq!'$key' => '$_->{$key}', !; }
            $str .= ' },';
        }
        else {
            if (($i==1) && (/and/ or /or/)) {
                $str      .= "\n$indent " if ($i==1) && (/and/ or /or/);
                $innermost = 0;
            }
            $str .= "'$_',";
        }
        $i++;
    }
    $str .= ' ';
    $str .= "\n$indent" unless $innermost;
    $str .= ']';
    $str .= ',' if $indent;
    $str;
}
###############################################################################
1;
__END__

=head1 METHODS

No publicly available methods except overriden display().

=head1 EXPORTS

Nothing.

=head1 AUTHOR

Copyright (c) 2000-2002 XAO, Inc.

Andrew Maltsev <am@xao.com>, Marcos Alves <alves@xao.com>.

=head1 SEE ALSO

Recommended reading:
L<XAO::Web>,
L<XAO::DO::Web::Page>.
