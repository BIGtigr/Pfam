# Family.pm
# jt6 20060411 WTSI
#
# $Id: Family.pm,v 1.54 2010-01-13 14:44:53 jt6 Exp $

=head1 NAME

PfamWeb::Controller::Family - controller to build the main Pfam family
page

=cut

package PfamWeb::Controller::Family;

=head1 DESCRIPTION

This is intended to be the base class for everything related to Pfam
families across the site. The L<begin|/"begin : Private"> method tries
to extract a Pfam ID or accession from the captured URL and tries to
load a Pfam object from the model.

Generates a B<tabbed page>.

$Id: Family.pm,v 1.54 2010-01-13 14:44:53 jt6 Exp $

=cut

use utf8;
use Moose;
use namespace::autoclean;

use LWP::UserAgent;
use Compress::Zlib;
use JSON;
use Text::Wrap qw( $columns wrap );

$Text::Wrap::columns = 60;

BEGIN {
  extends 'Catalyst::Controller::REST';
}

# roles that add the bulk of the functionality to this controller. When applying
# the "Section" role from PfamBase, we specifically exclude the "section" action,
# otherwise the "/family?acc=blah" redirect action doesn't get registered.
with 'PfamBase::Roles::Section' => { -excludes => 'section' },
     'PfamWeb::Roles::Family::HMM',
     'PfamWeb::Roles::Family::Methods',
     'PfamWeb::Roles::Family::Structure',
     'PfamWeb::Roles::Family::Tree',
     'PfamWeb::Roles::Family::Alignment',
     'PfamBase::Roles::SunburstMethods';

# set up the list of content-types that we handle via REST
__PACKAGE__->config(
  'default' => 'text/html',
  'content_type_stash_key' => 'serialize_to_content_type',
  'map'     => {
    'text/html'        => [ 'View', 'TT' ],
    'text/xml'         => [ 'View', 'TT' ],
    'text/plain'       => [ 'View', 'TT' ],
    'application/json' => 'JSON',
  }
);

# set the name of the section
__PACKAGE__->config( SECTION => 'family' );

has allowed_alignment_types => (
 is      => 'ro',
 default => sub { { full => 1,
                    seed => 1,
                    rp15 => 1,
                    rp35 => 1,
                    rp55 => 1,
                    rp75 => 1,
                    ncbi => 1,
                    meta => 1,
                    uniprot => 1,
                    long => 1 } },
);

#-------------------------------------------------------------------------------

=head1 ACTIONS

=head2 begin : Private

Extracts the Pfam family ID or accession from parameters on the URL. Handles
any of three parameters:

=over

=item acc

a valid Pfam accession, either for an A or B entry

=item id

a valid Pfam accession

=item entry

either an ID or accession

=back

This is the way in when there are parameters but for "RESTful" URLs, the
chained actions pick up.

=cut

sub begin : Private {
  my ( $this, $c ) = @_;

  # decide what format to emit. The default is HTML, in which case
  # we don't set a template here, but just let the "end" method on
  # the Section controller take care of us
  if ( defined $c->req->param('output') ) {
    if ( $c->req->param('output') eq 'xml' ) {
      $c->stash->{output_xml} = 1;
      # $c->res->content_type('text/xml');

      # the XML response is generated by serialising a slot in the stash. This
      # is done by Catalyst::Action::Serialize. It's paying attention to the
      # content type specified in the request, but we're using a request
      # parameter to decide that. Setting this value in the stash to the
      # necessary content type will override whatever C::A::Serialize would
      # otherwise use
      $c->stash->{serialize_to_content_type} = 'text/xml';

      # enable CORS (see http://www.w3.org/wiki/CORS_Enabled)
      $c->res->header( 'Access-Control-Allow-Origin' => '*' );
    }
    elsif ( $c->req->param( 'output' ) eq 'pfamalyzer' ) {
      $c->stash->{output_pfamalyzer} = 1;
      $c->res->content_type('text/plain');
      $c->stash->{serialize_to_content_type} = 'text/plain';
    }
  }

  # see if the entry is specified as a parameter
  my $tainted_entry = $c->req->param('acc')   ||
                      $c->req->param('id')    ||
                      $c->req->param('entry') ||
                      $c->req->query_keywords || # accept getacc-style params
                      '';

  if ( $tainted_entry ) {
    $c->log->debug( 'Family::begin: got a tainted entry' )
      if $c->debug;
    ( $c->stash->{param_entry} ) = $tainted_entry =~ m/^([\w-]+)(\.\d+)?$/;
  }

  $c->forward('deserialize');
}

