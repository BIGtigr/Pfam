
# DomainGraphics.pm
# jt6 20060410 WTSI
#
# $Id: DomainGraphics.pm,v 1.34 2010-01-13 14:44:53 jt6 Exp $

=head1 NAME

PfamWeb::Controller::Family::DomainGraphics

=cut

package PfamWeb::Controller::DomainGraphics;

=head1 DESCRIPTION

Controller to build a set of domain graphics for a given Pfam-A, Pfam-B or clan.
The initial usage of this controller is to build domain graphics for the unique
architectures for the given entry. However, if the parameters include an
architecture number, rather than unique architectures, we'll build graphics
for all of the sequences with that specified architecture.

If building architecture graphics, the controller defaults to building only
the first X rows, where X is specified in the config. The template shows a
button which will allow loading of the next Y rows, where, again, Y is specified
in the config.

If building sequence graphics, no attempt is currently made to page through the
results, but rather all rows are generated.

$Id: DomainGraphics.pm,v 1.34 2010-01-13 14:44:53 jt6 Exp $

=cut

use utf8;
use strict;
use warnings;

use Bio::Pfam::ContextPfamRegion;

use URI::Escape;
use Storable qw(thaw);
use JSON qw( -convert_blessed_universally );
use URI::Escape qw( uri_unescape );
use Data::Dump qw( dump );

use base 'Catalyst::Controller';

#-------------------------------------------------------------------------------

=head1 METHODS

=head2 begin : Private

This is the method that decides what kind of entry we're dealing with, be it
Pfam-A, Pfam-B or a clan. Having decided, it hands off to the appropriate
method to retrieve the sequence or architecture data.

=cut

sub begin : Private {
  my ( $this, $c, $entry_arg ) = @_;

  $c->cache_page( 604800 );

  # get a handle on the entry and detaint it
  my $tainted_entry = $c->req->param('acc')   ||
                      $entry_arg              ||
                      $c->req->param('taxId') ||
                      '';


  # if we were supplied with an auto_architecture, we need to put a
  # note in the stash to show that this is a post-load, so that we can
  # adjust what gets generated in the TT and stuffed into the existing
  # page
  if ( defined $c->req->param('arch') and
       $c->req->param('arch') =~ m/^(\d+|nopfama)$/ ) {
    $c->stash->{auto_arch} = $1;
    $c->log->debug( 'DomainGraphics::begin: got a real auto_arch: |'
      . $c->stash->{auto_arch} . '|') if $c->debug;
      $c->forward( 'get_family_data' ) unless $c->stash->{data_loaded};
  }

  #----------------------------------------
  # or do we have an accession ?
  if ( $tainted_entry ) {

    # we got a regular family accession...
    $c->log->debug( 'DomainGraphics::begin: found an accession' ) if $c->debug;

    # what type of accession is it ?
    if ( $tainted_entry =~ m/^(PF\d{5})(\.\d+)?$/i ) {

      # pfam A
      $c->stash->{acc} = $1;
      $c->log->debug( 'DomainGraphics::begin: found Pfam A accession |'
                      . $c->stash->{acc} . '|' ) if $c->debug;

      $c->forward( 'get_family_data' ) unless $c->stash->{data_loaded};

    }
    elsif ( $tainted_entry =~ m/^(CL\d{4})$/i ) {

      # looks like a clan
      $c->stash->{acc} = $1;
      $c->log->debug( 'DomainGraphics::begin: found Clan accession |'
                      . $c->stash->{acc} . '|' ) if $c->debug;

      my $clan = $c->model('PfamDB::Clan')
                   ->find( { clan_acc => $1 } );
      $c->stash->{clan_acc} = $clan->clan_acc;

      $c->forward( 'get_clan_data' );
    }
    elsif ( $tainted_entry =~ m/^(\d+)$/ ){
      # looks like an NCBI tax ID
      $c->log->debug( 'DomainGraphics::begin: found NCBI tax ID' )
        if $c->debug;
      $c->stash->{taxId} = $1;

      # see if we have a pfam family accession, which, when found in conjunction
      # with the taxId, means that we need to draw all of the architectures for
      # which include the given family from the given species
      if( defined $c->req->param('pfamAcc') and
          $c->req->param('pfamAcc')=~ m/(PF\d{5})(\.\d+)?$/ ) {
        $c->stash->{acc} = $1;
        #Is something breaks....look further into this. I have commented out the forward line.
        $c->stash->{pfam} = $c->model('PfamDB::Pfama')
                        ->find( { 'me.pfama_acc' => $c->stash->{acc} } );
        #$c->forward( 'get_family_data' ) unless $c->stash->{data_loaded};
      }
      # retrieve the data for we need regarding the specified proteome. This
      # action will decide for itself which exact query to run...
      $c->forward( 'get_proteome_data' );
    }

  }

  #----------------------------------------

  # do we have a sub-tree flag ? If so we should also have a job ID, which we
  # can use to retrieve the list of sequence accessions to process

  elsif ( $c->req->param('subTree') and
          $c->req->param('jobId') ) {

    $c->log->debug( 'DomainGraphics::begin: checking for selected sequences' )
      if $c->debug;

    # validate the UUID
    my $jobId = $c->req->param('jobId');
    unless ( $jobId =~ m/^([A-F0-9\-]{36})$/i ) {
      $c->log->debug( 'DomainGraphics::begin: bad job id' ) if $c->debug;
      $c->stash->{errorMsg} = 'Invalid job ID';
      return;
    }

    # retrieve the accessions for that job ID
    my $accession_list = $c->forward( '/utils/retrieve_ids', [ $jobId ] );
    unless ( $accession_list ) {
      $c->stash->{errorMsg} ||= 'Could not retrieve sequences for that job ID';
      return;
    }

    $c->stash->{subTree}         = 1;
    $c->stash->{jobId}           = $jobId;
    $c->stash->{selectedSeqAccs} = $accession_list;

    $c->forward( 'get_selected_seqs' );
  }

} # end of the "begin" method

