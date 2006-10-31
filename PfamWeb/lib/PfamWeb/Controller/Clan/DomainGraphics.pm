
# DomainGraphics.pm
# jt6 20060718 WTSI
#
# $Id

=head1 NAME

PfamWeb::Controller::Family - build the post-loaded clan graphics

=cut

package PfamWeb::Controller::Clan::DomainGraphics;

=head1 DESCRIPTION

Handles the generation of the graphics component of the clan pages.

Generates a B<page fragment>.

$Id: DomainGraphics.pm,v 1.3 2006-10-31 15:14:33 jt6 Exp $

=cut

use strict;
use warnings;

use Data::Dumper;
use Storable qw(thaw);

use base "PfamWeb::Controller::Clan";

#-------------------------------------------------------------------------------

=head1 METHODS

=head2 default : Path

Generates the Pfam-style domain graphics for a clan. If handed the
parameter "all=1" the controller will generate B<all> of the graphics
for a clan, which can be a pretty stupid thing to do. Otherwise it
generates only the first 50 graphics.

=cut

sub default : Path {
  my( $this, $c ) = @_;

  my $autoClan = $c->stash->{clan}->auto_clan;

  ( $c->stash->{auto_arch} ) = $c->req->param( "arch" ) =~ /^(\d+)$/
	if $c->req->param( "arch" );

  my( @seqs, %seqInfo, @architectures );
  if( $c->stash->{auto_arch} ) {
	# we want to see all of the sequences with a given architecture
	
    @architectures = $c->model("PfamDB::Pfamseq_architecture")
      ->search( { "arch.auto_architecture" => $c->stash->{auto_arch} },
				{ join      => [ qw/ arch annseq /],
				  prefetch  => [ qw/ arch annseq/] } );

	foreach my $arch ( @architectures ) {
	  push @seqs, thaw( $arch->annseq_storable );
	}

  } else{
	# we want to see the unique architectures containing this domain

	if( defined $c->req->param( "all" ) ) {

	  @architectures = $c->model("PfamDB::Architecture")
		->search( { auto_clan => $autoClan },
				  { join     => [qw/clan_arch storable type_example/],
					prefetch => [qw/storable type_example/],
					order_by => "no_seqs DESC"
				  } )->all;
	} else {

	  @architectures = $c->model("PfamDB::Architecture")
		->search( { auto_clan => $autoClan },
				  { join     => [qw/clan_arch storable type_example/],
					prefetch => [qw/storable type_example/],
					order_by => "no_seqs DESC",
					rows     => 50,
					page     => 1
				  } )->all;
	}

	foreach my $arch ( @architectures ) {
	  push @seqs, thaw( $arch->annseq_storable );
	  my @domains = split /\~/, $arch->architecture;
	  $seqInfo{$arch->pfamseq_id}{arch} = \@domains;
	  $seqInfo{$arch->pfamseq_id}{num} = $arch->no_seqs;
	  $seqInfo{$arch->pfamseq_id}{auto_arch} = $arch->auto_architecture;
	}

  }
  $c->log->debug( "found " . scalar @seqs . " storables" );

  my $layout = Bio::Pfam::Drawing::Layout::PfamLayoutManager->new;
  $layout->scale_x( $this->{scale_x} ); #0.33
  $layout->scale_y( $this->{scale_y} ); #0.45

  $layout->layout_sequences_with_regions_and_features( \@seqs,
													   { PfamA      => 1,
														 PfamB      => 1,
														 noFeatures => 0 } );
														
  my $imageset = Bio::Pfam::Drawing::Image::ImageSet->new;
  $imageset->create_images( $layout->layout_to_XMLDOM );

  $c->stash->{images} = $imageset;
  $c->stash->{seqInfo}  = \%seqInfo;

  # set the template and let the View render it via the "end" method
  # on the parent class
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
