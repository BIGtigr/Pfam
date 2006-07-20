
# Protein.pm
# jt6 20060427 WTSI
#
# Controller to build the main protein page.
#
# $Id: Protein.pm,v 1.5 2006-07-20 08:59:36 jt6 Exp $

package PfamWeb::Controller::Protein;

use strict;
use warnings;

use Data::Dumper;

use base "Catalyst::Controller";

#-------------------------------------------------------------------------------
# get the data from the database for the UniProt entry

sub begin : Private {
  my( $this, $c ) = @_;

  if( defined $c->req->param( "acc" ) ) {

	$c->req->param( "acc" ) =~ m/^([OPQ]\d[A-Za-z0-9]{3}\d)$/i;
	$c->log->info( "Protein::begin: found a uniprot accession |$1|" );

	# try a lookup in the main pfamseq table first
	my $p = PfamWeb::Model::Pfamseq->find( { pfamseq_acc => $1 } );

	# if we got a result there, so much the better...
	if( defined $p ) {
	  $c->stash->{pfamseq} = $p;
	} else {

	  # ... otherwise, see if this is really a secondary accession
	  $p = PfamWeb::Model::Secondary_pfamseq_acc->find( { secondary_acc => $1 },
													    { join =>     [ qw/pfamseq/ ],
														  prefetch => [ qw/pfamseq/ ] } );

	  $c->stash->{pfamseq} = $p if defined $p;
	}

  } elsif( defined $c->req->param( "id" ) ) {

	$c->req->param( "id" ) =~ m/^(\w+)$/;
	$c->log->info( "Protein::begin: found a uniprot ID |$1|" );
	
	# try a lookup in the main pfamseq table first
	my $p = PfamWeb::Model::Pfamseq->find( { pfamseq_id => $1 } );

	$c->stash->{pfamseq} = $p if defined $p;

  } elsif( defined $c->req->param( "entry" ) ) {

	# we don't know if this is an accession or an ID; try both

	if( $c->req->param( "entry" ) =~ m/^([OPQ]\d[A-Z0-9]{3}\d)$/i ) {

	  # looks like an accession; redirect to this action, appending the accession
	  $c->log->debug( "Protein::begin: looks like a uniprot accession ($1); redirecting" );
	  $c->res->redirect( $c->uri_for( "/protein", { acc => $1 } ) );
	  return 1;

	} elsif( $c->req->param( "entry" ) =~ m/^(\w+_\w+)$/ ) {

	  # looks like an ID; redirect to this action, appending the ID
	  $c->log->debug( "Protein::begin: looks like a uniprot ID; redirecting" );
	  $c->res->redirect( $c->uri_for( "/protein", { id => $1 } ) );
	  return 1;
	}

  }

  # we're done here unless there's an entry specified
  $c->log->warn( "Protein::begin: no ID or accession" )# and return
	unless defined $c->stash->{pfamseq};

  # add available DAS sources to the stash
  my @dasSources = PfamWeb::Model::Das_sources->search();
  $c->log->debug( "Protein::begin: " . \@dasSources );
  $c->stash->{dasSourcesRs} = \@dasSources;

}

#-------------------------------------------------------------------------------
# the hook into the class

# pick up a URL like http://localhost:3000/protein?acc=P00179

sub default : Private {
  my( $this, $c ) = @_;

  $c->log->debug( "Protein::default: action caught a URL..." );
}

#-------------------------------------------------------------------------------
# default end; hand off to the whole page layout

sub end : Private {
  my( $this, $c ) = @_;

  # don't try to render a page unless there's a Pfamseq object in the stash
  return 0 unless defined $c->stash->{pfamseq};

  # check for errors
  if ( scalar @{ $c->error } ) {
	$c->stash->{errors}   = $c->error;
	$c->stash->{template} = "components/blocks/protein/errors.tt";
  } else {
	$c->stash->{pageType} = "protein";
	$c->stash->{template} = "pages/layout.tt";
  }

  # and render the page
  $c->forward( "PfamWeb::View::TT" );

  # clear any errors
  $c->error(0);
}

#-------------------------------------------------------------------------------

1;
