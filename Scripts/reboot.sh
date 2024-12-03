#!/bin/bash

# Function to clear IP rules
clear_ip_rules() {
    echo "Clearing IP rules..."
    sudo bash /home/clearIPRules.sh
}

# Function to apply required firewall rules
apply_firewall_rules() {
    echo "Applying required firewall rules..."
    sudo modprobe br_netfilter
    sudo sysctl -p /etc/sysctl.conf
    sudo bash /home/required_firewall_rules.sh
}

stop_and_delete_containers() {
    # Get the list of all LXC containers (both running and stopped)
containers=$(sudo lxc-ls -f | awk 'NR>1 {print $1}')

# Loop through each container
  for container in $containers; do
      echo "Stopping container: $container"
      sudo lxc-stop -n $container 2>/dev/null  # Stop the container (ignore error if already stopped)

      echo "Deleting container: $container"
      sudo lxc-destroy -n $container  # Delete the container
  done

  echo "All containers have been deleted."
}

clear_pm2_processes() {
    # Stop all PM2 processes
    sudo pm2 stop all

    # Delete all PM2 processes from the list
    sudo pm2 delete all

    # Optionally, you can also save the PM2 list to reset the process list completely
    sudo pm2 save
}

kill_recycle_processes() {
    # Get all process IDs related to recycle2Final.sh except for the grep command itself
    pids=$(ps aux | grep 'recycleFinal.sh' | grep -v grep | awk '{print $2}')

    if [ -z "$pids" ]; then
        echo "No processes found for recycle2Final.sh"
    else
        echo "Killing the following processes related to recycle2Final.sh:"
        echo "$pids"

        # Kill all the found processes
        for pid in $pids; do
            sudo kill "$pid"
            echo "Killed process with PID: $pid"
        done

        # Verify if any processes are still running
        remaining_pids=$(ps aux | grep 'recycleFinal.sh' | grep -v grep | awk '{print $2}')

        if [ -z "$remaining_pids" ]; then
            echo "All processes related to recycle2Final.sh have been successfully terminated."
        else
            echo "Some processes could not be killed: $remaining_pids"
            echo "You may need to use kill -9 for these processes."
        fi
    fi
}

kill_recycle_processe
# You can call the function like this:
clear_pm2_processes

# Main execution starts here
stop_and_delete_containers
clear_ip_rules
apply_firewall_rules

echo "Start?"
sleep 5

# Honeypot Start
cd /home/ExternalIP_1/MITM || exit 1
nohup sudo bash recycleFinal.sh honeypot1 128.8.238.199 8001 &
disown

cd /home/ExternalIP_2/MITM || exit 1
nohup sudo bash recycleFinal.sh honeypot2 128.8.238.39 8003 &
disown

cd /home/ExternalIP_3/MITM || exit 1
nohup sudo bash recycleFinal.sh honeypot3 128.8.238.56 8002 &
disown

cd /home/ExternalIP_4/MITM || exit 1
nohup sudo bash recycleFinal.sh honeypot4 128.8.238.115 8008 &
disown

cd /home/ExternalIP_5/MITM || exit 1
nohup sudo bash recycleFinal.sh honeypot5 128.8.238.116 8005 &
disown


echo "Reboot script execution completed."
