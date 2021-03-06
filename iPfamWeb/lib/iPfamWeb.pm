
# iPfamWeb.pm
# jt 20060316 WTSI
#
# $Id: iPfamWeb.pm,v 1.3 2008-03-19 15:11:24 jt6 Exp $

=head1 NAME

iPfamWeb - application class for the Pfam website

=cut

package iPfamWeb;

=head1 DESCRIPTION

This is the main class for the Pfam website catalyst application. It
handles configuration of the application classes and error reporting
for the whole application.

$Id: iPfamWeb.pm,v 1.3 2008-03-19 15:11:24 jt6 Exp $

=cut

use strict;
use warnings;

use Sys::Hostname;
use Config::General;

use base 'PfamBase';

our $VERSION = '0.1';

#-------------------------------------------------------------------------------

=head1 CONFIGURATION

Configuration is done through a series of external "Apache-style"
configuration files.

=cut

# add to the configuration the name of the host that's actually serving 
# the site and its process ID. These will be pulled out later in the header 
# template
__PACKAGE__->config->{server_name} = hostname();
__PACKAGE__->config->{server_pid}  = $$;

# grab the location of the configuration file from the environment and
# detaint it. Doing this means we can configure the location of the
# config file in httpd.conf rather than in the code
my( $conf ) = $ENV{IPFAMWEB_CONFIG} =~ m/([\d\w\/-]+)/;

# set up the ConfigLoader plugin. Point to the configuration file and set up 
# Config::General to allow us to load external configuration files with
# a relative path and using apache-style "include" directives
__PACKAGE__->config->{'Plugin::ConfigLoader'}->{file} = $conf;

# read the configuration, configure the application and load these 
# catalyst plugins
__PACKAGE__->setup( qw(
                        PageCache  
                      ) );

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
