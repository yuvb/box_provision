#!/bin/bash
source /vagrant/provision/logger.sh
source /vagrant/provision/vars.sh

function create_db(){
  local db_name=$1
  local user_secret=${DB_PASSWORD}
  local grant_user=${DB_USER}
  info "Creating db ${db_name}"
  mysql -e "create database ${db_name};"
  local check_db=$(mysql -e "show databases;" | awk -v db_name=$db_name '$0 ~ db_name {print $1}')
  if [[ ${check_db} == "${db_name}" ]]
  then
    info "DB ${db_name} has been created successfully"
  else
    error "DB ${db_name} hasn't been created"
    exit 103
  fi
  info "Granting permissions for ${grant_user} on db ${db_name}"
  # After adding hosts to /etc/hosts files the error "ERROR: An unexpected error prevented the server from fulfilling your
  # request. (OperationalError) (1045, "Access denied for user 'root'@'grizzly' (using password: YES)") None None"
  # is appeared.
  if [[ (${OPENSTACK_VERSION} == 'grizzly') && (${db_name} == 'keystone') ]]
  then
    mysql << EOF
    GRANT ALL PRIVILEGES ON ${db_name}.* TO '${grant_user}'@'$(hostname)' IDENTIFIED BY '${user_secret}' WITH GRANT OPTION;
EOF
  fi
  mysql << EOF
  GRANT ALL PRIVILEGES ON ${db_name}.* TO '${grant_user}'@'%' IDENTIFIED BY '${user_secret}' WITH GRANT OPTION;
EOF
  if [[ $? ==  0 ]]
  then
    info "Granted permissions for user ${grant_user} on db  ${db_name}"
  else
    error "Couldn't grant permissions for user ${grant_user} on db  ${db_name}"
  fi
}

function get_id (){
  echo "$("$@" | awk '/ id / { print $4 }')"
}

function create_service(){
  local name="${1}"
  local type="${2}"
  local description="${3}"
  local public_url="${4}"
  local internal_url="${5}"

  # Create servises
  info "Creating service ${name}"
  keystone service-create --name ${name} --type ${type} --description "${description}"
  service_id=$(get_id keystone service-get ${name})

  if [[ -n ${service_id} ]]
  then
    info "Service ${name} has been created successfully"
  else
    error "Service ${name} hasn't been created"
  fi

  keystone endpoint-create --region integration --service-id ${service_id} --publicurl=${public_url} \
                           --adminurl ${internal_url} --internalurl ${internal_url}
  endpoint=$(keystone endpoint-list | awk -v service_id=$service_id '$0 ~ service_id {print $2}')
  if [[ -n ${endpoint} ]]
  then
    info "Endpoint ${name} has been created successfully with id ${endpoint}"
  else
    error "Endpoint ${name} hasn't been created"
  fi
}

function setup_keystone_authentication(){
  local config_file=$1
  local admin_user=$2
  local section=${3:-keystone_authtoken}
  crudini --set ${config_file} ${section} auth_uri "http://${MGMT_IP}:35357/v2.0"
  crudini --set ${config_file} ${section} auth_host ${MGMT_IP}
  crudini --set ${config_file} ${section} auth_port 35357
  crudini --set ${config_file} ${section} auth_protocol http
  crudini --set ${config_file} ${section} admin_tenant_name ${SERVICE_TENANT_NAME}
  crudini --set ${config_file} ${section} admin_user ${admin_user}
  crudini --set ${config_file} ${section} admin_password ${SERVICE_USER_PASSWORD}
}