sub deserialize : ActionClass('Deserialize') {}

#-------------------------------------------------------------------------------

=head2 end : Private

The L<Section> base class sets the C<end> action to use the L<RenderView>
C<ActionClass>, but that screws up the RESTful serialisation. Reset C<end> here
to use a serialiser to render the output, and rely on the mapping between
MIME type and serialiser to do the right thing.

=cut

sub end : Private {
  my ( $this, $c ) = @_;

  if ( scalar @{ $c->error } ) {
    $c->log->debug( 'Family::end: caught an error; setting error template and serialising' )
      if $c->debug;

    $c->stash->{template} = $c->stash->{output_xml}
                          ? 'rest/family/error_xml.tt'
                          : 'components/blocks/family/error.tt';

    $c->clear_errors;
  }

  # hand off to the serialiser to do its thing
  $c->forward('serialize');
}

sub serialize : ActionClass('Serialize') {}

#-------------------------------------------------------------------------------
#- main family actions ---------------------------------------------------------
#-------------------------------------------------------------------------------

=head2 family : Chained

Tries to get a row from the DB for the family. This is the entry point for
URLs with the accession/ID given like "/family/piwi".

=cut

sub family : Chained( '/' )
             PathPart( 'family' )
             CaptureArgs( 1 ) {
  my ( $this, $c, $entry_arg ) = @_;

  my $tainted_entry = $c->stash->{param_entry} ||
                      $entry_arg               ||
                      '';

  $c->log->debug( "Family::family: tainted_entry: |$tainted_entry|" )
    if $c->debug;

  # although these next checks might fail and end up putting an error message
  # into the stash, we don't "return", because we might want to process the
  # error message using a template that returns XML rather than simply HTML

  my $entry;
  if ( $tainted_entry ) {
    # strip off family version numbers, if present
    ( $entry ) = $tainted_entry =~ m/^([\w-]+)(\.\d+)?$/;
    $c->stash->{errorMsg} = 'Invalid Pfam family accession or ID'
      unless defined $entry;
  }
  else {
    $c->stash->{errorMsg} = 'No Pfam family accession or ID specified';
  }

  # retrieve data for the family
  $c->forward( 'get_data', [ $entry ] ) if defined $entry;
}

#-------------------------------------------------------------------------------

=head2 family_page : Chained

End point of a chain, which captures the URLs for the family page.

=cut

