#!/bin/bash
function collect {
  time (
    if [ "$line" = "$host_ip" ]
    then
      tput setaf 4
      echo ${line} LOCALHOST
      echo ===================================================
      tput setaf 7
      sed -i "94s/.*/ hostname = \"${line}\"/" /home/fedora/MVAC/telegraf.conf
      sudo podman rm -f influxdb
      sudo podman volume prune -f
      sudo podman container restore --tcp-established -i /home/fedora/MVAC/export.tar.gz
      sleep 5
      sudo podman start influxdb
      sleep 5
      influx=$(sudo podman ps | grep -o influxdb | sed -e '1d')
      if [ "influxdb" = "$influx" ]
      then
        sudo podman run -v /home/fedora/MVAC/telegraf.conf:/etc/telegraf/telegraf.conf:Z -d --name telegraf --net=container:influxdb docker.io/library/telegraf:1.18
        sleep 20
        sudo podman rm -f telegraf
        sudo podman container checkpoint influxdb --tcp-established -e /home/fedora/MVAC/export.tar.gz
      else
        sudo podman start influxdb
        sudo podman run -v /home/fedora/MVAC/telegraf.conf:/etc/telegraf/telegraf.conf:Z -d --name telegraf --net=container:influxdb docker.io/library/telegraf:1.18
        sleep 20
        sudo podman rm -f telegraf
        sudo podman container checkpoint influxdb --tcp-established -e /home/fedora/MVAC/export.tar.gz
      fi
      sudo podman rm -f influxdb
      sudo podman volume prune -f
    else
      tput setaf 4
      echo "${line}"
      echo ===================================================
      tput setaf 7
      ssh -i ./id_rsa fedora@${line} "mkdir -p /home/fedora/MVAC"
      scp -i ./id_rsa /home/fedora/MVAC/export.tar.gz fedora@${line}:/home/fedora/MVAC/export.tar.gz
      scp -i ./id_rsa /home/fedora/MVAC/telegraf.conf fedora@${line}:/home/fedora/MVAC/telegraf.conf
      ssh -i ./id_rsa fedora@${line} "sed -i '94s/.*/ hostname = \"${line}\"/' /home/fedora/MVAC/telegraf.conf"
      ssh -i ./id_rsa fedora@${line} "sudo podman container restore --tcp-established -i /home/fedora/MVAC/export.tar.gz"
      ssh -i ./id_rsa fedora@${line} "sleep 5"
      ssh -i ./id_rsa fedora@${line} "sudo podman start influxdb"
      ssh -i ./id_rsa fedora@${line} "sleep 5"
      influx=$(ssh -i ./id_rsa fedora@${line} "sudo podman ps | grep -o influxdb | sed -e '1d'")
      if [ "influxdb" = "$influx" ]
      then
        set +e
        ssh -i ./id_rsa fedora@${line} "sudo podman run -v /home/fedora/MVAC/telegraf.conf:/etc/telegraf/telegraf.conf:Z -d --name telegraf --net=container:influxdb docker.io/library/telegraf:1.18"
        ssh -i ./id_rsa fedora@${line} "sleep 20"
        ssh -i ./id_rsa fedora@${line} "sudo podman rm -f telegraf"
        ssh -i ./id_rsa fedora@${line} "sudo podman container checkpoint influxdb --tcp-established -e /home/fedora/MVAC/export.tar.gz"
        if [ $? -eq 0 ]; then
          echo "Checkpoint succeeded"
        else
          ssh -i ./id_rsa fedora@${line} "sudo podman start influxdb"
          ssh -i ./id_rsa fedora@${line} "sleep 10"
          echo "Trying again"
          ssh -i ./id_rsa fedora@${line} "sudo podman run -v /home/fedora/MVAC/telegraf.conf:/etc/telegraf/telegraf.conf:Z -d --name telegraf --net=container:influxdb docker.io/library/telegraf:1.18"
          ssh -i ./id_rsa fedora@${line} "sleep 20"
          ssh -i ./id_rsa fedora@${line} "sudo podman rm -f telegraf"
          ssh -i ./id_rsa fedora@${line} "sudo podman container checkpoint influxdb --tcp-established -e /home/fedora/MVAC/export.tar.gz"
        fi
        set -e
      else
        ssh -i ./id_rsa fedora@${line} "sudo podman start influxdb"
        ssh -i ./id_rsa fedora@${line} "sleep 10"
        ssh -i ./id_rsa fedora@${line} "sudo podman run -v /home/fedora/MVAC/telegraf.conf:/etc/telegraf/telegraf.conf:Z -d --name telegraf --net=container:influxdb docker.io/library/telegraf:1.18"
        ssh -i ./id_rsa fedora@${line} "sleep 20"
        ssh -i ./id_rsa fedora@${line} "sudo podman rm -f telegraf"
        ssh -i ./id_rsa fedora@${line} "sudo podman container checkpoint influxdb --tcp-established -e /home/fedora/MVAC/export.tar.gz"
      fi
      scp -i ./id_rsa fedora@${line}:/home/fedora/MVAC/export.tar.gz /home/fedora/MVAC/export.tar.gz
      ssh -i ./id_rsa fedora@${line} "sudo podman rm -f influxdb"
      ssh -i ./id_rsa fedora@${line} "sudo podman volume prune -f"
    fi
  )
}

