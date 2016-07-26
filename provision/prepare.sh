#!/bin/bash

source /vagrant/provision/logger.sh
source /vagrant/provision/functions.sh
source /vagrant/provision/vars.sh

OPENSTACK_VERSION=$1
APT_SOURCE="/etc/apt/sources.list.d/${OPENSTACK_VERSION}.list"

debug "Prepearing host to install openstack ..."

info "Updating packages"
apt-get update && apt-get upgrade -y
apt-get autoremove -y
info "Packages have been updated"
info "Installing openstack ${OPENSTACK_VERSION} repository"

apt-get -y purge cloud-init

apt-get install -y ubuntu-cloud-keyring python-software-properties software-properties-common python-keyring \
                   python-pip augeas-tools

info "Will be installing ${OPENSTACK_VERSION} on Ubuntu ${UBUNTU_VERSION}"
if [[ (${OPENSTACK_VERSION} == 'grizzly') && (${UBUNTU_VERSION} == '12.04') ]]
then
  echo deb http://ubuntu-cloud.archive.canonical.com/ubuntu precise-updates/grizzly main | \
       tee -a /etc/apt/sources.list.d/grizzly.list
  if [[ (-f ${APT_SOURCE}) && (-s ${APT_SOURCE}) ]]
  then
    info "Openstack ${OPENSTACK_VERSION} added successfully"
      info "Installing openstack ${OPENSTACK_VERSION} repository"
  else
    error "Openstack ${OPENSTACK_VERSION} repository hasn't been added"
    exit 102
  fi
  apt-get update
  apt-get upgrade -y
  pip install crudini
  info "Redy to install openstack grizzly"
elif [[ (${SUPPORT_OPENSTACK_VERSIONS} =~ ${OPENSTACK_VERSION}) && (${UBUNTU_VERSION} == '14.04') ]]
then
  add-apt-repository cloud-archive:${OPENSTACK_VERSION}
  apt-get install -y crudini
fi

apt-get update
apt-get -y dist-upgrade

apt-get install -y mysql-server python-mysqldb

info "Preparing mysql changing listen address and rebooting"
mysqladmin -u ${DB_USER} password ${DB_PASSWORD}
augtool << EOF
set /files/etc/mysql/my.cnf/target[. = 'client']/user ${DB_USER}
set /files/etc/mysql/my.cnf/target[. = 'client']/password ${DB_PASSWORD}
set /files/etc/mysql/my.cnf/target[. = 'mysqld']/bind-address 0.0.0.0
set /files/etc/mysql/my.cnf/target[. = 'mysqld']/default-storage-engine innodb
set /files/etc/mysql/my.cnf/target[. = 'mysqld']/innodb_file_per_table true
set /files/etc/mysql/my.cnf/target[. = 'mysqld']/collation-server utf8_general_ci
set /files/etc/mysql/my.cnf/target[. = 'mysqld']/init-connect '\'SET NAMES utf8\''
set /files/etc/mysql/my.cnf/target[. = 'mysqld']/character-set-server utf8
save
EOF
mysql -u ${DB_USER} -p${DB_PASSWORD} -e "DELETE FROM user WHERE user = 'root' AND host <> '%' AND host <> 'localhost';" mysql

restart_service mysql

apt-get install -y rabbitmq-server

apt-get install -y ntp vim curl

info "Redy to install openstack ${OPENSTACK_VERSION}"

debug "Host is ready for installing openstack ${OPENSTACK_VERSION}"

