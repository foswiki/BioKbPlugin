package Foswiki::Plugins::BioKbPlugin::MolecularBiology;

use strict;
use Scalar::Util qw(tainted);
use Clone qw(clone);

##########################################################################################
#                                                                                        #
#                                     Interface                                          #
#                                                                                        #
##########################################################################################

=pod

Form which searches KEGG given a pathway ID (specified in URL parameter). Will download all associated data and show them for addition

=cut

sub kegg_pathway_search {

    my ( $session, $params, $topic, $web ) = @_;

    my $query = Foswiki::Func::getCgiQuery();

    my $content = "";
    my %admin_data =
      %{ Foswiki::Plugins::BioKbPlugin::BioKb::read_topic_structure_admin($web)
      };

    if ( !defined $query->param("pathway_id")
        || $query->param("pathway_id") eq "" )
    {
        $content =
            CGI::start_form( -method => "POST" )
          . "---++ Seed the wiki from a KEGG pathway definition\n\n"
          . "Pathway ID: "
          . CGI::textfield(
            -name      => "pathway_id",
            -size      => 10,
            -maxlength => 50,
            -default   => ""
          )
          . "<br />"
          .

#"Keywords: " . CGI::textfield( -name => "pathway_keywords", -size => 10, -maxlength => 50, -default => "" ) . "&nbsp;&nbsp;" .
          CGI::submit( -class => "foswikiSubmit", -value => "Go" )
          . CGI::end_form();
    }

    else {

        my ($pathway_id) = $query->param("pathway_id") =~ /(\w+)/;

        my $spec = "";
        if ( $pathway_id =~ /([a-z]{3,3})\d+/ ) {
            my $prefix = $1;
            $spec = ucfirst( lc $prefix ) if ( $prefix ne "map" );
        }

        my $workarea = Foswiki::Func::getWorkArea("BioKbPlugin");
        mkdir $workarea . "/kegg" if ( !-e $workarea . "/kegg" );
        my $pathdir = "$workarea/kegg/$pathway_id";
        mkdir $pathdir or die $! if ( !-d $pathdir );

        Foswiki::Func::addToHEAD( "BioKb",
"<script type=\"text/javascript\" src=\"%PUBURL%/%TWIKIWEB%/BioKbPlugin/mootools.js\"></script>\n<script type=\"text/javascript\" src=\"%PUBURL%/%TWIKIWEB%/BioKbPlugin/moocheck.js\"></script>\n<script type=\"text/javascript\" src=\"%PUBURL%/%TWIKIWEB%/BioKbPlugin/checkAllToggle.js\"></script>\n\n"
        );

        my %diseases;

        # The set of data types that may be linked to from the KEGG pathway ID

        my %kegg_topic_types = (
            "Pathway"           => "pathway",
            "Orthologous Group" => "ko",
            "Gene"              => "gene",
            "Reference"         => "reference",
            "Compound"          => "compound",
            "Drug"              => "drug"
        );

        my $totalrecords = 0;

        my @gene_names;

        my $foo = "";

        foreach
          my $topic_type ( "Pathway", "Gene", "Compound", "Drug", "Disease",
            "Reference" )
        {
            $foo .= $topic_type . "\n";

            my $prefix = $admin_data{$topic_type}{"prefix"};
            $prefix = $topic_type if ( !defined $prefix );
            my @records;

            my @ids;

            # Check KEGG for entities linked to the supplied pathway ID

            if ( defined $kegg_topic_types{$topic_type} ) {
                my $datatype = $kegg_topic_types{$topic_type};
                my $datfile  = $pathdir . "/" . $datatype;

                if ( $datatype eq "pathway" ) {
                    push @ids, "pathway:" . $pathway_id;
                }
                else {
                    if ( !-e $datfile ) {
                        use SOAP::Lite;
                        my $wsdl = "http://soap.genome.jp/KEGG.wsdl";
                        my $serv = SOAP::Lite->service($wsdl);

                        my $method = "get_" . $datatype . "s_by_pathway";
                        my @fetched_ids =
                          @{ $serv->$method("path:$pathway_id") };
                        sleep 3;
                        Foswiki::Func::saveFile( $datfile, join "\n",
                            @fetched_ids );
                    }
                    @ids = split /\n/, Foswiki::Func::readFile($datfile);
                    next if ( scalar @ids == 0 );

                }

                # Untaint the IDs

                @ids = Foswiki::Plugins::BioKbPlugin::BioKb::untaint( \@ids,
                    "\\w\\:" );

            }

            if ( $topic_type eq "Reference" ) {
                my @articles = @{
                    Foswiki::Plugins::BioKbPlugin::Literature::get_by_pubmed_id(
                        @ids)
                  };
                foreach my $article (@articles) {
                    if ( !defined $article ) {
                        push @records, undef;
                    }
                    else {
                        my %art = %{$article};
                        $art{"topicname"}   = ucfirst $art{"Key"}{"value"};
                        $art{"description"} = $art{"Title"}{"value"};
                        $art{"id"}{"value"} = $art{"PubMed ID"}{"value"};
                        $art{"Reason added"}{"value"} =
                          "Linked from KEGG Pathway $pathway_id";
                        push @records, \%art;
                    }
                }
            }
            elsif ( $topic_type eq "Disease" ) {

                # See if we found any diseases

                if ( scalar keys %diseases > 0 ) {
                    foreach my $id ( sort keys %diseases ) {
                        my %disease = %{ $diseases{$id} };
                        $disease{"topicname"} = $disease{"dest_topic"}{"value"};
                        $disease{"id"}{"value"} =
                          @{ $disease{"Entry"}{"value"} }[0];
                        $disease{"description"} =
                          @{ $disease{"Title"}{"value"} }[0];
                        push @records, \%disease;
                    }
                }
            }
            else {

                # RETRIEVE KEGG RECORDS

                my $kegg_type;
                ( $kegg_type = $kegg_topic_types{$topic_type} ) =~ s/s$//i;
                my @kegg_results = fetch_kegg( $web, $kegg_type, @ids );

                foreach my $res (@kegg_results) {

                    next if ( !defined $res );
                    my %result = %{$res};
                    push @gene_names, @{ $result{"Title"}{"value"} }[0]
                      if ( $topic_type eq "Gene" );

                    my $topicname = "";
                    foreach
                      my $word ( split /\W/, @{ $result{"Title"}{"value"} }[0] )
                    {
                        $topicname .= ucfirst $word;
                    }

                    # Remove the taint introduced by substn

                    ( $result{"topicname"} ) = $topicname =~ /(\w+)/;
                    $result{"topicname"} =~ s/\//\_/g;

                    push @records, \%result;
                }
                if ( $topic_type eq "Gene" ) {
                    %diseases =
                      Foswiki::Plugins::BioKbPlugin::Disease::find_diseases(
                        $web, @gene_names );
                }
            }

            # Now present the table of results

            if ( scalar @records > 0 ) {

                if ( defined $query->param("submitted") ) {
                    my @addids = $query->param( $topic_type . "_addids" );
                    Foswiki::Plugins::BioKbPlugin::BioKb::save_changes(
                        $session, $topic, $web, \@records, $topic_type,
                        \@addids );
                }

                # Display resultant topic status

                my $table =
                  Foswiki::Plugins::BioKbPlugin::BioKb::make_formatted_result_table(
                    $web, \@records, $topic_type );
                $table .= CGI::hidden(
                    -name    => $topic_type . "_ids",
                    -default => join ",",
                    @ids, override => 1
                  )
                  . CGI::hidden(
                    -name    => "pathway_id",
                    -default => $query->param("pathway_id"),
                    override => 1
                  );

                $table = "\n---++ !" . $prefix . "s\n\n" . $table;

# Use molecular biology as the default. But if we have a medical-type topic, or a reference, then we can color the results differently

                $content .= "\n" . $table;
                $totalrecords += scalar @records;
            }
        }
        if ( $totalrecords == 0 ) {
            $content =
              "<h2>No results found for query of pathway ID $pathway_id</h2>\n";
        }
        $content =
          Foswiki::Plugins::BioKbPlugin::BioKb::wrap_result_table( $web, $topic,
            $content, "seed" );
    }

    return $content;
}

