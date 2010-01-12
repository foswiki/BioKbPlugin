package Foswiki::Plugins::BioKbPlugin::Literature;

use strict;

use Scalar::Util qw(tainted);
use LWP::Simple;

select( ( select(STDOUT), $| = 1 )[0] );

##########################################################################################
#                                                                                        #
#                                     Interface                                          #
#                                                                                        #
##########################################################################################

=pod

Make a search form to retrieve references for annotation

=cut

sub make_search_form {

    my ( $session, $params, $topic, $web ) = @_;

    my $query  = Foswiki::Func::getCgiQuery();
    my @params = $query->param();
    my $output;

    if ( scalar @params < 2 ) {
        $output = "<div id=\"literature\">\n---++ Search Pubmed\n\n"
          . CGI::start_form(
            -id     => "pubmedsearchform",
            -name   => "pubmedsearchform",
            -action => Foswiki::Func::getViewUrl( $web, $topic ),
            -method => 'get'
          )
          .

          CGI::hidden(
            -name     => "type",
            -default  => $query->param("type"),
            -override => 1
          )
          .

          "\n---+++ Search all fields\n\n"
          . "| *Search terms*: &nbsp;|"
          . CGI::textfield( -name => "ALL", -size => 50, -maxlength => 50 )
          . "|\n"
          .

          "\n---+++ Search specific fields\n\n" .

          "| Words in title: | "
          . CGI::textfield( -name => "TI", -size => 20, -maxlength => 50 )
          . "| Volume: |"
          . CGI::textfield( -name => "VI", -size => "20", -maxlength => "5" )
          . "|\n"
          .

          "| Words in title or abstract | "
          . CGI::textfield( -name => "TIAB", -size => "20", -maxlength => "50" )
          . "| Issue: |"
          . CGI::textfield( -name => "IP", -size => "20", -maxlength => "5" )
          . "|\n"
          .

          "| Author:| "
          . CGI::textfield( -name => "AU", -size => "20", -maxlength => "30" )
          . "| First page number:|"
          . CGI::textfield( -name => "PG", -size => "20", -maxlength => "5" )
          . "|\n"
          .

          "| First author: | "
          . CGI::textfield( -name => "1AU", -size => "20", -maxlength => "15" )
          . "| Publication date: | "
          . CGI::textfield( -name => "DP", -size => "20", -maxlength => "10" )
          . "|\n"
          .

          "| Journal title: |"
          . CGI::textfield( -name => "TA", -size => "20", -maxlength => "100" )
          . "| !MeSH Term: | "
          . CGI::textfield( -name => "MH", -size => "20", -maxlength => "100" )
          . " |\n"
          . "|||||\n" . "| "
          . CGI::radio_group(
            -name      => 'neworold',
            -values    => [ 'all', 'newonly', 'oldonly' ],
            -default   => 'all',
            -linebreak => 0,
            -labels    => {
                "newonly" => "new only",
                "oldonly" => "old only",
                "all"     => "all"
            }
          )
          . "||||\n"
          .

          "\n---++ Add a specific paper\n\n" 
          . "| !PubMed ID(s): | "
          . CGI::textfield(
            -name      => "pubmed_ids_manual",
            -size      => 50,
            -maxlength => "100"
          )
          . "|\n"
          . "| Reason for adding: | "
          . CGI::textarea( -name => "reason", -rows => 5, -columns => 50 )
          . "|\n"
          .

          "---++\n\n|  "
          . CGI::submit( -class => "twikiSubmit", -value => "Search" ) . "  |\n"
          . CGI::end_form()
          . "</div>\n\n";
    }

    else {
        $output = search_pubmed( $session, $params, $topic, $web );
    }
    return $output;
}

=pod

MAKE A TABLE LISTING THE RESULTS OF THE SEARCH AND ADDING BUTTONS FOR MODIFICATION IF THE USER HAS THE APPROPRIATE PERMISSIONS

=cut

sub _make_search_result_form {

    my ( $web, $topic, $query, $pagelimit ) = @_;

    my @ids = split /,/, $query->param("pubmed_ids");
    my @articles = @{ get_by_pubmed_id(@ids) };

    for ( my $i = 0 ; $i < scalar @articles ; $i++ ) {
        next if ( !defined $articles[$i] );
        my $article = $articles[$i];
        my %art     = %{$article};
        $art{"description"} = $art{"Title"}{"value"};
        $art{"topicname"}   = $art{"Key"}{"value"};
        ( $art{"id"}{"value"}, $art{"id"}{"source"} ) =
          ( $art{"PubMed ID"}{"value"}, "PubMed" );
        $articles[$i] = \%art;
    }

    # Create the table

    my $table =
      Foswiki::Plugins::BioKbPlugin::BioKb::make_formatted_result_table( $web,
        \@articles, "references", $query->param("position") );

    $table .= "\n" . _save_params( $web, $query );

    # Wrap the table in a form structure and add some buttons

    my $next;
    if ( $query->param("count") > $pagelimit
        && ( $query->param("position") + $pagelimit - 1 <
            $query->param("count") ) )
    {
        $next = _make_next_form( $web, $topic, $query, $pagelimit );
    }

    $table =
      Foswiki::Plugins::BioKbPlugin::BioKb::wrap_result_table( $web, $topic,
        $table, "references", $next );

    # Top and tail with forms enabling progression to the next page

    $table = "---++ References\n" . $table;

    return $table;
}

