
# $Id: PfamA_fasta.pm,v 1.2 2009-04-06 09:20:43 jt6 Exp $
#
# $Author: jt6 $

package PfamDB::PfamA_fasta;

use strict;
use warnings;

use base 'DBIx::Class';

__PACKAGE__->load_components( qw( Core ) );

# the table
__PACKAGE__->table( qq( pfamA_fasta ) );

# the columns
__PACKAGE__->add_columns( qw( auto_pfamA
                              fasta 
                              nr_threshold 
                               ) );

# keys
__PACKAGE__->set_primary_key( qw( auto_pfamA 
                                  ) );

# relationships

__PACKAGE__->has_one( pfam => 'PfamDB::Pfam',
                      { 'foreign.auto_pfamA' => 'self.auto_pfamA' } );



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

