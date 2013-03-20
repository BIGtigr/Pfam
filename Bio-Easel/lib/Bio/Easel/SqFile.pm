package Bio::Easel::SqFile;

use strict;
use warnings;
use File::Spec;
use Carp;

=head1 NAME

Bio::Easel - The great new Bio::Easel!

=head1 VERSION

Version 0.01

=cut

our $VERSION = '0.01';
# Easel status codes, these must be consistent with #define's in Bio-Easel/src/easel/easel.h
our $ESLOK =              '0';    # no error/success            
our $ESLFAIL =            '1';    # failure                     
our $ESLEOL =             '2';    # end-of-line (often normal)  
our $ESLEOF =             '3';    # end-of-file (often normal)  
our $ESLEOD =             '4';    # end-of-data (often normal)  
our $ESLEMEM =            '5';    # malloc or realloc failed    
our $ESLENOTFOUND =       '6';    # file or key not found       
our $ESLEFORMAT =         '7';    # file format not correct     
our $ESLEAMBIGUOUS =      '8';    # an ambiguity of some sort   
our $ESLEDIVZERO =        '9';    # attempted div by zero       
our $ESLEINCOMPAT =      '10';    # incompatible parameters     
our $ESLEINVAL =         '11';    # invalid argument/parameter  
our $ESLESYS =           '12';    # generic system call failure 
our $ESLECORRUPT =       '13';    # unexpected data corruption  
our $ESLEINCONCEIVABLE = '14';    # "can't happen" error        
our $ESLESYNTAX =        '15';    # invalid user input syntax   
our $ESLERANGE =         '16';    # value out of allowed range  
our $ESLEDUP =           '17';    # saw a duplicate of something
our $ESLENOHALT =        '18';    # a failure to converge       
our $ESLENORESULT =      '19';    # no result was obtained      
our $ESLENODATA =        '20';    # no data provided, file empty
our $ESLETYPE =          '21';    # invalid type of argument   
our $ESLEOVERWRITE =     '22';    # attempted to overwrite data
our $ESLENOSPACE =       '23';    # ran out of some resource   
our $ESLEUNIMPLEMENTED = '24';    # feature is unimplemented   
our $ESLENOFORMAT =      '25';    # couldn't guess file format 
our $ESLENOALPHABET =    '26';    # couldn't guess seq alphabet
our $ESLEWRITE =         '27';    # write failed (fprintf, etc)

our $FASTATEXTW =        '60';    # 60 characters per line in FASTA seq output

my $src_file      = undef;
my $typemaps      = undef;
my $easel_src_dir = undef;

BEGIN {
    $src_file = __FILE__;
    $src_file =~ s/\.pm/\.c/;

    my $file = __FILE__;
    ($easel_src_dir) = $file =~ /^(.*)\/blib/;
    $easel_src_dir = File::Spec->catfile($easel_src_dir, 'src/easel');

    $typemaps = __FILE__;
    $typemaps =~ s/\.pm/\.typemap/;
}

use Inline
  C        => "$src_file",
  VERSION  => '0.01',
  ENABLE   => 'AUTOWRAP',
  INC      => "-I$easel_src_dir",
  LIBS     => "-L$easel_src_dir -leasel",
  TYPEMAPS => $typemaps,
  NAME     => 'Bio::Easel::SqFile';

=head1 SYNOPSIS

Sequence file handling through inline C with Easel.

Perhaps a little code snippet.

    use Bio::Easel::SqFile;

    my $foo = Bio::Easel::MSA->SqFile({"fileLocation" => $sqfile});
    ...

=head1 EXPORT

No functions currently exported.

=head1 SUBROUTINES/METHODS

=cut

=head2 new 

  Title    : new
  Incept   : EPN, Mon Feb  4 14:36:57 2013
  Usage    : Bio::Easel::SqFile->new
  Function : Generates a new Bio::Easel::SqFile object
  Args     : <fileLocation>: file location of sequence file, <fileLocation.ssi> is index file
  Returns  : Bio::Easel::SqFile object