=pod

 THE 'NEXT RESULTS' BUTTON IS FROM A SEPARATE FORM, WHICH WILL SUPPLY THE NEXT SET OF IDS FOR DISPLAY AT THE NEXT INVOCATION THAN PRESSING THE 'SAVE CHANGES'. OTHER PARAMETERS ARE PRESERVED IN HIDDEN FIELDS AS FOR SAVING CHANGES.

=cut

sub _make_next_form {
    my ( $web, $topic, $query, $pagelimit ) = @_;

    die "CGI object does not contain a search string\n"
      if ( !defined $query->param("search") || $query->param("search") eq "" );

    my @ids = split /,/, $query->param("pubmed_ids");

    my $end;
    if ( ( $query->param("position") + $query->param("pagelimit") ) <
        $query->param("count") )
    {
        $end = ( $query->param("position") + $query->param("pagelimit") );
    }
    else {
        $end = $query->param("count");
    }

    my $form = "";
    $form .= CGI::start_form( -name => "next", -method => 'post' );
    $form .=
        "<div class='next'> *"
      . ( $query->param("position") + 1 )
      . "* to *"
      . $end
      . "* of *"
      . $query->param("count")
      . "* results &nbsp;&nbsp;&nbsp;";

    $query->param( "position",
        $query->param("position") + $query->param("pagelimit") );

    if ( ( $query->param("position") + $query->param("pagelimit") ) <
        $query->param("count") )
    {
        $end = ( $query->param("position") + $query->param("pagelimit") );
    }
    else {
        $end = $query->param("count");
    }

    $form .= CGI::submit(
        -name  => ( $query->param("position") + 1 ) . "-" . $end,
        -class => "twikiSubmit"
      )
      . "</div>"
      . _save_params( $web, $query, 1 )
      . CGI::end_form()
      . "\n&nbsp;\n&nbsp;\n&nbsp;";
}

##########################################################################################
#                                                                                        #
#                               Form Processing                                          #
#                                                                                        #
##########################################################################################

=pod

Process the pubmed search form

=cut

