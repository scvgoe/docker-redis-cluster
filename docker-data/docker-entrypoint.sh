#!/bin/sh

if [ "$1" = 'redis-cluster' ]; then
    # Allow passing in cluster IP by argument or environmental variable
    IP="${2:-$IP}"

    max_port=6384
    if [ "$STANDALONE" = "true" ]; then
      max_port=6386
    fi

    for port in `seq 6379 $max_port`; do
      mkdir -p /redis-conf/${port}
      mkdir -p /redis-data/${port}

      if [ -e /redis-data/${port}/nodes.conf ]; then
        rm /redis-data/${port}/nodes.conf
      fi

      if [ "$port" -lt "6385" ]; then
        PORT=${port} envsubst < /redis-conf/redis-cluster.tmpl > /redis-conf/${port}/redis.conf
      else
        PORT=${port} envsubst < /redis-conf/redis.tmpl > /redis-conf/${port}/redis.conf
      fi

      if [ "$port" -lt "6382" ]; then
        if [ "$SENTINEL" = "true" ]; then
          PORT=${port} SENTINEL_PORT=$((port - 2000)) envsubst < /redis-conf/sentinel.tmpl > /redis-conf/sentinel-${port}.conf
          cat /redis-conf/sentinel-${port}.conf
        fi
      fi

    done

    bash /generate-supervisor-conf.sh $max_port > /etc/supervisor/supervisord.conf

    supervisord -c /etc/supervisor/supervisord.conf
    sleep 3

    if [ -z "$IP" ]; then # If IP is unset then discover it
        IP=$(hostname -I)
    fi
    IP=$(echo ${IP}) # trim whitespaces

    /redis/src/redis-cli --version | grep -E "redis-cli 3.0|redis-cli 3.2|redis-cli 4.0"

    if [ $? -eq 0 ]
    then
      echo "Using old redis-trib.rb to create the cluster"
      echo "yes" | ruby /redis/src/redis-trib.rb create --replicas 1 ${IP}:6379 ${IP}:6380 ${IP}:6381 ${IP}:6382 ${IP}:6383 ${IP}:6384
    else
      echo "Using redis-cli to create the cluster"
      echo "yes" | /redis/src/redis-cli --cluster create --cluster-replicas 1 ${IP}:6379 ${IP}:6380 ${IP}:6381 ${IP}:6382 ${IP}:6383 ${IP}:6384
    fi


    for port in 6379 6380 6381; do
      redis-sentinel /redis-conf/sentinel-6379.conf &
    done

    tail -f /var/log/supervisor/redis*.log
else
  exec "$@"
fi
