
# Email.pm
# jt 20091204 WTSI
#
# $Id: Email.pm,v 1.1 2009-12-07 22:28:32 jt6 Exp $

=head1 NAME

PfamWeb::View::Email - PfamWeb Email view

=cut

package PfamWeb::View::Email;

=head1 DESCRIPTION

Wrapper for the Email view.

=cut

use strict;
use warnings;

use base 'Catalyst::View::Email';

#-------------------------------------------------------------------------------

=head1 AUTHOR

John Tate, C<jt6@sanger.ac.uk>

Rob Finn, C<rdf@sanger.ac.uk>

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