=cut

sub new {
  my( $caller, $args) = @_;
  my $class = ref($caller) || $caller;
  my $self = {};
  
  bless( $self, $caller );

  # First check that the file exists and it has a .ssi file associated with it.
  if(-e $args->{fileLocation}){
    eval{
      $self->{path} = $args->{fileLocation};
      $self->open_sqfile();
    }; # end of eval
    
    if($@) {
      confess("Error creating ESL_SQFILE from @{[$args->{fileLocation}]}, $@\n");
    }
  } 
  else {
    confess("Expected to receive a valid file location path (@{[$args->{fileLocation}]} doesn\'t exist)");
  }
  return $self;
}

=head2 sqfile

  Title    : sqfile
  Incept   : EPN, Tue Mar  5 05:44:10 2013
  Usage    : Bio::Easel::SqFile->sqfile()
  Function : Accessor for sqfile: sets/opens (if nec) and returns ESL_SQFILE.
  Args     : none
  Returns  : sqfile  

=cut

sub sqfile {
  my ($self) = @_;

  if ( !defined( $self->{esl_sqfile} ) ) {
    $self->open_sqfile();
  }
  return $self->{esl_sqfile};
}

=head2 path

  Title    : path
  Incept   : EPN, Tue Mar  5 05:46:00 2013
  Usage    : Bio::Easel::SqFile->path()
  Function : Accessor for path, read only.
  Args     : none
  Returns  : string containing path to the file or undef.   

=cut

sub path {
  my ($self) = @_;

  return defined( $self->{path} ) ? $self->{path} : undef;
}


=head2 open_sqfile

  Title    : open_sqfile
  Incept   : EPN, Mon Mar  4 11:10:33 2013
  Usage    : Bio::Easel::SqFile->open_seqfile
  Function : Opens a sequence file and its SSI index file (if no SSI file exists, it creates one)
           : and creates a ESL_SQFILE pointer to it.
  Args     : <fileLocation>: file location of sequence file, <fileLocation.ssi> is index file.
  Returns  : void
  Dies     : if unable to open sequence file

=cut

sub open_sqfile {
  my ( $self, $fileLocation ) = @_;

  if ($fileLocation) {
    $self->{path} = $fileLocation;
  }
  if ( !defined $self->{path} ) { die "trying to read sequence file but path is not set"; }

  $self->{esl_sqfile} = _c_open_sqfile( $self->{path} );

  if ( ! defined $self->{esl_sqfile} ) { die "_c_open_sqfile returned, but esl_sqfile still undefined"; }

  return;
}

=head2 open_ssi_index

  Title    : open_ssi_index
  Incept   : EPN, Mon Mar  4 13:55:40 2013
  Usage    : Bio::Easel::SqFile->open_ssi_index
  Function : Opens a SSI file for a given sequence file.
  Args     : None
  Returns  : $ESLOK if SSI file is successfully opened
           : $ESLENOTFOUND if SSI file does not exist
  Dies     : with croak in _c_open_ssi_index if:
             - SSI file exists but is wrong format or can't be opened
             - $self->{esl_sqfile} is an alignment
             - $self->{esl_sqfile} is gzipped
 
=cut

sub open_ssi_index {
  my ( $self ) = @_;

  if ( $self->{has_ssi} ) { 
    return $ESLOK;
  }

  if ( ! defined $self->{path} ) {
    die "trying to open SSI file but path is not set";
  }

  if ( ! defined $self->{esl_sqfile} ) {
    die "trying to open SSI for non-open sqfile";
  }

  my $status = _c_open_ssi_index( $self->{esl_sqfile} ); # this will call 'croak' upon an error 

  if($status == $ESLOK) { $self->{has_ssi} = 1; }
  return $status;
}

=head2 create_ssi_index

  Title    : create_ssi_index
  Incept   : EPN, Fri Mar  8 06:09:51 2013
  Usage    : Bio::Easel::SqFile->create_ssi_index
  Function : Creates an SSI file for a given sequence file.
  Args     : None
  Returns  : void
  Dies     : if SSI index creation fails, via croak in _c_create_ssi_index()
 
