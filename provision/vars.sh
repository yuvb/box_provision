#!/bin/bash

PASSWORD='secret'
OS_SERVICE_TOKEN="${PASSWORD}"
SUPPORT_OPENSTACK_VERSIONS='icehouse juno'

export DB_PASSWORD="${PASSWORD}"
export DB_USER='root'
export UBUNTU_VERSION=$(lsb_release -a | awk '/Release/ {print $2}')
export DEBIAN_FRONTEND=noninteractive
export MGMT_IP=$(ip a show dev eth1 | awk '/inet / {print $2}' | cut -d '/' -f 1)
export ADMIN_TENANT_NAME='admin'
export ADMIN_USER_NAME='admin'
export ADMIN_USER_PASSWORD='admin'
export SERVICE_USER_PASSWORD="${PASSWORD}"
export SERVICE_USER_NAME='service'
export SERVICE_TENANT_NAME='service'
export METADATA_PROXY_SHARED_SECRET="${PASSWORD}"
export OS_PASSWORD="${ADMIN_USER_PASSWORD}"
export OS_TENANT_NAME='admin'
export OS_AUTH_URL="http://${MGMT_IP}:35357/v2.0"
export OS_REGION_NAME="integration"
export OS_SERVICE_ENDPOINT="http://${MGMT_IP}:35357/v2.0"
export OS_SERVICE_TOKEN=${PASSWORD}

