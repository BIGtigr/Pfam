
# Alignment.pm
# jt6 20110720 WTSI
#
# $Id$

=head1 NAME

PfamWeb::Controller::PfamB::Alignment - handle alignments for Pfam-Bs

=cut

package PfamWeb::Controller::PfamB;

=head1 DESCRIPTION

This is intended as the basis for alignment-related code.

$Id$

=cut

use strict;
use warnings;

use Compress::Zlib;
use Text::Wrap;
use Bio::Pfam::AlignPfam;

use Data::Dump qw( dump );

use base 'Catalyst::Controller';

#-------------------------------------------------------------------------------

=head1 METHODS

=head2 alignment : Chained

Start of a chain for the other methods in this controller.

=cut

sub alignment : Chained( 'pfamb' )
                PathPart( 'alignment' )
								CaptureArgs( 0 ) { }

#-------------------------------------------------------------------------------
#- raw alignment methods -------------------------------------------------------
#-------------------------------------------------------------------------------

=head2 gzipped : Local

Returns a gzip-compressed file with the full or seed alignment for the specified
family. 

=cut

sub gzipped : Chained( 'alignment' )
              PathPart( 'gzipped' )
              Args( 0 ) {
  my ( $this, $c ) = @_;

  my ( $alignment, $filename );

  if ( $c->stash->{alnType} eq 'long' ) {
    $c->log->debug( 'Family::Alignment::Download::gzipped: building full length sequence FASTA' )
      if $c->debug;

    # build the alignment file
    my $rs = $c->model('PfamDB::PfamaRegFullSignificant')
               ->search( { auto_pfama => $c->stash->{pfam}->auto_pfama },
                         { prefetch => [ qw( auto_pfamseq ) ],
                           columns  => [ qw( auto_pfamseq.pfamseq_id 
                                             auto_pfamseq.pfamseq_acc
                                             auto_pfamseq.sequence ) ] } );
    my $sequences = '';
    while ( my $seq_row = $rs->next ) {
      $Text::Wrap::columns = 60;
      $sequences .= '>' . $seq_row->pfamseq_id . ' (' . $seq_row->pfamseq_acc . ")\n";
      $sequences .= wrap( '', '', $seq_row->sequence ) . "\n";
    }

    # compress it
    $alignment = Compress::Zlib::memGzip( $sequences );

    # build a filename for it
    $filename = $c->stash->{acc} . '_full_length_sequences.fasta.gz';
  }
  else {
    # retrieve the alignment
     my $rs = $c->model('PfamDB::AlignmentsAndTrees')
                ->search( { auto_pfama => $c->stash->{pfam}->auto_pfama,
                            type       => $c->stash->{alnType} },
                          { columns    => [ qw( alignment ) ] } )
                ->single();

    $alignment = $rs->alignment;
    $filename  = $c->stash->{acc} . '.' . $c->stash->{alnType} . '.gz';
  }

  unless ( defined $alignment ) {
    $c->log->warn( 'Family::Alignment::Download::gzipped: failed to retrieve alignment for '
                    . $c->stash->{acc} ) if $c->debug;
      
    $c->res->status( 204 ); # "no content"
    
    return;
  } 

  # set the filename on the HTTP headers, so that the browser will offer to 
  # download and save it
  $c->res->header( 'Content-disposition' => "attachment; filename=$filename" );
  
  # ... and dump it straight to the response
  $c->res->content_type( 'application/x-gzip' );
  $c->res->body( $alignment );
}

#---------------------------------------

=head2 old_gzipped : Path

This is used by the form in the Pfam family page. The form is currently 
submitted by the browser directly, so there's no javascript to intervene
and convert the parameters into URL arguments. This action will accept 
the parameters and redirect to the Chained action above.

=cut

sub old_gzipped : Path( '/pfamb/alignment/download/gzipped' ) {
  my ( $this, $c ) = @_;

  $c->log->debug( 'PfamB::Alignment::old_gzipped: redirecting to "gzipped"' )
    if $c->debug;
  $c->res->redirect( $c->uri_for( '/pfamb/'.$c->stash->{param_entry}.'/alignment/gzipped' ) );
}

#-------------------------------------------------------------------------------

=head2 format : Chained

Serves the plain text (no markup) alignment. Also applies various
changes to the alignment before hand, such as changing the gap style
or sequence order.

By default this method will generate Stockholm format, but the
following formats are also available and can be specified with the
C<format> parameter:

=over

=item * pfam

Essentially Stockholm with markup lines removed

=item * fasta

Vanilla FASTA format

=item * msf

No idea...

=item * stockholm (default)

Standard Stockholm format

=back

The exact styles (other than C<pfam>) are defined by BioPerl.

=cut

