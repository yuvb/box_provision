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
    exit 201
  fi
  info "Granting permissions for ${grant_user} on db ${db_name}"
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

create_service(){
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

function wait_http_available(){
  local url=$1
  for ((i=1;i<=30;i++))
  do
    if (curl --output /dev/null --silent --head --fail ${url})
    then
      break
    fi
    if [[ $i == 30 ]]
    then
      error "Service ${service} isn't running"
      exit 101
    fi
    sleep 1
  done
}

function restart_service(){
  local service=$1
  info "Restarting service $service"
  service ${service} restart
  info "Checking service ${service} status"
  i=0
  while [[ $i -lt 30 ]]
  do
    service ${service} status | grep running
    if [[ $? == 0 ]]
    then
      info "Service ${service} is running"
      break
    fi
    if [[ $i == 29 ]]
    then
      error "Service ${service} isn't running"
      exit 101
    fi
    sleep 1
    let "i++"
  done

  info "Service ${service} has been restarted successfully"
}

function restart_openstack_services(){
  local openstack_service=$1
  for service in $(initctl list | grep ${openstack_service} | awk '{print $1}')
  do
    restart_service ${service}
  done
}

function check_openstack_services(){
  local service=$1
  local count=$2
  local i=0
  while [[ $i -lt 30 ]]
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
    if [[ $i -eq 29 ]]
    then
      error "Some ${service} services didn't start"
      exit 103
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

