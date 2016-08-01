#!/bin/bash

MGMT_IP=$1
OPENSTACK_VERSION=$2
PUBLIC_URL="http://${MGMT_IP}:5000/v2.0"
INTERNAL_URL="http://${MGMT_IP}:35357/v2.0"
KEYSTONE_CFG='/etc/keystone/keystone.conf'

source /vagrant/provision/logger.sh
source /vagrant/provision/functions.sh
source /vagrant/provision/vars.sh

debug "Installing keystone service ..."

create_db keystone
apt-get install -y keystone python-keystoneclient

if [[ ${OPENSTACK_VERSION} == 'grizzly' ]]
then
  crudini --set ${KEYSTONE_CFG} sql connection "mysql://${DB_USER}:${DB_PASSWORD}@${MGMT_IP}/keystone"
else
  crudini --set ${KEYSTONE_CFG} database connection "mysql://${DB_USER}:${DB_PASSWORD}@${MGMT_IP}/keystone"
fi

crudini --set ${KEYSTONE_CFG} DEFAULT debug True
crudini --set ${KEYSTONE_CFG} DEFAULT verbose True
crudini --set ${KEYSTONE_CFG} DEFAULT admin_token "${OS_SERVICE_TOKEN}"
crudini --set ${KEYSTONE_CFG} DEFAULT log_dir /var/log/keystone

crudini --set ${KEYSTONE_CFG} token provider keystone.token.providers.uuid.Provider

crudini --set ${KEYSTONE_CFG} revoke driver keystone.contrib.revoke.backends.sql.Revoke

info "Syncing keystone DB"
keystone-manage db_sync

restart_service keystone

rm -rf /var/lib/keystone/keystone.db

echo '@hourly /usr/bin/keystone-manage token_flush >/var/log/keystone/keystone-tokenflush.log 2>&1' | \
     tee -a /var/spool/cron/crontabs/keystone

wait_http_available keystone ${INTERNAL_URL}

# Tenants
ADMIN_TENANT=$(get_id keystone tenant-create --name=admin)
SERVICE_TENANT=$(get_id keystone tenant-create --name=${SERVICE_TENANT_NAME})

# Users
ADMIN_USER=$(get_id keystone user-create --name=${ADMIN_USER_NAME} --pass=${ADMIN_USER_PASSWORD} \
              --email=${ADMIN_USER_NAME}@domain.com)
SERVICE_USER=$(get_id keystone user-create --name=${SERVICE_USER_NAME} --tenant-id=${SERVICE_TENANT} \
              --pass=${SERVICE_USER_PASSWORD} --email=${SERVICE_USER_NAME}@domain.com)

# Roles
ADMIN_ROLE=$(get_id keystone role-create --name=${ADMIN_USER_NAME})

# Add Roles to Users in Tenants
keystone user-role-add --user-id ${ADMIN_USER} --role-id ${ADMIN_ROLE} --tenant-id ${ADMIN_TENANT}
keystone user-role-add --user-id ${SERVICE_USER} --role-id ${ADMIN_ROLE} --tenant-id ${SERVICE_TENANT}

# Create service and endpoint
create_service keystone identity "OpenStack Identity" ${PUBLIC_URL} ${INTERNAL_URL}

# Openrc file
info "Creating admin openrc file"
cat<< EOF >>/home/vagrant/openrc_admin
#!/bin/sh
export LC_ALL=C
export OS_NO_CACHE='true'
export OS_TENANT_NAME=${ADMIN_TENANT_NAME}
export OS_USERNAME=${ADMIN_USER_NAME}
export OS_PASSWORD=${ADMIN_USER_PASSWORD}
export OS_AUTH_URL=${OS_SERVICE_ENDPOINT}
export OS_SERVICE_ENDPOINT="http://${MGMT_IP}:35357/v2.0"
export OS_SERVICE_TOKEN=${PASSWORD}
EOF

debug "Keystone service has been installed and has been configured"