sub search_pubmed {

    my ( $session, $params, $topic, $web ) = @_;

    my $query = Foswiki::Func::getCgiQuery();

    my $pagelimit = 100;    # Number of results displayed per page

    # Incorporate arguments to the Foswiki function into the CGI object

    my @pubmed_fields =
      qw (AD AID ALL AU CN RN EDAT FILTER 1AU FAU FIR GR IR IP TA LA LASTAU LID MHDA MAJR SH MH JID OT PG PS PA PL DP PT SI SB NM TW TI TIAB TT PMID VI);

    foreach my $pubmed_field ( @pubmed_fields, "neworold" ) {
        next
          if ( !defined $params->{$pubmed_field}
            || $params->{$pubmed_field} eq "" );
        $query->param(
            -name  => $pubmed_field,
            -value => $params->{$pubmed_field}
        );
    }

    $pagelimit = $query->param("pagelimit")
      if ( defined $query->param("pagelimit") );

    # HIDE THE FORM IF THE USER HAS USED THE ONE SUPPLIED

    my $output =
"<style type=\"text/css\" media=\"all\">\n#pubmedsearchform{display:none}\n</style>\n\n";

# USER HAS HIT 'SAVE CHANGES'- When the user has made any changes to the PubMed records presented to them- modify the topics

    if ( defined $query->param("pubmed_ids_manual") ) {
        $query->param(
            -name  => "pubmed_ids",
            -value => $query->param("pubmed_ids_manual")
        );
        $query->param(
            -name  => "references_addids",
            -value => [ split /,/, $query->param("pubmed_ids_manual") ]
        );
    }

    my @ids = split /,/, $query->param("pubmed_ids")
      if ( defined $query->param("pubmed_ids") );

    if ( scalar @ids > 0 ) {

        my @articles = @{ get_by_pubmed_id(@ids) };

        for ( my $i = 0 ; $i < scalar @articles ; $i++ ) {
            next if ( !defined $articles[$i] );
            my $article = $articles[$i];
            my %art     = %{$article};
            $art{"description"} = $art{"Title"}{"value"};
            $art{"topicname"}   = $art{"Key"}{"value"};

            if ( defined $query->param("reason") ) {
                ( $art{"Reason added"}{"value"} ) =
                  $query->param("reason") =~ /([\w\s\.\,]+)/;
            }
            else {
                my ($searchstring) =
                  $query->param("search") =~ /([\*\[\]\w\d\-\+\_\. ]+)/;
                $art{"Reason added"}{"value"} =
                  "Matched search string \"" . $searchstring . "\"";
            }

            ( $art{"id"}{"value"}, $art{"id"}{"source"} ) =
              ( $art{"PubMed ID"}{"value"}, "PubMed" );
            $articles[$i] = \%art;
        }
        my @addids = $query->param("references_addids");

        Foswiki::Plugins::BioKbPlugin::BioKb::save_changes( $session, $topic,
            $web, \@articles, "Reference", \@addids );
    }

# When the user has conducted a serach and we can retrieve the PubMed IDs from the hidden fields in the form

    if (   defined $query->param("pubmed_ids")
        && $query->param("pubmed_ids") ne ""
        && $query->param("pubmed_ids") !~ /^\s+$/ )
    {

# AFTER SAVING CHANGES, OR AFTER FIRST INVOCATION OF SEARCH, PROCESS PUBMED IDs AND MAKE OUTPUT

        $output .= _make_search_result_form( $web, $topic, $query, $pagelimit );
    }

# SEARCH FUNCTION HAS JUST BEEN CALLED. PARSE ARGUMENTS, RUN THE SEARCH, AND STORE THE PUBMED IDs

    else {

        my $searchstring = "";

        # Allow a URL-specified search string

        if ( defined $query->param("search") ) {
            $searchstring = $query->param("search");
            $searchstring =~ s/^(Gene|Disease|AnimalModel|Pathway)//
              ; # Remove any prefixes if a topic name has been used as a search term.....
            ($searchstring) = $searchstring =~ /([\*\[\]\w\d\-\+\_\. ]+)/;
        }
        else {
            foreach my $pubmed_field (@pubmed_fields) {
                next
                  if ( !defined $query->param($pubmed_field)
                    || $query->param($pubmed_field) eq "" );
                my @terms = split /,/, $query->param($pubmed_field);
                @terms =
                  Foswiki::Plugins::BioKbPlugin::BioKb::untaint( \@terms );
                foreach my $t (@terms) {
                    $t = join "+", ( split /\s/, $t );
                    $searchstring .= $t;
                    $searchstring .= " [$pubmed_field] "
                      if ( $pubmed_field ne "ALL" );
                }
            }
        }
        if ( !defined $searchstring || $searchstring eq "" ) {
            return "  No search string\n";
        }

        $searchstring =~ s/\s$//g;

        my $start = 0;
        $start = $query->param("position")
          if ( defined $query->param("position")
            && $query->param("position") ne "" );
        my ( $res, $count );

# Gather results to display- whether that's all present, or the result of a search

        my @results;
        my @existing;

        if ( $searchstring eq "*" ) {
            @results  = _check_existing($web);
            $count    = scalar @results;
            @results  = @results[ $start .. $start + $pagelimit - 1 ];
            @existing = @results;
        }
        else {
            ( $res, $count ) = _search_pubmed(
                $web,
                "search"   => $searchstring,
                "retmax"   => $pagelimit,
                "retstart" => $start,
                "neworold" => $query->param("neworold")
            );
            @results = @{$res};
            @existing = _check_existing( $web, @results );
        }

        die "No results for $searchstring\n" if ( scalar @results == 0 );

        # Values to encode in the forms

        my $pmids = join ",", @results;

        my %vals = (
            "type"              => $query->param("type"),
            "pubmed_ids"        => $pmids,
            "search"            => $searchstring,
            "position"          => $start,
            "pagelimit"         => $pagelimit,
            "count"             => $count,
            "references_addids" => \@existing,
            "neworold"          => $query->param("neworold")
        );

        # Skip straight to display of results

        if ( defined $query->param("now") && $query->param("now") == 1 ) {
            $query = _reset_cgi_values( $query, \%vals );
            $output .=
              _make_search_result_form( $web, $topic, $query, $pagelimit );
        }
        else {

# Inititialise the hidden fields we'll be using to persist information between script invocations

            $output .=
                "Search string <b>\""
              . $searchstring
              . "\" </b> returned $count\n\n";
            $output .=
                CGI::start_form( -name => "pubmedsearch", -method => 'post' )
              . _add_hidden_values( \%vals )
              . CGI::submit(
                -name  => "Retrieve first $pagelimit results",
                -class => "twikiSubmit"
              ) . CGI::end_form();

# Add another form which will allow the user to submit all results for addition. Limit to 10,000 results. Given 100 entries per request, this will be less than the 100 request limit of PubMed.

            my $local;
            ( $res, $count, $local ) = _search_pubmed(
                $web,
                "search"   => $searchstring,
                "neworold" => "newonly"
            );
            my @all_results = @{$res};

            $output .= "<p> $count new results not present in the wiki <br />";

            if ( ( $count - $local ) > 10000 ) {
                $output .=
"<p> Refine query to < 10,000 for the option to retrieve all query results";
            }
            else {

                # Set IDs to all results so that everythign is stored

                $vals{"references_addids"} = \@all_results;

                $output .= "<p>"
                  . CGI::start_form(
                    -name   => "storeall",
                    -action => Foswiki::Func::getViewUrl( $web, $topic ),
                    -method => 'post'
                  )
                  . _add_hidden_values( \%vals )
                  . CGI::submit(
                    -name  => "Store all $count new results",
                    -class => "twikiSubmit"
                  )
                  . "*"
                  . CGI::end_form()
                  . " <p> * This will take a large amount of time with large numbers of records, due to limititations in the frequency of queries sent to the NCBI.\n";
            }
        }
    }

# IMPORTANT TO EXPAND THE VARIABLES SO WE CAN USE THE Foswiki %URLPARAM% VARIABLE

    $output = Foswiki::Func::expandCommonVariables( $output, "PubMedFetchTest",
        "RAASbase" );

    return $output;
}

