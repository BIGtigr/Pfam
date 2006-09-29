package PfamSchemata::PfamDB::Pfamseq_markup;

use strict;
use warnings;
use base "DBIx::Class";

__PACKAGE__->load_components( qw/Core/ );

#Set up the table
__PACKAGE__->table( "pfamseq_markup" );

#Get the columns that we want to keep
__PACKAGE__->add_columns(qw/auto_pfamseq auto_markup residue annotation/);

__PACKAGE__->set_primary_key("auto_pfamseq");

__PACKAGE__->has_one("pfamseq" => "PfamSchemata::PfamDB::Pfamseq",
		     {"foreign.auto_pfamseq" => "self.auto_pfamseq"},
		     {proxy => [qw/pfamseq_id pfamseq_acc/]});

# renamed this relationship from "auto_markup" because it was blocking
# access to the column of that name.
# jt6 20060801 WTSI
__PACKAGE__->has_one("autoMarkup" => "PfamSchemata::PfamDB::Markup_key",
		     {"foreign.auto_markup" => "self.auto_markup"},
		     {proxy => [qw/label/]});

__PACKAGE__->might_have("pdbResidue" => "PfamSchemata::PfamDB::Pdb_residue",
						{"foreign.auto_pfamseq" => "self.auto_pfamseq",
						 "foreign.pfamseq_seq_number" => "self.residue"},
						{proxy => [qw/chain pdb_seq_number pdb_res auto_pdb pfamseq_seq_number/]});

1;