=cut

sub create_ssi_index {
  my ( $self ) = @_;

  if ( $self->{has_ssi} )              { die "trying to create SSI file but has_ssi flag already set!"; }
  if ( ! defined $self->{path} )       { die "trying to create SSI file but path is not set"; }
  if ( ! defined $self->{esl_sqfile} ) { die "trying to open SSI for non-open sqfile"; }

  _c_create_ssi_index( $self->{esl_sqfile} ); # this C function calls 'croak' if there's an error

  return;
}

=head2 fetch_seqs_given_names

  Title    : fetch_seqs_given_names
  Incept   : EPN, Mon Mar  4 14:43:12 2013
  Usage    : Bio::Easel::SqFile->fetch_seqs_given_names
  Function : Fetch sequence(s) with names listed in $seqnameAR from a 
           : sequence file and either return them as a string (if 
           : $outfile is !defined) or output them to a new FASTA file 
           : called $outfile (if defined).
  Args     : $seqnameAR: ref to array of seqnames to fetch
           : $textw:     width of FASTA seq lines, usually $FASTATEXTW, -1 for unlimited
           : $outfile:   OPTIONAL; name of output FASTA file to create
  Returns  : if $outfile is defined: string of all concatenated seqs
             else                  : "" (empty string)
  Dies     : if unable to open sequence file

=cut

sub fetch_seqs_given_names { 
  my ( $self, $seqnameAR, $textw, $outfile ) = @_;

  $self->_check_sqfile();
  $self->_check_ssi();    # fetching sequences by name requires SSI index

  my $retstring = "";
  if(defined $outfile) { 
    open(OUT, ">" . $outfile) || die "ERROR unable to open $outfile for writing";
  }

  my ($seqname, $seqstring);
  foreach $seqname (@{$seqnameAR}) { 
    $seqstring = _c_fetch_seq_to_fasta_string($self->{esl_sqfile}, $seqname, $textw); 
    if(defined $outfile) { print OUT $seqstring; }
    else                 { $retstring .= $seqstring; }
  }
  if(defined $outfile) { close(OUT); }
  
  return $retstring; # this will be "" if $outfile is defined, else it is all fetched seqs concatenated
}

=head2 fetch_consecutive_seqs

  Title    : fetch_consecutive_seqs
  Incept   : EPN, Fri Mar  8 05:30:56 2013
  Usage    : Bio::Easel::SqFile->fetch_consecutive_seqs
  Function : Fetch $n consecutive sequence(s) from a 
           : sequence file and either return them as a string (if 
           : $outfile is !defined) or output them to a new FASTA file 
           : called $outfile (if defined). The first sequence to fetch
           : is named $startname (if $startname != ""), else if 
           : $startname eq "" next sequence in the open file is the first 
           : sequence.
  Args     : $n:         number of sequences to fetch
           : $startname: name of first sequence to fetch, "" for next seq in file
           : $textw:     width of FASTA seq lines, usually $FASTATEXTW, -1 for unlimited
           : $outfile:   OPTIONAL: name of output FASTA file to create.
  Returns  : if $outfile is defined: string of all concatenated seqs
             else                  : "" (empty string)
  Dies     : if unable to open sequence file

=cut

sub fetch_consecutive_seqs { 
  my ( $self, $n, $startname, $textw, $outfile ) = @_;

  $self->_check_sqfile();
  if($startname ne "") { 
    $self->_check_ssi(); # positioning file to beginning of seq $startname requires SSI index 
  }

  my $retstring = "";
  if(defined $outfile) { 
    open(OUT, ">" . $outfile) || die "ERROR unable to open $outfile for writing";
  }

  my ($seqstring, $i);
  for($i = 1; $i <= $n; $i++) { 
    printf("i: %d\n", $i);
    # we fetch first seq in special way if $startname ne ""
    if($i == 1 && $startname ne "") { 
      $seqstring = _c_fetch_seq_to_fasta_string($self->{esl_sqfile}, $startname, $textw); 
    }
    else { 
      $seqstring = _c_fetch_next_seq_to_fasta_string($self->{esl_sqfile}, $textw); 
    }
    if(defined $outfile) { print OUT $seqstring; }
    else                 { $retstring .= $seqstring; }
  }
  if(defined $outfile) { close(OUT); }
    
  # printf STDERR ("in fetch_consecutive_seqs: returning $retstring");
  
  return $retstring; # this will be "" if $outfile is defined, else it is all fetched seqs concatenated
}

