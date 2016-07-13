#!/bin/bash

source /vagrant/provision/logger.sh
source /vagrant/provision/functions.sh
source /vagrant/provision/vars.sh

OPENSTACK_VERSION=$1
MONIT_CFG='/etc/monit/monitrc'
CHECK_SERVICE='nova-api'
debug "Prepearing monit service ..."

apt-get install -y monit

info "Changing monit config"
info "Setting check services at 10 seconds intervals"
sed -i 's/set daemon [0-9]*/set daemon 10/' ${MONIT_CFG}
info "Setting http port and allowing users"
cat<< EOF >>${MONIT_CFG}
  set httpd port 2812 and
    use address localhost  # only accept connection from localhost
    allow localhost        # allow localhost to connect to the server and
    allow admin:monit      # require user 'admin' with password 'monit'
    allow @monit           # allow users of group 'monit' to connect (rw)
    allow @users readonly  # allow users of group 'users' to connect readonly

EOF


if [[ ${OPENSTACK_VERSION} == 'grizzly' ]]
then
  NETWORK_SERVICE='quantum'
else
  NETWORK_SERVICE='neutron'
fi

info "Adding openstack services to monit"

for openstack_services in ${NETWORK_SERVICE} nova cinder glance keystone
do
  for service in $(initctl list | grep ${openstack_services} | awk '{print $1}')
  do
    create_monit_script ${service}
    add_service_to_monit ${service}
  done
done

for service in rabbitmq-server mysql apache2
do
  add_service_to_monit ${service}
done

restart_service monit

status=$(initctl list | grep ${CHECK_SERVICE} | awk '{print $2}')
info "Now ${CHECK_SERVICE} service ${status}"

if [[ ${status} =~ start ]]
then
  info "Stopping ${CHECK_SERVICE}"
  service ${CHECK_SERVICE} stop
fi

info "Waiting for servise ${CHECK_SERVICE} running"

checker "service ${CHECK_SERVICE} status | grep running" ${CHECK_SERVICE} 3

