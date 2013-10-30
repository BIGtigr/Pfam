use strict;
use warnings;
use Test::More tests => 1;
use FindBin;

BEGIN {
  use_ok( 'Bio::Rfam::SVN::Commit' ) || print "Failed to load Bio::Rfam::SVN::Commit!\n";
}

my $dir = $FindBin::Bin;
