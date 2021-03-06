#!/bin/bash

MGMT_IP=$1
OPENSTACK_VERSION=$2
NFS_HOST=$3
CINDER_CFG='/etc/cinder/cinder.conf'

source /vagrant/provision/logger.sh
source /vagrant/provision/functions.sh
source /vagrant/provision/vars.sh
source /home/vagrant/openrc_admin

debug "Installing cinder services ..."

apt-get install -y cinder-api cinder-scheduler cinder-volume

if [[ ${OPENSTACK_VERSION} == 'grizzly' ]]
then
  PUBLIC_URL='http://'"${MGMT_IP}"':8776/v1/$(tenant_id)s'
  INTERNAL_URL=${PUBLIC_URL}
  PASTE_CFG='/etc/cinder/api-paste.ini'

  apt-get install -y iscsitarget open-iscsi iscsitarget-dkms

  # /etc/cinder/api-paste.ini
  setup_keystone_authentication ${PASTE_CFG} "${SERVICE_USER_NAME}" 'filter:authtoken'
  crudini --set ${PASTE_CFG} filter:authtoken paste.filter_factory keystone.middleware.auth_token:filter_factory
  crudini --set ${PASTE_CFG} filter:authtoken service_protocol http
  crudini --set ${PASTE_CFG} filter:authtoken service_host "${MGMT_IP}"
  crudini --set ${PASTE_CFG} filter:authtoken service_port 5000
  crudini --set ${PASTE_CFG} filter:authtoken signing_dir /var/lib/cinder

  crudini --set ${CINDER_CFG} DEFAULT sql_connection "mysql://${DB_USER}:${DB_PASSWORD}@${MGMT_IP}/cinder"

else
  PUBLIC_URL="http://${MGMT_IP}:8776/v1/%(tenant_id)s"
  INTERNAL_URL=${PUBLIC_URL}
  crudini --set ${CINDER_CFG} database connection "mysql://${DB_USER}:${DB_PASSWORD}@${MGMT_IP}/cinder"
  setup_keystone_authentication ${CINDER_CFG} "${SERVICE_USER_NAME}"
  crudini --set ${CINDER_CFG} DEFAULT rpc_backend rabbit
  crudini --set ${CINDER_CFG} DEFAULT rabbit_host "${MGMT_IP}"
  crudini --set ${CINDER_CFG} DEFAULT rabbit_port 5672
  crudini --set ${CINDER_CFG} DEFAULT my_ip "${MGMT_IP}"
  crudini --set ${CINDER_CFG} DEFAULT glance_host "${MGMT_IP}"
fi

create_db cinder

# Create service and endpoint
create_service cinder volume "OpenStack Volume Service" "${PUBLIC_URL}" "${INTERNAL_URL}"

info "Modifying iscsi settings"
# ISCSI

if [[ ${OPENSTACK_VERSION} == 'grizzly' ]]
then
  sed -i 's/false/true/g' /etc/default/iscsitarget
  restart_service iscsitarget
  restart_service open-iscsi
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
${NFS_HOST}:/var/exports/${OPENSTACK_VERSION}${index}
EOF
done

info "Syncing cinder db"
cinder-manage db sync

cinder_services=$(initctl list | grep cinder | awk '{print $1}')

restart_service cinder

wait_http_available cinder "http://${MGMT_IP}:8776"

info "Cheking cinder services"
for service in ${cinder_services}
do
  service "${service}" status | tee -a "${SCRIPT_LOG}"
done

debug "Cinder services have been installed and has been configured"

