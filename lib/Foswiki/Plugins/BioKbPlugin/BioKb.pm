package Foswiki::Plugins::BioKbPlugin::BioKb;

use strict;
use vars qw($AUTOLOAD %ok_field);
use Scalar::Util qw(tainted);
use Time::Local;
use Clone qw(clone);

my ( $site_url, $username, $password );

# Authorize the attribute fields
for my $attr (qw(mc dictionary genecards links pubmed verbose)) {
    $ok_field{$attr}++;
}

select( ( select(STDOUT), $| = 1 )[0] );

#####################################################
#                                                   #
#                Admin Functions                    #
#                                                   #
#####################################################

=pod

Parse the topic structure admin topic specifically

=cut

sub read_topic_structure_admin {

    my ($web) = @_;

    my $admin = Foswiki::Func::readTopicText( $web, "AdminFormFields" );

    my @definitions = split /\-\-\-\+\+\+\+\s*/, $admin;
    my %output;

    my %admin_data;

    my $intro = shift @definitions;
    foreach my $def (@definitions) {

        my @lines = split /\n/, $def;
        my $topic_type = shift @lines;
        chomp $topic_type;
        next if ( $topic_type eq "Template" );

# Variables to store ordered version of sections and categories to define topic structure

        my @sections;
        my %ordered_fields_by_section;

        # Variables keep track of where we are in the admin topic

        my @properties;

        foreach my $line (@lines) {

            $line =~ s/\s+$//g;

            # Single-cell header line indicating a new topic section

            if ( $line =~ /^\|\s*\*([^\|]+)\*\s*[\|]{2,100}/ ) {
                push @sections, $1;
            }

# Allow specification of topic class- which will determine appearance via the css classes employed

            elsif ( $line =~ /class\=(\w+)/ ) {
                $admin_data{$topic_type}{"class"} = $1;
            }

            # Allow specification of topic prefix

            elsif ( $line =~ /prefix\=(\w+)/ ) {
                $admin_data{$topic_type}{"prefix"} = $1;
            }

            # Allow specification of topic prefix

            elsif ( $line =~ /image\=([\w\.]+)/ ) {
                $admin_data{$topic_type}{"image"} = $1;
            }

            # Read descriptor to show on Browse pages etc

            elsif ( $line =~ /descriptor\=([\w\. ]+)/ ) {
                $admin_data{$topic_type}{"descriptor"} = $1;
            }

            # Multi-cell header line indicating the names of field properties

            elsif ( $line =~ /\*[\w\s]+\*/ ) {
                @properties = $line =~ /\*([\w\s]+)\*/g;
            }

            # Data line defining topic structure

            elsif ( $line =~ /^\|/ ) {
                my @data = $line =~ /\|\s*([\w\s\,\-]+)/g;

                my $field = $data[0];
                $field =~ s/^\s+//;
                $field =~ s/\s+$//g;
                push
                  @{ $admin_data{$topic_type}{ $sections[-1] }{"field order"} },
                  $field;

                for ( my $i = 1 ; $i < scalar @data ; $i++ ) {
                    my @vals;

                    foreach my $val ( split /\s*\,\s*/, $data[$i] ) {
                        $val =~ s/^\s+//;
                        $val =~ s/\s+$//g;
                        push @vals, $val if ( $val =~ /\w/ );
                    }

                    if ( scalar @vals > 1
                        || ( scalar @vals == 1
                            && $properties[$i] eq "databases" ) )
                    {
                        $admin_data{$topic_type}{ $sections[-1] }{$field}
                          { $properties[$i] } = \@vals;
                    }
                    elsif ( scalar @vals == 1 ) {
                        $admin_data{$topic_type}{ $sections[-1] }{$field}
                          { $properties[$i] } = $vals[0];
                    }
                }
            }
        }
        $admin_data{$topic_type}{"section order"} = \@sections;
    }

    return \%admin_data;
}

=pod

Read data from various of the simpler (specified) Admin* topics of the web

=cut

sub read_admin {
    my ( $web, $type ) = @_;

    my $admin = Foswiki::Func::readTopicText( $web, "Admin" . $type );

    my %admin_data;

# An array to hold the category names in order, a hash to key the pertinent fields in other arrays

    my @lines = split /\n/, $admin;
    my @fields;
    foreach my $line (@lines) {
        if ( $line =~ /\*\w+\*/ ) {
            @fields = $line =~ m/\*([\w\s]+)\*/g;
        }
        elsif ( $line =~ /\|/ ) {
            my @dat =
              $line =~ m/(?=\|([\w\s\-\,\:\/\?\=\.\&\_\+\;\[\]\<\>]+)\|)/g;
            next if ( $dat[0] =~ /^\s+$/ );

            for ( my $i = 0 ; $i < scalar @dat ; $i++ ) {
                $dat[$i] =~ s/^\s+//g;
                $dat[$i] =~ s/\s+$//g;

                next if ( $i == 0 );
                $dat[$i] = undef if ( $dat[$i] eq "" );

                # For really simple admin topics

                if ( scalar @fields == 2 ) {
                    $admin_data{ lc $dat[0] } = $dat[$i];
                }

                # For more complicated ones

                else {

                    $admin_data{ $dat[0] }{ $fields[$i] } = $dat[$i];

                }

            }
        }
    }

    return ( \%admin_data );
}

#####################################################
#                                                   #
#                Edit Provenance                    #
#                                                   #
#####################################################

=pod

Make a field signature. Don't append with an author if this is exactly as retrieved from the database

=cut

sub make_fieldsig {

    my (
        $web,            $topic,           $source,
        $fieldtext,      $sourcefieldtext, $sourcefielddate,
        $sourcefieldgen, $sourcefielduser, $field
    ) = @_;

    my $wikiuser = Foswiki::Func::getWikiName();
    my $wikiname = "[[Main.$wikiuser][$wikiuser]]";
    $sourcefielduser = $wikiuser if ( !defined $sourcefielduser );

    if ( !defined $source ) {
        $source = $wikiname if ( !defined $source );
    }

    my $date = get_date();
    my $exists = Foswiki::Func::topicExists( $web, $topic );
    $source =~ s/\s/&nbsp\;/g;
    $source =~ s/\[\[(?:[^\]\[]+\]\[)?([^\[\]]+)\]\]/$1/g;
    my $newfieldsig = "(!$source)<br />";

    # Linking doesn't count as a difference

    $fieldtext =~ s/\[\[(?:[^\]\[]+\]\[)?([^\[\]]+)\]\]/$1/g;
    $sourcefieldtext =~ s/\[\[(?:[^\]\[]+\]\[)?([^\[\]]+)\]\]/$1/g
      if ( defined $sourcefieldtext );

    if ( defined $sourcefieldtext && $sourcefieldtext eq $fieldtext ) {
        $newfieldsig .= "$sourcefieldgen.&nbsp;$sourcefielddate";
        if ( defined $sourcefielduser ) {
            $newfieldsig .= "<br />[[Main.$sourcefielduser][$sourcefielduser]]";
        }
    }
    else {
        if (   defined $sourcefieldtext
            && $sourcefieldtext =~ /\w/
            && ( defined $exists && $exists == 1 ) )
        {
            $newfieldsig .= "Ed.&nbsp;$date";
        }
        else {
            $newfieldsig .= "Gen.&nbsp;$date";
        }
        $newfieldsig .= "<br />$wikiname";
    }

    return $newfieldsig;
}

=pod

Make formatted date string

=cut

sub get_date {
    my (
        $second,     $minute,    $hour,
        $dayOfMonth, $month,     $yearOffset,
        $dayOfWeek,  $dayOfYear, $daylightSavings
    ) = localtime();
    my $year = 1900 + $yearOffset;
    return join "/", ( $dayOfMonth, $month + 1, $year );
}

##########################################################################################
#                                                                                        #
#                                    Form functions                                      #
#                                                                                        #
##########################################################################################

=pod

Process input for form building. Presents form, and sends values for topic creation at the appropriate time

=cut

