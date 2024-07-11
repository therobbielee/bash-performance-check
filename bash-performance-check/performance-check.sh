#!/usr/bin/env bash

source .env

#Check system load
check_load() {
  error_message=""
  uptime=$(uptime)
  load1=$(echo "$uptime" | awk -F 'load average:' '{print $2}' | awk '{print $1}' | awk -F '.' '{print $1}' | sed 's_,__')
  load1_decimal=$(echo "$uptime" | awk -F 'load average:' '{print $2}' | awk '{print $1}' | awk -F '.' '{print $2}' | sed 's_,__')
  load2=$(echo "$uptime" | awk -F 'load average:' '{print $2}' | awk '{print $2}' | awk -F '.' '{print $1}' | sed 's_,__')
  load2_decimal=$(echo "$uptime" | awk -F 'load average:' '{print $2}' | awk '{print $1}' | awk -F '.' '{print $2}' | sed 's_,__')
  load3=$(echo "$uptime" | awk -F 'load average:' '{print $2}' | awk '{print $3}' | awk -F '.' '{print $1}' )
  load3_decimal=$(echo "$uptime" | awk -F 'load average:' '{print $2}' | awk '{print $1}' | awk -F '.' '{print $2}' | sed 's_,__')

  if [ "$load1" -gt "$load_5m_threshold" ]; then
    error_message+="Load (5m) too high: $load1.$load1_decimal\n"
  fi

  if [ "$load2" -gt "$load_10m_threshold" ]; then
    error_message+="Load (10m) too high: $load2.$load2_decimal\n"
  fi

  if [ "$load3" -gt "$load_15m_threshold" ]; then
    error_message+="Load (15m) too high: $load3.$load3_decimal\n"
  fi
}

#Check used RAM
check_memory() {
  total_mem=$(free | grep Mem | awk -F 'Mem:' '{print $2}' | awk '{print $1}')
  used_mem=$(free | grep Mem | awk -F 'Mem:' '{print $2}' | awk '{print $2}')

  percentage_used_mem=$(echo "scale=2; $used_mem / $total_mem * 100" | bc | cut -f1 -d ".")

  if [ "$percentage_used_mem" -gt "$ram_usage_threshold" ]; then
    error_message+="RAM usage above limit: $percentage_used_mem%\n"
  fi

}

#Check CPU % used
check_cpu_perc() {
  cpu_used_percentage=$(top -bn1 | grep "Cpu(s)" | sed "s/.*, *\([0-9.]*\)%* id.*/\1/" | awk '{print 100 - $1}' | cut -f1 -d ".")

  if [ "$cpu_usage_threshold" -gt "$cpu_used_percentage" ]; then
    error_message+="CPU usage above limit: $cpu_used_percentage%\n"
  fi
}

#Check if RAID is degraded
check_raid() {
  raid_status=$(grep "\[.*_-*\]" /proc/mdstat -c)

  if [ "$raid_status" -gt 0 ]; then
    error_message+="RAID is degraded\n"
  fi
}

#Check % used on each disk partition
check_disk_perc() {
  for part in $(df -hl | grep -v 'overlay' | awk -F '%' '{print $2}' | grep /);
  do
    disk_used=$(df -h $part | grep $part | awk -F ' ' '{print $5}' | cut -f1 -d "%")

    if [ "$disk_used" -gt "$disk_usage_threshold" ]; then
#      error_message+="Disk usage above threshold: $part ($disk_used%)\n"
      error_message+="Disk $part is $disk_used% full\n"
    fi
  done
}

#Check if ZFS pool is healthy
check_zfs_pool() {
  zpool list -H -o name | while IFS= read -r pool_name;
  do
    state=$(zpool status "$pool_name" | grep state | awk -F 'state: ' '{print $2}')
      if ! [ "$state" == "ONLINE" ]; then
        error_mesage+="$pool_name is $state\n"
      fi
  done
}

#Send notification to ntfy
send_ntfy() {
  if [[ "$error_message" && "$ntfy_priority" && "$ntfy_url" && "$ntfy_topic" ]]; then
    if [[ "$ntfy_user" && "$ntfy_password" ]]; then

	curl -H "Content-Type: application/json" \
	     -u "$ntfy_user:$ntfy_password" \
	     -d "$(ntfy_message)" \
	     $ntfy_url

    elif [[ -v "$ntfy_accesstoken" ]]; then

	curl -H "Content-Type: application/json" \
	     -H "Authorization: Bearer $ntfy_accesstoken" \
	     -d "$(ntfy_message)" \
	     $ntfy_url

    fi
  fi
}

#Send notification to Pushover
send_pushover() {
  if [[ "$error_message" && "$pushover_userkey" && "$pushover_apptoken" ]]; then
        curl -s --form-string "token=$pushover_apptoken" --form-string "user=$pushover_userkey" --form-string "message=$(echo -e $error_message)" https://api.pushover.net/1/messages.json
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
  "title": "System Checkup",
  "message": "$error_message"
}
EOF
}

send_ntfy
send_pushover