#-------------------------------------------------------------------------------

=head2 domain_graphics : Path

The main entry point for the controller. The begin method populates the stash
with the data for the entry type that we're dealing with, whilst this method
actually generates the graphics from those data.

Depending on whether we're drawing all architectures for an entry or all
sequences for an architecture, we hand off to one of two separate templates.

=cut

sub domain_graphics : Path {
  my ( $this, $c ) = @_;

  # set up the layout manager and hand it the sequences
  my $lm = Bio::Pfam::Drawing::Layout::LayoutManager->new;
  my $pfama = $lm->_getRegionConfigurator('Pfama');
  my $pfamb = $lm->_getRegionConfigurator('Pfamb');
  # TODO see if we can cache these things on the object, rather than
  # regenerating them for every request

  # see if we've been handed a hash containing colours that were originally
  # assigned by the layout manager
  if ( $c->req->param('ac') ) {

    # detaint the param by trying to decode it as JSON
    my $data;
    eval {
      $data = from_json( uri_unescape( $c->req->param('ac') ) );
    };
    if ( $@ or not defined $data ) {
      # decoding failed; don't try to use the data
      $c->log->warn( 'DomainGraphics::domain_graphics: failed to detaint colours param' )
        if $c->debug;
    }
    else {
      # decoding worked; set these assigned colours on the layout manager
      # before generating the new layout
      my $colours_json = uri_unescape( $c->req->param('ac') );
      my $colours = from_json( $colours_json );

      my ( $pfama_colours, $pfamb_colours );
      # Note that we're not validating the colours here, because they're going
      # to be passed to the Moose objects, which all have strict type checking
      # in place. Any broken data will cause an exception when the Moose object
      # tries to use the data.

      # split the colours into Pfam-A and Pfam-B colours
      foreach ( keys %$colours ) {
        if ( m/^(PF\d{5})$/ ) {
          $pfama_colours->{$1} = $colours->{$1};
        }
        elsif ( m/^(PB\d{6})$/ ) {
          $pfamb_colours->{$1} = $colours->{$1};
        }
      }

      # and pre-assign the colours to the respective configurators
      if ( $pfama_colours ) {
        $pfama->assignedColours( $pfama_colours );
        $pfama->colourIndex( scalar( keys %{ $pfama->assignedColours } ) + 1 );
      }

      if ( $pfamb_colours ) {
        $pfamb->assignedColours( $pfamb_colours );
      }
    }
  }

  # let the layout manager build the domain graphics definition from the
  # sequence objects
  $lm->layoutSequences( $c->stash->{seqs} );

  # configure the JSON object to correctly stringify the layout manager output
  my $json = new JSON;
  # $json->pretty(1);
  $json->allow_blessed;
  $json->convert_blessed;

  # encode and stash the sequences as a JSON string
  $c->stash->{layout} = $json->encode( $c->stash->{seqs} );

  # stash the assigned colours from the layout manager. First we need to merge
  # the sets of colours from the two configurators
  if ( defined $pfama and defined $pfamb ) {

    my $valid_colours;
    my $pfama_colours = $pfama->assignedColours;
    foreach ( keys %$pfama_colours ) {
      next unless $_;
      $valid_colours->{$_} = $pfama_colours->{$_};
    }
    my $pfamb_colours = $pfamb->assignedColours;
    foreach ( keys %$pfamb_colours ) {
      next unless $_;
      $valid_colours->{$_} = $pfamb_colours->{$_};
    }

    $c->stash->{assignedColours} = $json->encode( $valid_colours )
      if $valid_colours;
  }

  # use a different template for rendering sequences vs architectures vs
  # selected sequences
  if ( $c->stash->{auto_arch} ) {
    $c->log->debug( 'DomainGraphics::domain_graphics: rendering "allSequences.tt"' )
      if $c->debug;
    $c->stash->{template} = 'components/allSequences.tt';
  }
  elsif ( $c->req->param('subTree') ) {
    $c->log->debug( 'DomainGraphics::domain_graphics: rendering "someSequences.tt"' )
      if $c->debug;
    $c->stash->{template} = 'components/someSequences.tt';
  }
  else {
    $c->log->debug( 'DomainGraphics::domain_graphics: rendering "allArchitectures.tt"' )
      if $c->debug;
    $c->stash->{template} = 'components/allArchitectures.tt';
  }

}