sub make_input_form {
    my ( $session, $params, $topic, $web ) = @_;

    my $query = Foswiki::Func::getCgiQuery();
    my $type  = $query->param("type");

    my %admin_data =
      %{ Foswiki::Plugins::BioKbPlugin::BioKb::read_topic_structure_admin($web)
      };

    if ( !defined $admin_data{$type} ) {

        throw Foswiki::OopsException(
            'generic',
            params => [
"$type type invalid. Please supply one of the following values for the \'type\' argument in the URL: "
                  . ( join ",", keys %admin_data ) . "\n",
                "",
                "",
                ""
            ]
        );
    }

    %admin_data = %{ $admin_data{$type} };
    my %field_values;

    foreach my $section ( @{ $admin_data{"section order"} } ) {
        foreach my $field ( @{ $admin_data{$section}{"field order"} } ) {
            push @{ $field_values{$field}{"value"} },
              $admin_data{$section}{$field}{"default"};
            push @{ $field_values{$field}{"source"} }, "";
        }
    }

    my $workarea = Foswiki::Func::getWorkArea("BioKbPlugin");

# If populate_id is present and filled, we need to add this data to the defaults

    my $populate = $query->param("populate_id");
    my $edit     = $query->param("edit_topic");
    my $mesh     = $query->param("mesh");
    my $refs     = $query->param("refs");

    if (   ( defined $populate && $populate ne "" )
        || ( defined $edit && $edit ne "" ) )
    {

        my %result;

        if ( defined $populate && $populate ne "" ) {
            my $id;
            ( $id = $populate ) =~ /([\d\w\:]+)/;

            my @kegg_results =
              Foswiki::Plugins::BioKbPlugin::MolecularBiology::fetch_kegg( $web,
                lc $type, $id );
            if ( scalar @kegg_results == 0 ) {
                throw Foswiki::OopsException(
                    'generic',
                    params => [
                        "No results found for $type with ID of $id",
                        "", "", ""
                    ]
                );
            }
            %result = %{
                Foswiki::Plugins::BioKbPlugin::MolecularBiology::_add_kegg_orthologs(
                    $web, $type, $kegg_results[0] )
              };
            my @ihop_syns =
              Foswiki::Plugins::BioKbPlugin::MolecularBiology::_get_ihop_synonyms(
                @{ $result{"Title"}{"value"} }[0] );
            if ( scalar @ihop_syns > 0 ) {
                push @{ $result{"Synonyms"}{"value"} },
                  ( join "\n", @ihop_syns );
                push @{ $result{"Synonyms"}{"source"} }, "iHOP";
            }
            %result = %{ _read_form_values( $query, \%admin_data, \%result ) };
        }

        # The edit button has been clicked on an existing topic-parse it.

        elsif ( $query->param("edit_topic") ne "" ) {
            %result = %{
                Foswiki::Plugins::BioKbPlugin::BioKb::parse_topic_data(
                    $query->param("edit_topic"),
                    $web, $type )
              };
        }

        # Fetch MeSH terms- takes a few mins

        if (   ( defined $populate && $populate ne "" )
            || ( defined $mesh && $mesh ne "" ) )
        {
            my ($rec) = _add_mesh_data( $web, \%result );
            %result = %{$rec};
        }

        # Fetch the refernces for an OMIM record- takes a few mins

        if ( defined $refs && $refs ne "" && $type eq "Disease" ) {
            my ($omim) = Foswiki::Plugins::BioKbPlugin::Disease::_fetch_omim(
                $result{"Entry"}{"value"} );
            %result =
              %{ Foswiki::Plugins::BioKbPlugin::Disease::_parse_omim($omim) };
            my ( $pmids, $al ) =
              Foswiki::Plugins::BioKbPlugin::Disease::_pubmed_ids_from_references(
                split /\n\n/, $result{"Reference"}{"value"} );
            my @pubmed_ids = @{$pmids};
            $result{"PubMed"}{"value"} = join ",", @{$pmids};
            $result{"PubMed"}{"source"} = "OMIM";
        }

        %field_values = ( %field_values, %result );

    }

##############################################################################################
#                                                                                            #
# Process the submission- if title is defined and was not just filled by the populate button #
#                                                                                            #
##############################################################################################

    my $output;
    my $title = $query->param("Title");

    if (   ( defined $title && $title ne "" )
        && ( !defined $populate || $populate eq "" )
        && ( !defined $edit || $edit eq "" ) )
    {

        my %inhash = %{ _read_form_values( $query, \%admin_data ) };
        my $sourcetitle = @{ $inhash{"Title"}{"sourcevalue"} }[0];
        my ($topicname) = make_topicname($title) =~ /(\w+)/;
        $inhash{"topicname"} = $topicname;

        if (   defined $sourcetitle
            && $sourcetitle ne ""
            && $title ne $sourcetitle )
        {
            if ( !defined $inhash{"Synonyms"}{"value"} ) {
                $inhash{"Synonyms"}{"value"}       = [ [] ];
                $inhash{"Synonyms"}{"sourcevalue"} = [ [] ];
            }
            push @{ @{ $inhash{"Synonyms"}{"value"} }[0] }, $sourcetitle;
        }

        my $done =
          Foswiki::Plugins::BioKbPlugin::BioKb::build_topic( $session, \%inhash,
            $topic, $web );

        # If the topic has been edited- and the title changed

        if (   defined $sourcetitle
            && $sourcetitle ne ""
            && $title ne $sourcetitle )
        {
            my $sourcetopic = make_topicname($sourcetitle);
            my ( $mainmeta, $maintext ) =
              Foswiki::Func::readTopic( $web, $sourcetopic )
              ;    # Fetch existing main-pane content from pre-rename topic
            $maintext =~
              s/(\[\[)$sourcetopic(\]\[[^\]]+)?(\]\])/$1$topicname$2$3/;
            remove_topic( $web, $sourcetopic );    # Remove the previous topics
            Foswiki::Func::saveTopic( $web, $topicname, $mainmeta, $maintext )
              ; # Overwrite the blank main-pane that will have been created at the rename
        }

        my $page_location = Foswiki::Func::getScriptUrl( $web, $done, 'view' );
        print "Status: 302 Moved\nLocation: $page_location\n\n";
        exit;

    }

    elsif ( defined $query->param("type") && $query->param("type") ne "" ) {
        $output = _make_input_form( $web, $topic, $query, %field_values );

    }
    else {

        throw Foswiki::OopsException(
            'attention',
            def    => 'bad_search',
            web    => $web,
            topic  => $topic,
            params => ["Please suppy a desired form type with \"type\"\n"]
          )
          if ( ( !defined $type || $type eq "" )
            && ( !defined $query->param("Title")
                || $query->param("Title") eq "" ) );

    }
    return $output;

}

=pod

Make a topic name, splitting supplied phrase on any non-alphanumerics

=cut

sub make_topicname {
    my ($dest_topic) = @_;
    if ( $dest_topic =~ /\W/ ) {
        my @words = split /\W/, $dest_topic;
        $dest_topic = "";
        foreach my $word (@words) {
            $dest_topic .= ucfirst $word;
        }
    }
    return $dest_topic;
}

sub _read_form_values {

    my ( $query, $ad, $sup ) = @_;
    my %admin_data = %{$ad};

# Supplement allows form values to be augmented- e.g. if 'edit' is pressed, then 'populate'. Useful sometimes when updating topics.

    my %supplement = %{$sup} if ( defined $sup );

    # Pass the form parameters to the topic creation function

    my %inhash;

    foreach my $simpletype ( "type", "Comments", "overwrite", "edited" ) {
        ( $inhash{$simpletype} ) =
          Foswiki::Plugins::BioKbPlugin::BioKb::untaint(
            [ $query->param($simpletype) ] );
    }

    foreach my $section ( @{ $admin_data{"section order"} } ) {
        foreach my $field ( @{ $admin_data{$section}{"field order"} } ) {

# Remove the first where a hidden template div was used (to be cloned in the dynamic form elements). Couldn't figure out a way of ignoring, or deleteing these from the javascript

            my $dbs = "";
            if ( defined $admin_data{$section}{$field}{"databases"} ) {

                my $dbfieldset = 0;
                while (defined $query->param( $field . $dbfieldset )
                    || defined $supplement{ $field . $dbfieldset }{"value"} )
                {

                    my ( @vals, @sources, @source_vals, @dates, @gens, @users );

                    if ( defined $query->param( $field . $dbfieldset )
                        && $query->param( $field . $dbfieldset ) ne "" )
                    {
                        my @vals =
                          Foswiki::Plugins::BioKbPlugin::BioKb::untaint(
                            [ $query->param( $field . $dbfieldset ) ] );
                        my ($source) =
                          Foswiki::Plugins::BioKbPlugin::BioKb::untaint(
                            [
                                $query->param(
                                    $field . "source" . $dbfieldset
                                )
                            ]
                          );
                        my ($date) =
                          Foswiki::Plugins::BioKbPlugin::BioKb::untaint(
                            [ $query->param( $field . "date" . $dbfieldset ) ]
                          );
                        my ($gen) =
                          Foswiki::Plugins::BioKbPlugin::BioKb::untaint(
                            [ $query->param( $field . "gen" . $dbfieldset ) ] );
                        my ($user) =
                          Foswiki::Plugins::BioKbPlugin::BioKb::untaint(
                            [ $query->param( $field . "user" . $dbfieldset ) ]
                          );
                        my @source_vals =
                          Foswiki::Plugins::BioKbPlugin::BioKb::untaint(
                            [
                                $query->param(
                                    $field . "sourceval" . $dbfieldset
                                )
                            ]
                          );
                        my @db_source_vals =
                          Foswiki::Plugins::BioKbPlugin::BioKb::untaint(
                            [
                                $query->param(
                                    $field . "_dbsourceval" . $dbfieldset
                                )
                            ]
                          );

                        my @dbs = $query->param( $field . "_db" . $dbfieldset );
                        @dbs = Foswiki::Plugins::BioKbPlugin::BioKb::untaint(
                            \@dbs );

         # Remove the extra field resulting from the template for dynamic fields

                        pop @vals;
                        pop @dbs;

                        push @{ $inhash{ $field . "_db" }{"value"} }, \@dbs;
                        push @{ $inhash{$field}{"sourcevalue"} }, \@source_vals;
                        push @{ $inhash{ $field . "_db" }{"sourcevalue"} },
                          \@db_source_vals;
                        push @{ $inhash{$field}{"value"} },  \@vals;
                        push @{ $inhash{$field}{"source"} }, $source;
                        push @{ $inhash{$field}{"date"} },   $date;
                        push @{ $inhash{$field}{"gen"} },    $gen;
                        push @{ $inhash{$field}{"user"} },   $user;
                    }
                    $dbfieldset++;
                }

                if ( !defined $inhash{$field}{"value"} ) {
                    $inhash{$field} = $supplement{$field};
                    $inhash{ $field . "_db" } = $supplement{ $field . "_db" };
                }
                elsif ( defined $supplement{$field}{"value"}
                    && scalar @{ $supplement{$field}{"value"} } >
                    scalar @{ $inhash{$field}{"value"} } )
                {
                    my $lim   = scalar @{ $supplement{$field}{"value"} } - 1;
                    my $start = scalar @{ $inhash{$field}{"value"} };
                    push @{ $inhash{$field}{"value"} },
                      @{ $supplement{$field}{"value"} }[ $start .. $lim ];
                    push @{ $inhash{ $field . "_db" }{"value"} },
                      @{ $supplement{ $field . "_db" }{"value"} }
                      [ $start .. $lim ];
                    push @{ $inhash{$field}{"source"} },
                      @{ $supplement{$field}{"source"} }[ $start .. $lim ];
                    push @{ $inhash{$field}{"sourcevalue"} },
                      @{ $supplement{$field}{"sourcevalue"} }[ $start .. $lim ];
                }
            }
            else {

                my ( @vals, @sources, @source_vals, @dates, @gens, @users );
                my $default = "";
                $default = $admin_data{$section}{$field}{"default"}
                  if ( defined $admin_data{$section}{$field}{"default"} );

                if (   defined $query->param($field)
                    && $query->param($field) ne ""
                    && $query->param($field) ne $default )
                {

                    @vals = Foswiki::Plugins::BioKbPlugin::BioKb::untaint(
                        [ $query->param($field) ] );
                    @dates = Foswiki::Plugins::BioKbPlugin::BioKb::untaint(
                        [ $query->param( $field . "date" ) ] );
                    @gens = Foswiki::Plugins::BioKbPlugin::BioKb::untaint(
                        [ $query->param( $field . "gen" ) ] );
                    @users = Foswiki::Plugins::BioKbPlugin::BioKb::untaint(
                        [ $query->param( $field . "user" ) ] );
                    @sources = Foswiki::Plugins::BioKbPlugin::BioKb::untaint(
                        [ $query->param( $field . "source" ) ] );
                    @source_vals =
                      Foswiki::Plugins::BioKbPlugin::BioKb::untaint(
                        [ $query->param( $field . "sourceval" ) ] );

                    if ( defined $supplement{$field}{"value"}
                        && scalar @{ $supplement{$field}{"value"} } >
                        scalar @vals )
                    {
                        my $lim = scalar @{ $supplement{$field}{"value"} } - 1;
                        push @vals, @{ $supplement{$field}{"value"} }
                          [ scalar @vals .. $lim ];
                        push @sources, @{ $supplement{$field}{"source"} }
                          [ scalar @sources .. $lim ];
                        push @source_vals,
                          @{ $supplement{$field}{"sourcevalue"} }
                          [ scalar @source_vals .. $lim ];
                    }
                    for ( my $i = 0 ; $i < scalar @vals ; $i++ ) {
                        $vals[$i] =~ s/\<\/?pre\>//g if ( defined $vals[$i] );
                    }

                    if ( $field eq "Synonyms" ) {
                        @vals        = [ split /[\n\r]+/, $vals[0] ];
                        @source_vals = [ split /[\n\r]+/, $source_vals[0] ]
                          if ( defined $source_vals[0] );
                    }
                    $inhash{$field}{"value"}       = \@vals;
                    $inhash{$field}{"date"}        = \@dates;
                    $inhash{$field}{"gen"}         = \@gens;
                    $inhash{$field}{"user"}        = \@users;
                    $inhash{$field}{"source"}      = \@sources;
                    $inhash{$field}{"sourcevalue"} = \@source_vals;
                }
                elsif ( defined $supplement{$field}{"value"} ) {
                    $inhash{$field}{"value"}  = $supplement{$field}{"value"};
                    $inhash{$field}{"source"} = $supplement{$field}{"source"};
                    $inhash{$field}{"sourcevalue"} =
                      $supplement{$field}{"sourcevalue"};
                }
            }
        }
    }

    return \%inhash;
}

