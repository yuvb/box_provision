#!/bin/bash

MGMT_IP=$1
OPENSTACK_VERSION=$2
PUBLIC_URL="http://${MGMT_IP}:8774/v2/%(tenant_id)s"
INTERNAL_URL=${PUBLIC_URL}
NOVA_CFG='/etc/nova/nova.conf'

source /vagrant/provision/logger.sh
source /vagrant/provision/functions.sh
source /vagrant/provision/vars.sh
source /home/vagrant/openrc_admin

debug "Installing nova services ..."

create_db nova

# Create service and endpoint
create_service nova compute "OpenStack Compute" ${PUBLIC_URL} ${INTERNAL_URL}

apt-get install -y nova-api nova-cert nova-conductor nova-consoleauth nova-novncproxy nova-scheduler \
                   python-novaclient nova-compute sysfsutils

setup_keystone_authentication ${NOVA_CFG} ${SERVICE_USER_NAME}
crudini --set ${NOVA_CFG} database connection mysql://${DB_USER}:${DB_PASSWORD}@${MGMT_IP}/nova

if [[ ${OPENSTACK_VERSION} == 'grizzly' ]]
then
  PASTE_CFG='/etc/nova/api-paste.ini'
  COMPUTE_CFG='/etc/nova/nova-compute.conf'
  setup_keystone_authentication ${PASTE_CFG} ${SERVICE_USER_NAME} 'filter:authtoken'
  crudini --set ${PASTE_CFG} filter:authtoken paste.filter_factory keystoneclient.middleware.auth_token:filter_factory
  crudini --set ${PASTE_CFG} filter:authtoken signing_dirname /tmp/keystone-signing-nova
  # quantum
  crudini --set ${NOVA_CFG} DEFAULT network_api_class nova.network.quantumv2.api.API
  crudini --set ${NOVA_CFG} DEFAULT quantum_url http://${MGMT_IP}:9696
  crudini --set ${NOVA_CFG} DEFAULT quantum_auth_strategy keystone
  crudini --set ${NOVA_CFG} DEFAULT quantum_admin_tenant_name ${SERVICE_TENANT_NAME}
  crudini --set ${NOVA_CFG} DEFAULT quantum_admin_username ${SERVICE_TENANT_NAME}
  crudini --set ${NOVA_CFG} DEFAULT quantum_admin_password ${SERVICE_USER_PASSWORD}
  crudini --set ${NOVA_CFG} DEFAULT quantum_admin_auth_url http://${MGMT_IP}:35357/v2.0
  crudini --set ${NOVA_CFG} DEFAULT libvirt_vif_driver nova.virt.libvirt.vif.LibvirtHybridOVSBridgeDriver
  crudini --set ${NOVA_CFG} DEFAULT linuxnet_interface_driver nova.network.linux_net.LinuxOVSInterfaceDriver
  # metadata
  crudini --set ${NOVA_CFG} DEFAULT service_quantum_metadata_proxy True
  crudini --set ${NOVA_CFG} DEFAULT quantum_metadata_proxy_shared_secret ${METADATA_PROXY_SHARED_SECRET}
  crudini --set ${NOVA_CFG} DEFAULT metadata_host ${MGMT_IP}
  crudini --set ${NOVA_CFG} DEFAULT metadata_listen ${MGMT_IP}
  crudini --set ${NOVA_CFG} DEFAULT metadata_listen_port 8775
  # compute
  crudini --set ${NOVA_CFG} DEFAULT compute_driver libvirt.LibvirtDriver
  crudini --set ${NOVA_CFG} DEFAULT scheduler_default_filters AllHostsFilter
  # image
  crudini --set ${NOVA_CFG} DEFAULT glance_api_servers ${MGMT_IP}:9292
  crudini --set ${NOVA_CFG} DEFAULT image_service nova.image.glance.GlanceImageService
  # volume
  crudini --set ${NOVA_CFG} DEFAULT volume_api_class nova.volume.cinder.API
  crudini --set ${NOVA_CFG} DEFAULT osapi_volume_listen_port 5900
  crudini --set ${NOVA_CFG} DEFAULT security_group_api quantum
  crudini --set ${NOVA_CFG} DEFAULT firewall_driver nova.virt.firewall.NoopFirewallDriver
  crudini --set ${NOVA_CFG} DEFAULT iscsi_ip_address ${MGMT_IP}
  # compute
  crudini --set ${COMPUTE_CFG} DEFAULT libvirt_type qemu