sub family_page : Chained( 'family' )
                  PathPart( '' )
                  Args( 0 ) {
  my ( $this, $c ) = @_;

  # if we don't have an entry to work with by now, we're done
  unless ( $c->stash->{pfam} ) {
    $c->stash->{errorMsg} = 'No valid Pfam family accession or ID specified';
    $c->stash->{template} = $c->stash->{output_xml}
                          ? 'rest/family/error_xml.tt'
                          : 'components/blocks/family/error.tt';
    return;
  }

  # cache page for 1 week
  $c->cache_page( 604800 );

  # dead families are a special case...
  if ( defined $c->stash->{entryType} and
       $c->stash->{entryType} eq 'D' ) {

    $c->log->debug( 'Family::family_page: got a dead family; setting a refresh URI' )
      if $c->debug;

    if ( $c->stash->{pfam}->forward_to ) {
      $c->stash->{refreshUri} =
        $c->secure_uri_for( '/family', $c->stash->{pfam}->forward_to );
    }
    else {
      $c->stash->{refreshUri} = $c->secure_uri_for( '/' );

      # the default delay for redirecting is 5 seconds, but that's maybe
      # too short to allow the user to read the message telling them that
      # they're going to be redirected to the home page. Pause for a little
      # longer in this case
      $c->stash->{refreshDelay} = 20;
    }

    # set the template. This will be overridden below if we're emitting XML
    $c->stash->{template} = 'pages/dead.tt';

    return;
  }

  #----------------------------------------

  # use a redirect page if the ID of the family has changed
  if ( defined $c->stash->{entryType} and
       $c->stash->{entryType} eq 'R' ) {

    $c->log->debug( 'Family::family_page: arrived at a family using a previous ID; setting a refresh URI' )
      if $c->debug;

    $c->stash->{refreshUri} =
      $c->secure_uri_for( '/family', $c->stash->{acc} );

    # set the template for the intermediate page
    $c->stash->{template} = 'pages/moved.tt';

    return;
  }

  #----------------------------------------

  # add extra data to the stash, stuff that's required only to generate a page

  # GO data
  my @goTerms = $c->model('PfamDB::GeneOntology')
                  ->search( { pfama_acc => $c->stash->{pfam}->pfama_acc } );

  $c->stash->{goTerms} = \@goTerms;

  # copy required config values into the stash
  $c->stash->{sequence_size_display_limit} = $this->{sequence_size_display_limit};
  $c->stash->{raw_sequence_scale}          = $this->{raw_sequence_scale};
  # (scale is calculated as num seqs * av length)

  #----------------------------------------

  # detect DUFs
  $c->stash->{is_duf} = ( $c->stash->{pfam}->pfama_id =~ m/^DUF\d+$/ );

  #----------------------------------------

  # output is specific to PfamAlyzer
  if ( $c->stash->{output_pfamalyzer} ) {

    $c->log->debug( 'Family::family_page: outputting plain text for PfamAlyzer' )
      if $c->debug;

    $c->stash->{template} = 'rest/family/entry_pfamalyzer.tt';
  }

  # output is in XML format
  elsif ( $c->stash->{output_xml} ) {

    $c->log->debug( 'Family::family_page: outputting XML' )
      if $c->debug;

    # if there was an error...
    if ( $c->stash->{errorMsg} ) {
      $c->log->debug( 'Family::family_page: there was an error: |' .
                      $c->stash->{errorMsg} . '|' ) if $c->debug;
      $c->stash->{template} = 'rest/family/error_xml.tt';
      return;
    }

    # decide on the output template, based on the type of family that we have
    if ( $c->stash->{entryType} eq 'A' or
         $c->stash->{entryType} eq 'R' ) {
      # we'll use the same XML template to handle familes that were arrived at
      # using a "previous ID"
      $c->log->debug( 'Family::family_page: got data for a Pfam-A' ) if $c->debug;
      $c->stash->{template} = 'rest/family/pfama_xml.tt';
    }
    elsif( $c->stash->{entryType} eq 'B' ) {
      $c->log->debug( 'Family::family_page: got data for a Pfam-B' ) if $c->debug;
      $c->stash->{template} = 'rest/family/pfamb_xml.tt';
    }
    elsif( $c->stash->{entryType} eq 'D' ) {
      $c->log->debug( 'Family::family_page: got data for a dead family' ) if $c->debug;
      $c->stash->{template} = 'rest/family/dead_xml.tt';
    }
    else {
      $c->log->debug( 'Family::family_page: got an error' ) if $c->debug;
      $c->stash->{template} = 'rest/family/error_xml.tt';
    }

  }

  # output is a web page
  else {

    $c->log->debug( 'Family::family_page: outputting HTML' )
      if $c->debug;

    # we need to set the template explicitly here. It used to be set by the
    # "end" method that we got from the Section controller, but we're
    # overriding that so that we can use the RESTful controller for the
    # sunburst stuff
    $c->stash->{pageType} = 'family';
    $c->stash->{template} = 'pages/layout.tt';

    $c->log->debug( 'Family::family_page: adding extra family info' ) if $c->debug;

    # add the clan details, if any
    my $clan = $c->model('PfamDB::ClanMembership')
                          ->search( { 'pfama_acc' => $c->stash->{pfam}->pfama_acc },
                                    {  prefetch   => 'clan_acc' })->first;


    if($clan){

        $c->log->debug( 'Family::family_page: adding clan info' ) if $c->debug;
        $c->stash->{clan} = $clan->clan_acc;
        my @clanMembers = $c->model('PfamDB::ClanMembership')
                              ->search( {'clan_acc' => $clan->clan_acc->clan_acc },
                                        { prefetch => [qw(pfama_acc) ] });

        $c->stash->{clanMembers} = \@clanMembers;
    }

    $c->forward( 'get_summary_data' );
    $c->forward( 'get_db_xrefs' );
    $c->forward( 'get_interactions' );
    #$c->forward( 'get_pseudofam' );
    $c->forward( 'get_wikipedia' );

    return;

  } # end of "else"

}