##########################################################################################
#                                                                                        #
#                                 Search KEGG                                            #
#                                                                                        #
##########################################################################################

=pod

Work out which kegg ids haven't been retrieved before, and fetch them

=cut

sub retrieve_from_kegg {

    my ( $typein, @idsin ) = @_;

    my @new;
    my @old;
    my @newfilenames;
    my @oldfilenames;

    foreach my $idin (@idsin) {

        my ($id)   = $idin   =~ /([\w\:]+)/;
        my ($type) = $typein =~ /(\w+)/;

        my @allowedtypes = qw ( pathway gene compound drug ko);
        my %allowedtypes = map { $_, 1 } @allowedtypes;
        die "\"$type\" not recognised for KEGG\n"
          if ( !defined $allowedtypes{$type} );

        $id = $type . ":$id" if ( $id !~ /\:/ );

        my $workarea = Foswiki::Func::getWorkArea("BioKbPlugin");
        mkdir $workarea . "/kegg" if ( !-e $workarea . "/kegg" );
        my $outdir = $workarea . "/kegg/$type";
        mkdir $outdir
          or die "Can't create directory $outdir\n"
          if ( !-d $outdir );
        my $file = "$outdir/$id";

        my $result;

        if ( !-e $file ) {
            push @new,          $id;
            push @newfilenames, $file;
        }
        else {
            push @old,          $id;
            push @oldfilenames, $file;
        }
    }

    if ( scalar @new > 0 ) {

        use SOAP::Lite;
        my $wsdl = "http://soap.genome.jp/KEGG.wsdl";
        my $serv = SOAP::Lite->service($wsdl);

        my @all_results;
        for ( my $i = 0 ; $i < scalar @new ; $i += 100 ) {
            my $last = $i + 99;
            $last = scalar @new - 1 if ( $last > scalar @new - 1 );
            my @query = @new[ $i .. $last ];
            my $res = $serv->bget( join " ", @query );
            sleep 3;

            my @results = split /\/\/\/\n/, $res;
            push @all_results, @results;
        }

        for ( my $i = 0 ; $i < scalar @all_results ; $i++ ) {
            open( FILE, ">" . $newfilenames[$i] );
            print FILE $all_results[$i];
            close(FILE);
        }
    }
    return ( @newfilenames, @oldfilenames );
}