#-------------------------------------------------------------------------------
#- private actions -------------------------------------------------------------
#-------------------------------------------------------------------------------

=head2 calculateRange : Private

Works out the range for the architectures that we actually want to return.

=cut

sub calculateRange : Private {
  my ( $this, $c ) = @_;

  my $num_rows = $c->stash->{numRows};

  # set the first page values, also the defaults
  my ( $first, $last, $count );
  if ( $c->stash->{auto_arch} ) {

    # if we have an auto_arch, we're showing all sequences for a given
    # architecture, but we want to show ALL of them
    $first = 0;
    $last  = $num_rows - 1; # this is used as an array bound later, hence "- 1"
    $count = $num_rows;

  }
  else {
    # we have no auto_arch, so we're showing a set of the architectures for
    # this family. Start with the default limits
    $first = 0;
    $last  = $this->{firstPageLimit} - 1;
    $count = $this->{restPageLimit};

    # see if the request specified a start number and set limits accordingly
    if ( defined $c->req->param('start') and
        $c->req->param('start') =~ m/^(\d+)$/ ) {
      $first = $1;
      $last  = $1 + $count - 1;
    }
  }
  $c->log->debug( "DomainGraphics::calculateRange: before: first, last, count: |$first|$last|$count|" )
    if $c->debug;

  # check the calculated bounds
  $first = 0                     if $first < 0;
  $last  = $num_rows - 1         if $num_rows < $last + 1;
  $count = $num_rows - $last - 1 if $num_rows < $last + $count + 1;

  $c->log->debug( "DomainGraphics::calculateRange: after:  first, last, count: |$first|$last|$count|" )
    if $c->debug;

  $c->stash->{first} = $first;
  $c->stash->{last}  = $last;
  $c->stash->{count} = $count;
}

#-------------------------------------------------------------------------------

=head2 get_family_data : Private

Retrieves architecture or sequence information pertaining to the specified
Pfam-A.

=cut

