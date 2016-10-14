#!/bin/bash

[[ $# -ne 3 ]] && { echo "Usage: $0 port mongo_root repl_name"; exit 1; }

port=$1
mongo_root=$2
repl_name=$3
db_root=~/mongo_deploy/mongo_shard_${port}
db_path=$db_root/db
log_path=$db_root/log
log_name=shard.log

if [ ! -d "$db_path" ]; then
    mkdir -p $db_path
fi

if [ ! -d "$log_path" ]; then
    mkdir -p $log_path
fi

$mongo_root/mongod --shardsvr \
    --replSet $repl_name \
    --smallfiles \
    --oplogSize 50 \
    --port $port \
    --logpath $log_path/$log_name --logappend \
    --dbpath $db_path \
    --fork