=pod

Use above subroutine to retrieve KEGG records, or read them from the working directory if previously retrieved, and then parse them, returning as an array of data hashes.

=cut

sub fetch_kegg {

    my ( $web, $typein, @idsin ) = @_;
    retrieve_from_kegg( $typein, @idsin );

    my @records;

    foreach my $idin (@idsin) {

        my ($id)   = $idin   =~ /([\w\:]+)/;
        my ($type) = $typein =~ /(\w+)/;

        my @allowedtypes = qw ( pathway gene compound drug ko);
        my %allowedtypes = map { $_, 1 } @allowedtypes;
        die "\"$type\" not recognised for KEGG\n"
          if ( !defined $allowedtypes{$type} );

        $id = $type . ":$id" if ( $id !~ /\:/ );

        my $workarea = Foswiki::Func::getWorkArea("BioKbPlugin");
        mkdir $workarea . "/kegg" if ( !-e $workarea . "/kegg" );
        my $outdir = $workarea . "/kegg/$type";
        mkdir $outdir
          or die "Can't create directory $outdir\n"
          if ( !-d $outdir );
        my $file = "$outdir/$id";

        my $result;

        next if ( !-e $file );

        open( FILE, $file );
        while ( my $f = <FILE> ) {
            $result .= $f;
        }
        close(FILE);

        return if ( !defined $result || $result eq "" );
        my $parsed = _parse_kegg( $web, $type, $result, $id );
        my %parsed;
        if ( !defined $parsed ) {
            return;
        }
        else {
            %parsed = %{$parsed};
        }

        undef $parsed{"Entry"}{"value"};
        push @{ $parsed{"Entry"}{"value"} },  $id;
        push @{ $parsed{"Entry"}{"source"} }, "KEGG " . ucfirst $type;

        if ( $type eq "gene" ) {
            my ( $spec, $keggid ) = $id =~ /(\w+)\:(\w+)/;
            my ( $species, $ncbi_taxid ) = _find_tax_id_from_kegg($spec);

            push @{ $parsed{"Species"}{"value"} },  $species;
            push @{ $parsed{"Species"}{"source"} }, "KEGG " . ucfirst $type;
        }

        # Add some lines facilitating listing of the KEGG record

        $parsed{"id"}{"value"}  = $id;
        $parsed{"id"}{"source"} = "KEGG " . ucfirst $type;

        my $description;
        if ( defined $parsed{"Definition"}{"value"} ) {
            $description = $parsed{"Definition"}{"value"};
        }
        elsif ( defined $parsed{"Comment"}{"value"} ) {
            $description = $parsed{"Comment"}{"value"};
        }
        else {
            $description = $parsed{"Title"}{"value"};
        }
        $description =~ s/\n//g;
        ( $parsed{"description"} = @{$description}[0] ) =~ s/\n/ /g;
        push @records, \%parsed;

    }
    my %foo = %{ $records[0] };

    return @records;
}