function prepare_network_host(){
  local br_ex1=$1
  local br_ex2=$2
  local interface_cfg='/etc/network/interfaces'
  local ip_eth1=$(ip a show dev eth1 | awk '/inet / {print $2}' | cut -d '/' -f 1)
  local ip_eth2=$(ip a show dev eth2 | awk '/inet / {print $2}' | cut -d '/' -f 1)

  # Start script
cat << EOF > /etc/rc.local
#!/bin/sh -e
bridges=\$(awk '{ if (\$1 == "allow-ovs") { print \$2; } }' ${interface_cfg})
[ -n "\${bridges}" ] && ifup --allow=ovs \${bridges}

exit 0
EOF

  # Clean interfaces file
  source_str_number=$(grep -n "source ${interface_cfg}" ${interface_cfg} | cut -d ':' -f 1)
  sed -i  ''$((source_str_number+1))',$d' ${interface_cfg}

  info "Configuring certain kernel networking parameters"
  # Kernel networking parameters
  sed -i -e 's/^.net.ipv4.ip_forward=.*$/net.ipv4.ip_forward=1/g' \
         -e 's/^.net.ipv4.conf.all.rp_filter=.*$/net.ipv4.conf.all.rp_filter=0/g' \
         -e 's/^.net.ipv4.conf.default.rp_filter=.*$/net.ipv4.conf.default.rp_filter=0/g'  /etc/sysctl.conf
  sysctl -p

  info "Creating openvswitch bridges"
  restart_service openvswitch-switch
  ovs-vsctl add-br ${br_ex1}
  ovs-vsctl add-port ${br_ex1} eth1
  ovs-vsctl add-br ${br_ex2}
  ovs-vsctl add-port ${br_ex2} eth2

  if [[ ${NETWORK_SERVICE} == quantum ]]
  then
    ovs-vsctl add-br br-int
  fi

  for index in 1 2
  do
    ethtool -K eth${index} gro off tso off sg off
cat << EOF >> ${interface_cfg}

auto eth${index}
iface eth${index} inet manual
    up ip link set \$IFACE promisc on
    down ip link set \$IFACE promisc off
EOF
  done

cat << EOF >> /etc/network/interfaces

allow-ovs ${br_ex1}
iface ${br_ex1} inet static
    ovs_type OVSBridge
    address ${ip_eth1}
    netmask 255.255.255.0
    up ip link set \$IFACE promisc on
    down ip link set \$IFACE promisc off

allow-ovs ${br_ex2}
iface ${br_ex2} inet static
    ovs_type OVSBridge
    address ${ip_eth2}
    netmask 255.255.255.0
    up ip link set \$IFACE promisc on
    down ip link set \$IFACE promisc off
EOF

  restart_service ${NETWORK_SERVICE}
}

function wait_http_available(){
  local service=$1
  local url=$2
  checker "(curl --output /dev/null --silent --head --fail ${url})" ${service} 1
}

function checker(){
  local check_cmd=$1
  local service=$2
  local time_sleep=$3
  local timeout=30
  local i=0
  while [[ $i -lt ${timeout} ]]
  do
    echo ${check_cmd} | bash
    if [[ $? == 0 ]]
    then
      info "Service ${service} is running"
      break
    fi
    if [[ $i == $((timout -1)) ]]
    then
      error "Service ${service} isn't running"
      exit 104
    fi
    sleep ${time_sleep}
    let "i++"
  done
}

function restart_service(){
  local service=$1
  local openstack_services='nova glance cinder neutron quantum'
  local services=''
  if [[ ${openstack_services} =~ ${service} ]]
  then
    services=$(initctl list | grep ${service} | awk '{print $1}')
  else
    services=${service}
  fi
  for current_service in ${services}
  do
    info "Restarting service ${current_service}"
    service ${current_service} restart
    info "Checking service ${current_service} status"
    checker "service ${current_service} status | grep running" ${current_service} 1
  done
  info "Service ${service} has been restarted successfully"
}

function check_openstack_services(){
  local service=$1
  local count=$2
  local timeout=30
  local i=0
  while [[ $i -lt ${timeout} ]]
  do
    case $service in
    nova)
      services=$(nova service-list | sed '1,3d' | sed '$d' | wc -l)
      ;;
    cinder)
      services=$(cinder service-list | sed '1,3d' | sed '$d' | wc -l)
      ;;
    quantum)
      services=$(quantum agent-list | sed '1,3d' | sed '$d' | wc -l)
      ;;
    neutron)
      services=$(neutron agent-list | sed '1,3d' | sed '$d' | wc -l)
      ;;
    esac
    info "Checking service ${service}"
    if [[ ${services} == "${count}" ]]
    then
      info "All ${services} services exist"
      break
    fi
    if [[ $i -eq $((timout -1)) ]]
    then
      error "Some ${service} services didn't start"
      exit 105
    fi
    sleep 1
    let "i++"
  done
}

