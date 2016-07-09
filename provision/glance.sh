#!/bin/bash

source /vagrant/provision/logger.sh
source /vagrant/provision/functions.sh
source /vagrant/provision/vars.sh
source /home/vagrant/openrc_admin

OPENSTACK_VERSION=$1
PUBLIC_URL="http://${MGMT_IP}:9292"
INTERNAL_URL=${PUBLIC_URL}
IMAGE_NAME='cirros-0.3.3-x86_64'

create_db glance

# Create service and endpoint
create_service glance image "OpenStack Image Service" ${PUBLIC_URL} ${INTERNAL_URL}

apt-get install -y glance python-glanceclient

for config_file in "/etc/glance/glance-api.conf" "/etc/glance/glance-registry.conf"
do
  if [[ 'grizzly' = ${OPENSTACK_VERSION} ]]
  then
    crudini --set ${config_file} DEFAULT sql_connection "mysql://${DB_USER}:${DB_PASSWORD}@${MGMT_IP}/glance"
  else
    crudini --set /etc/glance/glance-api.conf DEFAULT rpc_backend rabbit
    crudini --set ${config_file} database connection "mysql://${DB_USER}:${DB_PASSWORD}@${MGMT_IP}/glance"
  fi
  crudini --set ${config_file} DEFAULT debug True
  crudini --set ${config_file} DEFAULT verbose True
  crudini --set ${config_file} paste_deploy flavor keystone
  setup_keystone_authentication ${config_file} ${SERVICE_USER_NAME}
done

crudini --set /etc/glance/glance-api.conf DEFAULT rabbit_host "${MGMT_IP}"
crudini --set /etc/glance/glance-api.conf DEFAULT os_region_name "${OS_REGION_NAME}"
crudini --set /etc/glance/glance-cache.conf DEFAULT os_region_name "${OS_REGION_NAME}"

info "Syncing glance db"
glance-manage db_sync

restart_openstack_services glance

wait_http_available ${PUBLIC_URL}
rm -f /var/lib/glance/glance.sqlite

# Upload images
glance_image_id=$(get_id glance image-create --name ${IMAGE_NAME} --file "/vagrant/images/${IMAGE_NAME}.img" --disk-format qcow2 --container-format bare --is-public True)
local result=$(glance image-list | awk -v image_id=${glance_image_id} '$0 ~ image_id {print $12}')
if [[ ${result} == 'active' ]]
then
  info "Image ${name} has been uploaded to glance with Id ${glance_image_id}"
else
  error "Image ${name} hasn't been uploaded to glance"
  exit 102
fi

debug "Glance has been installed and has been configured"

