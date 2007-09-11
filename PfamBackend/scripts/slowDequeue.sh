#!/bin/sh

#You will need to configure this for your system.
#General
export PATH="/sbin:/data/bin:/home/pfamweb/PfamBackend/scripts:$PATH"
export PERL5LIB="/home/pfamweb/PfamLib:/home/pfamweb/PfamSchemata:/home/pfamweb/BPModules:$PERL5LIB"

#Dequeuer config 
export PFAMOFFLINE_CONFIG=/home/pfamweb/PfamBackend/conf/pfam_backend.conf

#Stuff required for binaries.
export WISECONFIGDIR=/data/bin/wise2/wisecfg/
export WUBLASTMAT=/Users/rdf/Applications/wu-blast/matrix/

# Set up of the lsf config - WTSI specific
#. /usr/local/lsf/conf/profile.lsf

#Config for this shell script
DAEMON= <PATH-TO-THIS-SCRIPT>/slowDequeue.pl
NAME=slowDequeue
DESC="Slow queue daemon"

#End of config

test -f $DAEMON || exit 0

set -e
case "$1" in
  start)
 echo -n "Starting $DESC: "
 start-stop-daemon --start --quiet --pidfile /var/lock/$NAME.pid \
  --exec /usr/bin/perl --startas $DAEMON
 echo "$NAME."
 ;;
  stop)
 echo -n "Stopping $DESC: "
 # --quiet
 start-stop-daemon --stop --signal 15 --pidfile /var/lock/$NAME.pid \
  --exec /usr/bin/perl --startas $DAEMON
 echo "$NAME."
 ;;
  restart|force-reload)
 echo -n "Restarting $DESC: "
 start-stop-daemon --stop --quiet --pidfile \
  /var/lock/$NAME.pid --exec /usr/bin/perl --startas $DAEMON
 sleep 1
 start-stop-daemon --start --quiet --pidfile \
  /var/lock/$NAME.pid --exec /usr/bin/perl --startas $DAEMON
 echo "$NAME."
 ;;
  *)
 N=/etc/init.d/$NAME
 # echo "Usage: $N {start|stop|restart|reload|force-reload}" >&2
 echo "Usage: $N {start|stop|restart|force-reload}" >&2
 exit 1
 ;;
esac

exit 0
