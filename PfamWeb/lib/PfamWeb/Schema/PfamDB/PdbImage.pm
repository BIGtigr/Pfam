
package PfamWeb::Schema::PfamDB::PdbImage;

use strict;
use warnings;

use base "DBIx::Class";

__PACKAGE__->load_components( qw/Core/ );
__PACKAGE__->table( "pdb_image" );
__PACKAGE__->add_columns( qw/auto_pdb pdb_image/ );
__PACKAGE__->set_primary_key( "auto_pdb" );

__PACKAGE__->has_one( "pdb" => "PfamWeb::Schema::PfamDB::Pdb" );

1;