sub get_family_data : Private {
  my ( $this, $c ) = @_;

  $c->stash->{pfam} = $c->model('PfamDB::Pfama')
                        ->find( { 'me.pfama_acc' => $c->stash->{acc} } );

  # decide if we're showing the individual architectures or all sequences
  # for a particular architecture
  my @rows;
  if ( $c->stash->{auto_arch} ) {

    # we want to see all of the sequences with a given architecture
    $c->log->debug( 'DomainGraphics::get_family_data: getting all sequences for auto_arch |'
                    . $c->stash->{auto_arch} . '|' ) if $c->debug;

    @rows = $c->model('PfamDB::Pfamseq')
              ->search( { 'me.auto_architecture' => $c->stash->{auto_arch} },
                        { prefetch => [ qw( auto_architecture annseqs ) ] } );
  }
  else {
    # we want to see the unique architectures containing this domain
    $c->log->debug( 'DomainGraphics::get_family_data: getting unique architectures' )
      if $c->debug;

    @rows = $c->model('PfamDB::PfamaArchitecture')
              ->search( { 'me.pfama_acc' => $c->stash->{acc} },
                        { prefetch => [ 'pfama_acc', { auto_architecture => [qw(storable type_example)] } ],
                          order_by => 'auto_architecture.no_seqs DESC' } );
  }

  # how many architectures ?
  $c->stash->{numRows} = scalar @rows;

  # how many sequences in these architectures ?
  $c->stash->{numSeqs} = 0;
  map { $c->stash->{numSeqs} += $_->auto_architecture->no_seqs } @rows;

  $c->log->debug( 'DomainGraphics::get_family_data: found |'
                  . $c->stash->{numRows} . '| rows, with a total of |'
                  . $c->stash->{numSeqs} . '| sequences' )
    if $c->debug;

  # work out the range for the architectures that we actually want to return
  $c->forward( 'calculateRange' );

  # now walk through the set of rows (containing either architectures or
  # sequences, depending how we were called) and build a data structure that
  # the drawing code will use to generate the graphics
  my ( @seqs, %seqInfo, @ids );
  ARCH: foreach my $row ( @rows[ $c->stash->{first} .. $c->stash->{last} ] ) {

    # thaw out the sequence object for this architecture and get a handle on
    # the right DB object
    my $seq;
    if ( $c->stash->{auto_arch} ) {
      push @seqs, thaw( $row->annseqs->annseq_storable );

      # we're looking at a particular architecture, so we want all sequences
      $seq = $row;
    }
    else {
      eval {
        push @seqs, thaw( $row->auto_architecture->storable->annseq_storable );
      };
      if ( $@ ) {
        $c->log->debug( "DomainGraphics::get_family_data: failed to thaw storable: $@" )
          if $c->debug;
        next ARCH;
      }

      # we're looking at all sequences, so we want just the type example
      $seq = $row->auto_architecture->type_example;
    }

    # stash the sequence IDs for the type example in an array, so that we can
    # access them in the right order in the TT, i.e. ordered by number of
    # sequences with the given architecture)
    my $pfamseq_id = $seq->pfamseq_id;
    push @ids, $pfamseq_id;

    # work out which domains are present on this sequence
    my @domains = split m/\~/, $row->auto_architecture->architecture;
    $seqInfo{$pfamseq_id}{arch} = \@domains;

    # how many sequences ?
    $seqInfo{$pfamseq_id}{num} = $row->auto_architecture->no_seqs;

    # store a mapping between the sequence and the auto_architecture
    $seqInfo{$pfamseq_id}{auto_arch} = $row->get_column('auto_architecture');

    # store the sequence description, species name and length of each
    # individual sequence
    $seqInfo{$pfamseq_id}{desc}    = $seq->description;
    $seqInfo{$pfamseq_id}{species} = $seq->species;
    $seqInfo{$pfamseq_id}{length}  = $seq->length;
  }

  $c->log->debug( 'DomainGraphics::get_family_data: retrieved '
                  . scalar @seqs . ' storables' ) if $c->debug;

  $c->stash->{seqs}    = \@seqs;
  $c->stash->{ids}     = \@ids;
  $c->stash->{seqInfo} = \%seqInfo;

  # set a flag to make sure we don't try to load family data twice
  $c->stash->{data_loaded} = 1;
}
#-------------------------------------------------------------------------------