else
  crudini --set ${NOVA_CFG} DEFAULT rpc_backend rabbit
  crudini --set ${NOVA_CFG} DEFAULT network_api_class nova.network.neutronv2.api.API
  crudini --set ${NOVA_CFG} DEFAULT neutron_url http://${MGMT_IP}:9696
  crudini --set ${NOVA_CFG} DEFAULT neutron_auth_strategy keystone
  crudini --set ${NOVA_CFG} DEFAULT neutron_admin_tenant_name service
  crudini --set ${NOVA_CFG} DEFAULT neutron_admin_username service
  crudini --set ${NOVA_CFG} DEFAULT neutron_admin_password ${SERVICE_USER_PASSWORD}
  crudini --set ${NOVA_CFG} DEFAULT neutron_admin_auth_url http://${MGMT_IP}:35357/v2.0
  crudini --set ${NOVA_CFG} DEFAULT libvirt_vif_driver nova.virt.libvirt.vif.LibvirtHybridOVSBridgeDriver
  crudini --set ${NOVA_CFG} DEFAULT linuxnet_interface_driver nova.network.linux_net.LinuxOVSInterfaceDriver
  crudini --set ${NOVA_CFG} DEFAULT firewall_driver nova.virt.firewall.NoopFirewallDriver
  crudini --set ${NOVA_CFG} DEFAULT security_group_api neutron
  crudini --set ${NOVA_CFG} DEFAULT service_neutron_metadata_proxy true
  crudini --set ${NOVA_CFG} DEFAULT neutron_metadata_proxy_shared_secret ${METADATA_PROXY_SHARED_SECRET}
  crudini --set ${NOVA_CFG} DEFAULT libvirt_type qemu
fi

crudini --set ${NOVA_CFG} DEFAULT debug True
crudini --set ${NOVA_CFG} DEFAULT verbose True
crudini --set ${NOVA_CFG} DEFAULT rabbit_host ${MGMT_IP}
crudini --set ${NOVA_CFG} DEFAULT my_ip ${MGMT_IP}
crudini --set ${NOVA_CFG} DEFAULT vnc_enabled True
crudini --set ${NOVA_CFG} DEFAULT vncserver_listen ${MGMT_IP}
crudini --set ${NOVA_CFG} DEFAULT vncserver_proxyclient_address ${MGMT_IP}
crudini --set ${NOVA_CFG} DEFAULT novncproxy_base_url "http://${MGMT_IP}:6080/vnc_auto.html"
crudini --set ${NOVA_CFG} DEFAULT glance_host "${MGMT_IP}"
crudini --set ${NOVA_CFG} DEFAULT auth_strategy keystone
crudini --set ${NOVA_CFG} DEFAULT allow_resize_to_same_host True
crudini --set ${NOVA_CFG} DEFAULT allow_migrate_to_same_host True
crudini --set ${NOVA_CFG} DEFAULT api_rate_limit False
crudini --set /etc/nova/nova-compute.conf libvirt virt_type qemu

# Reducing of system resources consumption
crudini --set ${NOVA_CFG} DEFAULT osapi_compute_workers 1
crudini --set ${NOVA_CFG} DEFAULT metadata_workers 1
crudini --set ${NOVA_CFG} conductor workers 1

nova-manage db sync

# Cleans up `nova.instances` table with all it's constraints to automate
# live migration.
if [[ ${OPENSTACK_VERSION} == 'icehouse' ]]
then
  tables_to_remove=(
    block_device_mapping
    instance_actions_events
    instance_actions
    instance_faults
    instance_info_caches
    instance_system_metadata
    instances
  )
  service nova-compute stop
  for t in ${tables_to_remove[*]}
  do
    info "Removing table ${t} in db nova"
    mysql -u${DB_USER} -p${DB_PASSWORD} -e "delete from ${t}" nova
    if [[ $? == 0 ]]
    then
      info "Table $t has been successfully deleted"
    else
      error "Table $t hasn't been deleted"
    fi
  done
fi
restart_service nova

wait_http_available nova "http://${MGMT_IP}:8774"

#Should be 5 nova services: nova-cert, nova-consoleauth, nova-conductor, nova-scheduler, nova-compute
check_openstack_services nova 5

info "Checking nova services"
nova service-list | tee -a ${SCRIPT_LOG}

info "Checking nova images"
nova image-list | tee -a ${SCRIPT_LOG}

debug "Nova has been installed and has been configured"