=pod

This is the code for actually building the form. Reads values out of the CGI query object

=cut

sub _make_input_form {

    my ( $web, $topic, $query, %field_values ) = @_;

    my $type = $query->param("type");

    my %checkbox =
      ( -name => "overwrite", -label => "Overwrite?", -value => 1 );
    $checkbox{"checked"} = 1
      if ( defined $query->param("overwrite")
        && $query->param("overwrite") == 1 );
    my $submit =
        "<div class=\"rightalign\">"
      . CGI::submit( -class => "foswikiSubmit", -value => "Save Topic" )
      . CGI::checkbox(%checkbox)
      . "</div>";

    my %all_admin_data =
      %{ Foswiki::Plugins::BioKbPlugin::BioKb::read_topic_structure_admin($web)
      };
    my %admin_data = %{ $all_admin_data{$type} };

    # Determine which type of field is what size

    my %field_sizes = (
        "small" => CGI::textfield(
            -name      => "NAME",
            -size      => 20,
            -maxlength => 100,
            -default   => "DEFAULT"
        ),
        "medium" => CGI::textarea(
            -name    => "NAME",
            -rows    => 5,
            -columns => 80,
            -default => "DEFAULT"
        ),
        "large" => CGI::textarea(
            -name    => "NAME",
            -rows    => 10,
            -columns => 80,
            -default => "DEFAULT"
        )
    );

    my %database_sources = (
        "gene"     => "KEGG",
        "pathway"  => "KEGG",
        "compound" => "KEGG",
        "drug"     => "KEGG"
    );

    Foswiki::Func::addToHEAD( "BioKb",
"<script type=\"text/javascript\" src=\"%PUBURL%/%TWIKIWEB%/BioKbPlugin/dynamicFormField.js\"></script>\n"
    );

    my $form .=
      "---++ Create a topic of type !$type\n\n"
      . CGI::start_form( -name => $type, -method => 'post',
        -class => "results" );
    $form .= CGI::hidden( -name => "type", -default => $type, -override => 1 );
    $form .= CGI::hidden(
        -name     => "edited",
        -default  => $query->param("edit_topic"),
        -override => 1
      )
      if (
        (
            defined $query->param("edit_topic")
            && $query->param("edit_topic") ne ""
        )
        || ( defined $query->param("edited") && $query->param("edited") ne "" )
      );

    if (
          !defined $query->param('mesh')
        && defined $database_sources{ lc $type }
        && ( !defined $query->param("populate_id")
            || $query->param("populate_id") eq "" )
      )
    {
        $form .= "Populate from: "
          . CGI::popup_menu(
            -name   => "populate_db",
            -values => $database_sources{ lc $type },
          )
          . "&nbsp;&nbsp;"
          . CGI::textfield(
            -name      => "populate_id",
            -size      => 20,
            -maxlength => 50,
            -default   => ""
          ) . CGI::submit( -value => "Populate" );
    }

    foreach my $section ( @{ $admin_data{"section order"} } ) {
        $form .= "\n\-\-\-\+\+\+\+ $section\n\n";

        my @fields = @{ $admin_data{$section}{"field order"} };
        my $number_results;
        foreach my $field (@fields) {
            $number_results = scalar @{ $field_values{$field}{"value"} }
              if (!defined $number_results
                && defined $field_values{$field}{"value"} );
        }

        my @subsection_headers = ("");
        if ( $number_results > 1 ) {
            @subsection_headers = @{ $field_values{"Species"}{"value"} };
        }

        for ( my $i = 0 ; $i < $number_results ; $i++ ) {

            $form .= "\n\-\-\-\+\+\+\+ " . $subsection_headers[$i] . "\n";

            foreach my $field (@fields) {
                my $value  = shift @{ $field_values{$field}{"value"} };
                my $source = shift @{ $field_values{$field}{"source"} };
                my $sourcevalue =
                  shift @{ $field_values{$field}{"sourcevalue"} };
                my $date = shift @{ $field_values{$field}{"date"} };
                my $gen  = shift @{ $field_values{$field}{"gen"} };
                my $user = shift @{ $field_values{$field}{"user"} };

                my @params = $query->param();
                $value = "" if ( !defined $value );
                if (
                    !(
                        defined $query->param('mesh')
                        && (   $field eq "Text Summary"
                            || $field eq "MeSH Terms" )
                    )
                    && ( defined $query->param('edit_topic')
                        && !defined $sourcevalue )
                    && !(
                        defined $admin_data{$section}{$field}{"default"}
                        && $value eq $admin_data{$section}{$field}{"default"}
                    )
                  )
                {
                    $sourcevalue = $value;
                }

                $value =~ s/\n/ /g
                  if ( $admin_data{$section}{$field}{"size"} eq "small" );
                $source =~ s/\[\[[^\]]+\]\[([^\]]+)\]\]/$1/g
                  if ( defined $source );

                my $textfield;
                ( $textfield =
                      $field_sizes{ $admin_data{$section}{$field}{"size"} } ) =~
                  s/NAME/$field/;

# Add drop-down boxes where required- e.g. where external DB links are concerned

                if ( defined $admin_data{$section}{$field}{"databases"} ) {

                    $textfield =~ s/$field/$field$i/;
                    my $db =
                      shift @{ $field_values{ $field . "_db" }{"value"} };
                    my $sourcedb =
                      shift @{ $field_values{ $field . "_db" }{"sourcevalue"} };
                    if ( defined $query->param('edit_topic')
                        && !defined $sourcedb )
                    {
                        $sourcedb = $db;
                    }

                    my $fieldset;
                    my $defaultbox = 1;

                    my @dbs = @{ $admin_data{$section}{$field}{"databases"} };

                    if ( $value ne "" ) {
                        undef $defaultbox;

                        my @thesedbs = @{$db};
                        my @dbids    = @{$value};

                        my $fieldstring = "";
                        for ( my $j = 0 ; $j < scalar @thesedbs ; $j++ ) {
                            my $thistextfield;
                            ( $thistextfield = $textfield ) =~
                              s/DEFAULT/$dbids[$j]/;

                            $fieldstring .= CGI::popup_menu(
                                -name     => $field . '_db' . $i,
                                -values   => \@dbs,
                                -default  => $thesedbs[$j],
                                -override => 1
                              )
                              . "&nbsp;&nbsp;"
                              . $thistextfield
                              . "<br />";
                        }
                        $fieldset .= $fieldstring;
                    }

                    my $fieldstring = CGI::popup_menu(
                        -name   => $field . '_db' . $i,
                        -values => \@dbs,
                      )
                      . "&nbsp;&nbsp;"
                      . $textfield;
                    $fieldstring =~ s/\n//g;

                    $fieldset .=
                      _dynamic_field( $fieldstring, $field . "_fields" . $i,
                        $defaultbox );
                    $fieldset =~ s/\n//g;
                    $textfield = $fieldset;
                    $textfield =~ s/DEFAULT//;

                    # Preserve the fact that a field was blank to start with

                    $textfield .= CGI::hidden(
                        -name     => $field . "source" . $i,
                        -default  => $source,
                        -override => 1
                    );
                    $textfield .= "   "
                      . CGI::hidden(
                        -name     => $field . "sourceval" . $i,
                        -default  => $sourcevalue,
                        -override => 1
                      );
                    $textfield .= "   "
                      . CGI::hidden(
                        -name     => $field . "_dbsourceval" . $i,
                        -default  => $sourcedb,
                        -override => 1
                      );
                    $textfield .= "   "
                      . CGI::hidden(
                        -name     => $field . "date" . $i,
                        -default  => $date,
                        -override => 1
                      );
                    $textfield .= "   "
                      . CGI::hidden(
                        -name     => $field . "gen" . $i,
                        -default  => $gen,
                        -override => 1
                      );
                    $textfield .= "   "
                      . CGI::hidden(
                        -name     => $field . "user" . $i,
                        -default  => $user,
                        -override => 1
                      );
                    $textfield =~ s/DEFAULT//;
                }
                else {
                    $value = join( "\n", @{$value} )
                      if ( ref $value eq "ARRAY" );
                    $sourcevalue = join( "\n", @{$sourcevalue} )
                      if ( ref $sourcevalue eq "ARRAY" );

                    my @params = $query->param();

                    # Preserve the fact that a field was blank to start with

                    $textfield =~ s/DEFAULT/$value/;

                    $textfield .= CGI::hidden(
                        -name     => $field . "source",
                        -default  => $source,
                        -override => 1
                    );
                    $textfield .= "   "
                      . CGI::hidden(
                        -name     => $field . "sourceval",
                        -default  => $sourcevalue,
                        -override => 1
                      );
                    $textfield .= "   "
                      . CGI::hidden(
                        -name     => $field . "date",
                        -default  => $date,
                        -override => 1
                      );
                    $textfield .= "   "
                      . CGI::hidden(
                        -name     => $field . "gen",
                        -default  => $gen,
                        -override => 1
                      );
                    $textfield .= "   "
                      . CGI::hidden(
                        -name     => $field . "user",
                        -default  => $user,
                        -override => 1
                      );
                    $textfield =~ s/DEFAULT//;

                }
                $textfield =~ s/\n/ /g
                  if ( $admin_data{$section}{$field}{"size"} eq "small" );

                # Store the data source in a hidden field for future retrieval

                $form .=
                    "| !" 
                  . $field
                  . " | <noautolink>"
                  . $textfield
                  . "</noautolink> |\n";
            }
            $form .= "\n";
        }
    }

    $form = "<div id=\"disease\">\n" . $form . "\n</div>\n"
      if ( $all_admin_data{$type}{"class"} eq "Disease" );
    $form = "<div id=\"literature\">\n" . $form . "\n</div>\n"
      if ( $all_admin_data{$type}{"class"} eq "Reference" );

    $form .= $submit;
    $form .= CGI::end_form();
    return $form;
}