=pod

Return a list of Pubmed IDs stored in the wiki- or check a set of IDs if supplied

=cut

sub _check_existing {

    my ( $web, @ids ) = @_;
    my %ids = map { $_, 1 } @ids;

    my @found_ids;

    # Return a list of all pubmed IDs stored in the wiki

    my @topiclist = Foswiki::Func::getTopicList($web);
    my $workarea  = Foswiki::Func::getWorkArea("BioKbPlugin");
    my %convert;
    open( UIDS, "$workarea/unique_pubmed_ids" );
    while ( my $line = <UIDS> ) {
        chomp $line;
        my ( $key, $id ) = split /\t/, $line;
        $convert{$key} = $id;
    }
    close(UIDS);

    foreach my $top (@topiclist) {
        $top =~ s/\W//g;
        next if ( $top !~ /^Reference/ );
        my $key;
        ( $key = $top ) =~ s/^Reference//;

        next if ( !defined $convert{$key} );
        my ($pubmed_id) = $convert{$key} =~ /(\d+)/;

        next if ( !defined $pubmed_id || $pubmed_id !~ /\d/ );
        if ( defined $convert{$key}
            && ( scalar @ids == 0 || defined $ids{$pubmed_id} ) )
        {
            push @found_ids, $pubmed_id;
        }
    }

    return sort { $b <=> $a } @found_ids;
}

=pod

Reset supplied CGI values

=cut

sub _reset_cgi_values {
    my ( $query, $vals ) = @_;

    my %vals = %{$vals};

    foreach my $key ( keys %vals ) {
        if ( defined $query->param($key) && $query->param($key) ne "" ) {
            $query->param(
                -name     => $key,
                -value    => $vals{$key},
                -override => 1
            );
        }
        else {
            $query->append( -name => $key, -values => $vals{$key} );
        }
    }
    return $query;
}

=pod

Preserve values in hidden fields

=cut

sub _add_hidden_values {
    my ($vals) = @_;
    my %vals = %{$vals};

    my $content;
    foreach my $key ( keys %vals ) {
        $content .=
          CGI::hidden( -name => $key, -default => $vals{$key}, -override => 1 );
    }
    return $content;
}

##########################################################################################
#                                                                                        #
#                                     Search                                             #
#                                                                                        #
##########################################################################################

=pod

Extra layer over the pubmed search. Add ability to filter for new results only, or retrieve a particular index

=cut

sub _search_pubmed {
    my ( $web, %args ) = @_;

    my @ids = eutils_search( $args{"search"} );

    if (   defined $args{"neworold"}
        && $args{"neworold"} ne ""
        && $args{"neworold"} ne "all" )
    {

        # Read in a key relating PubMed ID to topic title

        my %keys = %{ fetch_unique_keys(@ids) };

        my @newids;
        foreach my $pmid (@ids) {

            die "PMID is not defined\n" if ( !defined $pmid );
            die "Web is not defined\n"  if ( !defined $web );

            if (   !defined $keys{$pmid}
                || !defined Foswiki::Func::topicExists( $web, $keys{$pmid} )
                || Foswiki::Func::topicExists( $web, $keys{$pmid} ) != 1 )
            {
                push @newids, $pmid if ( $args{"neworold"} eq "newonly" );
            }
            else {
                push @newids, $pmid if ( $args{"neworold"} eq "oldonly" );
            }
        }
        @ids = @newids;
    }

    # Find how many of these IDs we already have locally

    my $workarea = Foswiki::Func::getWorkArea("BioKbPlugin");
    my $bibdir   = $workarea . "/bibliography/";
    my $local    = 0;
    foreach my $id (@ids) {
        $local++ if ( -e $bibdir . $id );
    }

    my $last;

    if ( defined $args{"retmax"} && defined $args{"retstart"} ) {
        if ( $args{"retstart"} + $args{"retmax"} > scalar @ids ) {
            $last = scalar @ids - 1;
        }
        else {
            $last = $args{"retstart"} + $args{"retmax"} - 1;
        }
    }
    $args{"retstart"} = 0 if ( !defined $args{"retstart"} );
    $last = scalar @ids - 1 if ( !defined $last );

    my @res = @ids[ $args{"retstart"} .. $last ];

    return ( \@res, scalar @ids, $local );

}

=pod

Take PubMed search string and fetch the IDs of all resulting records. Remember the search and its results- and any new records, so that the same search is quicker in future.

=cut

