package Foswiki::Plugins::BioKbPlugin::Disease;

use strict;

use Scalar::Util qw(tainted);
use LWP::Simple;
use Cwd;

select( ( select(STDOUT), $| = 1 )[0] );

#####################################################
#                                                   #
#                      Search                       #
#                                                   #
#####################################################

=pod

Employing OMIM's 'morbid map', try and map a series of gene names to relevant disease conditions

=cut

sub find_diseases {

    my ( $web, @genes ) = @_;
    my %diseases;

    my $query = "\\W" . ( join "\\W\|\\W", @genes ) . "\\W";

    my $morbidmap =
      Foswiki::Func::readAttachment( "System", "BioKbPlugin", "morbidmap" );
    my @matches = grep /$query/, ( split "\n", $morbidmap );

    my @disease_ids;
    foreach my $m (@matches) {
        if ( $m =~ /[\{\[]?([\s,\w]+)[\]\}]?,\s+(\d+)/ ) {
            my ( $disease, $disease_id ) = ( $1, $2 );
            next if ( !defined $disease_id );
            push @disease_ids, $disease_id;
        }
    }

    my @records = _fetch_omim(@disease_ids);
    foreach my $record (@records) {
        my $dis = _parse_omim($record);
        next if ( !defined $dis );
        my %disease = %{$dis};
        $disease{"type"} = "Disease";
        $diseases{ $disease{"Entry"}{"value"} } = \%disease;
    }
    return %diseases;
}

=pod

OMIM records often have references- see if we can parse these out

=cut

sub _pubmed_ids_from_references {
    my @references = @_;

    my @pubmed_ids;
    my @authorlist;
    for ( my $i = 0 ; $i < scalar @references ; $i++ ) {
        my ( $title, $firstauthor, $authors, $year );
        if ( $references[$i] =~
            /\d+\.(\s*(\w+)[^\:]+)\:\s*(\w[^\.]+).+(\d{4,4})/ )
        {
            ( $authors, $firstauthor, $title, $year ) = ( $1, $2, $3, $4 );
        }
        else {
            next;
        }

        # Determine pubmed ID for this reference

        my ($pmid) =
          Foswiki::Plugins::BioKbPlugin::Literature::eutils_search( $title, 1 );
        next if ( !defined $pmid || $pmid !~ /\d/ );

        # Detaint

        my ($pubmed_id) = $pmid =~ /(\d+)/;

        push @pubmed_ids, $pubmed_id;
        push @authorlist, $authors;
    }
    return ( \@pubmed_ids, \@authorlist );
}

#####################################################
#                                                   #
#               Deal with OMIM                      #
#                                                   #
#####################################################

=pod

Fetch particular records from the OMIM database file

=cut

sub _fetch_omim {
    my @ids = @_;

    my %idhash = map { $_, 1 } @ids;

    my $workarea = Foswiki::Func::getWorkArea("BioKbPlugin");

    my $omim_file = $workarea . "/omim.txt";
    if ( !-e $omim_file ) {
        throw Foswiki::OopsException(
            'generic',
            params => [
"Please obtain the omim database (omim.txt) and place it at $omim_file\n",
                "",
                "",
                ""
            ]
        );
    }

    my @records;

    my $record;
    my $field;
    my $record_id;

    open( OMIM, $omim_file );
    while ( my $line = <OMIM> ) {
        chomp $line;
        if ( $line =~ /\*RECORD\*/ || $line =~ /\*THEEND\*/ ) {
            next if ( !defined $field );

            #if ( $record_id == $id ) {
            #last;
            if ( defined $idhash{$record_id} ) {
                ($record) =
                  Foswiki::Plugins::BioKbPlugin::BioKb::untaint( [$record] );
                push @records, $record;
                last if ( scalar @records == scalar @ids );
            }
            else {
                undef $record;
                undef $field;
            }
        }
        elsif ( $line =~ /\*FIELD\*\s+(\w+)/ ) {
            $field = $1;
        }
        elsif ( $field eq "NO" ) {
            $record_id = $line;
        }
        $record .= $line . "\n";
    }
    close(OMIM);

    return @records;
}

=pod 

Parse an OMIM record

=cut

sub _parse_omim {
    my ($text) = @_;

    my %omimkey = (
        "CN"   => "Contributors",
        "NO"   => "Entry",
        "AV"   => "Allelic Variant",
        "CH"   => "Chromosome",
        "CS"   => "Clinical Synopsis",
        "AU"   => "Contributors",
        "CD"   => "Creation Data",
        "EC"   => "EC Number",
        "ED"   => "Editor",
        "FI"   => "Filter",
        "GM"   => "Gene Map",
        "DI"   => "Gene Map Disorder",
        "GN"   => "Gene Name",
        "ID"   => "MIM Number",
        "MD"   => "Modification Date",
        "HIST" => "Modification History",
        "PR"   => "Properties",
        "RF"   => "Reference",
        "SA"   => "Additional References",
        "TX"   => "Text",
        "TI"   => "Title"
    );

    my %record;
    my $field;

    foreach my $line ( split /\n/, $text ) {
        if ( $line =~ /\*FIELD\*\s+(\w+)/ ) {
            chomp $record{$field} if ( defined $field );
            $field = $1;
            die "Unrecognised OMIM field $field\n"
              if ( !defined $omimkey{$field} );
        }
        elsif ( defined $field ) {
            $record{$field} .= $line . "\n";
        }
    }

    # Try to eliminate inappropriate newlines

    foreach my $linedfield ( "RF", "TX", "SA" ) {
        next if ( !defined $record{$linedfield} );
        if ( $record{$linedfield} =~ /(\S)\n(\S)/ ) {
            $record{$linedfield} =~ s/(\S)\n(\S)/$1 $2/g;
        }
    }

    $record{"TX"} =~ s/^A number sign.+$//mg;

    # Add user-friendly tags

    my %out;

    foreach my $key ( keys %record ) {
        push @{ $out{ $omimkey{$key} }{"value"} },  $record{$key};
        push @{ $out{ $omimkey{$key} }{"source"} }, "OMIM";
    }

    my ($longtitle) = $record{"TI"} =~ /^[\+\*\#\%]?\d+\s*([^\;]+)\;?/;

    delete $out{"Title"};
    my $title      = "";
    my $dest_topic = "";
    foreach my $word ( split /\W+/, $longtitle ) {
        $title .= ucfirst( lc $word ) . " ";
        $dest_topic .= ucfirst lc $word;
    }
    push @{ $out{"Title"}{"value"} },  $title;
    push @{ $out{"Title"}{"source"} }, "OMIM";
    $out{"dest_topic"}{"value"} = $dest_topic;

    return \%out;
}

1