#---------------------------------------

=head2 old_family : Path

Deprecated. Stub to redirect to the chained action.

=cut

sub old_family : Path( '/family' ) {
  my ( $this, $c ) = @_;

  $c->log->debug( 'Family::old_family: redirecting to "family"' )
    if $c->debug;

  delete $c->req->params->{id};
  delete $c->req->params->{acc};
  delete $c->req->params->{entry};

  if ( $c->stash->{param_entry} ) {
    $c->res->redirect( $c->secure_uri_for( '/family', $c->stash->{param_entry}, $c->req->params ) );
  }
  else {
    $c->stash->{errorMsg} = 'No Pfam family accession or ID specified';
    $c->stash->{template} = $c->stash->{output_xml}
                          ? 'rest/family/error_xml.tt'
                          : 'components/blocks/family/error.tt';
  }
}

#-------------------------------------------------------------------------------

=head2 sunburst

Stub to add a "sunburst" pathpart. All methods from the L<SunburstMethods> Role
will be hung off this stub.

=cut

sub sunburst : Chained( 'family' )
               PathPart( 'sunburst' )
               CaptureArgs( 0 ) {
  my ( $this, $c ) = @_;

  # specify the queue to use when submitting sunburst-related jobs
  $c->stash->{alignment_job_type} = 'pfalign';
}

#-------------------------------------------------------------------------------
#- general family-related private actions --------------------------------------
#-------------------------------------------------------------------------------

=head1 PRIVATE ACTIONS

=head2 get_data : Private

Retrieves family data for the given entry. Accepts the entry ID or accession
as the first argument. Does not return any value but drops the L<ResultSet>
for the relevant row into the stash.

=cut

