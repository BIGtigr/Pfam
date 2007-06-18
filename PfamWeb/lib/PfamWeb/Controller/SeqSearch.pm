
# SeqSearch.pm
# jt6 20061108 WTSI
#
# $Id: SeqSearch.pm,v 1.23 2007-06-18 12:26:43 jt6 Exp $

=head1 NAME

PfamWeb::Controller::SeqSearch - perform various sequence searches

=cut

package PfamWeb::Controller::SeqSearch;

=head1 DESCRIPTION

This controller is responsible for running sequence searches.

$Id: SeqSearch.pm,v 1.23 2007-06-18 12:26:43 jt6 Exp $

=cut

use strict;
use warnings;

use Bio::SearchIO::blast;
use File::Temp qw( tempfile );
use JSON;
use Scalar::Util qw( looks_like_number );
use Data::UUID;
use Storable qw( thaw );
use Sanger::Graphics::ColourMap;

use Data::Dump qw( dump );

use base "PfamWeb::Controller::Section";

# set the name of the section
__PACKAGE__->config( SECTION => 'seqsearch' );

#-------------------------------------------------------------------------------

=head1 METHODS

=head2 begin : Private

Tries to extract the query terms from the URL and de-taint them.

=cut

sub begin : Private {
  my( $this, $c ) = @_;

  # tell the navbar where we are
  $c->stash->{nav} = 'search';
  
  # tell the layout template to disable the summary icons
  $c->stash->{iconsDisabled} = 1;

  # if there's no query parameter, we're done here; drop straight to the 
  # template that will render the search forms
  return unless $c->req->param( 'query' );

  # get the query
  my( $terms ) = $c->req->param( 'query' ) =~ /^([\w\:\;\-\.\s]+)/;

  # we're done here unless there's a query specified
  $c->log->warn( 'Search::begin: no query terms supplied' ) and return
  unless defined $terms;

  # stash the de-tainted terms so we can safely display them later
  $c->stash->{rawQueryTerms} = $terms;

  # somewhere for the results of this search
  $c->stash->{results} = {};

}

#-------------------------------------------------------------------------------
#- exposed actions -------------------------------------------------------------
#-------------------------------------------------------------------------------

=head2 batch : Local

Executes a batch search.

=cut

sub batch : Local {
  my( $this, $c ) = @_;

  $c->log->debug( "SeqSearch::domain: executing a batch search" );
}

#-------------------------------------------------------------------------------

=head2 funshift : Local

Executes a functional similarity search.

=cut