=head2 get_clan_data : Private

Retrieves architecture or sequence information pertaining to the specified
clan.

=cut

sub get_clan_data : Private {
  my ( $this, $c ) = @_;

  my @rows;
  if ( $c->stash->{auto_arch} ) {

    # we want to see all of the sequences with a given architecture
    $c->log->debug( 'DomainGraphics::get_clan_data: getting all sequences for |'
                    . $c->stash->{auto_arch} . '|' ) if $c->debug;

    @rows = $c->model('PfamDB::Pfamseq')
              ->search( { 'me.auto_architecture' => $c->stash->{auto_arch} },
                        { prefetch  => [ qw( auto_architecture annseqs ) ] } );
  }
  else {

    # we want to see the unique architectures for this clan
    $c->log->debug( 'DomainGraphics::get_clan_data: getting unique architectures' )
      if $c->debug;

    @rows = $c->model('PfamDB::ClanArchitecture')
              ->search( { 'me.clan_acc' => $c->stash->{clan_acc} },
                        { prefetch  => [ 'clan_acc',  {auto_architecture=> [qw(type_example storable)]} ],
                          order_by  => 'auto_architecture.no_seqs DESC' } );
  }

  # how many architectures/sequences ?
  $c->stash->{numRows} = scalar @rows;

  $c->log->debug( 'DomainGraphics::get_clan_data: found |'
                  . $c->stash->{numRows} . '| rows' ) if $c->debug;

  # work out the range for the architectures that we actually want to return
  $c->forward( 'calculateRange' );

  my ( @seqs, %seqInfo, @ids );
  foreach my $row ( @rows[ $c->stash->{first} .. $c->stash->{last} ] ) {

    my ( $seq, $pfamseq_id );
    if ( $c->stash->{auto_arch} ) {
      push @seqs, thaw( $row->annseqs->annseq_storable );
      $seq = $row;
      $pfamseq_id = $row->pfamseq_id;
    }
    else {
      push @seqs, thaw( $row->auto_architecture->storable->annseq_storable );
      $seq = $row->auto_architecture->type_example;
      $pfamseq_id = $row->auto_architecture->pfamseq_id;
    }

    push @ids, $pfamseq_id;

    my @domains = split m/\~/, $row->auto_architecture->architecture;
    $seqInfo{$pfamseq_id}{arch}      = \@domains;
    $seqInfo{$pfamseq_id}{auto_arch} = $row->get_column('auto_architecture');
    $seqInfo{$pfamseq_id}{num}       = $row->auto_architecture->no_seqs;

    $seqInfo{$pfamseq_id}{desc}    = $seq->description;
    $seqInfo{$pfamseq_id}{species} = $seq->species;
    $seqInfo{$pfamseq_id}{length}  = $seq->length;
  }

  $c->stash->{seqs}    = \@seqs;
  $c->stash->{ids}     = \@ids;
  $c->stash->{seqInfo} = \%seqInfo;
}

#-------------------------------------------------------------------------------

=head2 get_selected_seqs : Private

Retrieves the sequences for the user-specified sequence accessions. Used by the
"display selected sequences" feature of the interactive species tree.

=cut