sub eutils_search {

    my ( $searchstring, $ignorecachedate ) = @_;

    die "Need a search string\n"
      if ( !defined $searchstring || $searchstring eq "" );

    my $workarea = Foswiki::Func::getWorkArea("BioKbPlugin");
    my $cachedir = $workarea . "/cached_searches";
    mkdir $cachedir if ( !-e $cachedir );

    my %time = %{ _time() };
    my $date = join "/", ( $time{"year"}, $time{"mon"}, $time{"mday"} );

    my $lastdate = "";
    my @ids;

    my $cachesearchstring;
    ( $cachesearchstring = $searchstring ) =~ s/[\s+\/\,\:]/_/g;
    $cachesearchstring = substr( $cachesearchstring, 0, 250 )
      if ( length $cachesearchstring > 250 );
    my $cachesearch = $cachedir . "/" . lc $cachesearchstring;

    my %result;

    if ( -e $cachesearch ) {
        my $filestring = Foswiki::Func::readFile($cachesearch);
        my @oldids;
        ( $lastdate, @oldids ) = split "\n", $filestring;
        push @ids, @oldids;
        $searchstring .= " $lastdate" . ":$date [dp]";
    }

    if ( !-e $cachesearch
        || ( $date ne $lastdate && !defined $ignorecachedate ) )
    {

        my $workarea = Foswiki::Func::getWorkArea("BioKbPlugin");
        select( ( select(LOG), $| = 1 )[0] );
        my $eutils = "http://www.ncbi.nlm.nih.gov/entrez/eutils";
        my $esearch =
          "$eutils/esearch.fcgi?" . "db=Pubmed&retmax=1&usehistory=y&term=";
        my $esearch_result = get( $esearch . $searchstring );

        sleep 3;

        my ( $Count, $QueryKey, $WebEnv ) = $esearch_result =~
m/<Count>(\d+)<\/Count>.*<QueryKey>(\d+)<\/QueryKey>.*<WebEnv>(\S+)<\/WebEnv>/s;

        # There will be no count if there are no results

        return @ids if ( !defined $Count );

#if ( !defined $Count ) {
#    open( ERROR, ">$workarea/pubmed.ERR" );
#    print ERROR "Search URL was $esearch.$searchstring\nResult was $esearch_result\n";
#    close(ERROR);
#    die "Invalid response from PubMed with query $esearch.$searchstring :\n\n$esearch_result\n";
#}

        # Now fetch all the IDs

        $esearch_result = get(
            "$eutils/esearch.fcgi?db=Pubmed&term=$searchstring&retmax=$Count");
        sleep 3;

        my @newids = $esearch_result =~ /<Id>(\d+)<\/Id>/g;
        my %idhash = map { $_, 1 } ( @newids, @ids );
        @ids = sort { $b <=> $a } keys %idhash;

        Foswiki::Func::saveFile( $cachesearch,
            $date . "\n" . ( join "\n", @ids ) );
    }

    return @ids;

}

=pod

Business end of fetching records for a set of pubmed IDs

=cut

sub get_by_pubmed_id {
    my @pmids = @_;
    die "No pubmed ID supplied\n" if ( scalar @pmids == 0 );

    my $medline = "";

    my %time = %{ _time() };

    my $workarea = Foswiki::Func::getWorkArea("BioKbPlugin");
    my $bibdir   = $workarea . "/bibliography/";
    mkdir $bibdir if ( !-e $bibdir );

    my %reshash;
    my @new;

    foreach my $pmid (@pmids) {
        my $bibfile = $bibdir . $pmid;
        if ( -e $bibfile ) {
            my ($article) = Foswiki::Plugins::BioKbPlugin::BioKb::untaint(
                [ Foswiki::Func::readFile($bibfile) ] );
            die
"Empty article \"$bibfile\" for PMID \"$pmid\" retrieved from local store\n"
              if ( $article eq "" || !defined $article );
            if ( $article =~ /XML not found for id/ ) {
                unlink $bibfile;
                push @new, $pmid;
                next;
            }
            my $res = _parse_medline($article);
            die "Unable to parse ID $pmid :\n\n $article\n"
              if ( !defined $res || scalar @{$res} == 0 );
            if ( !defined $res || scalar @{$res} == 0 ) {
                push @new, $pmid;
            }
            else {
                my @list = @{$res};
                $reshash{$pmid} = $list[0];
            }
        }
        else {
            push @new, $pmid;
        }
    }

    my $batch_unit = 100;

    for ( my $i = 0 ; $i < scalar @new ; $i += $batch_unit ) {
        my $idstring = "";
        for ( my $j = $i ; $j < ( $i + 100 ) && $j < scalar @new ; $j++ ) {
            $idstring .= $new[$j] . ",";
        }
        my $eutils = "http://www.ncbi.nlm.nih.gov/entrez/eutils";

        my $articles = get(
"$eutils/efetch.fcgi?db=Pubmed&id=$idstring&rettype=medline&retmode=xml"
        );

# Skip if we can't get anything back from NCBI- happens sometimes if the server is doing something funky.

        next if ( $articles eq "" || !defined $articles );

        my @res = @{ _parse_medline($articles) };
        foreach my $article (@res) {
            my %art = %{$article};
            $reshash{ $art{"PubMed ID"} } = \%art;
        }
        sleep 5;
    }

    my @results;
    foreach my $pmid (@pmids) {
        if ( defined $reshash{$pmid} ) {
            my %art = %{ $reshash{$pmid} };
            my %artdata;
            foreach my $key ( keys %art ) {
                $artdata{$key}{"value"}  = $art{$key};
                $artdata{$key}{"source"} = "PubMed";
            }
            push @results, \%artdata;
        }
        else {
            push @results, undef;
        }
    }

    return \@results;
}

