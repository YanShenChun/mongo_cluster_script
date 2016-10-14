#!/bin/bash

configsvr_list=data/configsvr.list
shardsvr_list=data/shardsvr.list
ssvr_list=data/ssvr.list

echo "Deploy the config server by using the $configsvr_list"
grep -v ^\# $configsvr_list | while read line
do
    username=`echo $line|awk '{print $1}'`
    ip=`echo $line|awk '{print $2}'`
    port=`echo $line|awk '{print $3}'`
    passwd=`echo $line|awk '{print $4}'`
    mongo_root=`echo $line|awk '{print $5}'`

    sshpass -p $passwd scp deploy_configsvr.sh $username@$ip:~/deploy_configsvr_$port.sh
    sshpass -p $passwd ssh $username@$ip "chmod u+x ~/deploy_configsvr_$port.sh" < /dev/null
    echo "   .try to start the config server:$username@$ip:$port.."
    sshpass -p $passwd ssh $username@$ip "~/deploy_configsvr_$port.sh \
        $port $mongo_root > ~/deploy_configsvr_$port.out" < /dev/null
    if [[ $? -ne 0 ]]; then
        echo "   .fail to start config server on $username@$ip:$port"
        sshpass -p $passwd scp $username@$ip:~/deploy_configsvr_$port.out deploy.error
        exit 1
    fi
done

echo ""
echo "Deploy the shards server by using the $shardsvr_list"
grep -v ^\# $shardsvr_list | while read line
do
    username=`echo $line|awk '{print $1}'`
    ip=`echo $line|awk '{print $2}'`
    port=`echo $line|awk '{print $3}'`
    passwd=`echo $line|awk '{print $4}'`
    mongo_root=`echo $line|awk '{print $5}'`
    repl=`echo $line|awk '{print $6}'`

    sshpass -p $passwd scp deploy_shardsvr.sh $username@$ip:~/deploy_shardsvr_$port.sh
    sshpass -p $passwd ssh $username@$ip \
        "chmod u+x ~/deploy_shardsvr_$port.sh" < /dev/null
    echo "   .try to start the shard server:$username@$ip:$port with repl $repl.."
    sshpass -p $passwd ssh $username@$ip "~/deploy_shardsvr_$port.sh \
        $port $mongo_root $repl > ~/deploy_shardsvr_$port.out" < /dev/null
    if [[ $? -ne 0 ]]; then
        echo "   .fail to start shards server on $username@$ip:$port"
        sshpass -p $passwd scp $username@$ip:~/deploy_shardsvr_$port.out deploy.error
        exit 1
    fi
done

config_dbs=
while read line
do
    ip=`echo $line|awk '{print $2}'`
    port=`echo $line|awk '{print $3}'`
    config_dbs=$config_dbs,$ip:$port
done <<< "$(grep -v ^\# ${configsvr_list})"
config_dbs=${config_dbs:1}

echo ""
echo "Deploy the mongos server by using the $ssvr_list"
grep -v ^\# $ssvr_list | while read line
do
    username=`echo $line|awk '{print $1}'`
    ip=`echo $line|awk '{print $2}'`
    port=`echo $line|awk '{print $3}'`
    passwd=`echo $line|awk '{print $4}'`
    mongo_root=`echo $line|awk '{print $5}'`

    sshpass -p $passwd scp deploy_ssvr.sh $username@$ip:~/deploy_ssvr_$port.sh
    sshpass -p $passwd ssh $username@$ip "chmod u+x ~/deploy_ssvr_$port.sh" \
        < /dev/null
    echo "   .try to start the mongos server:$username@$ip:$port.."
    sshpass -p $passwd ssh $username@$ip "~/deploy_ssvr_$port.sh \
        $port $mongo_root $config_dbs > ~/deploy_ssvr_$port.out" < /dev/null
    if [[ $? -ne 0 ]]; then
        echo "   .fail to start mongos server on $username@$ip:$port"
        sshpass -p $passwd scp $username@$ip:~/deploy_ssvr_$port.out deploy.error
        exit 1
    fi
done

echo ""
echo "Configure the replica set"

# Get the repl_name->[ip:port] key pairs
#declare -A repl_map
#while read line
#do
#    ip=`echo $line|awk '{print $2}'`
#    port=`echo $line|awk '{print $3}'`
#    repl=`echo $line|awk '{print $6}'`
#    repl_map[$repl]=${repl_map[$repl]}","$ip":"$port
#done <<< "$(grep -v ^\# ${shardsvr_list})"