=pod

Create a template of any field, which can be copied via an associated JavaScript function to create a dynamic form

=cut

sub _dynamic_field {
    my ( $fieldstring, $id, $defaultbox ) = @_;
    my $content;
    $content .= "<div id='dynamicInput_$id'>";
    $content .= $fieldstring if ( defined $defaultbox );
    $content .= "</div>";
    $content .=
"<input type='button' value='Add a field' onclick=\"addInput('dynamicInput_$id', '$id')\"><div id='$id' style='display: none'>$fieldstring</div>";
    $content =~ s/\n//g;
    return $content;
}

##########################################################################################
#                                                                                        #
#                                       Formatting                                       #
#                                                                                        #
##########################################################################################

=pod

Wrapper for the fairly complex topic creation. Given input values, see if references need adding, generate a suitable topic title, and send it to BioKb.pm's 'create_topic' for addition. 

=cut

sub build_topic {

    my ( $session, $inhash, $topic, $web, $auto ) = @_;

    my %inhash = %{$inhash};

    my $type  = $inhash{"type"};
    my $title = ( @{ $inhash{"Title"}{"value"} } )[0];

# The $auto argument states that this has been generated automatically rathan than through the form, so we can automatically attribute the source values

    if ( defined $auto && $auto == 1 ) {
        foreach my $key ( keys %inhash ) {
            next if ( ref $inhash{$key} ne "HASH" );
            $inhash{$key}{"sourcevalue"} = $inhash{$key}{"value"};
        }
    }

# If they've quoted any references, add them to the database and replace IDs in this field with topic IDs

    if ( defined $inhash{"PubMed"}{"value"}
        && $inhash{"PubMed"}{"value"} ne "" )
    {

        my @pubmed;
        foreach my $pubmed ( @{ $inhash{"PubMed"}{"value"} } ) {
            push @pubmed,
              _add_references( $session, $web, $topic, $pubmed,
                "Relevant to $type \"$title\"" );
        }
        $inhash{"PubMed"}{"value"} = \@pubmed;
    }

    my $input = format_data_topic( $web, \%inhash );
    my $exists = Foswiki::Func::topicExists( $web, $inhash{"topicname"} );

    if (   ( !defined $exists || $exists != 1 )
        || ( defined $inhash{"overwrite"} && $inhash{"overwrite"} == 1 ) )
    {

        my @terms = @{ $inhash{"Title"}{"value"} };
        push @terms, @{ @{ $inhash{"Synonyms"}{"value"} }[0] }
          if ( defined $inhash{"Synonyms"}{"value"}[0] );
        Foswiki::Plugins::BioKbPlugin::BioKb::create_topic(
            $session, $web,                 $topic,
            $type,    $inhash{"topicname"}, $title,
            $input,   \@terms,              $inhash{"edited"}
        );
    }
    return $inhash{"topicname"};
}

=pod

Fetch articles based on Pubmed IDs supplied at topic creation

=cut

sub _add_references {

    my ( $session, $web, $topic, $pubmed, $reason ) = @_;

    my @ref_topic_names;

    my @pubmed_ids = split /[\s\,]+/, $pubmed;

    foreach my $pubmed_id (@pubmed_ids) {
        my %art;
        my %existing;
        my $ref_topic;
        if ( $pubmed_id =~ /^\d+$/ ) {
            my ($article) = @{
                Foswiki::Plugins::BioKbPlugin::Literature::get_by_pubmed_id(
                    $pubmed_id)
              };
            %art       = %{$article};
            $ref_topic = ucfirst $art{"Key"}{"value"};
        }

        # Allow a topic name to be supplied if it's present

        else {
            $ref_topic = $pubmed_id;
        }
        $ref_topic =~ s/[\[\]]//g;

        # Save if this is a new association (via 'reason'), or a new topic

        my $exists = Foswiki::Func::topicExists( $web, $ref_topic );

        my $save;
        if ( defined $exists && $exists == 1 ) {
            %existing = %{
                Foswiki::Plugins::BioKbPlugin::Literature::parse_article( $web,
                    $ref_topic )
              };
            if ( $existing{"Reason added"}{"value"} !~ /$reason/ ) {
                %art = %existing if ( scalar %art == 0 );
                $art{"Reason added"}{"value"} =
                  $existing{"Reason added"}{"value"} . "<P>" . $reason;
                $save = 1;
            }

            # Reference topic exists, but the association already exists

            else {
                push @ref_topic_names, "[[" . $ref_topic . "]]";
            }
        }

        # Input was a pubmed ID so we can add the reference

        elsif ( $pubmed_id =~ /^\d+$/ ) {
            $art{"Reason added"}{"value"} = $reason;
            $save = 1;
        }

        if ( defined $save ) {
            my $input =
              Foswiki::Plugins::BioKbPlugin::Literature::format_article( $web,
                \%art );
            Foswiki::Plugins::BioKbPlugin::BioKb::create_topic( $session, $web,
                $topic, "Reference", $ref_topic, $art{"Title"}{"value"},
                $input, undef );
            push @ref_topic_names, "[[" . $ref_topic . "]]";
        }
    }
    return join " ", @ref_topic_names;
}

=pod

Format the data topic as a Foswiki table, tagging author etc as appropriate

=cut

sub format_data_topic {

    my ( $web, $inhash ) = @_;

    my %inhash = %{$inhash};

    my %source_value_hash = %{ clone($inhash) };
    foreach my $key ( keys %source_value_hash ) {
        next if ( ref $source_value_hash{$key} ne "HASH" );
        if ( defined $source_value_hash{$key}{"sourcevalue"} ) {
            $source_value_hash{$key}{"value"} =
              $source_value_hash{$key}{"sourcevalue"};
        }
    }

    my @admin =
      Foswiki::Plugins::BioKbPlugin::BioKb::read_admin( $web, "DatabaseURLs" );
    my %prefixes = %{ $admin[0] };

    my $text = "\%FORM_EDIT_TOPIC_DATA{type=\"" . $inhash{"type"} . "\"}\%";
    $text .= "\n";

    my %admin_data =
      %{ Foswiki::Plugins::BioKbPlugin::BioKb::read_topic_structure_admin($web)
      };
    die "No topic structure present for "
      . $inhash{"type"}
      . "\n\n(Must be one of "
      . ( join ",", keys %admin_data ) . "\n"
      if ( !defined $admin_data{ $inhash{"type"} } );
    %admin_data = %{ $admin_data{ $inhash{"type"} } };

    foreach my $section ( @{ $admin_data{"section order"} } ) {

        my $sectionheader = "\n\-\-\-\+\+\+\+ $section \n\n";
        my $sectiontext   = "";

        my @fields = @{ $admin_data{$section}{"field order"} };
        my $number_results;
        foreach my $field (@fields) {
            $number_results = scalar @{ $inhash{$field}{"value"} }
              if (!defined $number_results
                && defined $inhash{$field}{"value"} );
        }
        next if ( !defined $number_results );

        my @subsection_headers;
        if ( $number_results > 1 ) {
            @subsection_headers = @{ $inhash{"Species"}{"value"} };
        }

        for ( my $i = 0 ; $i < $number_results ; $i++ ) {

            my %this_inhash = (
                "type"      => $inhash{"type"},
                "topicname" => $inhash{"topicname"}
            );
            my %this_sourcehash = %this_inhash;

            foreach my $field (@fields) {

                $this_inhash{$field}{"value"} =
                  @{ $inhash{$field}{"value"} }[$i];
                $this_inhash{$field}{"source"} =
                  @{ $inhash{$field}{"source"} }[$i];
                $this_inhash{$field}{"date"} = @{ $inhash{$field}{"date"} }[$i];
                $this_inhash{$field}{"gen"}  = @{ $inhash{$field}{"gen"} }[$i];
                $this_inhash{$field}{"user"} = @{ $inhash{$field}{"user"} }[$i];

                $this_sourcehash{$field}{"value"} =
                  @{ $source_value_hash{$field}{"value"} }[$i];
                $this_sourcehash{$field}{"source"} =
                  @{ $source_value_hash{$field}{"source"} }[$i];

                if ( defined $inhash{ $field . "_db" }{"value"} ) {
                    $this_inhash{ $field . "_db" }{"value"} =
                      shift @{ $inhash{ $field . "_db" }{"value"} };
                    $this_sourcehash{ $field . "_db" }{"value"} =
                      shift @{ $source_value_hash{ $field . "_db" }{"value"} };
                }
            }

            my $subsection_text =
              _format_sectiontext( $web, \%admin_data, \%prefixes,
                \%this_sourcehash, \%this_inhash, $section, $sectionheader );
            if ( scalar @subsection_headers > 0 ) {
                $subsection_text =
                    "\n%TWISTY{\nshowlink=\""
                  . $subsection_headers[$i]
                  . "\"\nhidelink=\"Hide\"\nshowimgleft=\"%ICONURLPATH{toggleopen-small}%\"\nhideimgleft=\"%ICONURLPATH{toggleclose-small}%\"\nstart=\"hide\"\n}%\n\n$subsection_text%ENDTWISTY{}%\n";

            }

            $sectiontext .= $subsection_text;

        }
        $text .= $sectionheader . $sectiontext if ( $sectiontext ne "" );
    }

    return $text;
}

=pod

Format one section of a topic- called from format_data_topic

=cut