function create_monit_script(){
  local service=$1
  local script_folder='/etc/monit/scripts'
  local api_service='glance-api nova-api cinder-api keystone quantum-server neutron-server'
  local protocol='HTTP'
  local api_url=''
  local status_code='200'

  if [[ ! -d ${script_folder} ]]
  then
    mkdir -p ${script_folder}
    chmod 755 ${script_folder}
    info "Folder ${script_folder} has been created"
  else
    info "Folder ${script_folder} has been already created"
  fi

  info "Creating the monit config file "${script_folder}/check_${service}.sh""
  if [[ ${api_service} =~ ${service} ]]
  then
    case $service in
    nova-api)
      api_url="http://${MGMT_IP}:8774/"
      ;;
    glance-api)
      api_url="http://${MGMT_IP}:9292/"
      status_code='300'
      ;;
    cinder-api)
      api_url="http://${MGMT_IP}:8776/"
      ;;
    keystone)
      api_url="http://${MGMT_IP}:35357/v2.0/"
      ;;
    quantum-server)
      api_url="http://${MGMT_IP}:9696/"
      ;;
    neutron-server)
      api_url="http://${MGMT_IP}:9696/"
      ;;
    esac

cat<< EOF >>"${script_folder}/check_${service}.sh"
#!/bin/bash

status_code=${status_code}
api_url=${api_url}
protocol='HTTP'
EOF

cat<< \EOF >>"${script_folder}/check_${service}.sh"
check_code=$(curl -s -i ${api_url} | awk -v protocol=${protocol} '$0 ~ protocol {print $2}')
if [[ ${check_code} == ${status_code} ]]
then
  exit 0
else
  exit 1
fi
EOF

  else
cat<< EOF >>"${script_folder}/check_${service}.sh"
#!/bin/bash

/sbin/initctl list | grep ${service} | grep -v stop
EOF
  fi


  if [[ -s "${script_folder}/check_${service}.sh" ]]
  then
    info "The monit config file "${script_folder}/check_${service}.sh" has been created successfully"
  else
    error "The monit config file "${script_folder}/check_${service}.sh" hasn't been created"
  fi
  chmod 755 "${script_folder}/check_${service}.sh"
}

function add_service_to_monit(){
  local service=$1
  local script_folder='/etc/monit/scripts'
  local monit_cfg='/etc/monit/monitrc'
  local cmd_service='/usr/sbin/service'

  info "Adding  the ${service} service to the monit config file"
  if [[ ${service} == 'rabbitmq-server' ]]
  then
cat<< EOF >>${monit_cfg}
  check process ${service} with pidfile /var/run/rabbitmq/pid
    start program = "${cmd_service} ${service} start"
    stop program = "${cmd_service} ${service} stop"
    if failed port 5672 then restart

EOF
  elif [[ ${service} == 'apache2' ]]
  then
    if [[ ${UBUNTU_VERSION} == '14.04' ]]
    then
      pidfile="/var/run/${service}/${service}.pid"
    else
      pidfile="/var/run/${service}.pid"
    fi
cat<< EOF >>${monit_cfg}
  check process ${service} with pidfile ${pidfile}
    start program = "${cmd_service} ${service} start"
    stop program = "${cmd_service} ${service} stop"
    if failed port 80 then restart

EOF
  elif [[ ${service} == 'mysql' ]]
  then
cat<< EOF >>${monit_cfg}
  check process ${service} with pidfile /var/run/mysqld/mysqld.pid
    start program = "${cmd_service} ${service} start"
    stop program = "${cmd_service} ${service} stop"
    if failed port 3306 then restart

EOF
  else
cat<< EOF >>${monit_cfg}
  check program ${service} with path "${script_folder}/check_${service}.sh"
    start program = "${cmd_service} ${service} start"
    stop program = "${cmd_service} ${service} stop"
    if status != 0 then restart

EOF
  fi
}

