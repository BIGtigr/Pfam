
# News.pm
# jt 20061207 WTSI
#
# $Id: NewsFeed.pm,v 1.1 2007-01-15 15:10:19 jt6 Exp $

=head1 NAME

PfamWeb::Controller::News - generate the Pfam news feed RSS

=cut

package PfamWeb::Controller::NewsFeed;

=head1 DESCRIPTION

Generates the Pfam news feed RSS.

$Id: NewsFeed.pm,v 1.1 2007-01-15 15:10:19 jt6 Exp $

=cut

use strict;
use warnings;

use XML::Feed;
use DateTime::Format::MySQL;

use base "Catalyst::Controller";

#-------------------------------------------------------------------------------

=head1 METHODS

=head2 index : Private

Shows all Pfam news feed items in full.

=cut

sub index : Private {
	my( $this, $c ) = @_;
	
	# retrieve the news items from the feed
	my @entries = 
		$c->model("WebUser::News")->search( {}, { order_by => "pubDate DESC" } );
	$c->stash->{newsItems} = \@entries;

	$c->stash->{template} = "pages/news.tt";
}

#-------------------------------------------------------------------------------

=head2 rss : Global

Generates an RSS feed.

=cut

sub rss : Global {
	my( $this, $c ) = @_;

	# start a feed
	my $feed = XML::Feed->new("RSS");

	# build the channel info
	$feed->title("Pfam RSS Feed");
	$feed->link( $c->req->base );
	$feed->description("Pfam News");
	$feed->language("en-GB");

	# query the DB for news items, in reverse chronological order
	my @entries =
		$c->model("WebUser::News")->search( {}, { order_by => "pubDate DESC" } );

	# add each item to the feed
	foreach my $entry (@entries) {
		my $feedEntry = XML::Feed::Entry->new("RSS");
		$feedEntry->title( $entry->title );
		$feedEntry->link( $c->uri_for( "/newsfeed#" . $entry->auto_news ) );
		$feedEntry->issued(
									 DateTime::Format::MySQL->parse_datetime( $entry->pubDate ) );
		$feed->add_entry($feedEntry);
	}

	# just dump the raw XML to the body
	$c->res->body( $feed->as_xml );
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