sub _format_sectiontext {
    my ( $web, $adata, $pref, $svh, $inh, $section, $sectionheader ) = @_;

    my %admin_data        = %{$adata};
    my %prefixes          = %{$pref};
    my %inhash            = %{$inh};
    my %source_value_hash = %{$svh};

    my $section_text = "";
    foreach my $field ( @{ $admin_data{$section}{"field order"} } ) {

        next if ( !defined $inhash{$field} || $inhash{$field} eq "" );
        next
          if (
               !defined $inhash{$field}{"value"}
            || $inhash{$field}{"value"} eq ""
            || $inhash{$field}{"value"} =~ /one per line/
            || $inhash{$field}{"value"} =~ /comma-delim/
            || ( ref $inhash{$field}{"value"} eq "ARRAY"
                && scalar @{ $inhash{$field}{"value"} } == 0 )
          );

        my ($fieldtext) =
          _make_fieldtext( \%inhash, \%admin_data, \%prefixes, $section,
            $field );
        next if ( $fieldtext eq "" );
        my ($sourcefieldtext) =
          _make_fieldtext( \%source_value_hash, \%admin_data, \%prefixes,
            $section, $field )
          if ( defined $source_value_hash{$field} );
        my $output = "| !$field | " . $fieldtext . "  | ";

# Generate a new field signature. If the topic exists, and this field hasn't been changed, is_edited will return the existing signature to re-use

        my $newfieldsig = Foswiki::Plugins::BioKbPlugin::BioKb::make_fieldsig(
            $web,                      "Data" . $inhash{"topicname"},
            $inhash{$field}{"source"}, $fieldtext,
            $sourcefieldtext,          $inhash{$field}{"date"},
            $inhash{$field}{"gen"},    $inhash{$field}{"user"},
            $field
        );
        $output .= "<small>$newfieldsig</small> |\n";
        $output = Foswiki::Plugins::BioKbPlugin::BioKb::_hide( $field, $output )
          if ( $field eq "Protein Sequence"
            || $field eq "DNA Sequence"
            || $field =~ /Codon/ );

        $section_text .= $output;
    }
    return $section_text;
}

=pod

Format the text of a single field- called from _format_sectiontext

=cut

sub _make_fieldtext {
    my ( $ih, $ad, $pf, $section, $field ) = @_;

    my %inhash     = %{$ih};
    my %admin_data = %{$ad};
    my %prefixes   = %{$pf};

    my $fieldtext = "";
    if ( !defined $inhash{$field}{"value"} || $inhash{$field}{"value"} eq "" ) {
        return;
    }

# Data has been passed through Foswiki function with spaces replaced by underscores as required

    # Hyperlink the entry to the source database

    if ( $field eq "Entry" && $inhash{"Entry"}{"value"} ne "" ) {
        my $entry = $inhash{"Entry"}{"value"};
        my $link;
        if ( defined $prefixes{ lc $inhash{"Entry"}{"source"} } ) {
            ( $link = $prefixes{ lc $inhash{"Entry"}{"source"} } ) =~
              s/VAL/$inhash{"Entry"}{"value"}/;
            $link      = "[[$link][" . $inhash{"Entry"}{"value"} . "]]";
            $fieldtext = $link;
        }
        else {
            $fieldtext = $entry;
        }
    }

    # We have some dropdown-associated fields. Format appropriately

    elsif ( defined $admin_data{$section}{$field}{"databases"} ) {
        if ( !defined $inhash{ $field . "_db" }{"value"} ) {
            die "No db field set for $field\n";
        }

        my @dbs     = @{ $inhash{ $field . "_db" }{"value"} };
        my @dblinks = @{ $inhash{$field}{"value"} };

        my %saw;
        my @unique_dbs = grep( !$saw{$_}++, @dbs );

        my %linkstrings;
        for ( my $i = 0 ; $i < scalar @dbs ; $i++ ) {
            my $link;
            next if ( !defined $dblinks[$i] || $dblinks[$i] eq "" );

            if ( !defined $prefixes{ lc $dbs[$i] } ) {
                $linkstrings{ $dbs[$i] } = $dblinks[$i];
            }
            else {
                ( $link = $prefixes{ lc $dbs[$i] } ) =~ s/VAL/$dblinks[$i]/;
                $dblinks[$i] =
                  Foswiki::Plugins::BioKbPlugin::MolecularBiology::find_kegg_path_name(
                    $dblinks[$i] )
                  if ( $dbs[$i] eq "KEGG PATH" );
                $linkstrings{ $dbs[$i] } .= "[[$link][" . $dblinks[$i] . "]]  ";
            }
        }
        foreach my $dbkey (@unique_dbs) {
            $fieldtext .=
              "*" . $dbkey . "*: " . $linkstrings{$dbkey} . " <br /> "
              if ( defined $linkstrings{$dbkey} );
        }
    }
    elsif ( ref $inhash{$field}{"value"} eq "ARRAY" ) {
        my @array = @{ $inhash{$field}{"value"} };
        for ( my $i = 0 ; $i < scalar @array ; $i++ ) {
            $array[$i] =~ s/[\n\r]//g;
            if ( $field eq "MeSH Terms" ) {
                $array[$i] .=
                    "  ( [["
                  . Foswiki::Func::getViewUrl( "", "PubmedSearch" )
                  . "?search="
                  . $array[$i]
                  . "\%5Bmh\%5D][References]] ) ";
            }
        }

        $fieldtext = join " <br /> ", @array;
    }
    else {
        $fieldtext = $inhash{$field}{"value"};
    }

    if (   $field eq "Protein Sequence"
        || $field eq "DNA Sequence"
        || $field eq "Codon Usage" )
    {
        $fieldtext =~ s/[\n\r]+/\<br \/\>\\\n/g;
        $fieldtext = "=$fieldtext=";
    }
    else {

        # Hide extended lists of summary data- e.g. MeSH terms

        if ( $section =~ /Summary/ ) {
            my @lines = split /[\n\r]/, $fieldtext;
            if ( scalar @lines > 5 ) {
                $fieldtext = join( "\n", @lines[ 0 .. 4 ] );
                $fieldtext .=
"&nbsp;&nbsp;&nbsp;&nbsp;%TWISTYSHOW{id=\"twisty$field\" link=\"more\" imgleft=\"%ICONURLPATH{toggleopen}%\"}%";
                $fieldtext .=
"%TWISTYTOGGLE{id=\"twisty$field\" start=\"hide\" mode=\"span\" remember=\"on\"}%"
                  . ( join "\n", @lines[ 5 .. ( scalar @lines - 1 ) ] )
                  . "%ENDTWISTYTOGGLE%";
                $fieldtext .=
"\n%TWISTYHIDE{id=\"twisty$field\" link=\"less\" imgleft=\"%ICONURLPATH{toggleopenleft}%\"}%\n";
            }
        }

        $fieldtext =~ s/[\n\r]+/\<br \/\>/g;
    }

# Remove trailing or leading whitespaces which can mess up text alignment in Foswiki

    $fieldtext =~ s/(^\s|\s$)//;
    return $fieldtext;

}

=pod

Wrap in a twisty to show and hide text

=cut

sub _hide {
    my ( $fieldname, $string ) = @_;

    $string =
"\n&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;%TWISTY{\nshowlink=\"Show $fieldname\"\nhidelink=\"Hide $fieldname\"\nshowimgleft=\"%ICONURLPATH{toggleopen-small}%\"\nhideimgleft=\"%ICONURLPATH{toggleclose-small}%\"\nstart=\"hide\"\n}%\n\n$string%ENDTWISTY{}%\n";

    return $string;
}

=pod

Take a set of data hashes and format it as a table

=cut

sub make_formatted_result_table {

# TOPIC NAMES AND DESCRIPTIONS FOR DISPLAY, IDS AS VALUES IN THE FORM TO BE USED TO RETRIEVE RECORDS AND POPULATE TOPICS

    my ( $web, $records, $tag, $start ) = @_;

    my %admin_data =
      %{ Foswiki::Plugins::BioKbPlugin::BioKb::read_topic_structure_admin($web)
      };

    my @records = @{$records};

    $start = 0 if ( !defined $start );

    my $output   = "";
    my $wikiname = Foswiki::Func::getWikiName();

    for ( my $i = 1 ; $i <= scalar @records ; $i++ ) {
        next if ( !defined $records[ $i - 1 ] );
        my %record = %{ $records[ $i - 1 ] };

        my $exist = Foswiki::Func::topicExists( $web, $record{"topicname"} );

        if ( defined $exist && $exist == 1 ) {
            $output .= "| "
              . ( $start + $i ) . " | [["
              . $record{"topicname"}
              . "]]  | "
              . $record{"description"} . " |";
        }
        else {
            $output .= "| "
              . ( $start + $i ) . " | !"
              . $record{"topicname"} . " | "
              . $record{"description"} . " |";
        }

        # Add the changes buttons if the user has permissions

        if (
            Foswiki::Func::checkAccessPermission( "CHANGE", $wikiname, undef,
                $record{"topicname"}, $web ) == 1
          )
        {
            my %checkbox;
            if ( defined $exist && $exist == 1 ) {
                %checkbox = (
                    -name    => $tag . '_addids',
                    -id      => 'addids',
                    -class   => 'fancy-box',
                    -value   => $record{"id"}{"value"},
                    -label   => "",
                    -checked => "checked"
                );
            }
            else {
                %checkbox = (
                    -name  => $tag . '_addids',
                    -id    => 'addids',
                    -class => 'fancy-box',
                    -value => $record{"id"}{"value"},
                    -label => ""
                );
            }

            $output .= CGI::checkbox(%checkbox) . "|";
        }
        $output .= "\n";
    }

    $output .= CGI::hidden( -name => "submitted", -value => 1 ) . "\n";

    return $output;
}

=pod

Add the utitility functions to result forms produced in any topic type

=cut

