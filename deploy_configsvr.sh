#!/bin/bash

[[ $# -ne 2 ]] && { echo "Usage: $0 port mongo_root"; exit 1; }

port=$1
mongo_root=$2
db_root=~/mongo_deploy/mongo_config_${port}
db_path=$db_root/db
log_path=$db_root/log
log_name=config.log

if [ ! -d "$db_path" ]; then
    mkdir -p $db_path
fi

if [ ! -d "$log_path" ]; then
    mkdir -p $log_path
fi

$mongo_root/mongod --configsvr \
    --port $port \
    --logpath $log_path/$log_name --logappend \
    --dbpath $db_path \
    --fork

