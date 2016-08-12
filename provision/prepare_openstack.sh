#!/bin/bash

source /vagrant/provision/functions.sh

OPENSTACK_VERSION=$1

if [[ ${OPENSTACK_VERSION} == 'grizzly' ]]
then
  network_service='quantum'
else
  network_service='neutron'
fi

info "Deleting ip from eth interfaces"
ip_eth1=$(ip a show dev eth1 | awk '/inet / {print $2}' | cut -d '/' -f 1)
ip_eth2=$(ip a show dev eth2 | awk '/inet / {print $2}' | cut -d '/' -f 1)

ip a d "${ip_eth1}/24" dev eth1
ip a d "${ip_eth2}/24" dev eth2
ifdown eth1 eth2 && ifup eth1 eth2

info "Restarting all openstack services"
for service in keystone glance nova ${network_service} cinder
do
  restart_service "${service}"
done

