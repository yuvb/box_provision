#!/bin/bash

apt-get install -y apache2 memcached libapache2-mod-wsgi openstack-dashboard
dpkg --purge openstack-dashboard-ubuntu-theme
for service in apache2 memcached
do
  restart_service ${service}
done
