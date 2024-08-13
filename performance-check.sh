#!/usr/bin/env bash

source $(dirname "$0")/.env
error_message=""
hostname=$(cat /etc/hostname)
processes=()

#Check system load
check_load() {
  uptime=$(uptime)

  load_5m_integral=$(echo "$uptime" | awk -F 'load average:' '{print $2}' | awk '{print $1}' | awk -F '.' '{print $1}' | sed 's_,__')
  load_5m_fractional=$(echo "$uptime" | awk -F 'load average:' '{print $2}' | awk '{print $1}' | awk -F '.' '{print $2}' | sed 's_,__')
  load_5m_threshold_integral=$(echo "$load_5m_threshold" | cut -f1 -d '.')
  load_5m_threshold_fractional=$(echo "$load_5m_threshold" | awk -F '.' '{print $2}')

  load_10m_integral=$(echo "$uptime" | awk -F 'load average:' '{print $2}' | awk '{print $2}' | awk -F '.' '{print $1}' | sed 's_,__')
  load_10m_fractional=$(echo "$uptime" | awk -F 'load average:' '{print $2}' | awk '{print $2}' | awk -F '.' '{print $2}' | sed 's_,__')
  load_10m_threshold_integral=$(echo "$load_10m_threshold" | cut -f1 -d '.')
  load_10m_threshold_fractional=$(echo "$load_10m_threshold" | awk -F '.' '{print $2}')

  load_15m_integral=$(echo "$uptime" | awk -F 'load average:' '{print $2}' | awk '{print $3}' | awk -F '.' '{print $1}' )
  load_15m_fractional=$(echo "$uptime" | awk -F 'load average:' '{print $2}' | awk '{print $3}' | awk -F '.' '{print $2}' | sed 's_,__')
  load_15m_threshold_integral=$(echo "$load_15m_threshold" | cut -f1 -d '.')
  load_15m_threshold_fractional=$(echo "$load_15m_threshold" | awk -F '.' '{print $2}')

  if [[ "$load_5m_integral" -ge "$load_5m_threshold_integral" && "$load_5m_fractional" -ge "$load_5m_threshold_fractional" ]]; then
    error_message+="Load (5m) too high: $load_5m_integral.$load_5m_fractional\n"
    load_var="true"
  fi

  if [[ "$load_10m_integral" -ge "$load_10m_threshold_integral" && "$load_10m_fractional" -ge "$load_10m_threshold_fractional" ]]; then
    error_message+="Load (10m) too high: $load_10m_integral.$load_10m_fractional\n"
    load_var="true"
  fi

  if [[ "$load_15m_integral" -ge "$load_15m_threshold_integral" && "$load_15m_fractional" -ge "$load_15m_threshold_fractional" ]]; then
    error_message+="Load (15m) too high: $load_15m_integral.$load_15m_fractional\n"
    load_var="true"
  fi
}

#Check CPU % used
check_cpu_perc() {
  cpu_used_percentage=$(top -bn1 | grep "Cpu(s)" | sed "s/.*, *\([0-9.]*\)%* id.*/\1/" | awk '{print 100 - $1}' | cut -f1 -d ".")

  if [ "$cpu_used_percentage" -gt "$cpu_usage_threshold" ]; then
    error_message+="CPU usage above limit: $cpu_used_percentage%\n"
    cpu_var="true"
  fi
}

#Check used RAM
check_memory() {
  total_mem=$(free | grep Mem | awk -F 'Mem:' '{print $2}' | awk '{print $1}')
  used_mem=$(free | grep Mem | awk -F 'Mem:' '{print $2}' | awk '{print $2}')

  percentage_used_mem=$(echo "scale=2; $used_mem / $total_mem * 100" | bc | cut -f1 -d ".")

  if [ "$percentage_used_mem" -gt "$ram_usage_threshold" ]; then
    error_message+="RAM usage above limit: $percentage_used_mem%\n"
    mem_var="true"
  fi

}

