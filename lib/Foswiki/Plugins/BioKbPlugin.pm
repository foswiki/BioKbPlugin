# See bottom of file for license and copyright information
#
# See Plugin topic for history and plugin information

package Foswiki::Plugins::BioKbPlugin;

# Always use strict to enforce variable scoping
use strict;
use warnings;
use Scalar::Util qw(tainted);
require Foswiki::Func;       # The plugins API
require Foswiki::Plugins;    # For the API version

use vars
  qw( $VERSION $RELEASE $SHORTDESCRIPTION $debug $pluginName $NO_PREFS_IN_TOPIC );
$VERSION = '$Rev: 20091103 (2009-11-03) $';
$RELEASE = '3 Nov 2009';
$SHORTDESCRIPTION =
'Set of functions to create and populate a biological knowledgebase from online resources, ready for comment, annotation and discussion by a community.';
$NO_PREFS_IN_TOPIC = 1;
$pluginName        = 'BioKbPlugin';

sub initPlugin {
    my ( $topic, $web, $user, $installWeb ) = @_;

    # check for Plugins.pm versions
    if ( $Foswiki::Plugins::VERSION < 1.026 ) {
        Foswiki::Func::writeWarning(
            "Version mismatch between $pluginName and Plugins.pm");
        return 0;
    }

    $debug = $Foswiki::cfg{Plugins}{BioKbPlugin}{Debug} || 0;

    Foswiki::Func::registerTagHandler( 'ADMIN',         \&_ADMIN );
    Foswiki::Func::registerTagHandler( 'MOST_VIEWED',   \&_MOST_VIEWED );
    Foswiki::Func::registerTagHandler( 'REFRESH_LINKS', \&_REFRESH_LINKS );
    Foswiki::Func::registerTagHandler( 'REMOVE_TOPIC',  \&_REMOVE_TOPIC );
    Foswiki::Func::registerTagHandler( 'TOPICTYPES',    \&_TOPICTYPES );
    Foswiki::Func::registerTagHandler( 'SEARCHBYTYPE',  \&_SEARCHBYTYPE );
    Foswiki::Func::registerTagHandler( 'PUBMEDSEARCH',  \&_PUBMEDSEARCH );
    Foswiki::Func::registerTagHandler( 'PUBMEDSEARCH_FORM',
        \&_PUBMEDSEARCH_FORM );

    Foswiki::Func::registerTagHandler( 'MOLBIOL_FORM', \&_MOLBIOL_FORM );
    Foswiki::Func::registerTagHandler( 'MOLBIOL_SEARCH_FORM',
        \&_MOLBIOL_SEARCH_FORM );
    Foswiki::Func::registerTagHandler( 'FORM_EDIT_TOPIC_DATA',
        \&_FORM_EDIT_TOPIC_DATA );
    Foswiki::Func::registerTagHandler( 'FORM_EDIT_URLS', \&_FORM_EDIT_URLS );

    require Foswiki::Plugins::BioKbPlugin::BioKb;
    require Foswiki::Plugins::BioKbPlugin::Literature;
    require Foswiki::Plugins::BioKbPlugin::Disease;
    require Foswiki::Plugins::BioKbPlugin::MolecularBiology;

    # Plugin correctly initialized
    return 1;
}

=pod

Wrapper function for topic removal- deletes data topics corrects dictionary, fixes links etc

=cut

sub _REMOVE_TOPIC {

    my ( $session, $params, $topic, $web ) = @_;

    my $query      = Foswiki::Func::getCgiQuery();
    my $buttontext = "Delete !$topic";

    if ( defined $query->param("delete") ) {
        Foswiki::Plugins::BioKbPlugin::BioKb::remove_topic( $web, $topic );
        throw Foswiki::OopsException(
            'generic',
            params => [
                $query->param("delete") . " deleted and moved to trash",
                "", "", ""
            ]
        );
    }

    else {

        my $wikiname = Foswiki::Func::getWikiName();
        if ( Foswiki::Func::isAnAdmin($wikiname) == 1
            && $topic !~ /(^Browse|Admin|Stats|About|Help|Contact)/ )
        {

            my $output =
                "<span class='delete'>"
              . CGI::start_form( -method => "GET" )
              . CGI::hidden( -name => "delete", -default => $topic )
              . CGI::submit(
                -name  => 'edit',
                -value => $buttontext,
                -class => "foswikiSubmit"
              )
              . CGI::end_form()
              . "</span>";

            $output =
              Foswiki::Func::expandCommonVariables( $output, $topic, $web );

            return $output;
        }
    }

    return "";
}