=pod

For KEGG genes or pathways, also retrieve the orthologous entities from the model organisms specified in AdminContentLimits

=cut

sub _add_kegg_orthologs {

    my ( $web, $type, $rec ) = @_;
    my %admin_data =
      %{ Foswiki::Plugins::BioKbPlugin::BioKb::read_topic_structure_admin($web)
      };

    $rec = _replace_genes_ids($rec);
    my %record = %{$rec};

    my @orthologs;

    # Fetch orthologs, and augment the data section accordingly

    if ( lc $type eq "pathway" ) {

# If the type is pathway, then we need a different set of genes and compounds for each species

        my @retpar = Foswiki::Plugins::BioKbPlugin::BioKb::read_admin( $web,
            "ContentLimits" );
        my %retpar = %{ $retpar[0] };

        my @models = split /\, /, $retpar{"model_organisms"}{"Value"};
        my %models = map { $_, 1 } @models;

        my ( $spec, $path_no ) = $record{"id"}{"value"} =~ /([A-Za-z]+)?(\d+)/;

        my @paths;
        foreach my $model (@models) {
            push @paths, $model . $path_no
              if ( !defined $spec || $model ne $spec );
        }
        @orthologs = fetch_kegg( $web, "pathway", @paths );
    }
    elsif ( lc $type eq "gene" ) {

        @orthologs =
          Foswiki::Plugins::BioKbPlugin::MolecularBiology::fetch_kegg_orthologs(
            $web, $record{"id"}{"value"} );
    }

    for ( my $i = 0 ; $i < scalar @orthologs ; $i++ ) {
        $orthologs[$i] = _replace_genes_ids( $orthologs[$i] );
    }

    my @fields = @{ $admin_data{$type}{"Data"}{"field order"} };

    foreach my $orth (@orthologs) {
        my %ortholog = %{$orth};

        foreach my $field (@fields) {
            if ( defined $ortholog{$field}{"value"} ) {
                push @{ $record{$field}{"value"} },
                  @{ $ortholog{$field}{"value"} };
                push @{ $record{$field}{"source"} },
                  @{ $ortholog{$field}{"source"} };

                if ( defined $admin_data{$type}{"Data"}{$field}{"databases"} ) {
                    push @{ $record{ $field . "_db" }{"value"} },
                      @{ $ortholog{ $field . "_db" }{"value"} };
                }
            }
            else {
                push @{ $record{$field}{"value"} }, undef;
                if ( defined $admin_data{$type}{"Data"}{$field}{"databases"} ) {
                    push @{ $record{ $field . "_db" }{"value"} }, undef;
                }

            }
        }
    }
    return \%record;

}

=pod

The business end of ortholog fetching

=cut