#Check if RAID is degraded
check_raid() {
  raid_status=$(grep "\[.*_-*\]" /proc/mdstat -c)

  if [ "$raid_status" -gt 0 ]; then
    error_message+="RAID is degraded\n"
    raid_var="true"
  fi
}

#Check % used on each disk partition
check_disk_perc() {
  if [[ "$disk_usage_threshold_1" ]]; then
    if [[ "$disk_usage_threshold_1" == *","* ]]; then
      IFS=','
      read -r -a parts <<< "$disk_usage_threshold_1"
      for part in "${parts[@]}";
      do
        disk_used=$(df -h $part | awk -F ' ' '{print $5}' | grep "%" | grep -v "Use%" | cut -f1 -d "%")
        if [ "$disk_used" -gt "$disk_usage_threshold_1_limit" ]; then
          error_message+="Disk $part is $disk_used% full\n"
	  disk_var="true"
        fi
      done
    else
      disk_used=$(df -h $disk_usage_threshold_1 | awk -F ' ' '{print $5}' | grep "%" | grep -v "Use%" | cut -f1 -d "%")
      if [ "$disk_used" -gt "$disk_usage_threshold_1_limit" ]; then
        error_message+="Disk $disk_usage_threshold_1 is $disk_used% full\n"
	disk_var="true"
      fi
    fi
  fi

  if [[ "$disk_usage_threshold_2" ]]; then
    if [[ "$disk_usage_threshold_2" == *","* ]]; then
      IFS=','
      read -r -a parts <<< "$disk_usage_threshold_2"
      for part in "${parts[@]}";
      do
        disk_used=$(df -h $part | awk -F ' ' '{print $5}' | grep "%" | grep -v "Use%" | cut -f1 -d "%")
        if [ "$disk_used" -gt "$disk_usage_threshold_2_limit" ]; then
          error_message+="Disk $part is $disk_used% full\n"
 	  disk_var="true"
        fi
      done
    else
      disk_used=$(df -h $disk_usage_threshold_2 | awk -F ' ' '{print $5}' | grep "%" | grep -v "Use%" | cut -f1 -d "%")
      if [ "$disk_used" -gt "$disk_usage_threshold_2_limit" ]; then
        error_message+="Disk $disk_usage_threshold_2 is $disk_used% full\n"
	disk_var="true"
      fi
    fi
  fi

  if [[ "$disk_usage_threshold_3" ]]; then
    if [[ "$disk_usage_threshold_3" == *","* ]]; then
      IFS=','
      read -r -a parts <<< "$disk_usage_threshold_3"
      for part in "${parts[@]}";
      do
        disk_used=$(df -h $part | awk -F ' ' '{print $5}' | grep "%" | grep -v "Use%" | cut -f1 -d "%")
        if [ "$disk_used" -gt "$disk_usage_threshold_3_limit" ]; then
          error_message+="Disk $part is $disk_used% full\n"
	  disk_var="true"
        fi
      done
    else
      disk_used=$(df -h $disk_usage_threshold_3 | awk -F ' ' '{print $5}' | grep "%" | grep -v "Use%" | cut -f1 -d "%")
      if [ "$disk_used" -gt "$disk_usage_threshold_3_limit" ]; then
        error_message+="Disk $disk_usage_threshold_3 is $disk_used% full\n"
	disk_var="true"
      fi
    fi
  fi
}

#Check if ZFS pool is healthy
check_zfs_pool() {
  zpool list -H -o name | while IFS= read -r pool_name;
  do
    state=$(zpool status "$pool_name" | grep state | awk -F 'state: ' '{print $2}')
      if ! [ "$state" == "ONLINE" ]; then
        error_mesage+="$pool_name is $state\n"
	zfs_var="true"
      fi
  done
}