##########################################################################################
#                                                                                        #
#                                  Process Results                                       #
#                                                                                        #
##########################################################################################

=pod

Parse medline XML, which could contain multiple records

=cut

sub _parse_medline {
    my $medline_all = shift;
    die "Undefined article!\n"
      if ( !defined $medline_all || $medline_all eq "" );

    my $workarea = Foswiki::Func::getWorkArea("BioKbPlugin");

# First of all split down the record to individual references. XML::Simple messes up the structure if you read in the XML and try and write it again- so keep things in the MedLine format

    my @records;
    my $record;

    my $template =
"<?xml version=\"1.0\"?>\n<!DOCTYPE PubmedArticleSet PUBLIC \"-//NLM//DTD PubMedArticle, 1st January 2008//EN\" \"http://www.ncbi.nlm.nih.gov/entrez/query/DTD/pubmed_080101.dtd\">\n<PubmedArticleSet>\nINSERT\n<\/PubmedArticleSet>\n";

    foreach my $line ( split /\n/, $medline_all ) {

        if ( $line =~ /<PubmedArticle>/ ) {
            $record = $line;
        }

        elsif ( !defined $record ) {
            next;
        }
        elsif ( $line =~ /<\/PubmedArticle>/ ) {
            $record .= "\n" . $line;
            my $xmlout;
            ( $xmlout = $template ) =~ s/INSERT/$record/;
            push @records, $xmlout;
        }
        elsif ( $line =~ /<\/PubmedArticleSet>/ ) {
            undef $record;
            last;
        }
        else {
            $record .= "\n" . $line;
        }
    }

    # Now parse each reference as an independent unit of XML

    use XML::Simple;

    my @results;

    foreach my $rec (@records) {

        next if ( $rec =~ /XML not found for id/ );

        my %xml;
        eval { %xml = %{ XMLin($rec) } };
        if ($@) {
            die "Error parsing\n\n \"$rec\"\n";
        }

        my %hash    = %{ $xml{"PubmedArticle"} };
        my $pmid    = $hash{"MedlineCitation"}{"PMID"};
        my $bibfile = $workarea . "/bibliography/$pmid";

        if ( !-e $bibfile ) {
            Foswiki::Func::saveFile( $bibfile, $rec );
        }

        if ( !defined $hash{"MedlineCitation"}{"Article"} ) {
            die "No Article, keys are: "
              . ( join ",", keys %{ $hash{"MedlineCitation"} } )
              . "\nValue is:\n\n"
              . $hash{"MedlineCitation"}{"Article"}
              . "\nXML was: \n\n$medline_all";
            next;
        }
        my %article = %{ $hash{"MedlineCitation"}{"Article"} };
        my $key;

        my @authors;
        if ( ref $article{"AuthorList"}{"Author"} eq "ARRAY" ) {
            @authors = @{ $article{"AuthorList"}{"Author"} };
        }
        elsif ( defined $article{"AuthorList"}{"Author"} ) {
            push @authors, $article{"AuthorList"}{"Author"};
        }
        else {
            $key = "NoAuthor";
        }

        die "Key is tainted at step 1\n" if ( tainted($key) == 1 );

        my @parsedauthors;
        foreach my $a (@authors) {
            my %author = %{$a};

            next if ( !defined $author{"LastName"} );

            my $firstname = "";
            if ( defined $author{"FirstName"} ) {
                $firstname .= $author{"FirstName"};
            }
            elsif ( defined $author{"ForeName"} ) {
                $firstname .= $author{"ForeName"};
            }
            elsif ( defined $author{"Initials"} ) {
                $firstname .= $author{"Initials"};
            }

            $key = $author{"LastName"} if ( !defined $key );
            push @parsedauthors, $firstname . " " . $author{"LastName"};
        }

        die "Key is tainted at step 2\n" if ( tainted($key) == 1 );

# If there were no last names the key will be undefined- was this written by a collective? Anyway, name it by PMID

        if ( !defined $key ) {

            #($key) = $hash{"MedlineCitation"}{"PMID"} =~ /(\d+)/;
            $hash{"MedlineCitation"}{"PMID"} =~ /(\d+)/;
            $key = $1;
            die "blah key $key is tainted\n" if ( tainted($key) == 1 );
        }
        else {

            my $detainted_key = $key;
            $key =~ s/[^A-Za-z\d]//g
              ;  # Remove strange characters from names- not very useful in keys
            ( $key = $detainted_key ) =~ /[A-Za-z\d]+/;

            die "Key is tainted at step 2d\n" if ( tainted($key) == 1 );

            # Try and derive a year for a number of possible year fields

            if ( defined $article{"Journal"}{"JournalIssue"}{"PubDate"}{"Year"}
                && $article{"Journal"}{"JournalIssue"}{"PubDate"}{"Year"} =~
                /(\d+)/ )
            {
                $key .= $1;
                die "Key is tainted at step 2b\n" if ( tainted($key) == 1 );
            }
            elsif (
                defined $article{"Journal"}{"JournalIssue"}{"PubDate"}
                {"MedlineDate"} )
            {
                if ( $article{"Journal"}{"JournalIssue"}{"PubDate"}
                    {"MedlineDate"} =~ /(\d{4,4})/ )
                {
                    $key .= $1;
                }
                die "Key is tainted at step 2c\n" if ( tainted($key) == 1 );
            }
        }

        die "Key $key is tainted at step 3\n" if ( tainted($key) == 1 );

        $key =~ s/\s//g;
        die "Undefined key before unique\n" if ( !defined $key );
        $key = _make_unique_key( $key, $pmid );
        die "Undefined key after unique\n" if ( !defined $key );

        my @keys = (
            "PubMed ID", "Authors", "Title",  "Abstract",
            "Month",     "Year",    "Volume", "Issue",
            "Page"
        );

        die "Undefined key\n" if ( !defined $key );

        my %parsed = (
            "Key"       => $key,
            "PubMed ID" => $hash{"MedlineCitation"}{"PMID"},
            "Authors"   => ( join ", ", @parsedauthors ),
            "Title"     => $article{"ArticleTitle"},
            "Abstract"  => $article{"Abstract"}{"AbstractText"},
            "Month"  => $article{"Journal"}{"JournalIssue"}{"PubDate"}{"Month"},
            "Year"   => $article{"Journal"}{"JournalIssue"}{"PubDate"}{"Year"},
            "Volume" => $article{"Journal"}{"JournalIssue"}{"Volume"},
            "Issue"  => $article{"Journal"}{"JournalIssue"}{"Issue"},
            "Page"   => $article{"Pagination"}{"MedlinePgn"}
        );

        undef $parsed{"Page"} if ( ref $parsed{"Page"} eq "HASH" );
        push @results, \%parsed;

    }

 #    die "No results from parse of $medline_all\n" if ( scalar @results == 0 );
    return \@results;
}