sub fetch_kegg_orthologs {

    my ( $web, $kegg_gene ) = @_;

    use SOAP::Lite;

    my @query = @ARGV;

    my $wsdl = 'http://soap.genome.jp/KEGG.wsdl';
    my $serv;

    my @retpar =
      Foswiki::Plugins::BioKbPlugin::BioKb::read_admin( $web, "ContentLimits" );
    my %retpar = %{ $retpar[0] };

    my @models = split /\, /, $retpar{"model_organisms"}{"Value"};
    my %models = map { $_, 1 } @models;

    my $workarea = Foswiki::Func::getWorkArea("BioKbPlugin");
    my $dir      = $workarea . "/kegg/ko_by_gene";
    mkdir $dir if ( !-e $dir );
    my $file = "$dir/$kegg_gene";

    my @kos;
    if ( -e $file ) {
        @kos = split /\n/, Foswiki::Func::readFile($file);
    }
    else {
        $serv = SOAP::Lite->service($wsdl);
        @kos  = @{ $serv->get_ko_by_gene($kegg_gene) };
        Foswiki::Func::saveFile( $file, join "\n", @kos );
    }
    my @orthologs;

    @kos = Foswiki::Plugins::BioKbPlugin::BioKb::untaint( \@kos, "\\w\\:" );

    foreach my $ko (@kos) {

        my @genes;

        my $dir = $workarea . "/kegg/genes_by_ko";
        mkdir $dir if ( !-e $dir );
        my $file = "$dir/$ko";

        if ( -e $file ) {
            push @orthologs, split /\n/, Foswiki::Func::readFile($file);
        }
        else {
            $serv = SOAP::Lite->service($wsdl);
            @genes = @{ $serv->get_genes_by_ko( $ko, 'all' ) };
            my @orth;
            foreach my $gdef (@genes) {
                my %def = %{$gdef};
                my $id  = $def{"entry_id"};
                my ( $spec, $keggid ) = $id =~ /(\w+)\:(\S+)/;
                push @orth, $id
                  if ( $id ne $kegg_gene && defined $models{$spec} );
            }

            Foswiki::Func::saveFile( $file, join "\n", @orth );
            push @orthologs, @orth;
        }

    }

    return fetch_kegg( $web, "gene", @orthologs );
}

=pod

Replace a list of KEGG gene IDs with the slighly more useful NCBI gene IDs

=cut

sub _replace_genes_ids {

    my $orth = shift;

    my %ortholog = %{$orth};

    if ( defined $ortholog{"Genes"} ) {
        my ( $eg, $sc ) =
          _kegg_gene_to_ncbi_gene( @{ @{ $ortholog{"Genes"}{"value"} }[0] } );
        undef $ortholog{"Genes"}{"value"};
        undef $ortholog{"Genes_db"};
        push @{ $ortholog{"Genes"}{"value"} },    $eg;
        push @{ $ortholog{"Genes_db"}{"value"} }, $sc;
    }
    return \%ortholog;
}

sub _kegg_gene_to_ncbi_gene {

    my @keggids = @_;
    my %keggids = map { $_, 1 } @keggids;
    my @entrezids;
    my @source;
    my $workarea = Foswiki::Func::getWorkArea("BioKbPlugin");

    my $ncbifile = $workarea . "/genes_ncbi-geneid.list";

    if ( !-e $ncbifile ) {
        throw Foswiki::OopsException(
            'generic',
            params => [
"Please obtain KEGG-to-NCBI mapping file from KEGG and place it at $ncbifile\n",
                "",
                "",
                ""
            ]
        );
    }
    open( CONV, $ncbifile );
    while ( my $line = <CONV> ) {
        my ( $keggid, $entrezid ) = $line =~ /^(\S+)\tncbi-geneid\:(\d+)/;
        if ( defined $keggids{$keggid} ) {
            push @entrezids, $entrezid;
            push @source,    "NCBI-GeneID";
        }
        last if ( scalar @entrezids == scalar @keggids );
    }
    close(CONV);
    return ( \@entrezids, \@source );
}

##########################################################################################
#                                                                                        #
#                                  Parse KEGG                                            #
#                                                                                        #
##########################################################################################

=pod

Parse KEGG records with all their idiosyncrasies. Will probably genericise this a little once more data sources are incorported into BioKb

=cut

