#!/bin/bash

MGMT_IP=$1
OPENSTACK_VERSION=$2
PUBLIC_URL="http://${MGMT_IP}:9696"
INTERNAL_URL="${PUBLIC_URL}"
NETWORK_SERVICE='neutron'
NEUTRON_CFG='/etc/neutron/neutron.conf'
ML2_CFG='/etc/neutron/plugins/ml2/ml2_conf.ini'
L3_AGENT_CFG='/etc/neutron/l3_agent.ini'
DHCP_AGENT_CFG='/etc/neutron/dhcp_agent.ini'
METADATA_CFG='/etc/neutron/metadata_agent.ini'

source /vagrant/provision/logger.sh
source /vagrant/provision/functions.sh
source /vagrant/provision/vars.sh
source /home/vagrant/openrc_admin

debug "Installing ${NETWORK_SERVICE} servises ..."
apt-get install -y neutron-server neutron-plugin-ml2 python-neutronclient neutron-plugin-ml2 \
        neutron-plugin-openvswitch-agent neutron-l3-agent neutron-dhcp-agent neutron-lbaas-agent ethtool

crudini --set "${NEUTRON_CFG}" DEFAULT verbose True
crudini --set "${NEUTRON_CFG}" DEFAULT debug True
crudini --set "${NEUTRON_CFG}" DEFAULT auth_strategy keystone
crudini --set "${NEUTRON_CFG}" DEFAULT rpc_backend rabbit
crudini --set "${NEUTRON_CFG}" DEFAULT core_plugin ml2
crudini --set "${NEUTRON_CFG}" DEFAULT service_plugins router,lbaas
crudini --set "${NEUTRON_CFG}" DEFAULT rpc_backend neutron.openstack.common.rpc.impl_kombu
crudini --set "${NEUTRON_CFG}" DEFAULT rabbit_host "${MGMT_IP}"
crudini --set "${NEUTRON_CFG}" DEFAULT allow_overlapping_ips True
crudini --set "${NEUTRON_CFG}" DEFAULT notification_driver neutron.openstack.common.notifier.rpc_notifier
crudini --set "${NEUTRON_CFG}" DEFAULT notify_nova_on_port_status_changes True
crudini --set "${NEUTRON_CFG}" DEFAULT notify_nova_on_port_data_changes True
crudini --set "${NEUTRON_CFG}" DEFAULT nova_admin_username "${SERVICE_USER_NAME}"
crudini --set "${NEUTRON_CFG}" DEFAULT nova_admin_tenant_id "$(get_id keystone tenant-get service)"
crudini --set "${NEUTRON_CFG}" DEFAULT nova_admin_password "${SERVICE_USER_PASSWORD}"
crudini --set "${NEUTRON_CFG}" DEFAULT nova_admin_auth_url "http://${MGMT_IP}:35357/v2.0"
crudini --set "${NEUTRON_CFG}" DEFAULT nova_region_name "${OS_REGION_NAME}"

setup_keystone_authentication "${NEUTRON_CFG}" "${SERVICE_USER_NAME}"

crudini --set "${NEUTRON_CFG}" database connection "mysql://${DB_USER}:${DB_PASSWORD}@${MGMT_IP}/${NETWORK_SERVICE}"

crudini --set "${NEUTRON_CFG}" service_providers service_provider LOADBALANCER:Haproxy:neutron.services.loadbalancer.drivers.haproxy.plugin_driver.HaproxyOnHostPluginDriver:default
crudini --set "${NEUTRON_CFG}" service_providers service_provider VPN:openswan:neutron.services.vpn.service_drivers.ipsec.IPsecVPNDriver:default

crudini --set "${ML2_CFG}" ml2 type_drivers flat,gre
crudini --set "${ML2_CFG}" ml2 tenant_network_types gre,flat
crudini --set "${ML2_CFG}" ml2 mechanism_drivers openvswitch,linuxbridge