=pod

Return those keys that exist for a given set of PubMed IDs. A set of unique keys will be maintained to resolve ambiguities

=cut

sub fetch_unique_keys {

    my @pmids = @_;

    my %pmid_hash = map { $_, 1 } @pmids;

    my $workarea = Foswiki::Func::getWorkArea("BioKbPlugin");
    my $keyfile  = $workarea . "/unique_pubmed_ids";

    my %keys;

    if ( -e $keyfile ) {
        my $keystring = Foswiki::Func::readFile($keyfile);
        foreach my $line ( split /\n/, $keystring ) {
            my ( $pubkey, $pmid ) = split /\t/, $line;
            $keys{$pmid} = $pubkey if ( defined $pmid_hash{$pmid} );
        }
    }

    return \%keys;
}

=pod

Check if your pubmed ID already has a unique key and return it, otherwise generate a new one being careful to avoid previous ones

=cut

sub _make_unique_key {
    my ( $key, $pubmed_id ) = @_;

    $key       =~ s/[^A-Za-z\d]//g;
    $pubmed_id =~ s/\D//g;

    my $workarea = Foswiki::Func::getWorkArea("BioKbPlugin");
    my $keyfile  = $workarea . "/unique_pubmed_ids";

    my %keys;
    my $wikikey;

    if ( -e $keyfile ) {

        open( UIDS, $keyfile ) or die $!;
        while ( my $line = <UIDS> ) {
            chomp $line;
            my ( $pubkey, $val ) = split /\t/, $line;

            # We've got a key for this one. Note it- job done.

            if ( $val eq $pubmed_id ) {
                $wikikey = $pubkey;
                undef %keys;
                last;
            }
            $keys{$pubkey} = $val;
        }
        close(UIDS);
    }

    # Need to generate a new key

    if ( !defined $wikikey ) {

        my @subscripts =
          qw( a b c d e f g h i j k l m n o p q r s t u v w x y z);

        # Keep trying subscripts until we've got a unique key

        my $mod_key = $key;
        while ( defined $keys{$mod_key} && $keys{$mod_key} ne $pubmed_id ) {
            my $ss = shift @subscripts;
            $mod_key = $key . $ss;
        }

        ($wikikey) = $mod_key =~ /(\w+)/;

        # Re-store the file

        my $keystring = $wikikey . "\t" . $pubmed_id . "\n";

        # Store the key file

        if ( -e $keyfile ) {
            Foswiki::Func::saveFile( "$keyfile.more", $keystring );
            system("mv $keyfile $keyfile.old");
            system("cat $keyfile.old $keyfile.more >> $keyfile");
            unlink "$keyfile.old"  or die $!;
            unlink "$keyfile.more" or die $!;
        }
        else {
            Foswiki::Func::saveFile( $keyfile, $keystring );
        }
    }

    my ($outkey) = $wikikey =~ /([A-Za-z\d]+)/;
    die "Returned key is tainted\n" if ( tainted($outkey) == 1 );

    return $outkey;
}

=pod

Embed important values in hidden fields. Run a search to synchronize the stored ids with the position and serach string

=cut