sub _parse_kegg {
    my ( $web, $type, $kegg, $id ) = @_;

    my $titlefield = "Name";
    my @keywords;
    my @lines = split /\n/, $kegg;

    my $content = "";

    my $record_type;
    my $record_content;

    my @names;

    my %result;

    my %fieldkeys = (
        "NTSEQ"   => "DNA Sequence",
        "AASEQ"   => "Protein Sequence",
        "DBLINKS" => "Database Links"
    );
    my @dbtypes = (
        "DBLINKS",   "MOTIF", "STRUCTURE", "PATHWAY",
        "ORTHOLOGY", "GENE",  "COMPOUND"
    );
    my %dbtypes = map { $_, 1 } @dbtypes;
    my %dbnames = ( "PATH" => "KEGG PATH", "KO" => "KEGG Orthology" );

    my @retpar =
      Foswiki::Plugins::BioKbPlugin::BioKb::read_admin( $web, "ContentLimits" );
    my %retpar = %{ $retpar[0] };

    my @models = split /\, /, $retpar{"model_organisms"}{"Value"};
    my %models = map { $_, 1 } @models;

# Lists of things we can gather as we go along that might be common to different data types

    my %lists;
    my @pmids;

    for ( my $i = 1 ; $i <= scalar @lines + 1 ; $i++ ) {
        my $line = $lines[ $i - 1 ];
        if ( !defined $line
            || ( $line =~ /^(\S+)\s+(.+)\s*$/ || $i == scalar @lines + 1 ) )
        {
            if ( defined $record_type ) {
                my $record_name;
                my @words;
                foreach my $word ( split /\_/, $record_type ) {
                    push @words, ucfirst lc $word;
                }
                $record_name = join " ", @words;

                $record_name = $fieldkeys{$record_type}
                  if ( defined $fieldkeys{$record_type} );

                push @{ $result{$record_name}{"source"} },
                  "KEGG " . ucfirst $type;

                if ( $record_type eq "NAME" ) {
                    $record_content =~ s/[\:\;]//g;
                    $record_content =~ s/(\(.*\))//g if ( $type eq "drug" );

                    push @names, split /\s\-\s|\,\s|\n/, $record_content;

                    foreach my $name (@names) {
                        if ( $name !~ /^E\d+\./ ) {
                            push @{ $result{$record_name}{"value"} }, $name;
                            push @{ $result{$record_name}{"source"} },
                              "KEGG " . ucfirst $type;
                            last;
                        }
                    }
                    if (  !defined $result{$record_name}{"value"}
                        && scalar @names > 0 )
                    {
                        $names[0] =~ s/\./\_/g;
                        push @{ $result{$record_name}{"value"} }, $names[0];
                    }

                }
                elsif ( $record_type eq "SEQUENCE" ) {
                    if ( $record_content =~ /(.*)\nORGANISM.*\[(\w+)\:(\w+)\]/ )
                    {
                        my ( $seq, $spec, $keggid ) = ( $1, $2, $3 );
                        my ( $species, $ncbi_taxid ) =
                          _find_tax_id_from_kegg($spec);

                        push @{ $result{"Species"}{"value"} }, $species;
                        push @{ $result{"Species"}{"source"} },
                          "KEGG " . ucfirst $type;
                        my $gene_topic =
                          Foswiki::Plugins::BioKbPlugin::BioKb::consult_dictionary(
                            $web, lc $spec . ":" . $keggid );
                        push @{ $result{"Gene"}{"value"} }, $gene_topic
                          if ( defined $gene_topic );
                        push @{ $result{$record_name}{"value"} }, $seq;
                    }
                }
                elsif ( $record_name eq "Gene" || $record_name eq "Genes" ) {
                    if ( lc $type eq "ko" ) {
                        my @keggids =
                          $record_content =~ /([a-z]{3,3}\:\s*\w+)/gi;
                        for ( my $i = 0 ; $i < scalar @keggids ; $i++ ) {
                            $keggids[$i] =~ s/\s//g;
                        }
                        push @{ $lists{"Genes"} }, @keggids;

                    }
                    elsif ( lc $type eq "pathway" ) {
                        my @gene_numbers = $record_content =~ /^(\d+)/mg;
                        my ($spec) =
                          @{ $result{"Entry"}{"value"} }[0] =~
                          /^([A-Za-z]{3,3})/;

                        # Add the species while we're at it...

                        my ( $species, $ncbi_taxid ) =
                          _find_tax_id_from_kegg($spec);
                        push @{ $result{"Species"}{"value"} }, $species;
                        push @{ $result{"Species"}{"source"} },
                          "KEGG " . ucfirst $type;

                        foreach my $gn (@gene_numbers) {
                            push @{ $lists{"Genes"} }, $spec . ":" . $gn;
                        }
                    }
                }
                elsif ( $record_name eq "Compound" ) {
                    my @ids = $record_content =~ /^([CD]\d+)/mg;
                    push @{ $lists{"Compounds"} }, @ids;
                }
                elsif ( $record_name eq "Reference" ) {
                    my ($pmid) = $record_content =~ /PMID\:(\d+)/;
                    push @pmids, $pmid;
                }
                elsif ( defined $dbtypes{$record_type} ) {
                    my @dblinks = $record_content =~ m/^(\S+\:\s*.+)/mg;
                    my @dbs;
                    my @dbids;

                    foreach my $dbl (@dblinks) {
                        my ( $db, $dbids ) = $dbl =~ /(\S+)\:\s*(.+)/;
                        $db = $dbnames{$db} if ( defined $dbnames{$db} );
                        foreach my $dbid ( split /\s/, $dbids ) {
                            next if ( $dbid eq "" );
                            push @dbs,   $db;
                            push @dbids, $dbid;
                            last
                              if ( $record_type eq "PATHWAY"
                                || $record_type eq "ORTHOLOGY" );
                        }
                    }
                    push @{ $result{$record_name}{"value"} }, \@dbids;
                    push @{ $result{ $record_name . "_db" }{"value"} }, \@dbs;
                }
                elsif ( $record_name eq "Products" ) {
                    $record_content =~ s/\n/\<br \/\>/g;
                    push @{ $result{$record_name}{"value"} }, $record_content;
                }
                else {
                    $record_content =~ s/\s?\[[^\]]+\]\s?//g;
                    push @{ $result{$record_name}{"value"} }, $record_content;
                }
            }

            $record_type    = $1;
            $record_content = $2;
        }
        elsif ( $line =~ /^\s+(\S.+)\s*/ ) {
            $record_content .= "\n" . $1;
        }
    }
    $result{"Title"} = clone( $result{$titlefield} );

    if ( defined @{ $result{"Title"}{"value"} }[0]
        && @{ $result{"Title"}{"value"} }[0] =~ /Transferred to/ )
    {
        return;
    }

    # Add in the list values

    foreach my $list ( keys %lists ) {
        push @{ $result{$list}{"value"} },  $lists{$list};
        push @{ $result{$list}{"source"} }, "KEGG " . ucfirst $type;

        my @dbs;
        foreach my $id ( @{ $lists{$list} } ) {
            my $db = "KEGG " . ucfirst $list;
            $db =~ s/s\s*$//;
            push @dbs, $db;
        }
        push @{ $result{ $list . "_db" }{"value"} }, \@dbs;
    }

    push @{ $result{"PubMed"}{"value"} }, join ",", @pmids;
    push @{ $result{"PubMed"}{"source"} }, "KEGG " . ucfirst $type;

    if ( !defined $result{"Title"}{"value"} ) {
        my $title = "";
        foreach my $word ( split /\s/, $result{"Definition"}{"value"} ) {
            $title .= ucfirst $word;
        }
        push @{ $result{"Title"}{"source"} }, "KEGG " . ucfirst $type;
        push @{ $result{"Title"}{"value"} },  $title;
    }

    return ( \%result );
}

