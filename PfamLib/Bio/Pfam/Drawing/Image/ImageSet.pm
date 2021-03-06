
# $Author: jt6 $

package Bio::Pfam::Drawing::Image::ImageSet;

use strict;
use warnings;

use GD;
#use XML::DOM;
use XML::LibXML;
use XML::LibXML::XPathContext;
use Bio::Pfam::Drawing::Image::Image;
use Bio::Pfam::Drawing::Image::Graph;

use Time::HiRes qw( gettimeofday );

# provide the name of the Image class via a method on the class, so that we can 
# override and replace it
sub image_class { 'Bio::Pfam::Drawing::Image::Image' }

sub new{
  my $class = shift;
  my $self = bless {}, ref($class) || $class;
  $self->{ 'images' } = [];
  $self->{ 'graphs' } = [];
  $self->{timeStamp} = gettimeofday * 100000;
  
  # take the namespace from an environment variable, if set 
  $self->{ns} = $ENV{PFAM_XML_NS} || 'http://pfam.sanger.ac.uk/static/documents/pfamDomainGraphics.xsd';

  return $self;
}

# if "skipReparse" is set to true, the method will NOT re-parse the
# supplied dom.

sub create_images {
  my ($self, $origDom, $skipReparse ) = @_;

  my %stored_images;
#  print STDERR "received: |$origDom|\n";

  # a hideous hack. Dump the XML into a string and then parse it back
  # in to get a new DOM. This seems to be the only way to make the
  # whole thing work... we're putting it down to the insertion of
  # empty text nodes at various places in the re-parsed DOM, which, if
  # missing, screw up the XPaths that are executed on the original,
  # hand-crafted DOM. It's all very ugly.
  # jt6 20060120 WTSI.

  my $dom;
  unless( $skipReparse ) {
  	my $parser = XML::LibXML->new;
  	$dom = $parser->parse_string( $origDom->toString );
  } else {
  	$dom = $origDom;
  }
#print STDERR "creating image from XML: |" . $dom->toString(1) . "|\n";

  my $root = $dom->documentElement;
  my $xc = XML::LibXML::XPathContext->new( $root );
  $xc->registerNs( "pf" => $self->{ns} );

  foreach my $seqNode ( $xc->findnodes( "pf:sequence" ) ) {
	
#print STDERR "creating image for |$seqNode|", $seqNode->nodeName, "|\n";

    my $image = $self->image_class->new( { timeStamp => $self->{timeStamp} } );

#print STDERR "imageset: length: |", $seqNode->getAttribute( "length" ), "|\n";

    $image->scale_x( $root->getAttribute( "scale_x" ) );
    $image->scale_y( $root->getAttribute( "scale_y" ) );
    $image->format(  $root->getAttribute( "format"  ) );
    $image->bg_colour();#not yet implemented
    $image->create_image( $seqNode, \%stored_images );

    $self->add_image( $image );
  }

  my $maxOffSet = 0;
  foreach my $graphNode ( $xc->findnodes( "pf:graph" ) ) {
    my $image = Bio::Pfam::Drawing::Image::Graph->new( { timeStamp => $self->{timeStamp} } );
    $image->length( $root->getAttribute( "length" ) );
    $image->height( $root->getAttribute( "height" ) );
    $image->format(  $root->getAttribute( "format"  ) );
    $image->bg_colour();#not yet implemented
    $image->create_graph( $graphNode );
    if($image->offSet){
      $maxOffSet = $image->offSet if($image->offSet > $maxOffSet); 
    }
    $self->add_graph( $image );
  }

  if($maxOffSet){
    foreach my $image ($self->each_image){
      $image->addOffSet($maxOffSet);

    }
  }

}

sub add_image {
  my ($self, $pointer) = @_;
  if($pointer){
    push(@{$self->{'images'}}, $pointer);
# print STDERR "imageset: added image: |$pointer|\n";
  }
}

sub each_image {
  my $self = shift;
#  return @{$self->{images}};
  return wantarray ? @{$self->{images}} : $self->{images};
}

sub add_graph{
  my ($self, $graphObj) = @_;
  if($graphObj){
    push(@{$self->{'graphs'}}, $graphObj);
  }
}

sub each_graph{
  my $self = shift;
  return (@{$self->{'graphs'}});
}

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

