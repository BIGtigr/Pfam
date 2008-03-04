package RfamDB::RfamRegFull;

use strict;
use warnings;

use base 'DBIx::Class';

__PACKAGE__->load_components("Core");
__PACKAGE__->table("rfam_reg_full");
__PACKAGE__->add_columns(
  "auto_rfam",
  { data_type => "INT", default_value => 0, is_nullable => 0, size => 10 },
  "auto_rfamseq",
  { data_type => "INT", default_value => 0, is_nullable => 0, size => 10 },
  "seq_start",
  { data_type => "MEDIUMINT", default_value => 0, is_nullable => 0, size => 8 },
  "seq_end",
  {
    data_type => "MEDIUMINT",
    default_value => undef,
    is_nullable => 1,
    size => 8,
  },
  "bits_score",
  { data_type => "DOUBLE", default_value => 0, is_nullable => 0, size => 64 },
  "auto_genome",
  { data_type => "INT", default_value => undef, is_nullable => 1, size => 10 },
);
__PACKAGE__->belongs_to(
  "auto_rfamseq",
  "RfamDB::Rfamseq",
  { auto_rfamseq => "auto_rfamseq" },
);
__PACKAGE__->belongs_to(
  "auto_genome",
  "RfamDB::GenomeEntry",
  { auto_genome => "auto_genome" },
);
__PACKAGE__->belongs_to("auto_rfam", "RfamDB::Rfam", { auto_rfam => "auto_rfam" });


# Created by DBIx::Class::Schema::Loader v0.04004 @ 2008-02-29 10:23:32
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:ID5dtmPlV9ii4WMEsxzqyQ


#-------------------------------------------------------------------------------

=head1 AUTHOR

John Tate, C<jt6@sanger.ac.uk>
Rob Finn, C<rdf@sanger.ac.uk>
Paul Gardner, C<pg5@sanger.ac.uk>
Jennifer Daub, C<jd7@sanger.ac.uk>

=head1 COPYRIGHT

Copyright (c) 2007: Genome Research Ltd.

Authors: Rob Finn (rdf@sanger.ac.uk), John Tate (jt6@sanger.ac.uk),
         Paul Gardner, C<pg5@sanger.ac.uk>, Jennifer Daub, C<jd7@sanger.ac.uk>

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