sub get_data : Private {
  my ( $this, $c, $entry ) = @_;

  # check for a Pfam-A
  my $rs = $c->model('PfamDB::Pfama')
             ->search( [ { 'me.pfama_acc' => $entry },
                         { 'me.pfama_id'  => $entry } ],
                       { join     => [ { clan_memberships => 'clan_acc' },
                                       "interpros",
                                       "pfama_species_trees2" ],
                          prefetch => [ qw( interpros pfama_species_trees2 ) ] } );

  my $pfam = $rs->first if defined $rs;

  if ( $pfam ) {
    $c->log->debug( 'Family::get_data: got a Pfam-A' ) if $c->debug;
    $c->stash->{pfam}      = $pfam;
    $c->stash->{acc}       = $pfam->pfama_acc;
    $c->stash->{entryType} = 'A';

    return; # unless $c->stash->{output_xml};

  } # end of "if pfam..."

  #----------------------------------------
  # check for a dead Pfam-A

  if ( not $pfam ) {
    $pfam = $c->model('PfamDB::DeadFamily')
              ->search( [ { pfama_acc => $entry },
                          { pfama_id  => $entry } ] )
              ->single;

    if ( $pfam ) {
      $c->log->debug( 'Family::get_data: got a dead family' ) if $c->debug;
      $c->stash->{pfam}      = $pfam;
      $c->stash->{acc}       = $pfam->pfama_acc;
      $c->stash->{entryType} = 'D';
      return;
    }
  }

  #----------------------------------------
  # check for a previous ID

  if ( not $pfam ) {
    $pfam = $c->model('PfamDB::Pfama')
              ->find( { previous_id => { like => "%$entry;%" } } );

    # make sure the entry matches a whole ID, rather than just part of one
    # i.e. make sure that "6" doesn't match "DUF456"
    if ( $pfam ) {
      my $previous_id = $pfam->previous_id;
      if ( $previous_id =~ m/(^|.*?;\s*)$entry\;/ ) { # same pattern used in Jump.pm
        $c->log->debug( 'Family::get_data: got a family using a previous ID' )
          if $c->debug;
        $c->stash->{pfam}      = $pfam;
        $c->stash->{acc}       = $pfam->pfama_acc;
        $c->stash->{entryType} = 'R';
        return;
      }
    }
  }

  #----------------------------------------
  # there's a problem... by this point we really should have retrieved a
  # row and returned

  $c->stash->{errorMsg} = 'No valid Pfam family accession or ID';
}

#-------------------------------------------------------------------------------

=head2 get_summary_data : Private

Retrieves summary data for the family. For most fields this is a simple look-up
on the PfamA object that we already have, but for the number of interactions
we have to do one more query.

=cut

sub get_summary_data : Private {
  my ( $this, $c ) = @_;

  my $summaryData = {};

  # number of architectures....
  $summaryData->{numArchitectures} = $c->stash->{pfam}->number_archs;

  # number of sequences in full alignment
  $summaryData->{numSequences} = $c->stash->{pfam}->num_full;

  # number of structures known for the domain
  $summaryData->{numStructures} = $c->stash->{pfam}->number_structures;

  # Number of species
  $summaryData->{numSpecies} = $c->stash->{pfam}->number_species;

  # number of interactions
  my $pfamA_acc = $c->stash->{pfam}->pfama_acc;
  my $rs = $c->model('PfamDB::PfamaInteractions')
             ->search( [ { pfama_acc_a => $pfamA_acc }, {pfama_acc_b => $pfamA_acc} ],
                       { select => [ { count => 'pfama_acc_a' } ],
                         as     => [ qw( numInts ) ] } )
             ->first;
  $summaryData->{numInt} = $rs->get_column( 'numInts' );

  $c->stash->{summaryData} = $summaryData;
}

#-------------------------------------------------------------------------------

=head2 get_db_xrefs : Private

Retrieve the database cross-references for the family.

=cut