#Send notification to ntfy
send_ntfy() {
  if [[ "$error_message" && "$ntfy_priority" && "$ntfy_url" && "$ntfy_topic" ]]; then
    if [[ "$ntfy_user" && "$ntfy_password" ]]; then

	if [ "$ntfy_actions" == "true" ]; then
	  if [[ "$ntfy_action_password" && ("$cpu_var" == "true" || "$mem_var" == "true" || "$load_var" == "true") ]]; then
                ntfy_action_base64=$(echo -n "$ntfy_action_user:$ntfy_action_password" | base64)
		ntfy_action_auth=$(echo -n "Basic $ntfy_action_base64" | base64 | tr -d '=')
		curl -H "Content-Type: application/json" \
		     -H "Actions: http, Show processlist, $ntfy_action_url/$ntfy_action_topic/publish?message=Show+processes&priority=$ntfy_action_priority&auth=$ntfy_action_auth, method=GET" \
		     -u "$ntfy_user:$ntfy_password" \
		     -d "$(ntfy_message)" \
		     $ntfy_url
		     start_listener
	  elif [[ "$ntfy_action_accesstoken" && ("$cpu_var" == "true" || "$mem_var" == "true" || "$load_var" == "true") ]]; then
		ntfy_action_auth=$(echo -n "Bearer $ntfy_action_accesstoken" | base64 | tr -d '=')
		curl -H "Content-Type: application/json" \
		     -H "Actions: http, Show processlist, $ntfy_action_url/$ntfy_action_topic/publish?message=Show+processes&priority=$ntfy_action_priority&auth=$ntfy_action_auth, method=GET" \
		     -u "$ntfy_user:$ntfy_password" \
		     -d "$(ntfy_message)" \
		     $ntfy_url
		     start_listener
	  else
		curl -H "Content-Type: application/json" \
		     -u "$ntfy_user:$ntfy_password" \
		     -d "$(ntfy_message)" \
		     $ntfy_url
	  fi
	else
	  curl -H "Content-Type: application/json" \
	       -u "$ntfy_user:$ntfy_password" \
	       -d "$(ntfy_message)" \
	       $ntfy_url
        fi


    elif [[ "$ntfy_accesstoken" ]]; then
	if [ "$ntfy_actions" == "true" ]; then
	  if [[ "$ntfy_action_password" && ("$cpu_var" == "true" || "$mem_var" == "true" || "$load_var" == "true") ]]; then
                ntfy_action_base64=$(echo -n "$ntfy_action_user:$ntfy_action_password" | base64)
		ntfy_action_auth=$(echo -n "Basic $ntfy_action_base64" | base64 | tr -d '=')
		curl -H "Content-Type: application/json" \
		     -H "Actions: http, Show processlist, $ntfy_action_url/$ntfy_action_topic/publish?message=Show+processes&priority=$ntfy_action_priority&auth=$ntfy_action_auth, method=GET" \
		     -H "Authorization: Bearer $ntfy_accesstoken" \
		     -d "$(ntfy_message)" \
		     $ntfy_url
		     start_listener
	  elif [[ "$ntfy_action_accesstoken" && ("$cpu_var" == "true" || "$mem_var" == "true" || "$load_var" == "true") ]]; then
		ntfy_action_auth=$(echo -n "Bearer $ntfy_action_accesstoken" | base64 | tr -d '=')
		curl -H "Content-Type: application/json" \
		     -H "Actions: http, Show processlist, $ntfy_action_url/$ntfy_action_topic/publish?message=Show+processes&priority=$ntfy_action_priority&auth=$ntfy_action_auth, method=GET" \
		     -H "Authorization: Bearer $ntfy_accesstoken" \
		     -d "$(ntfy_message)" \
		     $ntfy_url
		     start_listener
	  else
		curl -H "Content-Type: application/json" \
                     -H "Authorization: Bearer $ntfy_accesstoken" \
                     -d "$(ntfy_message)" \
                     $ntfy_url
	  fi
	else
	  curl -H "Content-Type: application/json" \
               -H "Authorization: Bearer $ntfy_accesstoken" \
               -d "$(ntfy_message)" \
               $ntfy_url
	fi
    fi
  fi
}