=pod

Make a form that will search the BioKb web, allowing user to specify desired topic types (defined by PREFERENCE variables embedded in the content topics). When the form is submitted (and 'searchterm' defined), the summary function 'MOST_VIEWED' will be employed to display search results.  

=cut

sub _SEARCHBYTYPE {

    my ( $session, $params, $topic, $web ) = @_;

    my $query = Foswiki::Func::getCgiQuery();

    my $output;
    if ( defined $query->param("searchterm") ) {
        $output = "<h1>Results by type for search term \""
          . $query->param("searchterm") . "\"";
        $output .=
          " in topic types \"" . ( join ",", $query->param("type") ) . "\""
          if ( defined $query->param("type") );
        $output .= ":</h1>%MOST_VIEWED{browse=\"1\"}%";
    }
    else {

        my $form = CGI::start_form();

        my %admin_data = %{
            Foswiki::Plugins::BioKbPlugin::BioKb::read_topic_structure_admin(
                $web)
          };
        my @topic_types = keys %admin_data;
        $form .= "| <span class='inlineheader'>Search term:</span> | "
          . CGI::textfield(
            -name      => "searchterm",
            -size      => 50,
            -maxlength => 50
          ) . " |\n";
        $form .=
          "| <span class='inlineheader'>Restrict to topic type(s):</span> | "
          . CGI::checkbox_group(
            -name    => 'type',
            -values  => [@topic_types],
            -default => ["any"]
          ) . " |\n";

        my @authors = _find_authors($web);

        my $popup = CGI::popup_menu(
            -name   => 'author',
            -values => [ "any", @authors ],
        );
        $popup =~ s/\n//g;

        $form .= "| <span class='inlineheader'>Author:</span> | $popup |\n\n";
        $form .= "| "
          . CGI::submit(
            -name  => 'submit',
            -value => "Submit",
            -class => "foswikiSubmit"
          ) . " |\n";
        $form .= CGI::end_form();

        $output = "<h1>Search topics by type:</h1>" . $form;
    }

    $output = Foswiki::Func::expandCommonVariables( $output, $topic, $web );

    return $output;
}

=pod

Find a lit of authors in a given web.

=cut

sub _find_authors {
    my $web    = shift;
    my $result = Foswiki::Func::searchInWebContent(
        "author=", $web,
        [ Foswiki::Func::getTopicList($web) ],
        { casesensitive => 0, files_without_match => 0 }
    );

    my %authors;
    foreach my $topic ( keys %$result ) {
        foreach my $matching_line ( @{ $result->{$topic} } ) {
            my ($author) = $matching_line =~ /author=\"([^\"]+)\"/;
            $authors{$author} = 1;
        }
    }
    return keys %authors;
}

=pod

Command which produces a summary of content in a BioKb web. If the 'browse' parameter is specified, then a summary of all content (as opposed to admins, stats etc) topics is displayed in a spaced out manner with header images etc. This is what produces the content of the 'BrowseSite' topic, and the output of SEARCHBYTYPE (with the proviso that the 'searchterm' CGI parameter limits the displayed topics to those matching the term). If the 'browse' parameter is not specified, a more concise list of recently edited topics is displayed. 

=cut

