
# DomainGraphics.pm
# jt6 20061023 WTSI
#
# Controller to build a set of domain graphics for a given PfamB.
#
# $Id: DomainGraphics.pm,v 1.3 2006-10-31 15:17:06 jt6 Exp $

package PfamWeb::Controller::PfamB::DomainGraphics;

use strict;
use warnings;

use Storable qw(thaw);

use base "PfamWeb::Controller::PfamB";

# pick up a URL like http://localhost:3000/pfamb/domaingraphics?acc=PB000067

sub default : Path {
  my( $this, $c ) = @_;

  my $auto = $c->stash->{pfam}->auto_pfamB;

  # get a list of all the sequences and unique architectures for this
  # family
  ( $c->stash->{auto_arch} ) = $c->req->param( "arch" ) =~ /^(\d+|nopfama)$/i
	if $c->req->param( "arch" );

  my( @seqs, %seqInfo, %seenArch, @architectures, %archStore );

  if( $c->stash->{auto_arch} ){
	# we want to see all of the sequences with a given architecture

    if( $c->stash->{auto_arch} =~ /^nopfama$/i ) {

      # hmmm we are going to have to get everything and throw away
      # stuff with no auto_architecture.....

      @architectures = $c->model("PfamDB::PfamB_reg")
		->search( { auto_pfamB => $auto },
				  { join      => [ qw/ pfamseq_architecture annseq pfamseq /],
					prefetch  => [ qw/ pfamseq_architecture annseq pfamseq /]
				  } );
      foreach my $arch ( @architectures ) {
		push @seqs, thaw( $arch->annseq_storable )
		  unless $arch->auto_architecture =~ /\d+/;
	  }

    } else {

      @architectures = $c->model("PfamDB::PfamB_reg")
		->search( { auto_pfamB => $auto,
					auto_architecture => $c->stash->{auto_arch} },
				  { join      => [ qw/ pfamseq_architecture annseq pfamseq /],
					prefetch  => [ qw/ pfamseq_architecture annseq pfamseq /]
				  } );
      # query has already done the selection
      foreach my $arch ( @architectures ) {
		push @seqs, thaw( $arch->annseq_storable );
      }
    }

  } else {
	# we want to see the unique architectures containing this domain

    @architectures = $c->model("PfamDB::PfamB_reg")
	  ->search( { auto_pfamB => $auto },
				{ join      => [ qw/ pfamseq_architecture annseq pfamseq /],
				  prefetch  => [ qw/ pfamseq_architecture annseq pfamseq /]
				} );

	# grab only the unique architectures as they fly by
    foreach my $arch ( @architectures ) {
      unless( $seenArch{ $arch->auto_architecture } ) {		
		push @seqs, thaw( $arch->annseq_storable );
		$archStore{ $arch->pfamseq_id } = $arch;

      }
      $seenArch{ $arch->auto_architecture }++;
    }

	# generate the extra mapping for the architectures
	foreach my $seq ( @seqs ) {
	  if( $archStore{$seq->id}->auto_architecture =~ /^(\d+)$/ ) {
		my $rs = $c->model("PfamDB::Architecture")->find( auto_architecture => $1);
		my @domains = split /\~/, $rs->architecture;
		$seqInfo{$seq->id}{arch} = \@domains;
		$seqInfo{$seq->id}{auto_arch} = $1;
		$seqInfo{$seq->id}{num} = $seenArch{ $1 } ;
	  } else {
		$seqInfo{$seq->id}{arch} = "no Pfam A domains";
		$seqInfo{$seq->id}{auto_arch} = "nopfama";
		$seqInfo{$seq->id}{num} =  $seenArch{ $archStore{$seq->id}->auto_architecture };
	  }
	}

	# and finally sort the sequences according to the number of
	# sequences that have a given architecture
	@seqs = sort { $seqInfo{$b->id}{num} <=> $seqInfo{$a->id}{num} } @seqs;
  }

  $c->log->debug( "found " . scalar @seqs . " storables" );

  # draw them...
  my $layout = Bio::Pfam::Drawing::Layout::PfamLayoutManager->new;
  my %regionsAndFeatures = ( "PfamA"      => 1,
							 "PfamB"      => 1,
							 "noFeatures" => 1 );

  $layout->layout_sequences_with_regions_and_features( \@seqs,
													   { PfamA      => 1,
														 PfamB      => 1,
														 noFeatures => 1 } );

  my $imageset = Bio::Pfam::Drawing::Image::ImageSet->new;
  $imageset->create_images( $layout->layout_to_XMLDOM );

  # dump the images and the mapping into the stash
  $c->stash->{images} = $imageset;
  $c->stash->{seqInfo}  = \%seqInfo;

  # set up the view and rely on "end" from the parent class to render it
  $c->stash->{template} = "components/blocks/family/domainSummary.tt";

}

#-------------------------------------------------------------------------------

=head1 AUTHOR

John Tate, C<jt6@sanger.ac.uk>

Rob Finn, C<rdf@sanger.ac.uk>

=head1 COPYRIGHT

This program is free software, you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut

1;
