#!/bin/bash

SCRIPT_LOG=/home/vagrant/SystemOut.log
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
  echo -e "[$tstamp] [INFO]\t$msg" | tee -a ${SCRIPT_LOG}
}

function error(){
  local msg="$1"
  local tstamp=$(date)
  echo -e "[$tstamp] [ERROR]\t$msg" | tee -a ${SCRIPT_LOG}
}

function debug(){
  local msg="$1"
  local tstamp=$(date)
  echo -e "[$tstamp] [DEBUG]\t$msg" | tee -a ${SCRIPT_LOG}
}