sub _save_params {
    my ( $web, $query, $renew_ids ) = @_;

    my ( $res, $count ) = _search_pubmed(
        $web,
        "search"   => $query->param("search"),
        "retmax"   => $query->param("pagelimit"),
        "retstart" => $query->param("position"),
        "neworold" => $query->param("neworold")
    );

    my $hidden = "";

    foreach my $param ( "type", "search", "position", "pagelimit", "neworold",
        "count" )
    {
        next
          if ( !defined $query->param($param) || $query->param($param) eq "" );
        $hidden .= CGI::hidden(
            -name    => $param,
            -default => $query->param($param),
            override => 1
        );
    }

    my @existing;

    if ( defined $renew_ids ) {
        my @result;
        if ( $query->param("search") eq "*" ) {
            @existing = _check_existing($web);
            @result =
              @existing[ $query->param("position")
              .. ( $query->param("position") + $query->param("pagelimit") - 1 )
              ];
            @existing = @result;
        }
        else {
            my ( $res, $count ) = _search_pubmed(
                $web,
                "search"   => $query->param("search"),
                "retmax"   => $query->param("pagelimit"),
                "retstart" => $query->param("position"),
                "neworold" => $query->param("neworold")
            );
            @result = @{$res};
            @existing = _check_existing( $web, @{$res} );
        }
        $hidden .= CGI::hidden(
            -name    => "pubmed_ids",
            -default => ( join ",", @result ),
            override => 1
        );
        $hidden .= CGI::hidden(
            -name    => "references_addids",
            -default => \@existing,
            override => 1
        ) if ( defined $renew_ids );
    }
    else {
        $hidden .= CGI::hidden(
            -name    => "pubmed_ids",
            -default => $query->param("pubmed_ids"),
            override => 1
        );
        @existing =
          _check_existing( $web, split /,/, $query->param("pubmed_ids") );
    }

    return $hidden;
}

=pod

Produce a formatted article from the data hash

=cut

sub format_article {
    my ( $web, $art ) = @_;

    my @admin =
      Foswiki::Plugins::BioKbPlugin::BioKb::read_admin( $web, "DatabaseURLs" );
    my %prefixes = %{ $admin[0] };

    my %article = %{$art};

    my $art_string = "\n";

    my @foo;

    foreach my $field (
        "Reason added", "Authors", "Title",  "Abstract",
        "Month",        "Year",    "Volume", "Issue",
        "Page",         "PubMed ID"
      )
    {
        die "Tainted before sub\n" if ( tainted( $article{$field} ) == 1 );
        push @foo, $field;
        next if ( !defined $article{$field}{"value"} );

        # Add syntax to prevent camel-casing of names

        if (   $field eq "Authors"
            && $article{$field}{"value"} =~ /(\s+)([A-Z]+[a-z]+[A-Z]+\W)/ )
        {
            my $camel = $2;
            $article{$field}{"value"} =~ s/(\s+)($camel)/$1\!$camel/g;
            ( $article{$field}{"value"} ) =
              Foswiki::Plugins::BioKbPlugin::BioKb::untaint(
                [ $article{$field} ],
                undef, "format_article" );
        }
        elsif ( $field eq "PubMed ID" ) {
            my $link = $prefixes{"pubmed"};
            $link =~ s/VAL/$article{$field}{"value"}/;
            $article{$field}{"value"} =
              "[[$link][" . $article{$field}{"value"} . "]]";
        }

        $art_string .= "| !$field | " . $article{$field}{"value"} . " | (";
        if ( defined $article{$field}{"source"} ) {
            $art_string .= "!" . $article{$field}{"source"};
        }
        else {
            my ($wikiname) = Foswiki::Func::getWikiName();
            $art_string .= "[[Main.$wikiname][$wikiname]]";
        }
        $art_string .= ")|\n" if ( defined $article{$field} );
    }

    return $art_string;
}

=pod 

Produce a data hash from formatted article topic

=cut

sub parse_article {
    my ( $web, $topic ) = @_;

    my %data;

    my ( $meta, $text ) = Foswiki::Func::readTopic( $web, "Data" . $topic );

    my @lines = split /[\n\r]+/, $text;
    foreach my $line (@lines) {
        next if ( $line !~ /^\|/ );
        my ( $foo, $field, $val, $source ) = split /\s*\|\s*\!?/, $line;
        $source =~ s/\[\[(?:[^\]\[]+\]\[)?([^\[\]]+)\]\]/$1/g;
        $source =~ s/[\!\)\(]//g;
        $val    =~ s/\[\[(?:[^\]\[]+\]\[)?([^\[\]]+)\]\]/$1/g;
        $data{$field} = { "value" => $val, "source" => $source };
    }
    return \%data;
}

=pod

Make a useful hash of date strings

=cut

sub _time {
    my ( $sec, $min, $hour, $mday, $mon, $year, $wday, $yday, $isdst ) =
      localtime(time);

    $wday = sprintf "%02d", $wday + 1;    ## zeropad day of week; sunday = 1;
    $hour = sprintf "%02d", $hour;        ## zeropad hour
    $min  = sprintf "%02d", $min;
    $sec  = sprintf "%02d", $sec;
    $year = sprintf "%04d", ( $year + 1900 );
    $mon  = sprintf "%02d", ( $mon + 1 );
    $mday = sprintf "%02d", $mday;

    my %time = (
        "day"  => $wday,
        "hour" => $hour,
        "min"  => $min,
        "sec"  => $sec,
        "year" => $year,
        "mon"  => $mon,
        "mday" => $mday
    );
    return \%time;
}

1