sub funshift : Local {
  my( $this, $c ) = @_;

  return unless $c->req->param( 'entry' ) =~ m/^([\w_-]+)$/;
  $c->log->debug( "SeqSearch::funshift: executing a functional similarity search for |$1|" );

  # check for an accession or an ID
  if( $c->req->param( 'entry' ) =~ /^(PF\d{5})$/i ) {

    $c->log->debug( 'SeqSearch::funshift: might be a Pfam accession' );
    $c->stash->{pfam} = $c->model("PfamDB::Pfam")->find( { pfamA_acc => $1 } );

  } elsif( $c->req->param( "entry" ) =~ /^([\w_-]+)$/ ) {

    $c->log->debug( 'SeqSearch::funshift: might be a Pfam accession' );
    $c->stash->{pfam} = $c->model("PfamDB::Pfam")->find( { pfamA_id => $1 } );

  } else {
    
    $c->log->debug( q(SeqSearch::funshift: can't figure out whether it's an ID or acc) );
    $c->stash->{fsSearchError} = q(Couldn't find a Pfam family with that ID or accession.);
    return;
    
  }
  
  # make sure the query actually found an entry
  if( not defined $c->stash->{pfam} ) {
    $c->log->debug( "SeqSearch::funshift: can't find a Pfam family |$1|" );
    $c->stash->{fsSearchError} = q(Couldn't find a family with that ID or accession.);
    return;
  }
  
  # yes; now do the funshift search
  my @fs = $c->model('PfamDB::Funshift')
             ->search( { auto_pfamA_A => $c->stash->{pfam}->auto_pfamA,
                         auto_pfamA_B => { '!=' => $c->stash->{pfam}->auto_pfamA },
                         rfunSim      => { '>'  => 0.75 } },
                       { join     => [ qw/ pfam clan / ],
                         prefetch => [ qw/ pfam clan / ], 
                         order_by => "rfunSim DESC" } );

  $c->log->debug( 'SeqSearch::funshift: found |' . scalar @fs . '| rows' );

  if( scalar @fs ) {

    $c->stash->{template} = "pages/fsResults.tt";
    $c->stash->{results} = \@fs;
  
    # generate a gradient for this many rows
    my $cm = new Sanger::Graphics::ColourMap;
    my @grad = $cm->build_linear_gradient( scalar @fs, '008000', 'C00000' );
    $c->stash->{gradient} = \@grad;

  } else {
    # see if there are any GO terms for this family
    $c->stash->{goTerms} = $c->model('PfamDB::GO')
                             ->search( { 'me.auto_pfamA' => $c->stash->{pfam}->auto_pfamA } );
    
    $c->stash->{template} = 'pages/fsError.tt';
  }
}

#-------------------------------------------------------------------------------

=head2 domain : Local

Executes a domain query.

=cut

sub domain : Local {
  my( $this, $c ) = @_;

  $c->log->debug( 'SeqSearch::domain: executing a domain search' );

  $c->log->debug( 'SeqSearch::domain: |' . $c->req->param( 'have' ) . '|' );

  # point at the template right away
  $c->stash->{template} = 'components/blocks/family/domainSummary.tt';

  my $list;
  if( defined $c->req->param( 'have' ) ) {
    foreach ( split /\s+/, $c->req->param( 'have' ) ) {
      next unless /(PF\d{5})/;
      $list .= "+$1 ";
    }
  }
  if( defined $c->req->param( 'not' ) ) {
    foreach ( split /\s+/, $c->req->param( 'not' ) ) {
      next unless /(PF\d{5})/;
      $list .= "-$1 ";
    }
  }

  $c->log->debug( "SeqSearch::domain: list: |$list|" );

  return unless $list;

  my @architectures = $c->model('PfamDB::Architecture')
                        ->search( {},
                                  { join     => [ qw/ annseq / ],
                                    prefetch => [ qw/ annseq / ],
                                    order_by => "no_seqs DESC" } )
                        ->search_literal( 'MATCH( architecture_acc ) ' .
                                          'AGAINST( ? IN BOOLEAN MODE )',
                                          $list );

  my $sum = 0;
  foreach my $arch ( @architectures ) {
    $sum += $arch->no_seqs;
  }

  $c->log->debug( 'SeqSearch::domain: found ' . scalar @architectures .
                  ' rows, with a total of $sum sequences' );

  $c->stash->{numRows} = scalar @architectures;
  $c->stash->{numSeqs} = $sum;

  # if there are too many results, bail here and let the TT just
  # display the text summary, plus an admonition to the user to
  # restrict their search a bit
  return if scalar @architectures > 500;

  # build the mappings that we'll need to interpret all this...
  my( @seqs, %seqInfo );
  foreach my $arch ( @architectures ) {

    # thaw out the sequence object for this architecture
    push @seqs, thaw( $arch->annseq_storable );
  
    # work out which domains are present on this sequence
    my @domains = split /\~/, $arch->architecture;
    $seqInfo{$arch->pfamseq_id}{arch} = \@domains;
  
    # store a mapping between the sequence and the auto_architecture
    $seqInfo{$arch->pfamseq_id}{auto_arch} = $arch->auto_architecture;
  
    # if this is a call to retrieve all of the architectures, we don't
    # have an auto_architecture, so this won't work
    $seqInfo{$arch->pfamseq_id}{num} = $arch->no_seqs unless $c->stash->{auto_arch};
  }
  $c->log->debug( 'found ' . scalar @seqs . ' storables' );

  if( scalar @seqs ) {
    my $layout = Bio::Pfam::Drawing::Layout::PfamLayoutManager->new;
    
    $layout->layout_sequences_with_regions_and_features( \@seqs, { PfamA      => 1,
                                                                   PfamB      => 1,
                                                                   noFeatures => 1 } );
    
    my $imageset = Bio::Pfam::Drawing::Image::ImageSet->new;
    $imageset->create_images( $layout->layout_to_XMLDOM );
  
    $c->stash->{images} = $imageset;
    $c->stash->{seqInfo}  = \%seqInfo;
  }

}

#-------------------------------------------------------------------------------

=head2 seq : Local

Queues a sequence search job and returns a page that polls the server for
results.

=cut

sub seq : Local {
  my( $this, $c ) = @_;
  
  $c->log->debug( 'SeqSearch::seq: form was submitted' );

  # check the input

  # the sequence itself
  $c->stash->{seq} = $c->forward( 'parseSequence' );
  unless( $c->stash->{seq} ) {
    $c->stash->{seqSearchError} = 'No valid sequence found. Please enter a valid amino-acid sequence and try again.';
    return;
  }
  
  # sequence search options
  if( defined $c->req->param( 'seqOpts' ) ) {
    $c->stash->{seqOpts} = $c->req->param( 'seqOpts' );
    unless( $c->stash->{seqOpts} eq 'both' or
            $c->stash->{seqOpts} eq 'bothNoMerge' or
            $c->stash->{seqOpts} eq 'ls' or
            $c->stash->{seqOpts} eq 'fs' ) {
      $c->stash->{seqSearchError} = 'You must select a valid search option.';

      $c->log->debug( 'SeqSearch::seq: bad search option; returning to form' );
      return;
    }
  } else {
    $c->log->debug( 'SeqSearch::seq: search options not specified; returning to form' );
    $c->stash->{seqSearchError} = 'You must select a search option.';
    return;
  }

  # if we have an evalue, we'll use that, otherwise we'll use the gathering
  # threshold
  if( defined $c->req->param( 'ga' ) and $c->req->param( 'ga' ) ) {
    $c->stash->{ga} = 1;
  } else {
    if( defined $c->req->param( 'evalue' ) and 
      looks_like_number( $c->req->param( 'evalue' ) ) ) {
      $c->stash->{evalue} = $c->req->param( "evalue" );
    } else {
      $c->log->debug( 'SeqSearch::seq: bad evalue; returning to form' );
      $c->stash->{seqSearchError} = 'You did not enter a valid E-value.';
      return;
    }
  }

  # try to submit the search
  my $submissionStatus = $c->forward( 'queueSeqSearch' );

  # and see if we managed it...
  if( $submissionStatus > 0 ) {
    $c->log->debug( 'SeqSearch::seq: sequence is pre-calculated; returning results' ); 
    $c->stash->{template} = 'pages/seqSearchDone.tt';

  } elsif( $submissionStatus < 0 ) {
    $c->log->debug( 'SeqSearch::seq: problem with submission; re-rendering form' ); 
    return;

  } else {
    $c->log->debug( 'SeqSearch::seq: sequence search submitted; polling' ); 
    $c->stash->{template} = 'pages/polling.tt';
  }
}

#-------------------------------------------------------------------------------

=head2 checkStatus : Local

Returns the status of the specified job. Used by the javascript that polls for
the status via XMLHttpRequest calls.

=cut

sub checkStatus : Local {
  my( $this, $c ) = @_;

  # build a hash that we'll convert into JSON and return
  $c->stash->{status} = {};

  my $jobId = $c->req->param( 'jobId' );

  if( length( $jobId ) != 36 or $jobId !~ /[A-F0-9\-]/ ) {
    $c->log->debug( 'SeqSearch::checkStatus: bad job id' );
    $c->stash->{status}->{error} = 'Invalid job ID';
    $c->detach( 'returnStatus' );
  }

  # job ID appears to be valid; try querying for the status of that job
  my $jobStatus = $c->model( 'WebUser::JobHistory' )
                    ->find( { job_id => $jobId } );

  # make sure the query returned *something*
  if( not defined $jobStatus ) {
    $c->log->debug( "SeqSearch::checkStatus: problem retrieving job status for job |$jobId|" );
    $c->stash->{status}->{error} = 'Could not retrieve job status';
    $c->detach( 'returnStatus' );
  }

  # finally, check the real status 
  if( $jobStatus->status eq 'PEND' ) {
    $c->log->debug( 'SeqSearch::checkStatus: job is pending' );
    $c->stash->{status}->{status} = 'PEND';

  } elsif( $jobStatus->status eq 'RUN' ) {
    $c->log->debug( 'SeqSearch::checkStatus: job is running' );
    $c->stash->{status}->{status} = 'RUN';

  } elsif( $jobStatus->status eq 'DONE' ) {
    $c->log->debug( 'SeqSearch::checkStatus: job is done' );
    $c->stash->{status}->{status} = 'DONE';

  } elsif( $jobStatus->status eq 'FAIL' ) {
    $c->log->debug( 'SeqSearch::checkStatus: job failed' );
    $c->stash->{status}->{status} = 'FAIL';

  } else {
    $c->log->error( q(SeqSearch::checkStatus: can't determine job status) );
    $c->stash->{status}->{status} = 'UNKNOWN';
  }

#  $c->log->debug( 'SeqSearch::checkStatus: opened:  |' . $jobStatus->opened .'|' );
#  $c->log->debug( 'SeqSearch::checkStatus: started: |' . $jobStatus->started .'|' );
#  $c->log->debug( 'SeqSearch::checkStatus: closed:  |' . $jobStatus->closed .'|' );

  # see how many jobs are pending
  my $rs = $c->model( 'WebUser::JobHistory' )
             ->search( { status => 'PEND',
                         id     => { '<',  $jobStatus->id },
                         job_id => { 'not like', $jobStatus->job_id } },
                       { select => [
                                     { count => 'id' },
                                     { sum   => 'estimated_time' }
                                   ],
                         as     => [ qw( num wait ) ] }
                     );
  $c->stash->{status}->{numPending} = $rs->first()->get_column( 'num' );
  $c->stash->{status}->{waitTime}   = $rs->first()->get_column( 'wait' ) || 0;

  $c->log->debug( 'SeqSearch::checkStatus: found      |' .
                  $c->stash->{status}->{numPending} . '| pending jobs' );
  $c->log->debug( 'SeqSearch::checkStatus: wait time: |' .
                  $c->stash->{status}->{waitTime} . '|' );

  # add the times to the response
  $c->stash->{status}->{opened}  = $jobStatus->opened;
  $c->stash->{status}->{started} = $jobStatus->started;
  $c->stash->{status}->{closed}  = $jobStatus->closed;

  # and hand back that status
  $c->forward( 'returnStatus' );
}

#-------------------------------------------------------------------------------
#- private actions -------------------------------------------------------------
#-------------------------------------------------------------------------------

=head2 parseSequence : Private

Parses the sequence supplied by the CGI parameter "seq". Returns the sequence
as a single string if it's parsed successfully, or the empty string if there
was a problem parsing or if the final sequence contains a character other than
[A-Za-z].

=cut

sub parseSequence : Private {
  my( $this, $c ) = @_;

  return unless defined $c->req->param( 'seq' );
  
  my @seqs = split /\n/, $c->req->param( 'seq' );
  shift @seqs if $seqs[0] =~ /^\>/;
  my $seq = uc( join '', @seqs );
  $seq =~ s/[\s\r]+//g;

  $c->log->debug( "SeqSearch::parseSequence: parsed sequence: |$seq|" );
  return ( $seq =~ /^[A-Z]+$/ ) ? $seq : '';
}

#-------------------------------------------------------------------------------

=head2 queueSeqSearch : Private

Executes a protein sequence search. Queues a Pfam A search to one queue
and, if the appropriate box was checked in the submission form, a Pfam B search
to another queue.

=cut

sub queueSeqSearch : Private {
  my( $this, $c ) = @_;

  # Taken out MD% check as we need to search the sequence as the results are different.

  # first, check there's room in the queue
  my $rs = $c->model( 'WebUser::JobHistory' )
             ->find( { status => 'PEND' },
                     { select => [ { count => 'status' } ],
                       as     => [ "numberPending" ] } );

  $c->stash->{numberPending} = $rs->get_column( 'numberPending' );
  $c->log->debug( 'SeqSearch::queueSeqSearch: |' . $c->stash->{numberPending} .
                  '| jobs pending' );

  if( $c->stash->{numberPending} > $this->{pendingLimit} ) {
    $c->log->debug( 'SeqSearch::queueSeqSearch: too many jobs in queue (' .
                    $c->stash->{numberPending} . ')' );
    $c->stash->{seqSearchError} = 'There are currently too many jobs in the sequence search queue. Please try again in a little while.';
    return -1;
  }

  # ok. There's room on the queue, so we can submit the hmmer job and the blast job

  my @jobs; 
  push @jobs, $c->forward( 'queuePfamA' );
  push @jobs, $c->forward( 'queuePfamB' ) if $c->req->param( 'searchBs' );
  
  # build a job status data structure that we'll convert to JSON and hand back
  # to the javascript on the client side
  $c->log->debug( dump( \@jobs ) );

  $c->stash->{jobStatus} = objToJson( \@jobs );

  $c->log->debug( 'json string: |' . $c->stash->{jobStatus} . '|' );

  return 0;
}

#-------------------------------------------------------------------------------

=head2 queuePfamA : Private

Submits a pfam A search.

=cut

sub queuePfamA : Private {
  my( $this, $c ) = @_;

  # make a guess at the runtime for the job
  my $estimatedTime = int( length( $c->stash->{seq} ) / 100 );
  $c->log->debug(  q(SeqSearch::queuePfamA: estimated search time: ) . 
                  qq(|$estimatedTime| seconds) );
  ($estimatedTime *= 2 ) if( $c->stash->{seqOpts} eq 'both' or
                             $c->stash->{seqOpts} eq 'bothNoMerge' );
  $c->log->debug(  q(SeqSearch::queuePfamA: estimated search time: ) .
                  qq(|$estimatedTime| seconds) );

  # generate a job ID
  my $jobId = Data::UUID->new()->create_str();

  # build the command to run
  my $cmd;
  $cmd  =  q(/home/pfamweb/scripts/pfam_scan.pl -pvm -align -d /data/blastdb/Pfam/data);
  $cmd .=  q( --mode ) . $c->stash->{seqOpts} if( $c->stash->{seqOpts} ne 'both' and 
                                                  $c->stash->{seqOpts} ne 'bothNoMerge' );
  $cmd .=  q( --no_merge )                    if( $c->stash->{seqOpts} eq 'bothNoMerge' );
  $cmd .=  q( -e )     . $c->stash->{evalue}  if( $c->stash->{evalue} and not $c->stash->{ga} );
  $cmd .=  q( --overlap )                     if( $c->stash->{showOverlap} );
  $cmd .= qq( /tmp/$jobId.fa);

  # add this job to the tracking table
  my $resultHistory = $c->model('WebUser::JobHistory')
                        ->create( { command        => $cmd,
                                    priority       => 'hmmer',
                                    estimated_time => $estimatedTime,
                                    job_id         => $jobId,
                                    opened         => \'NOW()',
                                    status         => 'PEND' } );

  my $resultStream = $c->model('WebUser::JobStream')
                       ->create( { id    => $resultHistory->id,
                                   stdin => $c->stash->{seq} || q() } );

  # check the submission time with a separate query
  my $historyRow = $c->model( 'WebUser::JobHistory' )
                     ->find( { id => $resultHistory->id } );

  # build a job status data structure that we'll convert to JSON and hand back
  # to the javascript on the client side
  my $jobStatus = {
                    checkURI      => $c->uri_for( '/seqsearch/checkStatus' )->as_string,
                    doneURI       => $c->uri_for( '/seqsearch/jobDone' )->as_string,    
                    estimatedTime => $estimatedTime,
                    interval      => $this->{pollingInterval},
                    jobId         => $jobId,
                    name          => 'Pfam A search',
                    jobClass      => 'pfamASearch',
                    opened        => $historyRow->opened,
                  };
  return $jobStatus;
}

#-------------------------------------------------------------------------------

=head2 queuePfamB : Private

Submits a pfam B search.

=cut

sub queuePfamB : Private {
  my( $this, $c ) = @_;

  # make a guess at the runtime for the job
  my $estimatedTime = int( length( $c->stash->{seq} ) / 100 );
  $c->log->debug( "SeqSearch::queuePfamB: estimated search time: |$estimatedTime| seconds" );

  # generate a job ID
  my $jobId = Data::UUID->new()->create_str();

  # build the command to run
  my $cmd;
  $cmd  =  q(/data/bin/wublastp /data/blastdb/Pfam/data/Pfam-B.fasta);
  $cmd .= qq( /tmp/$jobId.fa);
  $cmd .=  q( -cpus 2 -gapE=2000 -T=12);

  # add this job to the tracking table
  my $resultHistory = $c->model('WebUser::JobHistory')
                        ->create( { command        => $cmd,
                                    priority       => 'fast',
                                    estimated_time => $estimatedTime,
                                    job_id         => $jobId,
                                    opened         => \'NOW()',
                                    status         => 'PEND' } );

  my $resultStream = $c->model('WebUser::JobStream')
                       ->create( { id    => $resultHistory->id,
                                   stdin => $c->stash->{seq} || q() } );

  # check the submission time with a separate query
  my $historyRow = $c->model( 'WebUser::JobHistory' )
                     ->find( { id => $resultHistory->id } );

  # build a job status data structure that we'll convert to JSON and hand back
  # to the javascript on the client side
  my $jobStatus = {
                    checkURI      => $c->uri_for( '/seqsearch/checkStatus' )->as_string,
                    doneURI       => $c->uri_for( '/seqsearch/jobDone' )->as_string,    
                    estimatedTime => $estimatedTime,
                    interval      => $this->{pollingInterval},
                    jobId         => $jobId,
                    name          => 'Pfam B search',
                    jobClass      => 'pfamBSearch',
                    opened        => $historyRow->opened,
                  };
  return $jobStatus;
}

#-------------------------------------------------------------------------------

=head2 returnStatus : Local

Returns the status of a polled job as a JSON snippet. Short-circuits the default
end action because we're adding content directly to the response body. We also
take care to set apropriate headers to avoid this response being cached on the
client side.

=cut

sub returnStatus : Private {
  my( $this, $c ) = @_;

  # convert the status hash to a JSON object and return it
  my $status = objToJson( $c->stash->{status} );

  $c->log->debug( 'SeqSearch::returnStatus: returning: ' );
  $c->log->debug( dump( $c->stash->{status} ) );

  $c->res->content_type( 'application/json' );
  $c->res->body( $status );

  # make damned sure this isn't cached...
  $c->res->header( 'Pragma'        => 'no-cache' );
  $c->res->header( 'Expires'       => 'Thu, 01 Jan 1970 00:00:00 GMT' );
  $c->res->header( 'Cache-Control' => 'no-store, no-cache, must-revalidate,'.
                                      'post-check=0, pre-check=0, max-age=0' );

}

#-------------------------------------------------------------------------------

=head2 jobDone : Local

Returns the URI of the Pfam graphic that is the result of the specified job.

=cut

sub jobDone : Local {
  my( $this, $c ) = @_;

  # extract the list of IDs from the URI
  my @jobIds = $c->req->param( 'jobId' );
  foreach ( @jobIds ) {

    # detaint the job ID
    ( my $jobId ) = $_ =~ m/^([A-F0-9\-]+)$/;
    $c->log->debug( "SeqSearch::jobDone: looking up details for job ID: |$jobId|" );

    next unless defined $jobId;

    # job ID *looks* valid; try looking for that job
    my $job = $c->model( 'WebUser::JobHistory' )
                ->find( { job_id => $jobId },
                        { join     => [ qw( job_stream ) ],
                          prefetch => [ qw( job_stream ) ] } );

    # bail unless it exists
    next unless defined $job;

    # retrieve the results of the job and stash them
    $c->stash->{results}->{$jobId}->{rawData} = $job->stdout;
    $c->stash->{results}->{$jobId}->{method}  = $job->priority;
    $c->stash->{results}->{$jobId}->{command} = $job->command;
    $c->{stash}->{seq} = $job->stdin;
  }

  # do something interesting with the results
  $c->forward( 'handleResults' );
  $c->forward( 'generateGraphic' );
  $c->stash->{template} = 'pages/jobDone.tt';
}

#-------------------------------------------------------------------------------

=head2 handleResults : Private

Parse the results and filter based on the the users defined parameters. The 
parsed results are put in a very generic format so that they can then be used 
for generating the results tables and graphics.

=cut

sub handleResults : Private {
  my( $this, $c ) = @_;

  #There two arrays will be populated with each hit represented as a hash.
  #We go through these step for two reasons
  #1. Allows us to potentially use the data in the database rather than 
  #   searching every sequence
  #2. Removes redundancy in the pfamB results.
  my(@rawPfamAResults, @rawPfamBResults);

  foreach my $jobId ( keys %{ $c->stash->{results} } ) {
    $c->log->debug( "SeqSearch::handleResults: handling results for |$jobId|" );

    #Identify What sort of job we have performed.....
    if( $c->{stash}->{results}->{$jobId}->{method} eq 'hmmer' ){
      
      #We have performed a hmmer search, must be a pfamA
      my( $userEvalue ) = $c->{stash}->{results}->{$jobId}->{command} =~ /-e (\S+)/;
      
      #Are we using GA cut-offs of Evalues?
      $c->stash->{evalue} = $userEvalue ? $userEvalue : 0;
      
      #Read in the pfam_scan data. This assumes that pfam_Scan is spitting out 
      #alignments so each domain is represented by 4 lines. 
      my @results = split(/\n/, $c->{stash}->{results}->{$jobId}->{rawData});

      while( @results ) {
        my @set = splice( @results, 0, 4 );
        
        my( $start, $end, $pfamA_acc, $hmmStart, $hmmEnd, $mode, $bits, 
            $evalue, $pfamA_id, $aliHmm, $aliMatch, $aliSeq, $s, $pfamData );
        foreach ( @set ) {

          #Line 1 is the domain positional information, lines 2-4 contain the 
          #actual alignment
          if( /^\S+\s+(\d+)\s+(\d+)\s+(PF\d{5})\.\d+\s+(\d+)\s+(\d+)\s+(\S+)\s+(\S+)\s+(\S+)\s+(\S+)/ ) {

            ( $start, $end, $pfamA_acc, $hmmStart, $hmmEnd, $mode, $bits, 
              $evalue, $pfamA_id ) = ( $1, $2, $3, $4, $5, $6, $7, $8, $9 );
              
            $pfamData = $c->model('PfamDB::Pfam')
                          ->find( { pfamA_acc => $pfamA_acc } );
                          
            if( $mode eq 'ls' ) {
              $s = $pfamData->ls_domain_GA < $bits ? 1 : 0; 
            }elsif( $mode eq 'fs' ) {
              $s = $pfamData->fs_domain_GA < $bits ? 1 : 0; 
            }
          } elsif( /\#HMM/ ) {
            $aliHmm = $_;
            $aliHmm .= "-*" if $aliHmm =~ m/\<$/; 
            $aliHmm .= "*"  if $aliHmm =~ m/\<\-$/; 
          } elsif( /\#MATCH/ ) {
            $aliMatch = $_; 
          } elsif( /\#SEQ/ ) {
            $aliSeq = $_; 
          }
        }

        #Now shove all of the data elements into an anonymous hash
        push @rawPfamAResults, { pfama_id     => $pfamA_id,
                                 pfama_acc    => $pfamA_acc,
                                 start        => $start,
                                 end          => $end,
                                 hmm_start    => $hmmStart,
                                 hmm_end      => $hmmEnd,
                                 model_length => $pfamData->model_length,
                                 mode         => $mode,
                                 significant  => $s,
                                 bits         => $bits,
                                 evalue       => $evalue,
                                 type         => $pfamData->type,
                                 desc         => $pfamData->description,
                                 aliMatch     => $aliMatch,
                                 aliHmm       => $aliHmm,
                                 aliSeq       => $aliSeq };

      } 

    } elsif( $c->{stash}->{results}->{$jobId}->{method} eq 'fast' ) {
      #Okay, looks like we have a pfamB result
      
      # flag the fact that we're searching PfamBs in the stash, so the template
      # can write some clever text...
      $c->stash->{searchedPfamB} = 1;
      
      #Grr - Write results to file as this is the only way we can get BioPerl to read it.
      #However, bioperl does a good jobs (most of the time, although some wu-blast errors cause expections to be thrown  
      my $tmpRoot;
      if( $ENV{PFAM_DOMAIN_IMAGES} ) {
        $tmpRoot = $ENV{PFAM_DOMAIN_IMAGES};
      } elsif( $ENV{DOCUMENT_ROOT} ) {
        $tmpRoot = "$ENV{DOCUMENT_ROOT}/tmp/pfam";
      } else {
        die q(Can't set a temp directory for muscle output);
      }
      ( $tmpRoot ) = $tmpRoot =~ m|([a-z0-9_\./]+)|i;

      my( $tmpFh, $tmpFile ) = tempfile( DIR => $tmpRoot );
      print $tmpFh $c->{stash}->{results}->{$jobId}->{rawData};
      close $tmpFh;

      #Parse the results and remove the redundancy
      my %results;  
      my $searchio = new Bio::SearchIO::blast( -format => 'blast',
                                                -file   => $tmpFile,
                                                -signif => 0.001 );
      unlink( $tmpFile );
      
      while( my $result = $searchio->next_result ) {
        $c->log->debug( 'Pfam-B Query sequence: ' . $result->query_name );
        while( my $hit = $result->next_hit ) {
          my( $pfamB_acc, $pfamB_id ) = split ';', $hit->description;
           
          HIT: while( my $hsp = $hit->next_hsp ) {
            if($results{$pfamB_acc}){
              foreach my $r (@{$results{$pfamB_acc}}){
                 
                next HIT if( ( $r->{'start'} >= $hsp->start and $r->{'start'} <= $hsp->end ) or
                             ( $r->{'end'}   >= $hsp->start and $r->{'end'}   <= $hsp->end ) or
                             ( $r->{'start'} <= $hsp->start and $r->{'end'}   >= $hsp->end ) );          
              }
            }

            $c->log->debug( "PfamB hit |$hsp|".$pfamB_acc."\t".$hit->accession."\t".$hit->description."\t".$hit->length."\t".$hit->score."\t".$hsp->pvalue);
            push @{ $results{$pfamB_acc} }, { pfamB_acc => $pfamB_acc, 
                                              pfamB_id => $pfamB_id, 
                                              start => $hsp->start, 
                                              end => $hsp->end, 
                                              score => $hsp->score, 
                                              pvalue => $hsp->pvalue, 
                                              hitString => $hsp->hit_string,
                                              homoString => $hsp->homology_string,
                                              queryString => $hsp->query_string };
            
            $c->log->debug("Hit string". $hsp->query_string ."\t". $hsp->hit_string."\t". $hsp->homology_string);
          }
        }
      }
       
      #Now make the generic results for each Pfam-B.
      foreach my $pfamB_acc (keys %results){
        foreach my $reg (@{$results{$pfamB_acc}}){
          push @rawPfamBResults, { pfamb_id    => $reg->{pfamB_id},
                                   pfamb_acc   => $reg->{pfamB_acc},
                                   start       => $reg->{start},
                                   end         => $reg->{end},
                                   score       => $reg->{score},
                                   pvalue      => $reg->{pvalue},
                                   hitString   => $reg->{hitString},
                                   homoString  => $reg->{homoString},
                                   queryString => $reg->{queryString} };
        }            
      }
    }
  }

  $c->log->debug( 'SeqSearch::handleResults: got ' . scalar @rawPfamAResults . 
                  ' PfamA results' );
  #$c->log->debug( dump @rawPfamAResults );
  $c->log->debug( 'SeqSearch::handleResults: got ' . scalar @rawPfamBResults .
                  ' PfamB results' );
  #$c->log->debug( dump @rawPfamBResults );
  
  $c->stash->{genPfamARes} = \@rawPfamAResults;
  $c->stash->{genPfamBRes} = \@rawPfamBResults;

}

#-------------------------------------------------------------------------------

=head2 generateGraphic : Private

Generate the Pfam graphic from the generic results.

=cut

sub generateGraphic : Private {
  my( $this, $c ) = @_;

  # Convert the generic results into BioPerl objects and subsequently generate 
  # the graphic.... This may seem a waste, but it abstracts us from changes to 
  # the XML.   
  
  # Generate a sequence object for the query sequence
  my $fac = Bio::Pfam::AnnSeqFactory->new;
  my $annseq = $fac->createAnnotatedSequence();
  my @seqs;
  push @seqs, $annseq;

  $annseq->sequence( 
    Bio::Pfam::SeqPfam->new( '-seq'      => $c->{stash}->{seq},
                             '-start'    => '1',
                             '-end'      => length($c->{stash}->{seq}),
                             '-id'       => 'QuerySeq',
                             '-acc'      => 'QuerySeq',
                             '-organism' => 'Unknown',
                             '-desc'     => 'QuerySeq' )
  );

  # For each pfamA region, make the PfamRegion object
  foreach my $pfamA ( @{ $c->{stash}->{genPfamARes} } ) {
    next unless $pfamA->{significant};
    $annseq->addAnnotatedRegion(
      Bio::Pfam::PfamRegion->new( '-PFAM_ACCESSION' => $pfamA->{pfama_acc},
                                  '-PFAM_ID'        => $pfamA->{pfama_id},
                                  '-SEQ_ID'         => $annseq->id,
                                  '-FROM'           => $pfamA->{start},
                                  '-TO'             => $pfamA->{end},
                                  '-MODEL_FROM'     => $pfamA->{hmm_start},
                                  '-MODEL_TO'       => $pfamA->{hmm_end},
                                  '-MODEL_LENGTH'   => $pfamA->{hmm_length},
                                  '-BITS'           => $pfamA->{bits},
                                  '-EVALUE'         => $pfamA->{evalue},
                                  '-ANNOTATION'     => $pfamA->{desc},
                                  '-REGION'         => $pfamA->{type},
                                  '-TYPE'           => "pfama" )
    );
  }
                                                     
  #Now do the same for any PfamB hits  
  foreach my $pfamB ( @{ $c->{stash}->{genPfamBRes} } ) {
    $annseq->addAnnotatedRegion(
      Bio::Pfam::PfamRegion->new( '-PFAM_ACCESSION' => $pfamB->{pfamb_acc},
                                  '-PFAM_ID'        => $pfamB->{pfamb_id},
                                  '-SEQ_ID'         => $annseq->id,
                                  '-FROM'           => $pfamB->{start},
                                  '-TO'             => $pfamB->{end},
                                  '-TYPE'           => "pfamb" )
    );  
  }
  
  #Now generate the image object that can be used for generating the graphic.
  #The actual image is printed within the tt.
  my $layout = Bio::Pfam::Drawing::Layout::PfamLayoutManager->new;
  $layout->layout_sequences( @seqs);
  #$c->log->debug($layout->layout_to_XMLDOM->toString(1));

  my $imageset = Bio::Pfam::Drawing::Image::ImageSet->new;
  $imageset->create_images( $layout->layout_to_XMLDOM );  
  $c->stash->{images} = $imageset;
}

#-------------------------------------------------------------------------------

=head1 AUTHOR

John Tate, C<jt6@sanger.ac.uk>

Rob Finn, C<rdf@sanger.ac.uk>

=head1 COPYRIGHT

Copyright (c) 2007: Genome Research Ltd.

Authors: Rob Finn (rdf@sanger.ac.uk), John Tate (jt6@sanger.ac.uk)

This is free software; you can redistribute it and/or
modify it under the terms of the GNU General Public License
as published by the Free Software Foundation; either version 2
of the License, or (at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program; if not, write to the Free Software
Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA  02111-1307, USA.
or see the on-line version at http://www.gnu.org/copyleft/gpl.txt

=cut

1;
