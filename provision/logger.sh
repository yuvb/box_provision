#!/bin/bash

SCRIPT_LOG=/home/vagrant/SystemOut.log
COLOR_OFF='\033[0m'
RED='\033[0;31m'
GREEN='\033[0;32m'
BYELLOW='\033[1;33m'
touch $SCRIPT_LOG
function scriptentry(){
  script_name=$(basename "$0")
  echo "$FUNCNAME: $script_name" | tee -a ${SCRIPT_LOG}
}

function scriptexit(){
  script_name=$(basename "$0")
  echo "$FUNCNAME: $script_name" | tee -a ${SCRIPT_LOG}
}

function entry(){
  local cfn="${FUNCNAME[1]}"
  local tstamp=$(date)
  local msg="> $cfn $FUNCNAME"
  echo -e "[$tstamp] [DEBUG]\t$msg" | tee -a ${SCRIPT_LOG}
}

function info(){
  local msg="$1"
  local tstamp=$(date)
  echo -e "${GREEN}[$tstamp] [INFO]\t$msg${COLOR_OFF}" | tee -a ${SCRIPT_LOG}
}

function error(){
  local msg="$1"
  local tstamp=$(date)
  echo -e "${RED}[$tstamp] [ERROR]\t$msg${COLOR_OFF}" | tee -a ${SCRIPT_LOG}
}

function debug(){
  local msg="$1"
  local tstamp=$(date)
  echo -e "${BYELLOW}[$tstamp] [DEBUG]\t$msg${COLOR_OFF}" | tee -a ${SCRIPT_LOG}
}

