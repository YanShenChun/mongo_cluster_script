#!/bin/bash

[[ $# -ne 3 ]] && { echo "Usage: $0 port mongo_root config_dbs"; exit 1; }

port=$1
mongo_root=$2
config_dbs=$3
db_root=~/mongo_deploy/mongo_s_${port}
log_path=$db_root/log
log_name=s.log

if [ ! -d "$log_path" ]; then
    mkdir -p $log_path
fi

$mongo_root/mongos --configdb $config_dbs \
    --port $port \
    --logpath $log_path/$log_name --logappend \
    --fork