crudini --set "${ML2_CFG}" ml2_type_flat flat_networks '*'
crudini --set "${ML2_CFG}" securitygroup firewall_driver neutron.agent.linux.iptables_firewall.OVSHybridIptablesFirewallDriver
crudini --set "${ML2_CFG}" securitygroup enable_security_group True

crudini --set "${ML2_CFG}" ovs local_ip "${MGMT_IP}"
crudini --set "${ML2_CFG}" ovs tunnel_type gre
crudini --set "${ML2_CFG}" ovs enable_tunneling True
crudini --set "${ML2_CFG}" ovs bridge_mappings "physnet1:${BR_EX1},physnet2:${BR_EX2}"
crudini --set "${ML2_CFG}" ml2_type_gre tunnel_id_ranges 1:1000

crudini --set "${L3_AGENT_CFG}" DEFAULT interface_driver neutron.agent.linux.interface.OVSInterfaceDriver
crudini --set "${L3_AGENT_CFG}" DEFAULT use_namespaces True
crudini --set "${L3_AGENT_CFG}" DEFAULT metadata_port 8775
crudini --set "${L3_AGENT_CFG}" DEFAULT enable_metadata_proxy True

crudini --set "${DHCP_AGENT_CFG}" DEFAULT interface_driver neutron.agent.linux.interface.OVSInterfaceDriver
crudini --set "${DHCP_AGENT_CFG}" DEFAULT dhcp_driver neutron.agent.linux.dhcp.Dnsmasq
crudini --set "${DHCP_AGENT_CFG}" DEFAULT use_namespaces True

crudini --set "${METADATA_CFG}" DEFAULT auth_url "http://${MGMT_IP}:5000/v2.0"
crudini --set "${METADATA_CFG}" DEFAULT auth_region "${OS_REGION_NAME}"

crudini --set "${METADATA_CFG}" DEFAULT admin_tenant_name service
crudini --set "${METADATA_CFG}" DEFAULT admin_user "${SERVICE_USER_NAME}"
crudini --set "${METADATA_CFG}" DEFAULT admin_password "${SERVICE_USER_PASSWORD}"
crudini --set "${METADATA_CFG}" DEFAULT nova_metadata_ip "${MGMT_IP}"
crudini --set "${METADATA_CFG}" DEFAULT nova_metadata_port 8775
crudini --set "${METADATA_CFG}" DEFAULT metadata_proxy_shared_secret "${METADATA_PROXY_SHARED_SECRET}"

if [[ ${OPENSTACK_VERSION} == 'juno' ]]
then
   LBAAS_AGENT_CFG='/etc/neutron/lbaas_agent.ini'
   crudini --set "${LBAAS_AGENT_CFG}" DEFAULT interface_driver neutron.agent.linux.interface.OVSInterfaceDriver
   crudini --set "${LBAAS_AGENT_CFG}" DEFAULT ovs_use_veth False
fi

create_db "${NETWORK_SERVICE}"

if [[ "${OPENSTACK_VERSION}" == 'juno' ]]
then
  neutron-db-manage --config-file /etc/neutron/neutron.conf \
  --config-file /etc/neutron/plugins/ml2/ml2_conf.ini upgrade juno
fi

# Create service and endpoint
create_service "${NETWORK_SERVICE}" network "OpenStack Networking service" "${PUBLIC_URL}" "${INTERNAL_URL}"

prepare_network_host "${BR_EX1}" "${BR_EX2}"

wait_http_available "${NETWORK_SERVICE}" "${INTERNAL_URL}"

if [[ "${OPENSTACK_VERSION}" == 'juno' ]]
then
  #Should be 5 neutron services: Open vSwitch agent, L3 agent, Metadata agent, DHCP agent, Loadbalancer agent
  check_openstack_services "${NETWORK_SERVICE}" 5
else
  #Should be 4 neutron services: Open vSwitch agent, L3 agent, Metadata agent, DHCP agent
  check_openstack_services "${NETWORK_SERVICE}" 4
fi

info "Checking agents status ..."
${NETWORK_SERVICE} agent-list | tee -a "${SCRIPT_LOG}"

debug "${NETWORK_SERVICE} has been installed and has been configured"