sub wrap_result_table {
    my ( $web, $topic, $table, $title, $next ) = @_;

    $next = "" if ( !defined $next );

    my $formname = $title . "search";
    my $savebar =
        "<div class='save'>"
      . CGI::submit( -name => "Save changes", -class => "twikiSubmit" )
      . CGI::checkbox(
        -id      => "checkall",
        -onClick => "checkAll(document.$formname.addids,this)"
      )
      . "Select/Deselect All"
      . "&nbsp;"
      . CGI::checkbox(
        -name  => "confirm_delete",
        -label => "Confirm for deletion of unticked items"
      ) . "</div>\n";

    Foswiki::Func::addToHEAD( "BioKb",
"<script type=\"text/javascript\" src=\"%PUBURL%/%TWIKIWEB%/BioKbPlugin/mootools.js\"></script>\n<script type=\"text/javascript\" src=\"%PUBURL%/%TWIKIWEB%/BioKbPlugin/moocheck.js\"></script>\n<script type=\"text/javascript\" src=\"%PUBURL%/%TWIKIWEB%/BioKbPlugin/checkAllToggle.js\"></script>\n\n"
    );

    my $key = Foswiki::Plugins::BioKbPlugin::BioKb::search_key();

    my $output =
        "<div class='results'>\n\n$key\n\n<div class='bar'>" 
      . $next
      . CGI::start_form( -name => $formname, -method => 'post' )
      . $savebar
      . $table
      . $savebar
      . CGI::end_form()
      . $next
      . "</div></div>";

    return $output;
}

=pod

Process bulk results tables, checking whether each topic already exists, and based on arguments from the input, add or remove topics as necessary.

=cut

sub save_changes {
    my ( $session, $topic, $web, $rec, $datatype, $addids ) = @_;

    my @records  = @{$rec};
    my %addids   = map { $_, 1 } @{$addids};
    my $wikiname = Foswiki::Func::getWikiName();

# Add in some date to particular topic types which it was inappropriate to do before they were selected

    for ( my $i = 0 ; $i < scalar @records ; $i++ ) {
        next if ( !defined $records[$i] );
        my %record = %{ $records[$i] };
        my $exists = Foswiki::Func::topicExists( $web, $record{"topicname"} );

# Don't bother if this record is not tagged for addition- or if it's already present

        next
          if ( !defined $addids{ $record{"id"}{"value"} }
            || ( defined $exists && $exists == 1 ) );
        $record{"type"} = $datatype;
        if ( $datatype eq "Gene" ) {

            my @ihop_syns =
              Foswiki::Plugins::BioKbPlugin::MolecularBiology::_get_ihop_synonyms(
                @{ $record{"Title"}{"value"} }[0] );
            %record = %{
                Foswiki::Plugins::BioKbPlugin::MolecularBiology::_add_kegg_orthologs(
                    $web, lc $datatype, \%record )
              };

            if ( scalar @ihop_syns > 0 ) {
                push @{ $record{"Synonyms"}{"value"} },  \@ihop_syns;
                push @{ $record{"Synonyms"}{"source"} }, "iHOP";
            }

            $records[$i] = \%record;
        }
        elsif ( lc $datatype eq "pathway" ) {
            %record = %{
                Foswiki::Plugins::BioKbPlugin::MolecularBiology::_add_kegg_orthologs(
                    $web, lc $datatype, \%record )
              };
        }
        $records[$i] = \%record;
    }

    for ( my $i = 0 ; $i < scalar @records ; $i++ ) {
        next if ( !defined $records[$i] );
        my %record = %{ $records[$i] };

        my $exists = Foswiki::Func::topicExists( $web, $record{"topicname"} );
        my %perm_type = ( 0 => "CREATE", 1 => "CHANGE" );

        if (
            Foswiki::Func::checkAccessPermission( defined $exists
                  && $perm_type{$exists},
                $wikiname, undef, $record{"topicname"}, $web ) == 1
          )
        {

# Add this reference if its entry has been ticked, the user has the appropriate permissions, and it does not yet exist

            my $id = $record{"id"}{"value"};
            my $exists =
              Foswiki::Func::topicExists( $web, $record{"topicname"} );

            if ( defined $addids{$id} ) {
                if ( !defined $exists || $exists != 1 ) {
                    if ( $datatype eq "Reference" ) {
                        my $input =
                          Foswiki::Plugins::BioKbPlugin::Literature::format_article(
                            $web, \%record );
                        Foswiki::Plugins::BioKbPlugin::BioKb::create_topic(
                            $session,             $web,
                            $topic,               "Reference",
                            $record{"topicname"}, $record{"Title"}{"value"},
                            $input,               undef
                        );
                    }
                    else {
                        build_topic( $session, \%record, $topic, $web, 1 );
                    }
                }
            }

# Delete this topic if it's entry has been unticked, the user has the appropriate permissions, and it does exist

            elsif ( defined $exists && $exists == 1 ) {
                remove_topic( $web, $record{"topicname"} );
            }
        }
    }
}

=pod

Compose a key indicating the symbols used for topic status

=cut

sub search_key {
    my %icons = (
        "Topic present/ queued for addition" => "accept2",
        "Topic absent/ marked for deletion"  => "not2"
    );
    my $text = "| *Topic status- click icons to toggle and save changes*";
    foreach my $icon ( keys %icons ) {
        $text .=
            " | <img src=\"%PUBURL%/%TWIKIWEB%/BioKbPlugin/_BioKb_"
          . $icons{$icon}
          . ".png\"> | $icon |";
    }
    return $text;
}

##########################################################################################
#                                                                                        #
#                                 MeSH Handling                                          #
#                                                                                        #
##########################################################################################

=pod

Medical Subject headings is a useful source of Text summaries and of course MeSH terms. This subroutine tries to find releated records in MeSH, and copies the appropriate data across. Be aware that this takes a while as the MeSH dictionary is large. This won't happen in bulk additions (e.g. via AdminSeed), but will happen on manual topic creation, and if the 'Add MeSH data' button is pressed.

=cut

sub _add_mesh_data {

    my ( $web, @records ) = @_;

    my %syn_sets;
    foreach my $rec (@records) {
        my %record = %{$rec};
        my ($title) = @{ $record{"Title"}{"value"} };
        $syn_sets{$title} = [$title];
        push @{ $syn_sets{$title} }, split /\n/,
          @{ $record{"Synonyms"}{"value"} }[0]
          if ( defined $record{"Synonyms"}{"value"} );
    }
    my ( $mt, $ms ) = _get_mesh_terms(%syn_sets);
    my %mesh_terms     = %{$mt};
    my %mesh_summaries = %{$ms};

    for ( my $i = 0 ; $i < scalar @records ; $i++ ) {
        my %record = %{ $records[$i] };
        my ($title) = @{ $record{"Title"}{"value"} };
        if ( !defined $record{"Text Summary"}{"value"} ) {
            push @{ $record{"Text Summary"}{"value"} }, $mesh_summaries{$title};
            push @{ $record{"Text Summary"}{"source"} }, "MeSH";
        }
        push @{ $record{"MeSH Terms"}{"value"} },  $mesh_terms{$title};
        push @{ $record{"MeSH Terms"}{"source"} }, "MeSH";
        $records[$i] = \%record;
    }

    return @records;
}

=pod

Business end of MeSH searchign and parsing

=cut

sub _get_mesh_terms {

    my %searchtermsin = @_;
    my %matches;
    my %summaries;

    my %re_searchterms;

# Convert search terms to regexes and make sure we don't search twice when two search terms reduce to the same regex

    foreach my $title ( keys %searchtermsin ) {
        my @searchterms = @{ $searchtermsin{$title} };
        for ( my $i = 0 ; $i < scalar @searchterms ; $i++ ) {
            $searchterms[$i] =~ s/\W/\\W/gi;
        }
        my %saw;
        @searchterms = grep( !$saw{$_}++, @searchterms );

        $searchtermsin{$title} = \@searchterms;
        $re_searchterms{$title} = "(" . ( join "|", @searchterms ) . ")";
    }

    my $workarea          = Foswiki::Func::getWorkArea("BioKbPlugin");
    my $mesh_descriptions = "$workarea/mesh_descriptions.txt";

    if ( !-e $mesh_descriptions ) {
        throw Foswiki::OopsException(
            'generic',
            params => [
"Please obtain the ASCII Medical subject headings descriptor file and place it at $mesh_descriptions\n",
                "",
                "",
                ""
            ]
        );
    }

    open( DESC, $mesh_descriptions )
      or die "Can't open descriptions file $mesh_descriptions\n";
    my $record;

    my %relevant_summaries;
    my %exact_candidates;

    while ( my $line = <DESC> ) {

        # We've read a complete record

        if ( $line =~ /^\*/ ) {

# Skip if we've not got a complete record yet, or if there's not a match to any of the terms

            next if ( !defined $record );

            # Check the synonyms provided for each of the titles

            foreach my $title ( keys %re_searchterms ) {
                my $pattern = $re_searchterms{$title};

                if ( $record =~ /\W$pattern(\W|$)/im ) {
                    my ($recordtitle) = $record =~ /^MH\s+\=\s+(.+)/m;
                    push @{ $matches{$title} }, $recordtitle;

# Consider a match exact if a slightly fuzzy match can be produced next to the MESH heading or an ENTRY line then we can use the MeSH summary
# Check each synonym individually

                    foreach my $st ( @{ $searchtermsin{$title} } ) {
                        if ( $record =~ /(MH|ENTRY)\s+\=\s+$st($|\s*[\|])/im ) {
                            ( $relevant_summaries{$recordtitle} ) =
                              $record =~ /^MS\s+\=\s+(.+)/m;
                            $exact_candidates{$title}{$recordtitle} = 0
                              if ( !defined $exact_candidates{$title}
                                {$recordtitle} );
                            $exact_candidates{$title}{$recordtitle}++;
                        }
                    }
                }

            }

            undef $record;
        }

        # Add lines to a new record

        $record .= $line;
    }
    close(DESC);

    foreach my $title ( keys %exact_candidates ) {
        my %hash = %{ $exact_candidates{$title} };
        my $exact;
        foreach my $key ( keys %hash ) {
            if (
                   !defined $exact
                || $hash{$key} > $hash{$exact}
                || (
                    (
                        $hash{$key} == $hash{$exact}
                        && length $key > length $exact
                    )
                )
              )
            {
                $exact = $key;
            }
        }
        $summaries{$title} = $relevant_summaries{$exact};
    }
    foreach my $match ( keys %matches ) {
        $matches{$match} = join "\n", @{ $matches{$match} };
    }

    return ( \%matches, \%summaries );

}

#####################################################
#                                                   #
#           Topic addition/ removal                 #
#                                                   #
#####################################################

=pod

Does what it says- deals with removing all components of a topic, including data and dictionary

=cut

sub remove_topic {
    my ( $web, $topic ) = @_;

    remove_from_dictionary( $web, $topic );
    Foswiki::Func::moveTopic( $web, $topic, $Foswiki::cfg{TrashWebName},
        $topic );
    Foswiki::Func::moveTopic(
        $web,
        "Data" . $topic,
        $Foswiki::cfg{TrashWebName},
        "Data" . $topic
    );
    return 1;
}