sub get_db_xrefs : Private {
  my ( $this, $c ) = @_;

  my $xRefs = {};

  # stuff in the accession and ID for this entry
  $xRefs->{entryAcc} = $c->stash->{pfam}->pfama_acc;
  $xRefs->{entryId}  = $c->stash->{pfam}->pfama_id;

  # Interpro
  my $i = $c->model('PfamDB::Interpro')
            ->find( $c->stash->{pfam}->pfama_acc );

  push @{ $xRefs->{interpro} }, $i if defined $i;


  # PDB
  $xRefs->{pdb} = keys %{ $c->stash->{pdbUnique} }
    if $c->stash->{summaryData}{numStructures};


  # PfamA relationship based on SCOOP
  my @ataSCOOP = $c->model('PfamDB::Pfama2pfamaScoop')
                   ->search( { pfama_acc_1 => $c->stash->{pfam}->pfama_acc,
                               score       => { '>', 10.0 } },
                             { join        => [ qw( pfama_acc_1 pfama_acc_2 ) ],
                               select      => [ qw( pfama_acc_1.pfama_id
                                                    pfama_acc_2.pfama_id
                                                    pfama_acc_1.pfama_acc
                                                    pfama_acc_2.pfama_acc
                                                    score ) ],
                               as          => [ qw( l_pfama_id
                                                    r_pfama_id
                                                    l_pfama_acc
                                                    r_pfama_acc
                                                    score ) ]
                             } );

  my @ataSCOOP2 = $c->model('PfamDB::Pfama2pfamaScoop')
                ->search( { pfama_acc_2 => $c->stash->{pfam}->pfama_acc,
                              score       => { '>', 10.0 } },
                             { join        => [ qw( pfama_acc_2 pfama_acc_1 ) ],
                               select      => [ qw( pfama_acc_2.pfama_id
                                                    pfama_acc_1.pfama_id
                                                    pfama_acc_2.pfama_acc
                                                    pfama_acc_1.pfama_acc
                                                    score ) ],
                               as          => [ qw( l_pfama_id
                                                    r_pfama_id
                                                    l_pfama_acc
                                                    r_pfama_acc
                                                    score ) ]
                             } );


   push(@ataSCOOP, @ataSCOOP2);
   my @sortedSCOOP = sort { lc($a->get_column('r_pfama_id')) cmp lc($b->get_column('r_pfama_id'))  } @ataSCOOP;
   
   foreach my $ref ( @sortedSCOOP ) {
    if ( $ref->get_column('l_pfama_acc') ne $ref->get_column('r_pfama_acc') ) {
      push @{ $xRefs->{scoop} }, $ref;
    }
  }

  # PfamA to PfamB links based on ADDA
  my %atobPRODOM;
  foreach my $xref ( $c->stash->{pfam}->pfama_database_links ) {
    push @{ $xRefs->{$xref->db_id} }, $xref;
  }

  # PfamA to PfamA links based on HHsearch
  my @atoaHH = $c->model('PfamDB::Pfama2pfamaHhsearch')
                 ->search( { 'pfama_acc_1' => $c->stash->{pfam}->pfama_acc },
                           { join     => [ qw( pfama_acc_1 pfama_acc_2 ) ],
                             select   => [ qw( pfama_acc_1.pfama_id
                                               pfama_acc_1.pfama_acc
                                               pfama_acc_2.pfama_id
                                               pfama_acc_2.pfama_acc
                                               evalue ) ],
                             as       => [ qw( l_pfama_id
                                               l_pfama_acc
                                               r_pfama_id
                                               r_pfama_acc
                                               evalue ) ],
                             order_by => 'pfama_acc_2.pfama_acc ASC'
                           } );

  $xRefs->{atoaHH} = [];
  foreach ( @atoaHH ) {
    if ( $_->get_column( 'evalue' ) <= 0.001 and
         $_->get_column( 'l_pfama_id' ) ne $_->get_column( 'r_pfama_id' ) ) {
      push @{ $xRefs->{atoaHH} }, $_;
    }
  }

  $c->stash->{xrefs} = $xRefs;
}

#-------------------------------------------------------------------------------

=head2 get_interactions : Private

Retrieves details of the interactions between this family and others.

=cut

sub get_interactions : Private {
  my ( $this, $c ) = @_;

  my @interactions = $c->model('PfamDB::PfamaInteractions')
                       ->search( [{ pfama_acc_a => $c->stash->{pfam}->pfama_acc }, {pfama_acc_b => $c->stash->{pfam}->pfama_acc}],
                                 { prefetch => [ qw( pfama_acc_a pfama_acc_b ) ] } );

  $c->stash->{interactions} = \@interactions;
}

#-------------------------------------------------------------------------------

=head2 get_pseudofam : Private

Retrieves details of the interactions between this family and others.

=cut

