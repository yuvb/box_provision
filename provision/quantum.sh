#!/bin/bash

source /vagrant/provision/logger.sh
source /vagrant/provision/functions.sh
source /vagrant/provision/vars.sh
source /home/vagrant/openrc_admin

PUBLIC_URL="http://${MGMT_IP}:9696"
INTERNAL_URL=${PUBLIC_URL}
NETWORK_SERVICE='quantum'
PASTE_CFG='/etc/quantum/api-paste.ini'
OVS_PLUGIN_CFG='/etc/quantum/plugins/openvswitch/ovs_quantum_plugin.ini'
METADATA_CFG='/etc/quantum/metadata_agent.ini'
QUANTUM_CFG='/etc/quantum/quantum.conf'
L3_AGENT_CFG='/etc/quantum/l3_agent.ini'
DHCP_AGENT_CFG='/etc/quantum/dhcp_agent.ini'

debug "Installing ${NETWORK_SERVICE} services ..."

apt-get install -y openvswitch-switch quantum-plugin-openvswitch quantum-plugin-openvswitch-agent quantum-server \
                   dnsmasq quantum-dhcp-agent quantum-l3-agent quantum-lbaas-agent ethtool module-assistant

#  /etc/quantum/api-paste.ini
setup_keystone_authentication ${PASTE_CFG} ${SERVICE_USER_NAME} 'filter:authtoken'
crudini --set ${PASTE_CFG} DEFAULT debug true
crudini --set ${PASTE_CFG} filter:authtoken paste.filter_factory keystoneclient.middleware.auth_token:filter_factory
# /etc/quantum/plugins/openvswitch/ovs_quantum_plugin.ini
crudini --set ${OVS_PLUGIN_CFG} DEFAULT debug true
crudini --set ${OVS_PLUGIN_CFG} DATABASE sql_connection "mysql://${DB_USER}:${DB_PASSWORD}@${MGMT_IP}/${NETWORK_SERVICE}"
crudini --set ${OVS_PLUGIN_CFG} OVS tenant_network_type gre
crudini --set ${OVS_PLUGIN_CFG} OVS tunnel_id_ranges 1:1000
crudini --set ${OVS_PLUGIN_CFG} OVS integration_bridge br-int
crudini --set ${OVS_PLUGIN_CFG} OVS local_ip ${MGMT_IP}
crudini --set ${OVS_PLUGIN_CFG} OVS enable_tunneling True
crudini --set ${OVS_PLUGIN_CFG} OVS network_vlan_ranges physnet1:1000:2999
# /etc/quantum/metadata_agent.ini
setup_keystone_authentication ${METADATA_CFG} ${SERVICE_USER_NAME} DEFAULT
crudini --set ${METADATA_CFG} DEFAULT debug true
crudini --set ${METADATA_CFG} DEFAULT nova_metadata_ip ${MGMT_IP}
crudini --set ${METADATA_CFG} DEFAULT nova_metadata_port 8775
crudini --set ${METADATA_CFG} DEFAULT metadata_proxy_shared_secret ${METADATA_PROXY_SHARED_SECRET}
# /etc/quantum/quantum.conf
crudini --set ${QUANTUM_CFG} DEFAULT debug true
setup_keystone_authentication ${QUANTUM_CFG} ${SERVICE_USER_NAME}
crudini --set ${QUANTUM_CFG} DEFAULT keystone_authtoken signing_dir /var/lib/quantum/keystone-signing
crudini --set ${QUANTUM_CFG} DEFAULT core_plugin quantum.plugins.openvswitch.ovs_quantum_plugin.OVSQuantumPluginV2
crudini --set ${QUANTUM_CFG} DEFAULT service_plugins quantum.plugins.services.agent_loadbalancer.plugin.LoadBalancerPlugin
crudini --set ${QUANTUM_CFG} DEFAULT allow_overlapping_ips True
crudini --set ${QUANTUM_CFG} QUOTAS quota_driver quantum.db.quota_db.DbQuotaDriver
# /etc/quantum/l3_agent.ini
setup_keystone_authentication ${L3_AGENT_CFG} ${SERVICE_USER_NAME} DEFAULT
crudini --set ${L3_AGENT_CFG} DEFAULT interface_driver quantum.agent.linux.interface.OVSInterfaceDriver
crudini --set ${L3_AGENT_CFG} DEFAULT metadata_port 8775
crudini --set ${L3_AGENT_CFG} DEFAULT auth_url http://${MGMT_IP}:35357/v2.0
# /etc/quantum/dhcp_agent.ini
crudini --set ${DHCP_AGENT_CFG} DEFAULT dhcp_driver quantum.agent.linux.dhcp.Dnsmasq

create_db ${NETWORK_SERVICE}

# Create service and endpoint
create_service ${NETWORK_SERVICE} network "OpenStack Networking service" ${PUBLIC_URL} ${INTERNAL_URL}

prepare_network_host ${BR_EX1} ${BR_EX2}

wait_http_available ${NETWORK_SERVICE} ${INTERNAL_URL}

#Should be 3 neutron services: Open vSwitch agent, L3 agent, DHCP agent
check_openstack_services ${NETWORK_SERVICE} 3

info "Checking agents status"
${NETWORK_SERVICE} agent-list | tee -a ${SCRIPT_LOG}

debug "${NETWORK_SERVICE} has been installed and has been configured"