=pod

Create data and free-text parts of a content topic, amending the dictionary as appropriate

=cut

sub create_topic {
    my (
        $session, $web,     $topic, $type, $dest_topic,
        $title,   $content, $terms, $dataonly
    ) = @_;

    my $query  = Foswiki::Func::getCgiQuery();
    my @params = $query->param();

    my $wikiname = Foswiki::Func::getWikiName();
    if (
        Foswiki::Func::checkAccessPermission( "CHANGE", $wikiname, undef,
            $dest_topic, $web ) != 1
      )
    {
        throw Foswiki::OopsException(
            'accessdenied',
            def    => 'topic_access',
            web    => $web,
            topic  => $topic,
            params => [ 'save', $dest_topic ]
        );
    }

# Save the main topic- this will import the data
# Assemble the Meta information. Important to use putKeyed where multiple values for the same thing are required- e.g. preferences

    if ( !defined $dataonly || $dataonly eq "" ) {
        my $meta = new Foswiki::Meta();
        $meta->putAll(
            'PREFERENCE',
            {
                name  => 'VIEW_TEMPLATE',
                title => 'VIEW_TEMPLATE',
                value => 'mainlayout',
                type  => 'Set'
            },
            {
                name  => 'TOPIC_TYPE',
                title => 'TOPIC_TYPE',
                value => $type,
                type  => 'Set'
            }, # This allows the system to indentify the type of topic we're dealing with
        );

        my $text = "\n---+ $title\n\n\n";
        my $templateexists =
          Foswiki::Func::topicExists( $web, $type . "Template" );
        if ( defined $templateexists && $templateexists == 1 ) {
            my ( $templatemeta, $templatetext ) =
              Foswiki::Func::readTopic( $web, $type . "Template" );
            $text .= $templatetext;
        }

        Foswiki::Func::saveTopic( $web, $dest_topic, $meta, $text,
            { forcenewrevision => 1 } );
        _check_saved( $web, $dest_topic );
    }

    # Save the data topic, which will be imported

    my $meta = new Foswiki::Meta();
    my %view = (
        "name"  => "VIEW_TEMPLATE",
        "title" => "VIEW_TEMPLATE",
        "type"  => "Set",
        "value" => "data"
    );
    $meta->putKeyed( "PREFERENCE", \%view );

    # Prevent non-admin users making manual changes to the data topics

    my %change = (
        "name"  => "ALLOWTOPICCHANGE",
        "title" => "ALLOWTOPICCHANGE",
        "value" => "AdminGroup"
    );
    $meta->put( "ALLOWTOPICCHANGE", \%change );

    my $typeclass;
    ( $typeclass = $type ) =~ s/\s/_/g;

    Foswiki::Func::saveTopic(
        $web,
        "Data" . $dest_topic,
        $meta,
        "<div id='dataheader' class='"
          . ( lc $typeclass )
          . "'>\n---++ $type</div>$content",
        { forcenewrevision => 1 }
    );
    _check_saved( $web, "Data" . $dest_topic );

    Foswiki::Plugins::BioKbPlugin::BioKb::add_to_dictionary( $session, $web,
        $dest_topic, $terms );

    return $dest_topic;
}

=pod

Make sure the specified topic was saved

=cut

sub _check_saved {
    my ( $web, $topic ) = @_;
    my $exists = Foswiki::Func::topicExists( $web, $topic );

    if ( !defined $exists || $exists != 1 ) {
        throw Foswiki::OopsException( 'generic',
            params => [ "Could not create $topic", "", "", "" ] );
    }
}

#####################################################
#                                                   #
#                 Topic parsing                     #
#                                                   #
#####################################################

=pod

Parse out topic content and return data as a hash

=cut

sub parse_topic_data {
    my ( $topic, $web, $type, $text ) = @_;

    my %admin_data =
      %{ Foswiki::Plugins::BioKbPlugin::BioKb::read_topic_structure_admin($web)
      };

    %admin_data = %{ $admin_data{$type} };

    my %result;

    my $section;
    my $field;

    my $existing = $text;

    if ( !$text ) {
        my $meta;
        ( $meta, $text ) = Foswiki::Func::readTopic( $web, $topic );
    }

    $text =~
s/&nbsp;&nbsp;&nbsp;&nbsp;\%TWISTYSHOW\{id=\".*\" link=\"more\" imgleft=\"\%ICONURLPATH\{toggleopen\}\%\"\}\%\%TWISTYTOGGLE\{id=\".*\" start=\"hide\" mode=\"span\" remember=\"on\"\}\%\<br \/\>/\<br \/\>/g;
    $text =~
s/\%ENDTWISTYTOGGLE\%\<br \/\>\%TWISTYHIDE\{id=\".*\" link=\"less\" imgleft=\"\%ICONURLPATH\{toggleopenleft\}\%\"\}\%//g;
    $text =~ s/\n*(&nbsp;)*\%TWISTY.*?\n\}\%//gs;
    $text =~ s/\%ENDTWISTY\{\}\%//g;

    my @lines = split /\n/, $text;

    while ( scalar @lines > 0 ) {

        my $line = shift @lines;
        if ( $line =~ /\-\-\-\+\+\+\+\s+(.+)/ ) {
            $section = $1;
            $section =~ s/\s+$//;
        }
        elsif ( defined $section ) {
            if ( $line =~ /^\|\s*/ ) {
                while ( $line !~ /\s*\|\s*$/ ) {
                    my $newline = shift @lines;
                    $line .= $newline;
                }

                my @dat = split /\s*\|\s*/, $line;
                next if ( scalar @dat < 3 );
                my ( $foo, $val, $datesig );
                ( $foo, $field, $val, $datesig ) = @dat;
                $field   =~ s/^\!//;
                $datesig =~ s/\<\/?small\>//g;

                $field =~ s/^!//;
                my ( $source, $gen, $date, $user ) = $datesig =~
/\(\!?(.+)\)\D*(Gen|Ed)\.\D*(\d+\/\d+\/\d+)(?:.*\[\[[^\]]+\]\[([^\]]*))?/;
                $val =~ s/\<\/?noautolink\>//g;
                my @vals = split /\n/, $val;

                $val =~ s/\s*\<br \/\>\\?\s*/\n/g;
                $val =~ s/^[\=\\]//mg;
                $val =~ s/\=$//mg;

                if ( defined $admin_data{$section}{$field}{"databases"} ) {
                    my ( $ids, $dbs ) = _read_dbline( $topic, $val, $field );
                    $val = $ids;
                    push @{ $result{ $field . "_db" }{"value"} },  $dbs;
                    push @{ $result{ $field . "_db" }{"source"} }, $source;
                }
                else {

                    # Un-linkify

                    $val =~ s/\[\[(?:[^\]]+\]\[)?([^\]]+)\]\]/$1/g;
                    $val =~ s/ *\(\s*References\s*\) *//g;
                }

                push @{ $result{$field}{"value"} },  $val;
                push @{ $result{$field}{"date"} },   $date;
                push @{ $result{$field}{"gen"} },    $gen;
                push @{ $result{$field}{"user"} },   $user;
                push @{ $result{$field}{"source"} }, $source;
            }
        }
    }

    return ( \%result );
}

=pod

Parse data lines

=cut

sub _read_dbline {
    my ( $topic, $lines, $field ) = @_;

    my ( @dblist, @idlist, @urllist );

    foreach my $line ( split /\n/, $lines ) {
        next if ( $line !~ /\*([\w\- ]+)\*\:\s*(.+)/ );
        my ( $db, $ids ) = $line =~ /\*([\w\- ]+)\*\:\s*(.+)/;
        my @ids  = $ids =~ /\[\[[^\]]+\]\[([^\]]+)\]\]/g;
        my @urls = $ids =~ /\[\[([^\]]+)\]\[[^\]]+\]\]/g;
        for ( my $i = 0 ; $i < scalar @ids ; $i++ ) {
            push @dblist, $db;
            if ( $db eq "KEGG PATH" ) {
                my ($id) = $urls[$i] =~ /\?([^\]]+)/;
                push @idlist, $id;
            }
            else {
                push @idlist, $ids[$i];
            }
        }
    }
    return \@idlist, \@dblist;
}

#####################################################
#                                                   #
#                      Utility                      #
#                                                   #
#####################################################

sub untaint {
    my ( $strings, $allowed, $tag ) = @_;
    my @strings = @{$strings};

    # Default string with characters we can expect to used reasonably

    $allowed =
"\\s\\w\\,\\.\\[\\]\\:\\-\\(\\)\\*\\+\\-\\<\\>\\%\\/\\?\\=\\&\\\"\\\'\\n\#\;\!"
      if ( !defined $allowed );
    my @newstrings;

    for ( my $i = 0 ; $i < scalar @strings ; $i++ ) {
        my $string = $strings[$i];

        my @unallowed = $string =~ /([^$allowed])/g;
        foreach my $ua (@unallowed) {
            $string =~ s/$ua//g;
        }

        my ($newstring) = $string =~ /([$allowed]+)/m;
        push @newstrings, $newstring;
    }
    return @newstrings;
}

#####################################################
#                                                   #
#        Dictionary + link Manipulation             #
#                                                   #
#####################################################

=pod

Return the topic that a given term points to

=cut

sub consult_dictionary {

    my ( $web, $interm ) = @_;
    my $outtopic;

    my %dictionary = %{ read_dictionary($web) };
    $outtopic = $dictionary{$interm} if ( defined $dictionary{$interm} );

    return $outtopic;
}

=pod

Clean up the dictionary when you remove a topic, removing all associated links as we do

=cut

sub remove_from_dictionary {
    my ( $web, $topic_to_remove ) = @_;

    my %dictionary = %{ read_dictionary($web) };

    my %reverse;
    foreach my $term ( keys %dictionary ) {
        $term =~ s/[\r\n]//g;
        $term =~ s/\s+$//;
        push @{ $reverse{ $dictionary{$term} } }, $term if ( length $term > 3 );
    }

    my $content = "%REFRESH_LINKS{button=\"1\" all=\"1\"}%\n\n";
    foreach my $topic ( sort keys %reverse ) {
        next if ( $topic eq $topic_to_remove );
        $content .=
          "| $topic | " . ( join "+", @{ $reverse{$topic} } ) . " |\n";
    }

    my $meta = new Foswiki::Meta();
    my %parent = ( "name" => "Admin" );
    $meta->put( "TOPICPARENT", \%parent );
    my %change = (
        "name"  => "ALLOWTOPICCHANGE",
        "title" => "ALLOWTOPICCHANGE",
        "value" => "AdminGroup"
    );
    $meta->put( "ALLOWTOPICCHANGE", \%change );

    Foswiki::Func::saveTopic( $web, "AdminDictionary", $meta, $content );
    _remove_all_links( $web, $topic_to_remove );
}