sub get_pseudofam : Private {
  my ( $this, $c ) = @_;

  my $cache_key = 'pseudofam_families';
  $c->stash->{pseudofam_accessions} = $c->cache->get( $cache_key );

  if ( defined $c->stash->{pseudofam_accessions} ) {
    $c->log->debug( 'Family::get_pseudofam: retrieved pseudofam families list from cache' )
      if $c->debug;
  }
  else {
    $c->log->debug( 'Family::get_pseudofam: failed to retrieve pseudofam families list from cache; going to pseudofam web service' )
      if $c->debug;

    # get the accessions list from the web service
    $c->forward( 'get_pseudofam_accessions' );

    if ( defined $c->stash->{pseudofam_accessions} ) {
      $c->log->debug( 'Family::get_pseudofam: got pseudofam_accessions' )
        if $c->debug;
      $c->cache->set( $cache_key, $c->stash->{pseudofam_accessions} ) unless $ENV{NO_CACHE};
    }
    else {
      $c->log->debug( 'Family::get_pseudofam: failed to retrieve pseudofam accessions' )
        if $c->debug;
      return;
    }
  }

  # for convenience, pull the URL prefix out of the accessions hash and stash
  # it individually
  $c->stash->{pseudofam_prefix_url} = $c->stash->{pseudofam_accessions}->{_prefix};

  $c->log->debug( 'Family::get_pseudofam: got a hash of '
                  . scalar( keys %{$c->stash->{pseudofam_accessions} } )
                  . ' accessions' )
    if $c->debug;
}

#-------------------------------------------------------------------------------

=head2 get_pseudofam_accessions : Private

Parses the XML containing the list of pseudofam accessions.

=cut

sub get_pseudofam_accessions : Private {
  my ( $this, $c ) = @_;

  # go to the web service and retrieve the XML
  $c->forward( 'retrieve_pseudofam_xml' );

  # did we manage to retrieve it ?
  unless ( defined $c->stash->{pseudofam_xml} ) {
    $c->log->warn( 'Family::get_pseudofam_accessions: failed to retrieve pseudofam families list from the pseudofam web service: '
                   . $c->stash->{error} ) if $c->debug;
    return;
  }

  # now parse the XML to extract the list of families, which we then store
  # as hash keys
  my $xml_parser = XML::LibXML->new();
  my $xml_document;
  my $xml_root;
  eval {
    $xml_document = $xml_parser->parse_string( $c->stash->{pseudofam_xml} );
    $xml_root     = $xml_document->documentElement();
  };
  if ( $@ ) {
    $c->log->warn( "Family::get_pseudofam_accessions: failed to parse pseudofam xml: $@" )
      if $c->debug;
    return;
  }

  # get the family accessions
  my @accession_nodes = $xml_root->findnodes( '/pseudofam/families/accession' );
  $c->log->debug( 'Family::get_pseudofam_accessions: found '
                  . scalar @accession_nodes . ' accessions in file' )
    if $c->debug;

  my %accessions = map { $_->textContent => 1 } @accession_nodes;

  # get the URL prefix from the XML and drop that into the accessions hash
  my $prefix_url = $xml_root->find( '/pseudofam/families' )
                            ->shift()
                            ->getAttribute('urlPrefix');
  $accessions{_prefix} = $prefix_url;

  $c->stash->{pseudofam_accessions} = \%accessions;
}

#-------------------------------------------------------------------------------

=head2 retrieve_pseudofam_xml : Private

Retrieves the XML containing the list of pseudofam accessions from their web
service.

=cut

sub retrieve_pseudofam_xml : Private {
  my ( $this, $c ) = @_;

  if ( not defined $this->{_ua} ) {
    $c->log->debug( 'Family::retrieve_pseudofam_xml: building a new user agent' )
      if $c->debug;
    $this->{_ua} = LWP::UserAgent->new;
    $this->{_ua}->timeout(10);
    $this->{_ua}->env_proxy;
  }

  my $response = $this->{_ua}->get( $this->{pseudofam_ws_url} );

  if ( $response->is_success ) {
    $c->log->debug( 'Family::retrieve_pseudofam_xml: successful response from web service' )
      if $c->debug;
    $c->stash->{pseudofam_xml} = $response->decoded_content;
  }
  else {
    $c->log->debug( 'Family::retrieve_pseudofam_xml: got an error from web service' )
      if $c->debug;
    $c->stash->{error} = $response->status_line;
  }
}

