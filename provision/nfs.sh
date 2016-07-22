#!/bin/bash

source /vagrant/provision/logger.sh
source /vagrant/provision/vars.sh

NFS_SETTINGS='*(rw,sync,no_subtree_check)'
NFS_ROOT='/var/exports'
NFS_CFG='/etc/exports'

debug "Installing nfs service ..."

info "Updating packages"
apt-get update && apt-get upgrade -y
apt-get autoremove -y
info "Packages have been updated"

apt-get install -y nfs-kernel-server nfs-common

mkdir -p ${NFS_ROOT}/cinder
mkdir -p ${NFS_ROOT}/source
mkdir -p ${NFS_ROOT}/destination
mkdir -p ${NFS_ROOT}/grizzly{1..2}
mkdir -p ${NFS_ROOT}/icehouse{1..2}
mkdir -p ${NFS_ROOT}/juno{1..2}

# Adding cinder group and user
useradd cinder
usermod -G cinder cinder

# Change owner
info "Changing folder owner on cinder"
find ${NFS_ROOT} -maxdepth 1 -type d -execdir chown -R cinder. {} + -execdir chmod 777 {} \;

# Add to exports file
cat<< EOF >>${NFS_CFG}

${NFS_ROOT}/cinder ${NFS_SETTINGS}
${NFS_ROOT}/source ${NFS_SETTINGS}
${NFS_ROOT}/destination ${NFS_SETTINGS}
${NFS_ROOT}/grizzly1 ${NFS_SETTINGS}
${NFS_ROOT}/grizzly2 ${NFS_SETTINGS}
${NFS_ROOT}/icehouse1 ${NFS_SETTINGS}
${NFS_ROOT}/icehouse2 ${NFS_SETTINGS}
${NFS_ROOT}/juno1 ${NFS_SETTINGS}
${NFS_ROOT}/juno2 ${NFS_SETTINGS}
EOF

info "Creating the NFS table that holds the exports"
sudo exportfs -a

info "Running the nfs server"
service nfs-kernel-server start

# check nfs shares
count_nfs_shares=$(showmount -e ${MGMT_IP} | sed '1d' | wc -l)
if [[ ${count_nfs_shares} == 9 ]]
then
  info "NFS shares have been created successfully"
else
  error "NFS shares haven't been created"
  exit 101
fi

debug "NFS service has been installed and  has been configured"