=pod

Remove links- all links to a topic if supplied, or all explicit links involving a supplied set of terms

=cut

sub _remove_all_links {
    my ( $web, $topic, @terms ) = @_;

    # Locate topics with explicit links to this topic

    if ( !defined $topic ) {
        $topic = "[^\]\[]+";
    }
    my $terms = "[^\]\[]+";
    if ( scalar @terms > 0 ) {
        $terms = "(" . ( join "|", @terms ) . ")";
    }

    my $regex = "\\\[\\\[$topic\\\]\\\[$terms\\\]\\\]";

    my $result = Foswiki::Func::searchInWebContent(
        $regex, $web,
        [ Foswiki::Func::getTopicList($web) ],
        { type => "regex", casesensitive => 0, files_without_match => 1 }
    );

    foreach my $top ( keys %$result ) {
        my ( $meta, $text ) = Foswiki::Func::readTopic( $web, $top );
        $text =~ s/\[\[$topic\]\[($terms)\]\]/$1/g;
        Foswiki::Func::saveTopic( $web, $top, $meta, $text );
    }
}

=pod

Add a term to the dictionary, making all appropriate links

=cut

sub add_to_dictionary {
    my ( $session, $web, $dest_topic, $terms ) = @_;

    my %dictionary = %{ read_dictionary($web) };

    my @old_terms;

  TERM: foreach my $term ( @{$terms} ) {

        $term =~ s/[\r\n]//g;
        $term =~ s/\s+$//;
        next if ( $term !~ /\w/ || length $term < 4 );

# Link this term to the new topic. If this term is already linked, remove existing links that use this term

        if ( defined $dictionary{ lc $term } ) {
            push @old_terms, lc $term;
        }

        $dictionary{ lc $term } = $dest_topic;
    }

# Remove links via the dead terms- we've worked out these should be part of a longer term linked somewhere else

    if ( scalar @old_terms > 0 ) {
        _remove_all_links( $web, undef, @old_terms );
    }

    # Now re-save the dictionary

    my %reverse;
    foreach my $term ( keys %dictionary ) {
        push @{ $reverse{ $dictionary{$term} } }, $term if ( length $term > 3 );
    }

    my $content = "%REFRESH_LINKS{button=\"1\" all=\"1\"}%\n\n";
    foreach my $topic ( sort keys %reverse ) {
        my $exists     = Foswiki::Func::topicExists( $web, $topic );
        my $dataexists = Foswiki::Func::topicExists( $web, "Data" . $topic );

        next
          if ( ( !defined $exists || $exists == 0 )
            && ( !defined $dataexists || $dataexists == 0 ) );
        $content .=
          "| $topic | " . ( join "+", @{ $reverse{$topic} } ) . " |\n";
    }

    my $meta = new Foswiki::Meta();
    my %parent = ( "name" => "Admin" );
    $meta->put( "TOPICPARENT", \%parent );

    # This will prevent non-admin users making manual changes to the dictionary

    my %change = (
        "name"  => "ALLOWTOPICCHANGE",
        "title" => "ALLOWTOPICCHANGE",
        "value" => "AdminGroup"
    );
    $meta->put( "ALLOWTOPICCHANGE", \%change );

    Foswiki::Func::saveTopic( $web, "AdminDictionary", $meta, $content );

    # Add links to existing topics from this one

    _add_links_to_all( $session, $web, undef, $dest_topic );

    # Add links to this topic from all existing topics

    _add_links_to_all( $session, $web, $dest_topic );

}

=pod

Make sure all the content topics are linked appropriately. Add links to $topicto from everywhere else- or from a specific topic if supplied (useful when creating a new one).

=cut

sub _add_links_to_all {

    my ( $session, $web, $topicto, $topicfrom ) = @_;

    # Get the dictionary and reverse it so we can relate topic to terms

    my %dictionary = %{ read_dictionary($web) };
    my %reverse;
    foreach my $term ( keys %dictionary ) {
        push @{ $reverse{ $dictionary{$term} } }, $term if ( length $term > 3 );
    }

# If particular topics have been supplied, we'll insert links into these only. Otherwise just use all topics (excluding admin etc)

    my @topicsfrom;
    if ( defined $topicfrom ) {
        @topicsfrom = ( $topicfrom, "Data" . $topicfrom );
    }
    else {
        @topicsfrom =
          grep { !/^(Web|Admin|Stats)/ } Foswiki::Func::getTopicList($web);
    }

# Particular targets might have been supplied- e.g. where a new topic has been create that might need linking to from everywhere else

    my @topiclist;
    if ( defined $topicto ) {
        @topiclist = ($topicto);
    }
    else {
        @topiclist = keys %reverse;
    }

    foreach my $topicname (@topiclist) {

        next if ( !defined $reverse{$topicname} );

        my @terms = @{ $reverse{$topicname} };

# PRETTY COMPLEX REGEXES ASSEMBLED HERE. THIS TOOK AGES TO SET UP- TINKER AT YOUR PERIL! OBJECTIVES:
#
# - Don't even open files that don't need messing with- so pass the appropriate grep regex syntax to prevent this happening. This is slightly, but significantly different from perl regex syntax
# - Allow links both to bare terms, and those involved in other links
# - Over-write linked terms shorter than the current, but not longer. This means searching for terms not already inside existing links ([])
# - Don't overwrite terms already linked to this topic. This wouldn't matter, and replacing itself would introduce no changes. except it causes us to open files when we don't need to, and slows us down

# Parts to allow for over-writing of existing links, and widening of terms - e.g. links to the word 'renin' would be overwritten by 'renin angiotensin system'.

        my $beforelink = "(?:\\[\\[\\w+\\]\\[)?";
        my $firstbeforelink =
            "(?:\\[\\["
          . reg_negate($topicname)
          . "\\]\\[)?"
          ; # If the whole term is already linked, exclude it. This requires some negation hackery done by the reg-negate subroutine.
        my $afterlink = "(?:\\]\\])?";

# Replace all non-alphanumerics so that hyphens, spaces etc will be considered equally. Allow pluralised versions of terms, i.e. [term]'s?'

        for ( my $i = 0 ; $i < scalar @terms ; $i++ ) {
            $terms[$i] = $firstbeforelink
              . (
                join $afterlink . "[^A-Za-z0-9_]+" . $beforelink,
                split /\W+/, $terms[$i]
              )
              . "s?"
              . $afterlink;
        }

# Don't match within a word- make sure surrounding characters are non-alphanumeric (or end-of-line)

        my $regex =
            "((?:^|\\])[^\\[\\<]*[^A-Za-z0-9\\=\\[]|^)" . "("
          . ( join "|", @terms ) . ")"
          . "(\$|[^A-Za-z0-9\\=][^\>\]]*(?:\$|\\[))";

# grep doesn't like perl's '?:' non-matching syntax, but captures are irrelevant in the initial search anyway, so create a different version of the regex for searching, lacking '?:'

        my $egrepregex;
        ( $egrepregex = $regex ) =~ s/\?\://g;

# Use Foswiki's search routine (which calls grep) to find topics with changes needed

        my $result =
          Foswiki::Func::searchInWebContent( $egrepregex, $web, [@topicsfrom],
            { type => "regex", casesensitive => 0, files_without_match => 0 } );

# If the search returned any matches, open these topics and make the required changes

        foreach my $topic ( keys %$result ) {

            # Only want 'content' topics

            next if ( $topic =~ /^(Web|Admin|Stats)/ );
            my ( $meta, $text ) = Foswiki::Func::readTopic( $web, $topic );

# Create a copy of the text so we can check later if changes have been made and not re-save unnecessarily

            my $newtext = $text;

            # Remove links within links

            while ( $newtext =~ /$regex/i ) {
                $newtext =~ s/$regex/$1\[\[$topicname\]\[$2\]\]$3/ig;
                $newtext =~
s/(\[\[[^\[\]]+\]\[[^\[\]]*)\[\[[^\[\]]*\]\[([^\[\]]*)\]\]([^\[\]]*\]\])/$1$2$3/g;
            }

            # Save the changes if necessary

            if ( $newtext ne $text ) {

                # Re-save the text

                my $wikiname = Foswiki::Func::getWikiName();
                if (
                    Foswiki::Func::checkAccessPermission( "CHANGE", $wikiname,
                        undef, $topic, $web ) != 1
                  )
                {
                    throw Foswiki::OopsException(
                        'accessdenied',
                        def    => 'topic_access',
                        web    => $web,
                        topic  => $topic,
                        params => [ "CHANGE", $session->security->getReason() ]
                    );
                }

                Foswiki::Func::saveTopic( $web, $topic, $meta, $newtext );
            }
        }
    }
}

=pod

Contruct a regex that will exclude matches to a given word. Modified to match extensions/ substrings of the excluded word- e.g. a supplied 'foo' would not match, but 'foof' would

=cut

sub reg_negate {
    my $string  = shift;
    my $partial = "";
    my @branches;

    foreach my $c ( split "", $string ) {
        push @branches, $partial . "[^$c]";
        $partial .= $c;
    }

# Basically what we're doing here is matching any alphanumeric string of a different length to the input, mis-matching at any character, or greater than its length

    return
        "(?:\\w{1,"
      . ( ( length $string ) - 1 )
      . "}|\\w{"
      . ( ( length $string ) + 1 ) . ",}|"
      . join( "|", @branches )
      . "|$partial\\w+)";
}

=pod

Read in the dictionary for your BioKb web

=cut

sub read_dictionary {

    my $web = shift;
    my %dictionary;

    if ( Foswiki::Func::topicExists( $web, "AdminDictionary" ) ) {
        my ( $meta, $dictionary_text ) =
          Foswiki::Func::readTopic( $web, "AdminDictionary" );
        foreach my $line ( split /\n/, $dictionary_text ) {
            chomp $line;
            if ( $line =~ /\| ([^\|]+) \| ([^\|]+) \|/ ) {
                my ( $topic, $terms ) = ( $1, $2 );
                foreach my $term ( split /\+/, $terms ) {
                    next if ( length $term < 4 );
                    $dictionary{$term} = $topic;
                }
            }
        }
    }
    return \%dictionary;
}

1