function migrate {
  set +e
  timestamp=$(cat ./bin/timestamp)
  bucket_id=$(sudo podman exec -it influxdb influx bucket list | grep bucket | awk '{print $1}')
  if [ -z "$bucket_id" ]
  then
    echo "InfluxDB down, restarting"
    sudo podman start influxdb
    sleep 5
    bucket_id=$(sudo podman exec -it influxdb influx bucket list | grep bucket | awk '{print $1}')
    echo $bucket_id
  fi
  sudo podman exec -it influxdb influx v1 dbrp create --db telegraf --rp telegraf --bucket-id ${bucket_id} --default
  sudo podman exec -it influxdb curl --get http://localhost:8086/query?db=telegraf --header "Authorization: Token mfndKMWpG8B3tVjjJYZm " --header "Accept: application/csv" --data-urlencode "q=SELECT time,host,max(available) FROM telegraf.telegraf.mem WHERE time > '${timestamp}'"
  
  if [ $? -eq 0 ]; then
    query=$(sudo podman exec -it influxdb curl --get http://localhost:8086/query?db=telegraf --header "Authorization: Token mfndKMWpG8B3tVjjJYZm " --header "Accept: application/csv" --data-urlencode "q=SELECT time,host,max(available) FROM telegraf.telegraf.mem WHERE time > '${timestamp}'" | awk -F',' '{print $4}')
  else
    sudo podman start influxdb
    sleep 20
    query=$(sudo podman exec -it influxdb curl --get http://localhost:8086/query?db=telegraf --header "Authorization: Token mfndKMWpG8B3tVjjJYZm " --header "Accept: application/csv" --data-urlencode "q=SELECT time,host,max(available) FROM telegraf.telegraf.mem WHERE time > '${timestamp}'" | awk -F',' '{print $4}')
    if [ $? -ne 0 ]; then
      echo "RESTARTING"
      bucket_id=$(sudo podman exec -it influxdb influx bucket list | grep bucket | awk '{print $1}')
      sudo podman exec -it influxdb influx v1 dbrp create --db telegraf --rp telegraf --bucket-id ${bucket_id} --default
      query=$(sudo podman exec -it influxdb curl --get http://localhost:8086/query?db=telegraf --header "Authorization: Token mfndKMWpG8B3tVjjJYZm " --header "Accept: application/csv" --data-urlencode "q=SELECT time,host,max(available) FROM telegraf.telegraf.mem WHERE time > '${timestamp}'" | awk -F',' '{print $4}')
    fi
  fi
  ip=$(echo $query | awk '{print $2}')
}

function move {
  rsync -ahI /home/fedora/MVAC fedora@${ip}:/home/fedora/MVAC
  sudo podman container checkpoint main-app -e /home/fedora/MVAC/main-export.tar.gz
  rsync -ah --progress /home/fedora/MVAC/main-export.tar.gz fedora@${ip}:/home/fedora/MVAC/main-export.tar.gz
  ssh fedora@${ip} "sudo podman restore -i /home/fedora/MVAC/main-export.tar.gz"
  ssh -i ./id_rsa fedora@${ip} "(sudo -u root crontab -l 2>/dev/null; echo "* * * * * ~/MVAC/trigger.shh") | sudo crontab -u root -"
  
  rm -r /home/fedora/MVAC
  (sudo crontab -u root -l | grep -v 'trigger.hh')  | sudo crontab -u root -
}

function query {
  timestamp_2=$(cat ./bin/timestamp_2)
  cp ./bin/results-current ./bin/results-previous
  sudo podman exec -it influxdb curl --get http://localhost:8086/query?db=telegraf --header "Authorization: Token mfndKMWpG8B3tVjjJYZm " --header "Accept: application/csv" --data-urlencode "q=SELECT time,host,max(available) FROM telegraf.telegraf.mem WHERE time > '${timestamp_2}' GROUP by host" > ./bin/results-current
  sed -i "1d" ./bin/results-current
  if [ $c -eq 1 ]
  then
    cp ./bin/results-current ./bin/results-list
  fi
}

function calc {
  > ./bin/calc
  while read line
  do
    ip1=$(echo $line | awk -F ',' '{print $4}')
    pre=$(cat ./bin/results-list | grep $ip1)
    first=$(echo $pre | awk -F ',' '{print int($5)}')
    second=$(echo $line | awk -F ',' '{print int($5)}')
    
    calc=$(expr $first - $second)
    echo "$first - $second = $calc"
    if [[ ${calc:0:1} == "-" ]]
    then
      newcalc=$(echo $calc | sed 's/^-\(.*\)/\1/')
      echo $newcalc >> ./bin/calc
    else
      echo $calc >> ./bin/calc
    fi
    
    sed -i -e "s/$pre/$line/" ./bin/results-list
    
    if [ $? -eq 1 ]
    then
      echo $line >> ./bin/results-list
    fi
    
  done < ./bin/results-current
  var=$(sort -nrk1 ./bin/calc | head -1)
  echo $var > ./bin/calc
  
  calc_file=$(cat ./bin/calc)
}

function restore {
  tput setaf 4
  echo "Restoring influx at host"
  tput setaf 7
  influxdb=$(sudo podman ps -a | grep -o influxdb | sed -e '1d')
  
  if [ "influxdb" = "$influxdb" ]
  then
    sudo podman rm -f influxdb
    sudo podman volume prune -f
    sleep 5
    sudo podman container restore --tcp-established -i /home/fedora/MVAC/export.tar.gz
  else
    sudo podman container restore --tcp-established -i /home/fedora/MVAC/export.tar.gz
  fi
}
set -e

file=/home/fedora/MVAC/export.tar.gz
if [ ! -f $file ]
then
  sudo podman run -d --name influxdb -p 8086:8086 \
  -e DOCKER_INFLUXDB_INIT_MODE=setup \
  -e DOCKER_INFLUXDB_INIT_USERNAME=telegraf \
  -e DOCKER_INFLUXDB_INIT_PASSWORD=telegraf \
  -e DOCKER_INFLUXDB_INIT_ORG=my-org \
  -e DOCKER_INFLUXDB_INIT_BUCKET=bucket \
  -e DOCKER_INFLUXDB_INIT_ADMIN_TOKEN=mfndKMWpG8B3tVjjJYZm \
  docker.io/library/influxdb:2.0.4
  sudo podman container checkpoint influxdb --tcp-established -e /home/fedora/MVAC/export.tar.gz
  sudo chown fedora:fedora /home/fedora/MVAC/export.tar.gz
  echo 0 > ./bin/counter
  if [ -f ./bin/calc* ]; then
    rm ./bin/calc*
  fi
  if [ -f ./bin/pickle.p ]; then
    rm ./bin/pickle.*
  fi
  > ./bin/results-list
  > ./bin/ip
fi

n=$(cat ./bin/counter)
m=$(( n + 1 ))
echo $m > ./bin/counter

#host_ip=$(curl -s ifconfig.me)   # use this if using public ip addresses
host_ip=$(hostname -I | awk '{print $1}')   # use this if using local ip addresses

FILES="./hosts.txt"

c=$(cat ./bin/counter)
if [ $c  -lt 3 ]
then
  ssh -i ./id_rsa fedora@172.16.0.70 ~/MVAC/stress.sh &
  ssh -i ./id_rsa fedora@172.16.0.71 ~/MVAC/stress.sh &
  date --rfc-3339=seconds | sed 's/ /T/' | sed 's/.\{6\}$//' | sed 's/$/Z/g' > ./bin/timestamp
  date --rfc-3339=seconds | sed 's/ /T/' | sed 's/.\{6\}$//' | sed 's/$/Z/g' > ./bin/timestamp_2
  LINES=$(cat $FILES)
  for line in $LINES
  do
    collect
  done
  restore
  migrate
  query
  
  if [ $c -gt 1 ]
  then
    calc
    py=$(python3 LA_with_barriers.py)
    echo $py
    nr=$(echo $py | awk 'END {print $NF}')
    cat ./hosts.txt | sed -n "${nr}p" > ./bin/ip
  fi
  echo $ip
fi

if [ $c -gt 2 ]
then
  r=$(cat ./hosts.txt | wc -l)
  r=$(expr $r \* 2)
  r=180
  date --rfc-3339=seconds | sed 's/ /T/' | sed 's/.\{6\}$//' | sed 's/$/Z/g' > ./bin/timestamp
  ssh -i ./id_rsa fedora@172.16.0.69 ~/MVAC/log.sh &
  ssh -i ./id_rsa fedora@172.16.0.70 ~/MVAC/log.sh &
  ssh -i ./id_rsa fedora@172.16.0.71 ~/MVAC/log.sh &
  for i in $( seq 1 $r )
  do
    date --rfc-3339=seconds | sed 's/ /T/' | sed 's/.\{6\}$//' | sed 's/$/Z/g' > ./bin/timestamp_2
    line=$(cat ./bin/ip)
    rc=$(cat ./bin/results-current)
    collect
    time (
      restore
      migrate
      query
      if [ -z "$rc" ]
      then
        echo "Restarting restore, migrate and query"
        restore
        migrate
        query
      fi
      calc
      py=$(python3 LA_with_barriers.py)
      echo $py
      nr=$(echo $py | awk 'END {print $NF}')
      cat hosts.txt | sed -n "${nr}p" > ./bin/ip
      echo $ip > ./bin/ip-2
    )
  done
  ip=$(cat ./bin/ip-2)
  echo $ip
  ssh -i ./id_rsa fedora@172.16.0.69 "pkill -f log.sh"
  ssh -i ./id_rsa fedora@172.16.0.70 "pkill -f log.sh"
  ssh -i ./id_rsa fedora@172.16.0.71 "pkill -f log.sh"
  ssh -i ./id_rsa fedora@172.16.0.70 "pkill -f stress.sh"
  ssh -i ./id_rsa fedora@172.16.0.71 "pkill -f stress.sh"
fi
