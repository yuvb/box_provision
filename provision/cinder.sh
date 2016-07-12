#!/bin/bash

source /vagrant/provision/logger.sh
source /vagrant/provision/functions.sh
source /vagrant/provision/vars.sh
source /home/vagrant/openrc_admin

OPENSTACK_VERSION=$1
CINDER_CFG='/etc/cinder/cinder.conf'

debug "Installing cinder services ..."

apt-get install -y cinder-api cinder-scheduler cinder-volume

if [[ ${OPENSTACK_VERSION} == 'grizzly' ]]
then
  PUBLIC_URL="http://${MGMT_IP}:8776/v1/$(tenant_id)s"
  INTERNAL_URL=${PUBLIC_URL}
  PASTE_CFG='/etc/cinder/api-paste.ini'

  apt-get install -y iscsitarget open-iscsi iscsitarget-dkms

  # /etc/cinder/api-paste.ini
  setup_keystone_authentication ${PASTE_CFG} ${SERVICE_USER_NAME} 'filter:authtoken'
  crudini --set ${PASTE_CFG} filter:authtoken paste.filter_factory keystone.middleware.auth_token:filter_factory
  crudini --set ${PASTE_CFG} filter:authtoken service_protocol http
  crudini --set ${PASTE_CFG} filter:authtoken service_host ${MGMT_IP}
  crudini --set ${PASTE_CFG} filter:authtoken service_port 5000
  crudini --set ${PASTE_CFG} filter:authtoken signing_dir /var/lib/cinder

  crudini --set ${CINDER_CFG} DEFAULT sql_connection "mysql://${DB_USER}:${DB_PASSWORD}@${MGMT_IP}/cinder"

else
  PUBLIC_URL="http://${MGMT_IP}:8776/v1/%(tenant_id)s"
  INTERNAL_URL=${PUBLIC_URL}
  crudini --set ${CINDER_CFG} database connection "mysql://${DB_USER}:${DB_PASSWORD}@${MGMT_IP}/cinder"
  setup_keystone_authentication ${CINDER_CFG} ${SERVICE_USER_NAME}
  crudini --set ${CINDER_CFG} DEFAULT rpc_backend rabbit
  crudini --set ${CINDER_CFG} DEFAULT rabbit_host ${MGMT_IP}
  crudini --set ${CINDER_CFG} DEFAULT rabbit_port 5672
  crudini --set ${CINDER_CFG} DEFAULT my_ip ${MGMT_IP}
  crudini --set ${CINDER_CFG} DEFAULT glance_host ${MGMT_IP}
fi

create_db cinder

# Create service and endpoint
create_service cinder volume "OpenStack Volume Service" ${PUBLIC_URL} ${INTERNAL_URL}

info "Modifying iscsi settings"
# ISCSI

if [[ ${OPENSTACK_VERSION} == 'grizzly' ]]
then
  sed -i 's/false/true/g' /etc/default/iscsitarget
  for service in iscsitarget open-iscsi
  do
    restart_service ${service}
  done
else
  restart_service tgt
fi

# /etc/cinder/cinder.conf
crudini --set ${CINDER_CFG} DEFAULT debug True
crudini --set ${CINDER_CFG} DEFAULT scheduler_driver cinder.scheduler.filter_scheduler.FilterScheduler
crudini --set ${CINDER_CFG} DEFAULT enabled_backends nfs1,nfs2

for index in 1 2
do
  crudini --set ${CINDER_CFG} nfs${index} volume_driver cinder.volume.drivers.nfs.NfsDriver
  crudini --set ${CINDER_CFG} nfs${index} nfs_shares_config /etc/cinder/nfsshares${index}
  crudini --set ${CINDER_CFG} nfs${index} nfs_mount_point_base /var/lib/cinder
  crudini --set ${CINDER_CFG} nfs${index} volume_backend_name nfs${index}
# NFS share
cat<< EOF >>"/etc/cinder/nfsshares${index}"
192.168.1.10:/var/exports/${OPENSTACK_VERSION}${index}
EOF
done

info "Syncing cinder db"
cinder-manage db sync

cinder_services=$(initctl list | grep cinder | awk '{print $1}')

restart_openstack_services cinder

info "Cheking cinder services"
if [[ ${OPENSTACK_VERSION} == 'grizzly' ]]
then
  for service in ${cinder_services}
  do
    service $service status | tee -a ${SCRIPT_LOG}
  done
else
  #Should be 3 cinder services: cinder-scheduler and 2 cinder-volume
  check_openstack_services cinder 3
  cinder service-list | tee -a ${SCRIPT_LOG}
fi

debug "Cinder services have been installed and has been configured"