sub _MOST_VIEWED {
    my ( $session, $params, $topic, $web ) = @_;

    my $query = Foswiki::Func::getCgiQuery();
    my %admin_data =
      %{ Foswiki::Plugins::BioKbPlugin::BioKb::read_topic_structure_admin($web)
      };
    my @alltopics = Foswiki::Func::getTopicList($web);

    my $search;
    my %topics;

    my @types;
    if ( defined $query->param("type") ) {
        @types = $query->param("type");
        my $result = Foswiki::Func::searchInWebContent(
            "TOPIC_TYPE\" type=\"Set\" value=\"("
              . ( join "|", @types ) . ")\"",
            $web,
            [@alltopics],
            { type => "regex", casesensitive => 0, files_without_match => 0 }
        );
        @alltopics = keys %$result;
        foreach my $topic ( keys %$result ) {
            push @alltopics, "Data" . $topic;
        }
    }
    else {
        @types = keys %admin_data;
    }

    if ( defined $query->param("searchterm") ) {
        $search = 1;
        my $result = Foswiki::Func::searchInWebContent(
            "[^A-Za-z0-9]" . $query->param("searchterm") . "[^A-Za-z0-9]",
            $web,
            [@alltopics],
            { type => "regex", casesensitive => 0, files_without_match => 0 }
        );
        my @topics = keys %$result;
        return
            "<span class='error'>No results for \""
          . $query->param("searchterm")
          . "\"</span>"
          if ( scalar @topics == 0 );
        s/^Data// for (@topics);
        %topics = map { $_, 1 } @topics;
    }

    # Examine the statistics for the web and extract the viewing frequencies

    my ( $meta, $text ) = Foswiki::Func::readTopic( $web, "WebStatistics" );
    my ($views) = $text =~
/.*?\-\-statTopContributors\-\-\>[^\|]+\|[^\|]+\|[^\|]+\|[^\|]+\|[^\|]+\|[^\|]+(\|[^\|]+\|[^\|]+\|).*/;
    my @matches;
    if ( defined $views ) {
        @matches = $views =~ /(\d+\s+\[\[\w+)/g;
    }
    my %popular;
    foreach my $match (@matches) {
        my ( $viewno, $topic ) = $match =~ /(\d+)\s+\[\[(\w+)/;
        $popular{$topic} = $viewno
          if ( !defined $search || defined $topics{$topic} );
    }

    # Store topic and type popularity

    my $result = Foswiki::Func::searchInWebContent(
        "TOPIC_TYPE\" type=\"Set\" value=\"(" . ( join "|", @types ) . ")\"",
        $web,
        [ keys %popular ],
        { type => "regex", casesensitive => 0, files_without_match => 0 }
    );

    my %section_popular;
    my %section_count;

    foreach my $topic ( sort { $popular{$b} <=> $popular{$a} } keys %popular ) {
        next if ( $topic =~ "Stats" );
        foreach my $matching_line ( @{ $result->{$topic} } ) {
            my ($type) =
              $matching_line =~ /TOPIC_TYPE\" type=\"Set\" value=\"([^\"]+)\"/;
            $section_popular{$type}{$topic} = $popular{$topic};
            $section_count{$type} += $popular{$topic};
        }
    }

# Extract counts for each type of topic over all content topics of the wiki - or over matching topics if a search term is provided by a form.

    my @topics;
    if ( defined $search ) {
        @topics = keys %topics;
    }
    else {
        @topics = @alltopics;
    }

    $result =
      Foswiki::Func::searchInWebContent( "TOPIC_TYPE\" type=\"Set\" value=\"",
        $web, [@topics], { casesensitive => 0, files_without_match => 0 } );

    my %count;

    foreach my $topic ( sort keys %$result ) {
        next if ( $topic =~ "Stats" );
        foreach my $matching_line ( @{ $result->{$topic} } ) {
            my ($type) =
              $matching_line =~ /TOPIC_TYPE\" type=\"Set\" value=\"([^\"]+)\"/;
            $count{$type}{$topic} = 1;
        }
    }

    # Write out results

    if ( defined $params->{"browse"} ) {
        return _print_browse( $web, \%section_count, \%section_popular,
            \%admin_data, \%count );
    }
    else {
        return _print_most_viewed( $web, \%section_count, \%section_popular,
            \%admin_data, \%count );

    }
}

=pod

Output of MOST_VIEWED when 'browse' is not specified (see above)

=cut

sub _print_most_viewed {
    my ( $web, $sc, $sp, $ad, $c ) = @_;
    my %section_count   = %{$sc};
    my %section_popular = %{$sp};
    my %admin_data      = %{$ad};
    my %count           = %{$c};

    my $output = "";

    $output .= "<h2>Most viewed: </h2><p>";

    my @sections =
      sort { $section_count{$b} <=> $section_count{$a} } keys %section_count;

    for ( my $i = 0 ; $i < scalar @sections ; $i++ ) {
        my $section = $sections[$i];
        my $sectionclass;
        ( $sectionclass = $section ) =~ s/\s/_/g;

        $output .=
            "<span class='inlineheader "
          . lc $sectionclass . "'>"
          . $section
          . "s:</span>&nbsp;&nbsp;&nbsp;&nbsp;";
        my @topics = sort {
            $section_popular{$section}{$b} <=> $section_popular{$section}{$a}
        } keys %{ $section_popular{$section} };

        my $print = 0;
        foreach my $topic (@topics) {
            last if ( $print == 10 );
            my $alias = $topic;
            if ( length $topic > 10 ) {
                $alias = substr( $topic, 0, 10 ) . "..";
            }
            $output .= "[[" . $topic . "][$alias]] ";
            $output .= "(" . $section_popular{$section}{$topic} . ") ";
            $print++;
        }
        $output .=
          "... (of " . ( scalar keys %{ $count{$section} } ) . " total)<p>";
    }
    return $output;
}

=pod

Output of MOST_VIEWED when 'browse' is specified (see above)

=cut

sub _print_browse {

    my ( $web, $sc, $sp, $ad, $c ) = @_;
    my %section_count   = %{$sc};
    my %section_popular = %{$sp};
    my %admin_data      = %{$ad};
    my %count           = %{$c};

    my $output = "";
    $output .= "<div id='browse'>";

    my @sections =
      sort { $section_count{$b} <=> $section_count{$a} } keys %section_count;
    foreach my $section ( keys %count ) {
        push @sections, $section if ( !defined $section_count{$section} );
    }

    for ( my $i = 0 ; $i < scalar @sections ; $i++ ) {
        my $section = $sections[$i];

        $output .= "<div class='typeblock ";
        $output .= " rightblock" if ( $i % 2 != 0 );
        $output .= "'>";

        my @topics = sort {
            $section_popular{$section}{$b} <=> $section_popular{$section}{$a}
        } keys %{ $section_popular{$section} };
        foreach my $topic ( keys %{ $count{$section} } ) {
            push @topics, $topic
              if ( !defined $section_popular{$section}{$topic} );
        }

        my $sectionclass;
        ( $sectionclass = $section ) =~ s/\s/_/g;

        my $descriptor =
            "<span class='inlineheader "
          . lc $sectionclass . "'>"
          . $section
          . "s: </span>";
        if ( defined $admin_data{$section}{"descriptor"} ) {
            $descriptor .= "<P>" . $admin_data{$section}{"descriptor"};
        }
        $output .= "<div class='typedescriptor'>" . $descriptor . "</div>";
        if ( defined $admin_data{$section}{"image"} ) {
            $output .=
                "<div class='typeimage'><img src=\""
              . Foswiki::Func::getPubUrlPath()
              . "/$web/AdminFormFields/"
              . $admin_data{$section}{"image"}
              . "\"></div>";
        }

        my $sep = "";
        foreach my $topic (@topics) {
            $output .=
                $sep . "[[" 
              . $topic . "]["
              . Foswiki::Func::spaceOutWikiWord($topic) . "]] ";
            $sep = " &bull; ";
        }
        $output .= "<p>";
        $output .= "</div> ";
    }
    $output .= "</div>";

    return $output;

}

=pod

Any page using this hook will be scanned for possible linking after every edit (due to hidden field 'edited' in edit.quickmenumod.tmpl). Users can be allowed to force this by specifying 'button' and an argument to the function. By default only the current topic will be scanned for linking, but specifying 'all' (either as an argument to the function, or as a CGI parameter) will cause a scan of all content topics.

=cut

sub _REFRESH_LINKS {
    my ( $session, $params, $topic, $web ) = @_;

    my $query      = Foswiki::Func::getCgiQuery();
    my $buttontext = "Refresh links";

    my $edited = Foswiki::Func::getSessionValue("edited");

    if ( defined $query->param("refresh")
        || ( defined $edited && $edited == 1 ) )
    {
        my $target;
        if ( $params->{"all"} eq "" && $query->param("all") eq "" ) {
            $target = $topic;
        }
        else {

        }
        Foswiki::Plugins::BioKbPlugin::BioKb::_add_links_to_all( $session, $web,
            undef, $target );
        Foswiki::Func::clearSessionValue("edited");
    }

    if ( defined $params->{"button"} ) {
        if ( defined $params->{"all"} ) {
            $buttontext =
              "Refresh links throughout !$web with reference to the dictionary";
        }

        my $output =
            "<span class='refresh'>"
          . CGI::start_form( -method => "GET" )
          . CGI::hidden( -name => "refresh", -default => 1 )
          . CGI::submit(
            -name  => 'edit',
            -value => $buttontext,
            -class => "foswikiSubmit"
          )
          . CGI::end_form()
          . "</span>";

        $output = Foswiki::Func::expandCommonVariables( $output, $topic, $web );

        return $output;
    }

    return "";
}

=pod

Provide the 'Edit Structured Data' button, which basically points to the 'CreateForm' topic, with an embedded MOLBIOL_FORM, which causes topic to be parsed and fill the form's fields. Specify overwrite by default.

=cut

sub _FORM_EDIT_TOPIC_DATA {
    my ( $session, $params, $topic, $web ) = @_;

    my $edit_topic;
    $edit_topic = $topic if ( !defined $params->{"edit_topic"} );
    my $type   = $params->{"type"};
    my $output = "";

    my $wikiname = Foswiki::Func::getWikiName();
    if (
        Foswiki::Func::checkAccessPermission( "CHANGE", $wikiname, undef,
            $edit_topic, $web ) == 1
      )
    {
        $output = CGI::start_form(
            -method => "GET",
            -action => Foswiki::Func::getViewUrl( $web, "CreateForm" )
          )
          . CGI::hidden( -name => "edit_topic", -default => $edit_topic )
          . CGI::hidden( -name => "type",       -default => $type )
          . CGI::hidden( -name => "overwrite",  -default => 1 )
          . CGI::submit(
            -name  => 'edit',
            -value => "Edit Structured Data",
            -class => "foswikiSubmit"
          )
          . "   "
          . CGI::submit(
            -name  => 'mesh',
            -value => "Add !MeSH data",
            -class => "foswikiSubmit"
          )
          . CGI::end_form()
          . "<br />";

        $output = Foswiki::Func::expandCommonVariables( $output, $topic, $web );
    }

    return $output;
}

=pod

Provide a form to edit the BioKb web's root URLs checks the formatting a bit, and then scans content to replace existing instances and maintain consistency. 

=cut

sub _FORM_EDIT_URLS {
    my ( $session, $params, $topic, $web ) = @_;

    my $query = Foswiki::Func::getCgiQuery();

    my @admin =
      Foswiki::Plugins::BioKbPlugin::BioKb::read_admin( $web, "DatabaseURLs" );
    my %prefixes = %{ $admin[0] };
    my %replacements;

    my $form =
      CGI::start_form() . "| *Database* | *Root URL* | *New value* |\n";
    foreach my $db ( sort keys %prefixes ) {
        $form .=
            "| $db | " 
          . $prefixes{$db} . " | "
          . CGI::textfield(
            -name      => $db . "_replacement",
            -size      => 30,
            -maxlength => 50,
            -default   => ""
          ) . " |\n";
        if ( defined $query->param( $db . "_replacement" )
            && $query->param( $db . "_replacement" ) =~ /\w/ )
        {

            # Check validity of the URL

            if ( $query->param( $db . "_replacement" ) !~
                /^((http:\/\/|https:\/\/)?\w+\.\w+(\.\w{2,4})?\.\w{2,4}).+$/ )
            {
                throw Foswiki::OopsException(
                    'generic',
                    params => [
                        "Invalid URL entered. Please try again.\n", "", "", ""
                    ]
                );
            }

            # Check that a wildcard for the DB entry has been included

            if ( $query->param( $db . "_replacement" ) !~ /VAL/ ) {
                throw Foswiki::OopsException(
                    'generic',
                    params => [
"Root URL supplied without a 'VAL' wildcard to indicate where to put the ID. Please try again.\n",
                        "",
                        "",
                        ""
                    ]
                );
            }
            $replacements{$db} = $query->param( $db . "_replacement" );
        }
    }
    $form .= "<p>"
      . CGI::submit( -class => "foswikiSubmit", -value => "Submit" )
      . CGI::end_form();

    # Search for the string to be replaced in all topics

    my $output;

    if ( scalar keys %replacements > 0 ) {

        my @topiclist = Foswiki::Func::getTopicList($web);
        my %options   = (
            "type"          => "regex",
            "casesensitive" => 0,
            "files_without_match" =>
              1    # Quick search- doesn't return line matches
        );

        my $alldone = 0;
        my %changed_topics;

        foreach my $db ( keys %replacements ) {
            my $newroot = $replacements{$db};
            next if ( $newroot eq $prefixes{$db} );

            my $pattern;
            ( $pattern = $prefixes{$db} ) =~ s/(\W)/\\$1/g;
            $pattern =~ s/VAL/\(\\w+\)/g;

            my $result =
              Foswiki::Func::searchInWebContent( $pattern, $web, \@topiclist,
                \%options );

            foreach my $topic ( keys %$result, "AdminDatabaseURLs" ) {
                $changed_topics{$topic} = 1;
                next
                  if ( ( $topic =~ /^Admin/ && $topic ne "AdminDatabaseURLs" )
                    || $topic =~ /^Web/ );

                # Get topic text

                my ( $meta, $text ) = Foswiki::Func::readTopic( $web, $topic );

                # Make replacements in text

                while ( $text =~ /($pattern)/g ) {
                    my ( $match, $id ) = ( $1, $2 );
                    my $replacement;
                    ( $replacement = $newroot ) =~ s/VAL/$id/;
                    $match =~ s/(\W)/\\$1/g;

                    my $newtext;
                    my $done = ( $newtext = $text ) =~ s/$match/$replacement/;
                    $alldone += $done;
                    $text = $newtext;
                }

                # Save topic

                my $wikiname = Foswiki::Func::getWikiName();
                if (
                    Foswiki::Func::checkAccessPermission( "CHANGE", $wikiname,
                        undef, $topic, $web ) != 1
                  )
                {
                    die "Access dendied for $wikiname\n";
                    throw Foswiki::OopsException(
                        'accessdenied',
                        def    => 'topic_access',
                        web    => $web,
                        topic  => $topic,
                        params => [ "CHANGE", $session->security->getReason() ]
                    );
                }

                Foswiki::Func::saveTopic( $web, $topic, $meta, $text );
            }
        }
        $output =
            "<h4>Fixed AdminDatabaseURLs and corrected "
          . ( $alldone - 1 )
          . " URLs in "
          . ( ( scalar keys %changed_topics ) - 1 )
          . " topics</h4><br />\n";
    }
    else {
        $output =
"Use this page to make changes to the root URLS used to reference external databases. Use 'VAL' as the wildcard to indicate where in the URL to put the appropriate IDs. <b>Warning: making this change will alter every matching URL in the database, as well as new ones.</b><p>"
          . $form;
    }

    return $output;
}

=pod

Where user has appropriate permissions, place admin links

=cut

sub _ADMIN {
    my ( $session, $params, $topic, $web ) = @_;

    my $format = $params->{format};
    my $result = '';

    my %admin_topics = (
        "FormFields"    => "Topic structure",
        "DatabaseURLs"  => "Database URLs",
        "ContentLimits" => "Retrieval parameters",
        "Dictionary"    => "Dictionary",
        "Seed"          => "Add seed data"
    );

    my $i = 0;
    foreach my $type ( keys %admin_topics ) {
        my $item = $format;
        my $name = $admin_topics{$type};
        $item =~ s/\$admintopic/Admin$type/g;
        $item =~ s/\$adminname/$name/g;
        $result .= "\n" if $i;
        $result .= $item;
        $i++;
    }
    return $result;
}

=pod

Produce a list of topics with format specified by a format paramter as per VarSearch et al. This is primarily for use in a BioKb web's 'QuickMenuBar'

=cut

sub _TOPICTYPES {
    my ( $session, $params, $topic, $web ) = @_;
    my %admin_data =
      %{ Foswiki::Plugins::BioKbPlugin::BioKb::read_topic_structure_admin($web)
      };

    my $format = $params->{format};

    my $result = '';
    my $i      = 0;
    foreach my $type ( keys %admin_data ) {
        my $item = $format;
        $item =~ s/\$topictype/$type/g;
        $result .= "\n" if $i;
        $result .= $item;
        $i++;
    }
    return $result;
}

=pod

This is the function embedded in a BioKb web's 'AdminSeed', and right now simply sends a KEGG pathway ID to the functions necessary to retrieve the data. Functionality needs expansion.

=cut

sub _MOLBIOL_SEARCH_FORM {
    my ( $session, $params, $topic, $web ) = @_;

    my $form =
      Foswiki::Plugins::BioKbPlugin::MolecularBiology::kegg_pathway_search(
        $session, $params, $topic, $web );

    return $form;
}

=pod

Provides the form functionality used to create and edit Data topics. 

=cut

sub _MOLBIOL_FORM {
    my ( $session, $params, $topic, $web ) = @_;

    my $output = "";

    my $query = Foswiki::Func::getCgiQuery();
    if ( lc $query->param("type") eq "reference" ) {
        $output .= "%PUBMEDSEARCH_FORM%";
    }
    else {
        $output =
          Foswiki::Plugins::BioKbPlugin::BioKb::make_input_form( $session,
            $params, $topic, $web );
    }

    return $output;
}

=pod

 CREATE A FORM TO FEED SEARCH TERMS TO PUBMEDSEARCH- DEVELOPERS COULD REPLACE THIS WITH ANY VARIANT THEY WISHED

=cut

sub _PUBMEDSEARCH_FORM {
    my ( $session, $params, $topic, $web ) = @_;

    my $form =
      Foswiki::Plugins::BioKbPlugin::Literature::make_search_form( $session,
        $params, $topic, $web );

    return $form;
}

=pod

 TAKE INPUT TO ANY OF THE AVAILABLE PUBMED FIELDS AND RETURN RESULTS IN PRETTIFIED LIST. 

=cut

sub _PUBMEDSEARCH {
    my ( $session, $params, $topic, $web ) = @_;

    my $output =
      Foswiki::Plugins::BioKbPlugin::Literature::search_pubmed( $session,
        $params, $topic, $web );

    return $output;
}

1;
__DATA__
# Plugin for Foswiki - The Free and Open Source Wiki, http://foswiki.org/
#
# Copyright (C) 2008 Foswiki Contributors. All Rights Reserved.
# Foswiki Contributors are listed in the AUTHORS file in the root
# of this distribution. NOTE: Please extend that file, not this notice.
#
# Additional copyrights apply to some or all of the code in this
# file as follows:
#
# Copyright (C) 2001-2006 TWiki Contributors. All Rights Reserved.
# TWiki Contributors are listed in the AUTHORS file in the root
# of this distribution. NOTE: Please extend that file, not this notice.
# Copyright (C) 2004-2008 Crawford Currie
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version. For
# more details read LICENSE in the root of this distribution.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