## Generate the replicate set initialize script.
#declare -A script_map
#OLD_IFS="$IFS"
#IFS=","
#for i in "${!repl_map[@]}"
#do
#    script='config={"_id":"'
#    script=$script$i'",'
    
#    script=$script'rs.initialize(config);'
#    #echo "key   :$i"
#    #echo "value :${repl_map[$i]}"
#    addr_arr=(${repl_map[$i]})
#    for s in ${addr_arr[@]}
#    do

#    done
#done
#IFS="$OLD_IFS"
declare -A repl_map

while read line
do
    name_ip_port_pwd=`echo $line|awk '{print $1 ":" $2 ":" $3 ":" $4 ":" $5}'`
    repl=`echo $line|awk '{print $6}'`

    if [[ -n "${repl_map[$repl]}" ]]; then
        repl_map[$repl]=${repl_map[$repl]}","$name_ip_port_pwd
    else
        repl_map[$repl]=$name_ip_port_pwd
    fi
done <<< "$(grep -v ^\# ${shardsvr_list})"

# Generate the replicate set initialize script.
declare -A script_map
for i in "${!repl_map[@]}"
do
    _id_stub=$i
    addr_arr=$(echo ${repl_map[$i]} | tr "," "\n")

    inc_id=0
    members_stub=
    for s in ${addr_arr[@]}
    do
        ip_port=`echo $s|awk -F ":" '{print $2 ":" $3}'`
        member_stub=$(cat <<EOF

            {
                \"_id\" : $inc_id,
                \"host\": \"$ip_port\"
            }
EOF
        )

        if [[ -n "$members_stub" ]]; then
            members_stub=$members_stub,$member_stub
        else
            members_stub=$member_stub
        fi

        ((inc_id += 1))
    done

    script=$(cat <<EOF
    config = {
        \"_id\" : \"$_id_stub\",
        \"members\":[
            $members_stub
        ]
    };
    rs.initiate(config);
EOF
    )

    script_map[$i]=$script
done

for i in "${!script_map[@]}"
do
    # login the first box in a repl set
    first_box=`echo ${repl_map[$i]}|awk -F "," '{print $1}'`
    ip=`echo $first_box|awk -F ":" '{print $2}'`
    port=`echo $first_box|awk -F ":" '{print $3}'`
    username=`echo $first_box|awk -F ":" '{print $1}'`
    userpwd=`echo $first_box|awk -F ":" '{print $4}'`
    mongo_root=`echo $first_box|awk -F ":" '{print $5}'`

    echo "   .try to configure repl set on box:$username@$ip:$port.."
    config_script='"'${script_map[$i]}'"'
    sshpass -p $userpwd ssh $username@$ip "$mongo_root/mongo --port $port \
        --eval $config_script > ~/config_repl.out" < /dev/null
    if [[ $? -ne 0 ]]; then
        echo "   .fail to configure repl set on box:$username@$ip:$port"
        sshpass -p $passwd scp $username@$ip:~/config_repl.out deploy.error
        exit 1
    fi
done

echo ""
echo "Configure the shards"

# Generate the configure shards script
shards_script=
for i in "${!repl_map[@]}"
do
    first_box=`echo ${repl_map[$i]}|awk -F "," '{print $1}'`
    ip=`echo $first_box|awk -F ":" '{print $2}'`
    port=`echo $first_box|awk -F ":" '{print $3}'`
    shards_script=${shards_script}$(cat <<EOF
    db.adminCommand({\"addshard\":\"$i/$ip:$port\"});
EOF
    )
done

while read line
do
    username=`echo $line|awk '{print $1}'`
    ip=`echo $line|awk '{print $2}'`
    port=`echo $line|awk '{print $3}'`
    passwd=`echo $line|awk '{print $4}'`
    mongo_root=`echo $line|awk '{print $5}'`

    echo "   .try to configure shards on mongos server:$username@$ip:$port.."
    sshpass -p $passwd ssh $username@$ip "$mongo_root/mongo --port $port \
        --eval \"$shards_script\" > ~/config_shards.out" < /dev/null
    if [[ $? -ne 0 ]]; then
        echo "   .fail to configure shards on mongos server:$username@$ip:$port"
        sshpass -p $passwd scp $username@$ip:~/config_shards.out deploy.error
        exit 1
    fi
done <<< "$(grep -v ^\# ${ssvr_list})"


echo ""
echo ""
echo "Success!"