#Send notification to Pushover
send_pushover() {
  if [[ "$error_message" && "$pushover_userkey" && "$pushover_apptoken" ]]; then
        curl -s --form-string "token=$pushover_apptoken" --form-string "user=$pushover_userkey" --form-string "message=$(echo -e $hostname : $error_message)" https://api.pushover.net/1/messages.json
  fi
}

send_processlist() {
  if [[ "$ntfy_priority" && "$ntfy_url" && "$ntfy_topic" ]]; then
    if [[ "$ntfy_user" && "$ntfy_password" ]]; then

	curl -H "Content-Type: application/json" \
	     -u "$ntfy_user:$ntfy_password" \
	     -d "$(ntfy_message_processes)" \
	     $ntfy_url

    elif [[ "$ntfy_accesstoken" ]]; then

	curl -H "Content-Type: application/json" \
	     -H "Authorization: Bearer $ntfy_accesstoken" \
	     -d "$(ntfy_message_processes)" \
	     $ntfy_url
    fi
  fi
}

poll_ntfy() {
  if [ "$ntfy_action_password" ]; then
    ntfy_action_base64=$(echo -n "$ntfy_action_user:$ntfy_action_password" | base64)
    ntfy_action_auth=$(echo -n "Basic $ntfy_action_base64" | base64 | tr -d '=')
    ntfy_poll=$(curl -H "Content-Type: application/json" -H "Accept: application/json" -X GET -s "$ntfy_action_url/$ntfy_action_topic/json?poll=1&auth=$ntfy_action_auth" | sed 's_Show+processlist__' | sed 's_Show+processes__' | grep "Show processes" | cut -f1 -d ',' | cut -f2 -d ':' | tr -d '"')
  elif [ "$ntfy_action_accesstoken" ]; then
    ntfy_action_auth=$(echo -n "Bearer $ntfy_action_accesstoken" | base64 | tr -d '=')
    ntfy_poll=$(curl -H "Content-Type: application/json" -H "Accept: application/json" -X GET -s "$ntfy_action_url/$ntfy_action_topic/json?poll=1&auth=$ntfy_action_auth" | sed 's_Show+processlist__' | sed 's_Show+processes__' | grep "Show processes" | cut -f1 -d ',' | cut -f2 -d ':' | tr -d '"')
  fi
  if [ "$ntfy_poll" ]; then
    echo "$ntfy_poll" | while IFS= read -r id ; do
      if [ $(cat $(dirname "$0")/log.txt | grep $id) ]; then
        continue;
      else
        echo "$id" >> $(dirname "$0")/log.txt
	process_list=$(top -bn1 -o %CPU -i | tail -n +7 | awk '{print $9"% ", $10"% ", $12}' | sed 's_%CPU%_CPU%_' | sed 's_%MEM%_MEM%_')
	while IFS= read -r process; do
	  processes+=$(echo "$process")
	  processes+=" \n"
	done <<< "$process_list"
	send_processlist
      fi
    done
  fi
}


#Run the functions based on their .env value
if [ "$load" == "true" ]; then
  check_load
fi

if [ "$memory" == "true" ]; then
  check_memory
fi

if [ "$cpu_perc" == "true" ]; then
  check_cpu_perc
fi

if [ "$raid" == "true" ]; then
  check_raid
fi

if [ "$disk_perc" == "true" ]; then
  check_disk_perc
fi

if [ "$zfs" == "true" ]; then
  check_zfs_pool
fi

ntfy_message() {
  cat <<EOF
{
  "topic": "$ntfy_topic",
  "tags": ["warning"],
  "title": "System Checkup: $hostname",
  "message": "$error_message"
}
EOF
}

ntfy_message_processes() {
  cat <<EOF
{
  "topic": "$ntfy_topic",
  "tags": ["magic_wand"],
  "title": "System Checkup: $hostname",
  "message": "$processes"
}
EOF
}

start_listener() {
while :
  do
    for i in $(seq 1 18); do
      poll_ntfy
      if [ -n "$processes" ]; then
        break;
      else
        sleep 5
      fi
    done
    break;
  done
}

send_ntfy
send_pushover

poll_ntfy