#-------------------------------------------------------------------------------

=head2 get_wikipedia : Private

Retrieves the wikipedia content, if any, for this family.

=cut

sub get_wikipedia : Private {
  my ( $this, $c ) = @_;

  my @articles;
  eval {
    @articles = $c->model('WebUser::ArticleMapping')
      ->search( { accession => $c->stash->{acc} },
                { join      => [ 'wikitext' ], prefetch => [ 'wikitext' ] } );
  };

  return unless scalar @articles;

  $c->log->debug( 'Family::get_wikipedia: found ' . scalar @articles . ' articles' )
    if $c->debug;

  $c->stash->{articles} = \@articles;
}

#-------------------------------------------------------------------------------

=head2 build_fasta : Private

Builds a FASTA-format sequence file containing the region sequences for the
supplied accessions. This is used by the "required" by the L<SunburstMethods>
role.

Takes two arguments: ref to an array with the list of
accessions; boolean specifying whether or not to "pretty print" the sequences
by wrapping at 60 characters per line.

=cut

sub build_fasta : Private {
  my ( $this, $c, $accessions, $pretty ) = @_;

  $c->log->debug( 'Family::build_fasta: wrapping sequence lines' )
    if ( $c->debug and $pretty );

  my $fasta = '';
  foreach ( @$accessions ) {
    next unless m/^\w+$/;
    my $rs = $c->model( 'PfamDB::PfamaRegFullSignificant' )
               ->search( { 'me.pfamseq_acc' => $_,
                           'me.pfamA_acc' => $c->stash->{pfam}->pfama_acc,
                           in_full                    => 1 },
                         { join     => [ qw( pfama_acc pfamseq_acc ) ],
                           select   => [ qw( me.pfamseq_acc
                                             pfamseq_acc.seq_version
                                             seq_start
                                             seq_end
                                             pfamseq_acc.sequence
                                             pfamseq_acc.description ) ],
                           as       => [ qw( pfamseq_acc
                                             version
                                             seq_start
                                             seq_end
                                             sequence
                                             description ) ] } );
    while ( my $row = $rs->next ) {
      my $header = '>' .
                   $row->get_column('pfamseq_acc') . '.' . $row->get_column('version') . '/' .
                   $row->seq_start . '-' . $row->seq_end . ' ' .
                   $row->get_column('description');
      my $sequence = $row->get_column('sequence');
      $sequence =~ s/[-.]//g;
      $sequence = wrap( '', '', $sequence ) if $c->debug;
      $fasta .= "$header\n$sequence\n";
    }
  }

  return $fasta;
}

#-------------------------------------------------------------------------------

__PACKAGE__->meta->make_immutable;

#-------------------------------------------------------------------------------

=head1 AUTHOR

John Tate, C<jt6@sanger.ac.uk>

Rob Finn, C<rdf@sanger.ac.uk>

=head1 COPYRIGHT

Copyright (c) 2007: Genome Research Ltd.

Authors: Rob Finn (rdf@sanger.ac.uk), John Tate (jt6@sanger.ac.uk)

This is free software; you can redistribute it and/or modify it under
the terms of the GNU General Public License as published by the Free Software
Foundation; either version 2 of the License, or (at your option) any later
version.

This program is distributed in the hope that it will be useful, but WITHOUT
ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
FOR A PARTICULAR PURPOSE. See the GNU General Public License for more
details.

You should have received a copy of the GNU General Public License along with
this program. If not, see <http://www.gnu.org/licenses/>.

=cut

1;