=pod

Does what it says- employing the mapping file from KEGG

=cut

sub _find_tax_id_from_kegg {
    my $kegg_species = lc shift;

    my $convert = Foswiki::Func::readAttachment( "System", "BioKbPlugin",
        "kegg_to_ncbi.txt" );

    my ( $species, $taxid ) = $convert =~ /$kegg_species\t([^\t]+)\t(\d+)/;

    return ( $species, $taxid );
}

=pod

Find the more informative name of the KEGG pathway- if map_title.tab from KEGG is present

=cut

sub find_kegg_path_name {

    my $pathway_id = shift;
    my ($pathway_number) = $pathway_id =~ m/\D+(\d+)/;
    my $workarea = Foswiki::Func::getWorkArea("BioKbPlugin");

    my $pathway_name;
    my $kegg_name_file = $workarea . "/map_title.tab";

    if ( -e $kegg_name_file ) {
        open( MT, $kegg_name_file );
        while ( my $line = <MT> ) {
            chomp $line;
            my ( $id, $name ) = $line =~ /(\S+)\s+(.+)/;
            if ( $id eq $pathway_number ) {
                $pathway_name = $name;
            }
        }
        close(MT);
    }
    else {
        throw Foswiki::OopsException(
            'generic',
            params => [
"Please obtain map_table.tab from the KEGG ftp site and save it at "
                  . $workarea
                  . "/map_title.tab\n",
                "",
                "",
                ""
            ]
        );
    }

    return $pathway_id if ( !defined $pathway_name || $pathway_name eq "" );

    return $pathway_name;
}

=pod

This was supposed to extract some synonyms from KEGG definition fields. But it got a bit messy, so not used right now.

=cut

