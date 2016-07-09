#!/bin/bash

source /vagrant/provision/logger.sh
source /vagrant/provision/vars.sh

EXPORT_SETTINGS='*(rw,sync,no_subtree_check)'
EXPORT_ROOT='/var/exports'$
EXPORT_CFG='/etc/exports'

debug "Installing nfs service ..."

info "Updating packages"
apt-get update && apt-get upgrade -y
apt-get autoremove -y
info "Packages have been updated"

apt-get install -y nfs-kernel-server nfs-common

mkdir -p ${EXPORT_ROOT}/cinder
mkdir -p ${EXPORT_ROOT}/source
mkdir -p ${EXPORT_ROOT}/destination
mkdir -p ${EXPORT_ROOT}/grizzly{1..2}
mkdir -p ${EXPORT_ROOT}/icehouse{1..2}
mkdir -p ${EXPORT_ROOT}/juno{1..2}

# Change owner
info "Changing folder owner on cinder"
for folder in $(ls ${EXPORT_ROOT})
do
  chown -R cinder. ${EXPORT_ROOT}/${folder}
done

# Add to exports file

cat<<EOF>>${EXPORT_CFG}

${EXPORT_ROOT}/cinder ${EXPORT_SETTINGS}
${EXPORT_ROOT}/source ${EXPORT_SETTINGS}
${EXPORT_ROOT}/destination ${EXPORT_SETTINGS}
${EXPORT_ROOT}/grizzly1 ${EXPORT_SETTINGS}
${EXPORT_ROOT}/grizzly2 ${EXPORT_SETTINGS}
${EXPORT_ROOT}/icehouse1 ${EXPORT_SETTINGS}
${EXPORT_ROOT}/icehouse2 ${EXPORT_SETTINGS}
${EXPORT_ROOT}/juno1 ${EXPORT_SETTINGS}
${EXPORT_ROOT}/juno2 ${EXPORT_SETTINGS}
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