sub get_selected_seqs : Private {
  my( $this, $c ) = @_;

  # get each of the sequences in turn...
  my @rows;
  foreach my $seqAcc ( @{ $c->stash->{selectedSeqAccs} } ) {
    my $r = $c->model('PfamDB::Pfamseq')
              ->find( { pfamseq_acc => $seqAcc },
                      { prefetch => [ qw( annseqs ) ] } );
    push @rows, $r;
  }

  # how many sequences did we end up with ?
  $c->log->debug( 'DomainGraphics::get_selected_seqs: found |' . scalar @rows
                  . '| sequences to draw' ) if $c->debug;
  $c->stash->{numRows} = scalar @rows;

  $c->forward( 'calculateRange' );

  my ( @seqs, %seqInfo, @ids );
  foreach my $seq ( @rows[ $c->stash->{first} .. $c->stash->{last} ] ) {

    push @seqs, thaw( $seq->annseqs->annseq_storable );

    # stash the sequence IDs for the type example in an array, so that we can
    # access them in the right order in the TT, i.e. ordered by number of
    # sequences with the given architecture)
    my $id = $seq->pfamseq_id;
    $c->log->debug( "DomainGraphics::get_selected_seqs: row sequence ID: |$id|" )
      if $c->debug;
    push @ids, $id;

    my $aa = $seq->get_column('auto_architecture')
             ? $seq->get_column('auto_architecture')
             : 'nopfama';

    $c->log->debug( "DomainGraphics::get_selected_seqs: checking |$id|, architecture |$aa|" )
      if $c->debug;

    if ( $aa =~ /^(\d+)$/ ) {

      $c->log->debug( "DomainGraphics::get_selected_seqs: found architecture |$1|: "
                      . $seq->auto_architecture->architecture )
        if $c->debug;

      my @domains = split /\~/, $seq->auto_architecture->architecture;
      $seqInfo{$id}{arch}      = \@domains;
      $seqInfo{$id}{num}       = $seq->auto_architecture->no_seqs;
      $seqInfo{$id}{auto_arch} = $aa;
    }
    else {

      $c->log->debug( 'DomainGraphics::get_pfamB_no_arch: no PfamA domains' )
        if $c->debug;
      $seqInfo{$id}{arch}      = 'no Pfam-A domains';
      $seqInfo{$id}{auto_arch} = 'nopfama';
      $seqInfo{$id}{num}       = 1;
      #$seqInfo{$id}{num}       = $seen_arch{nopfama};
    }

#    # work out which domains are present on this sequence
#    my @domains = split m/\~/, $seq->auto_architecture->architecture;
#    $seqInfo{$id}{arch} = \@domains;
#
#    # how many sequences ?
#    $seqInfo{$id}{num} = $seq->auto_architecture->no_seqs;
#
#    # store a mapping between the sequence and the auto_architecture
#    $seqInfo{$id}{auto_arch} = $seq->auto_architecture->auto_architecture;

    # store the sequence description, species name and length of each
    # individual sequence
    $seqInfo{$id}{desc}    = $seq->description;
    $seqInfo{$id}{species} = $seq->species;
    $seqInfo{$id}{length}  = $seq->length;
  }

  $c->log->debug( 'DomainGraphics::get_selected_seqs: retrieved '
                  . scalar @seqs . ' storables' ) if $c->debug;

  $c->stash->{seqs}    = \@seqs;
  $c->stash->{ids}     = \@ids;
  $c->stash->{seqInfo} = \%seqInfo;
}

#-------------------------------------------------------------------------------

=head2 get_proteome_data : Private

Retrieves the sequences for the specified proteome.

=cut