sub format : Chained( 'alignment' )
             PathPart( 'format' )
             Args( 0 ) {
  my ( $this, $c ) = @_;

  # retrieve the alignment
  $c->forward( 'get_alignment_from_db' );

  if ( defined $c->stash->{alignment} ) {
    $c->log->debug( 'PfamB::Alignment::format: successfully retrieved an alignment' )
      if $c->debug;
  }
  else {
    $c->log->debug( 'PfamB::Alignment::format: failed to retrieve an alignment' )
      if $c->debug;
  }

  # drop it into an AlignPfam object
  my $pfamaln = new Bio::Pfam::AlignPfam->new;
  eval {
    $pfamaln->read_stockholm( $c->stash->{alignment} );
  };
  if ( $@ ) {
    $c->log->debug( "PfamB::Alignment::format: problem reading stockholm data: $@" )
      if $c->debug;
    $c->stash->{errorMsg} = 'There was a problem with the alignment data for '
                            . $c->stash->{acc};
    return;
  };

  # gaps param can be default, dashes, dot or none
  if ( $c->req->param('gaps') ) {
    $c->log->debug( 'PfamB::Alignment::format: handling gaps parameter' )
      if $c->debug;
      
    if ( $c->req->param('gaps') =~ m/^n\w*$/ ) {
      $pfamaln->map_chars('-', '');
      $pfamaln->map_chars('\.', '');
    }
    elsif ( $c->req->param('gaps') =~ m/^do\w*$/ ) {
      $pfamaln->map_chars('-', '.');
    }
    elsif ( $c->req->param('gaps') =~ m/^da\w*$/ ) {
      $pfamaln->map_chars('\.', '-');
    }
  }

  # case param can be u or l
  if ( $c->req->param('case') and $c->req->param('case') =~ m/^u\w*$/ ) {
    $c->log->debug( 'PfamB::Alignment::format: uppercasing alignment' )
      if $c->debug;
    $pfamaln->uppercase;
  }

  # order param can be tree or alphabetical
  if ( $c->req->param('order') and $c->req->param('order') =~ m/^a\w*$/ ) {
    $c->log->debug( 'PfamB::Alignment::format: sorting alphabetically' )
      if $c->debug;
    $pfamaln->sort_alphabetically;
  }

  # format param can be one of pfam, stockholm, fasta or MSF
  my $output;
  if ( $c->req->param( 'format' ) ) {
    if ( $c->req->param( 'format' ) =~ m/^p\w*$/ ) {
      $c->log->debug( 'PfamB::Alignment::format: writing Pfam format' )
        if $c->debug;
      $output = $pfamaln->write_Pfam;
    }
    elsif ( $c->req->param( 'format' ) =~ m/^f\w*$/ ) {
      $c->log->debug( 'PfamB::Alignment::format: writing FASTA format' )
        if $c->debug;
      $output = $pfamaln->write_fasta;
    }
    elsif ( $c->req->param( 'format' ) =~ m/^m\w*$/ ) {
      $c->log->debug( 'PfamB::Alignment::format: writing MSF format' )
        if $c->debug;
      $output = $pfamaln->write_MSF;
    }
  }

  # default to writing stockholm
  $output ||= $pfamaln->write_stockholm;

  # are we downloading this or just dumping it to the browser ?
  if ( $c->req->param( 'download' ) ) {
    $c->log->debug( 'PfamB::Alignment::format: sending alignment as download' )
      if $c->debug;

    my $filename = $c->stash->{acc} . '.txt';
  
    $c->res->header( 'Content-disposition' => "attachment; filename=$filename" );
  }

  $c->res->content_type( 'text/plain' );
  $c->res->body( join '', @$output );
}

#---------------------------------------

=head2 old_format : Path

This is used by the form in the Pfam family page. The form is currently 
submitted by the browser directly, so there's no javascript to intervene
and convert the parameters into URL arguments. This action will accept 
the parameters and redirect to the Chained action above.

=cut

sub old_format : Path( '/pfamb/alignment/download/format' ) {
  my ( $this, $c ) = @_;

  $c->log->debug( 'PfamB::Alignment::old_format: redirecting to "format"' )
    if $c->debug;
  $c->res->redirect( $c->uri_for( '/pfamb/'.$c->stash->{param_entry}.'/alignment/format',
                                  $c->req->params ) );
}

#-------------------------------------------------------------------------------
#- alignment presentation methods ----------------------------------------------
#-------------------------------------------------------------------------------

=head2 html : Chained

Retrieves the HTML alignment and dumps it to the response. We first try to 
extract the HTML from the cache or, if that fails, we retrieve it from the DB.

=cut

