#!/bin/sh
#
# libvirt can change the IP addresses for your VMs after a while
# (for example, if you put your laptop to sleep), so we need to
# "refresh" the "tfstate" by doing a "terraform refresh" and update
# some other things...
#
# env vars:
#
#   FORCE: force the refresh, even if the Admin Node IP is the same
#

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# ssh password and flags
SSH_PASSWD="${SSH_PASSWD:-linux}"
SSH_OPTS="-oStrictHostKeyChecking=no \
          -oUserKnownHostsFile=/dev/null"

# force the refresh, even if the Admin Node IP does not change
FORCE="${FORCE:-}"

# the hostname used for the Admin Node
ADMIN_HOSTNAME="${ADMIN_HOSTNAME:-dashboard}"

###############################################################

while [ $# -gt 0 ] ; do
	case "$1" in
	    --forced|--force|-f)
			FORCE=1
	        ;;
	    --pass|--password|-p)
			SSH_PASSWD="$2"
			shift
			;;
	    --admin)
			ADMIN_HOSTNAME=$2
			shift
	        ;;
	    *)
	        echo ">>> Unknown command $1"
	        ;;
	esac
	shift
done

###############################################################

do_ssh()    { sshpass -p "$SSH_PASSWD" ssh $SSH_OPTS $@ ; }
num_nodes() { terraform output nodes | wc -l ; }


old_admin_ip=$($DIR/get-admin-ip.sh)
[ -n "$old_admin_ip" ] || ( echo "could not determine current Admin Node IP" ; exit 1 ;)

echo ">>> Refreshing Terraform..."
[ -f terraform.tfstate ] || ( echo "terraform.tfstate does not exist" ; exit 1 ;)
terraform refresh

n=$((`num_nodes` - 1))
admin_ip=$($DIR/get-admin-ip.sh)
[ -n "$admin_ip" ] || ( echo "could not determine new Admin Node IP" ; exit 1 ;)

if [ "$admin_ip" = "$old_admin_ip" ] && [ -z "$FORCE" ] ; then
	echo ">>> Admin Node IP has not changed: nothing else to do."
	exit 0
fi

for i in $(seq 0 $n) ; do
	node_ip=$($DIR/get-node-ip.sh $i)

	echo ">>> Updating dashboard IP as $admin_ip..."
	do_ssh root@$node_ip "/tmp/caasp/caaspctl dns set $ADMIN_HOSTNAME $admin_ip"

	echo ">>> Linking node-$i ($node_ip) to $ADMIN_HOSTNAME..."
	do_ssh root@$node_ip "/tmp/caasp/caaspctl salt set-master $admin_ip"

	echo ">>> Checking NTP service"
	do_ssh root@$node_ip "systemctl is-active ntpd &>/dev/null || systemctl restart ntpd"
done