sub get_proteome_data : Private {
  my ( $this, $c ) = @_;
  # get each of the sequences in turn...
  $c->log->debug( 'DomainGraphics::get_proteome_data: getting sequence for |'
                  . $c->stash->{taxId} . '|' ) if $c->debug;

  # get the auto_proteome number, since that's guaranteed to be there, whereas
  # the tax ID isn't
  my $rs = $c->model('PfamDB::CompleteProteomes')
             ->find( { ncbi_taxid => $c->stash->{taxId} } );

  unless ( defined $rs->species ) {
    $c->log->debug( 'DomainGraphics::get_proteome_data: no species found' )
      if $c->debug;
    return;
  }

  $c->log->debug( 'DomainGraphics::get_proteome_data: mapped tax ID '
                  . $c->stash->{taxId} . " to proteome: $rs->species" )
    if $c->debug;


  my @rows;
  if ( $c->stash->{auto_arch} ) {

    $c->log->debug( 'DomainGraphics::get_proteome_data: got an auto_arch: '
                    . $c->stash->{auto_arch} ) if $c->debug;

    @rows = $c->model('PfamDB::Pfamseq')
              ->search( { 'me.ncbi_taxid' => $rs->ncbi_taxid,
                          'me.auto_architecture' => $c->stash->{auto_arch} },
                        { join      => [ qw( annseqs ) ],
                          select    => [ qw( pfamseq_id
                                             annseqs.annseq_storable ) ],
                          as        => [ qw( pfamseq_id
                                             annseq_storable  ) ] } );
  }
  elsif ( $c->stash->{acc} ) {

    $c->log->debug( 'DomainGraphics::get_proteome_data: got a pfamAcc: '
                    . $c->stash->{acc} ) if $c->debug;

    @rows = $c->model('PfamDB::Pfamseq')
              ->search( { 'me.ncbi_taxid' => $rs->ncbi_taxid,
                          'in_full'    => 1,
                          'pfama_reg_full_significants.pfama_acc'     => $c->stash->{pfam}->pfama_acc },
                        { join      => [ qw( pfama_reg_full_significants
                                             annseqs ) ],
                          select    => [ { distinct => [ 'me.pfamseq_acc' ] } ,
                                         qw( pfamseq_id
                                             annseqs.annseq_storable ) ],
                          as        => [ qw( pfamseq_acc
                                             pfamseq_id
                                             annseq_storable ) ] } );
  }
  else {

    $c->log->debug( 'DomainGraphics::get_proteome_data: got neither auto_arch nor pfamAcc' )
      if $c->debug;

    @rows = $c->model('PfamDB::ProteomeArchitecture')
              ->search( { 'me.ncbi_taxid' => $rs->ncbi_taxid },
                        { join   => [ { auto_architecture => [ qw(type_example storable)]}],
                          select => [ qw( type_example.pfamseq_id
                                          storable.annseq_storable
                                          auto_architecture.architecture
                                          me.auto_architecture
                                          me.no_seqs ) ],
                          as     => [ qw( pfamseq_id
                                          annseq_storable
                                          architecture
                                          auto_architecture
                                          numberSeqs ) ],
                          order_by => 'me.no_seqs DESC',
                          rows     => 500 } );


    # this is the query we're aiming for (join order is important):
    #   SELECT s.pfamseq_id,
    #          a.architecture,
    #          length( pas.annseq_storable ),
    #          pa.no_seqs
    #   FROM   proteome_architecture pa
    #   JOIN   architecture a  ON  pa.auto_architecture =   a.auto_architecture
    #   JOIN   pfam_annseq pas ON  pa.type_example      = pas.pfamseq_acc
    #   JOIN   pfamseq s       ON   s.pfamseq_acc       = pa.type_example
    #   WHERE  auto_proteome = ?;
  }

  #----------------------------------------

  # how many sequences did we end up with ?
  $c->stash->{numRows} = scalar @rows;

  $c->log->debug( 'DomainGraphics::get_proteome_data: found |'
                  . $c->stash->{numRows} . '| sequences to draw' ) if $c->debug;

  # work out the range for the sequences that we actually want to return
  $c->forward( 'calculateRange' );

  #----------------------------------------

  my ( @seqs, %seqInfo, @ids );
  foreach my $row ( @rows[ $c->stash->{first} .. $c->stash->{last} ] ) {

    my $seq = thaw( $row->get_column('annseq_storable') );
    push @seqs, $seq;
    push @ids,  $seq->metadata->identifier;

    my $id = $row->get_column('pfamseq_id');

    unless ( $c->stash->{auto_arch} or
            (exists($c->stash->{pfam}) and $c->stash->{pfam}->pfama_acc ) ) {

      my @domains = split /\~/, $row->get_column('architecture');

      $seqInfo{$id}{arch}      = \@domains;
      $seqInfo{$id}{auto_arch} = $row->get_column('auto_architecture');
      $seqInfo{$id}{num}       = $row->get_column('numberSeqs');

    }

    $seqInfo{$id}{desc}    = $seq->metadata->description;
    $seqInfo{$id}{species} = $seq->metadata->organism;
    $seqInfo{$id}{length}  = $seq->length;

  }

  $c->stash->{seqs}    = \@seqs;
  $c->stash->{ids}     = \@ids;
  $c->stash->{seqInfo} = \%seqInfo;
}

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
