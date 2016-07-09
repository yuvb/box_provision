#!/bin/bash

source /vagrant/provision/logger.sh
source /vagrant/provision/functions.sh
source /vagrant/provision/vars.sh
source /home/vagrant/openrc_admin

apt-get install -y apache2 memcached libapache2-mod-wsgi openstack-dashboard
dpkg --purge openstack-dashboard-ubuntu-theme
for service in apache2 memcached
do
  restart_service ${service}
done