sub _synonyms_from_definition {

    my $def = shift;
    return if ( !defined $def );

# Try and extract additional synonyms from the Definition term- probably derived from KEGG

    # Remove EC terms and other things in brackets and add to synonyms

    my @defterms;

    $def =~ s/\.\-//;

    while ( $def =~ /([\[\(]([^\[\]\(\)]+)[\]\)])/ ) {
        my ( $outer, $inner ) = ( $1, $2 );
        $outer =~ s/([^\w\s]+)/\\$1/g;
        $def   =~ s/\s*$outer//;
        push @defterms, $inner;
    }

    @defterms = Foswiki::Plugins::BioKbPlugin::BioKb::untaint( \@defterms );
    unshift @defterms, $def;

# Extra synonyms from splitting on commas- only the first of these is usually valuable;

    my @splitterms;

    foreach my $defterm (@defterms) {
        if ( $defterm =~ /\,/ ) {
            my @dat = split /\,/, $defterm;
            push @defterms, $dat[0];
        }
    }

    return @defterms;
}

##########################################################################################
#                                                                                        #
#                                 iHOP Handling                                          #
#                                                                                        #
##########################################################################################

=pod

Generate an iHOP link given gene name and species

=cut

sub _make_ihop_url {

    my ( $web, $par ) = @_;
    my %parsed = %{$par};

    my @admin =
      Foswiki::Plugins::BioKbPlugin::BioKb::read_admin( $web, "DatabaseURLs" );
    my %prefixes = %{ $admin[0] };

    my $ihop_url;

    my ( $spec, $geneid ) = $parsed{"Entry"} =~ /(\w+)\:(\w+)/;
    my ( $species, $ncbi_taxid ) = _find_tax_id_from_kegg($spec);

    $ihop_url = $prefixes{"ihop"};
    my $title = $parsed{"Title"}{"value"};
    $ihop_url =~ s/TAX/$ncbi_taxid/;
    $ihop_url =~ s/VAL/$title/;

    return $ihop_url;
}

=pod

Given a gene ID, see if we can find some synonyms in iHOP

=cut

sub _get_ihop_synonyms {

    my ($gene) = @_;

    my @synonyms;
    my $workarea = Foswiki::Func::getWorkArea("BioKbPlugin");

    my $unparsedsom;

    foreach my $dir ( "ihop", "ihop/failed" ) {
        mkdir $workarea . "/$dir" if ( !-e $workarea . "/$dir" );
    }

    $gene =~ s/\W/\_/g;
    my $ihopfile   = $workarea . "/ihop/" . $gene;
    my $ihopfailed = $workarea . "/ihop/failed/$gene";

    if ( -e $ihopfile ) {
        $unparsedsom = Foswiki::Func::readFile($ihopfile);
    }
    else {

        my $uri = 'http://www.pdg.cnb.uam.es/UniPub/iHOP/xml';
        my $proxy =
          'http://ubio.bioinfo.cnio.es/biotools/iHOP/cgi-bin/iHOPSOAP';

        my $soap = new SOAP::Lite( uri => $uri, proxy => $proxy );
        $soap->outputxml('true');

        ($unparsedsom) = $soap->call( 'getSymbolInfoFromSymbol', $gene );

# This step is needed to avoid problems with XML entities encoded inside the soap message

        $unparsedsom =~ s/&amp;#([0-9]+);/&#$1;/g;

        if ( $unparsedsom =~ /Not Found/ ) {
            Foswiki::Func::saveFile( $ihopfailed, $unparsedsom );
            return @synonyms;
        }
        else {
            Foswiki::Func::saveFile( $ihopfile, $unparsedsom );
        }

        sleep 1;
    }

    if ( defined $unparsedsom && $unparsedsom ne "" ) {
        ($unparsedsom) =
          Foswiki::Plugins::BioKbPlugin::BioKb::untaint( [$unparsedsom] );

        use XML::LibXML;
        my ($parser) = XML::LibXML->new();
        my ($doc)    = $parser->parse_string($unparsedsom);
        my ($result) = ( $doc->getElementsByLocalName('result') )[0];

        if ( defined $result ) {

            my @syns = $result->getElementsByTagName("synonym");

            for ( my $i = 0 ; $i < scalar @syns ; $i++ ) {
                my $syn = $syns[$i]->textContent();
                next if ( length $syn < 5 || $syn =~ /type \d/i );
                push @synonyms, $syn;
            }
        }
    }
    return @synonyms;
}

1