sub html : Chained( 'alignment' )
           PathPart( 'html' )
           Args( 0 ) {
  my ( $this, $c ) = @_;

  # point to the "tool" window
  $c->stash->{template} = 'components/tools/html_alignment.tt';
  
  my $cacheKey = 'jtml' . $c->stash->{acc} . $c->stash->{alnType};
  
  my $jtml = $c->cache->get( $cacheKey );
  if ( defined $jtml ) {
    $c->log->debug( 'PfamB::Alignment::Download::html: extracted HTML from cache' )
      if $c->debug;
  }
  else {
    $c->log->debug( 'PfamB::Alignment::Download::html: failed to extract HTML from cache; going to DB' )
      if $c->debug;  

    # make sure the Pfam-B HTML is already available
    unless ( defined $c->stash->{pfam}->pfamb_stockholms->single ) {
      $c->stash->{errorMsg} = 'We could not retrieve the alignment for '
                              . $c->stash->{acc};
      return;
    }

    my $row = $c->stash->{pfam}->pfamb_stockholms->single;

    # uncompress the row to get the raw HTML
    $jtml = Compress::Zlib::memGunzip( $row->jtml );
    unless ( defined $jtml ) {
      $c->stash->{errorMsg} = 'We could not extract the alignment for '
                              . $c->stash->{acc};
      return;
    }

    $c->log->debug( 'PfamB::Alignment::Download::html: retrieved HTML from DB' )
      if $c->debug;
    $c->cache->set( $cacheKey, $jtml ) unless $ENV{NO_CACHE};
  }

  # stash the HTML
  $c->stash->{html_alignment} = $jtml;
}

#---------------------------------------

=head2 old_html : Path

Deprecated. Stub to redirect to the chained action(s).

=cut

sub old_html : Path( '/pfamb/alignment/download/html' ) {
  my ( $this, $c ) = @_;

  $c->log->debug( 'PfamB::Alignment::old_html: redirecting to "html"' )
    if $c->debug;
  $c->res->redirect( $c->uri_for( '/pfamb/'.$c->stash->{param_entry}.'/alignment/html' ) );
}

#-------------------------------------------------------------------------------

=head2 jalview : Chained

This is the way into the JalView alignment viewer applet.

Hands straight off to a template that generates a "tool" page containing the 
JalView applet.

=cut

sub jalview : Chained( 'alignment' )
              PathPart( 'jalview' )
              Args( 0 ) {
  my ( $this, $c ) = @_;

  $c->stash->{template} = 'components/tools/jalview.tt';
}

#---------------------------------------

=head2 old_jalview : Path

Deprecated. Stub to redirect to the chained action(s).

=cut

sub old_jalview : Path( '/pfamb/alignment/jalview' ) {
  my ( $this, $c ) = @_;

  $c->log->debug( 'PfamB::Alignment::old_jalview: redirecting to "jalview"' )
    if $c->debug;
  $c->res->redirect( $c->uri_for( '/pfamb/'.$c->stash->{param_entry}.'/alignment/jalview' ) );
}

#-------------------------------------------------------------------------------
#- private actions -------------------------------------------------------------
#-------------------------------------------------------------------------------

=head2 get_alignment_from_db : Private

Retrieves the complete alignment ("seed", "full", etc.) from the database.

=cut

sub get_alignment_from_db : Private {
  my ( $this, $c ) = @_;

  # see if we can extract the raw alignment from the cache first
  my $cache_key  = 'alignment' . $c->stash->{acc};
  my $alignment = $c->cache->get( $cache_key );

  if ( defined $alignment ) {
    $c->log->debug( 'PfamB::Alignment::get_alignment_from_db: extracted alignment from cache' )
      if $c->debug;
  }
  else {
    $c->log->debug( 'PfamB::Alignment::get_alignment_from_db: failed to extract alignment from cache; going to DB' )
      if $c->debug;

    # make sure the relationship to the pfamB_stockholm table works
    unless ( $c->stash->{pfam}->pfamb_stockholms->single->stockholm_data ) {

      $c->log->warn( 'PfamB::Alignment::get_alignment: failed to retrieve '
        . ' alignment for Pfam-B ' . $c->stash->{acc} )
        if $c->debug;

      $c->stash->{errorMsg} = 'We could not retrieve the alignment for '
                              . $c->stash->{acc};
      return;
    }

    # uncompress it
    $alignment = Compress::Zlib::memGunzip( $c->stash->{pfam}->pfamb_stockholms->single->stockholm_data );

    unless ( defined $alignment ) {

      $c->log->warn( 'PfamB::Alignment::get_alignment_from_db: failed to uncompress '
        . ' alignment for Pfam-B ' . $c->stash->{acc} )
        if $c->debug;

      $c->stash->{errorMsg} = 'We could not extract the alignment for '
                              . $c->stash->{acc};
      return;
    }

    # cache the raw alignment
    $c->cache->set( $cache_key, $alignment ) unless $ENV{NO_CACHE};
  }

  # we need the alignment as an array ref, so...
  my @alignment = split /\n/, $alignment;
  $c->stash->{alignment} = \@alignment;
  
  $c->log->debug( 'PfamB::Alignment::get_alignment_from_db: got '
                  . scalar @alignment . ' rows in alignment' ) if $c->debug;
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