=head2 fetch_seq_to_fasta_string

  Title    : fetch_seq_to_fasta_string
  Incept   : EPN, Fri Mar  8 10:21:56 2013
  Usage    : Bio::Easel::SqFile->fetch_seq_to_fasta_string
  Function : Fetches a sequence named $seqname from a sequence file and returns it as a FASTA string 
  Args     : $seqname: name or accession of desired sequence
             $textw  : width of FASTA seq lines, -1 for unlimited, if !defined $FASTATEXTW is used
  Returns  : string, the sequence in FASTA format
  Dies     : upon error in _c_fetch_seq_to_fasta_string(), with C croak() call

=cut

sub fetch_seq_to_fasta_string {
  my ( $self, $seqname, $textw ) = @_;

  $self->_check_sqfile();
  $self->_check_ssi();

  if(! defined $textw) { $textw = $FASTATEXTW; }

  return _c_fetch_seq_to_fasta_string($self->{esl_sqfile}, $seqname, $textw); 
}

=head2 dl_load_flags


#############################
# Internal helper subroutines
#############################

=head2 _check_sqfile

  Title    : _check_sqfile
  Incept   : EPN, Mon Mar  4 14:57:35 2013
  Usage    : Bio::Easel::SqFile->_check_sqfile()
  Function : Opens sqfile only if it is currently undefined
  Args     : none
  Returns  : void

=cut

sub _check_sqfile {
  my ($self) = @_;

  if ( !defined $self->{esl_sqfile} ) {
    $self->open_seqfile();
  }
  return;
}

=head2 _check_ssi

  Title    : _check_ssi
  Incept   : EPN, Fri Mar  8 09:56:59 2013
  Usage    : Bio::Easel::SqFile->_check_ssi()
  Function : Opens SSI for sqfile if it's not already open,
             or if it doesn't exist, we create and open it.
  Args     : none
  Returns  : void

=cut

sub _check_ssi {
  my ($self) = @_;

  $self->_check_sqfile();

  if( ! $self->{has_ssi} ) { 
    # try to open SSI file
    my $status = $self->open_ssi_index();
    if($status == $ESLENOTFOUND) { 
      # SSI file does not exist, try to create one
      $self->create_ssi_index(); # this will croak in C upon an error
      $status = $self->open_ssi_index();
    }

    if($status != $ESLOK || (! $self->{has_ssi})) { 
      die "unable to open newly created SSI index file for $self->{path}"; 
    }

  }
  return;
}

=head1 AUTHORS

Eric Nawrocki, C<< <nawrockie at janelia.hhmi.org> >>
Jody Clements, C<< <clementsj at janelia.hhmi.org> >>
Rob Finn, C<< <finnr at janelia.hhmi.org> >>
William Arndt, C<< <arndtw at janelia.hhmi.org> >>

=head1 BUGS

Please report any bugs or feature requests to C<bug-bio-easel at rt.cpan.org>.

=head1 SUPPORT

You can find documentation for this module with the perldoc command.

    perldoc Bio::Easel::SqFile

=head1 ACKNOWLEDGEMENTS

Sean R. Eddy is the author of the Easel C library of functions for
biological sequence analysis, upon which this module is based.

=head1 LICENSE AND COPYRIGHT

Copyright 2013 Eric Nawrocki.

This program is free software; you can redistribute it and/or modify it
under the terms of either: the GNU General Public License as published
by the Free Software Foundation; or the Artistic License.

See http://dev.perl.org/licenses/ for more information.


=cut

1;