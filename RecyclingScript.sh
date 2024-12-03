#!/bin/bash

# Function to print usage information
print_usage() {
    echo "Usage: $0 <base_container_name> <external_ip> <mitm_port>"
}

# Check if correct number of arguments are provided
if [ $# -ne 3 ]; then
    print_usage
    exit 1
fi

# Path to the log backup and cleanup script
directory="/FakeCompany"
log_script_path="./dataCollection2.sh"  # Adjust this path if needed

counter_file="IP_list.txt"  # File to store the current counter value# Load the counter value from the file if it exists
if [ -f "$counter_file" ]; then
    counter=$(<"$counter_file")  # Load the last saved counter value
else
    counter=1  # Start with counter at 1024 if no file exists
fi

cleanup() {
    echo "Cleaning up..."
    # Kill the background process
    if [[ -n "$preload_pid" ]]; then
        kill "$preload_pid" 2>/dev/null
    fi
    jobs -p | xargs -r kill  # Kill any other background jobs
    remove_existing
    sudo bash "$log_script_path"
    exit 0
}

trap cleanup SIGINT SIGTERM

# Assign arguments to variables
base_container_name=$1
external_ip=$2
mitm_port=$3
attacker_ip=""
curr_container_name=""
next_container_name=""

# Function to remove the container, networking rules, and MITM process
remove_existing() {

    echo "Removing existing container and rules for $curr_container_name"

    local current_container_ip=$(sudo lxc-info -n $curr_container_name -iH 2>/dev/null)

    # Clean up any existing rules for the attacker IP
    if [ -n "$attacker_ip" ]; then
        echo "Cleaning up iptables rules for attacker IP: $attacker_ip"
        sudo iptables -w --table nat --delete PREROUTING --source "$attacker_ip" --destination "$external_ip" --jump DNAT --to-destination "$current_container_ip"
        sudo iptables -w --table nat --delete PREROUTING --source "$attacker_ip" --destination "$external_ip" --protocol tcp --dport 22 --jump DNAT --to-destination "10.0.3.1:$mitm_port"
    fi

    if [ -n "$current_container_ip" ]; then
        sudo iptables -w -t nat -D PREROUTING -s 0.0.0.0/0 -d $external_ip -j DNAT --to-destination $current_container_ip 2>/dev/null
        sudo iptables -w -t nat -D POSTROUTING -s $current_container_ip -d 0.0.0.0/0 -j SNAT --to-source $external_ip 2>/dev/null
    fi

    sudo iptables -w -t nat -D PREROUTING -s 0.0.0.0/0 -d $external_ip -p tcp --dport 22 -j DNAT --to-destination "10.0.3.1:$mitm_port" 2>/dev/null
    sudo ip addr del $external_ip/24 dev eth3 2>/dev/null

    if sudo pm2 list | grep -q "$curr_container_name"; then
        echo "Stopping MITM process for $curr_container_name"
        sudo pm2 stop "$curr_container_name"
        sudo pm2 delete "$curr_container_name"
    fi

    sudo lxc-stop -n $curr_container_name -k 2>/dev/null
    sudo lxc-destroy -n $curr_container_name 2>/dev/null

    echo "Existing container, rules, and MITM removed."

    # Update the counter value in IP_list.txt
    echo "$counter" > "$counter_file"

    echo "Counter value $counter saved to $counter_file."

}

start_mitm() {

    echo "Starting MITM for $curr_container_name"

    local current_container_ip=$(sudo lxc-info -n $curr_container_name -iH 2>/dev/null)

    if sudo pm2 start mitm.js --name "$curr_container_name" -- -n "$curr_container_name" -i "$current_container_ip" -p $mitm_port --mitm-ip 10.0.3.1 --auto-access --auto-access-fixed 1 --debug; then
        echo "MITM server started successfully"
    else
        echo "Failed to start MITM server"
        exit 1
    fi
}

setup_networking() {

    local current_container_ip=$(sudo lxc-info -n $curr_container_name -iH 2>/dev/null)

    sudo ip link set eth3 up
    sudo ip addr add $external_ip/24 brd + dev eth3
    sudo iptables -w --table nat --insert PREROUTING --source 0.0.0.0/0 --destination $external_ip --jump DNAT --to-destination $current_container_ip
    sudo iptables -w --table nat --insert POSTROUTING --source $current_container_ip --destination 0.0.0.0/0 --jump SNAT --to-source $external_ip
    sudo iptables -w --table nat --insert PREROUTING --source 0.0.0.0/0 --destination $external_ip --protocol tcp --dport 22 --jump DNAT --to-destination "10.0.3.1:$mitm_port"
    sudo sysctl -w net.ipv4.ip_forward=1
}

# Function to start a recycling timer and repeat every 5 minutes
check_log_and_start_recycling_timer() {

    log_file="logs/authentication_attempts/${curr_container_name}.log"
    local current_container_ip=$(sudo lxc-info -n $curr_container_name -iH 2>/dev/null)

    while true; do
        sleep 1

        # Break if a termination signal has been received
        if [[ ! -z "$terminate_flag" ]]; then
            echo "Termination signal received. Exiting log check."
            break
        fi

        if [ -f "$log_file" ]; then
            if [ -s "$log_file" ]; then
                echo "Log file $log_file exists and is non-empty. Starting recycling timer..."

                # Extract the attacker's IP from the second field in the log file
                attacker_ip=$(awk -F';' '{print $2}' "$log_file" | head -1)

                if [ -n "$attacker_ip" ]; then
                    echo "Detected attacker IP: $attacker_ip"

                    # Allow traffic from the attacker IP
                    sudo iptables -w --table nat --insert PREROUTING --source $attacker_ip --destination $external_ip --jump DNAT --to-destination $current_container_ip

                    # Allow only the attacker to SSH on the MITM port
                    sudo iptables -w --table nat --insert PREROUTING --source $attacker_ip --destination $external_ip --protocol tcp --dport 22 --jump DNAT --to-destination "10.0.3.1:$mitm_port"

                    # Remove the rule that allows all connections (if it exists)
                    sudo iptables -w --table nat --delete PREROUTING --destination $external_ip --jump DNAT --to-destination $current_container_ip 2>/dev/null
                    sudo iptables -w --table nat --delete PREROUTING --destination $external_ip --protocol tcp --dport 22 --jump DNAT --to-destination "10.0.3.1:$mitm_port" 2>/dev/null

                    echo "Recycling timer started, allowing only the attacker IP: $attacker_ip"
                    start_recycling_timer
                    break
                else
                    echo "Could not detect attacker IP from the log file."
                fi
            else
                echo "Log file $log_file is empty. Continuing to check..."
            fi
        else
            echo "Log file $log_file does not exist yet. Continuing to check..."
        fi
    done
}

create_container() {

    local container_name=$1

    echo "Creating new container: $container_name"
    sudo lxc-create -t download -n "$container_name" -- -d ubuntu -r focal -a amd64
    sudo lxc-start -n "$container_name"
    sleep 10  # Wait for container to start
}

setup_firewall() {

    local container_name=$1

    echo "Setting up firewall for $container_name"
    sudo lxc-attach -n $container_name -- bash -c "apt update && apt install -y ufw"
    sudo lxc-attach -n $container_name -- bash -c "ufw allow 22/tcp && ufw --force enable"
}

setup_ssh() {

    local container_name=$1

    echo "Setting up SSH server $container_name"
    sudo lxc-attach -n $container_name -- bash -c "
        if ! dpkg -s openssh-server >/dev/null 2>&1; then
            apt-get update
            apt-get install -y openssh-server
        fi
    "
}

verify_ssh_setup() {

    local container_name=$1

    echo "Verifying SSH setup for $container_name"
    sudo lxc-attach -n $container_name -- bash -c "
        if dpkg -s openssh-server >/dev/null 2>&1; then
            echo 'SSH server is installed'
            if systemctl is-active --quiet ssh; then
                echo 'SSH service is running'
            else
                echo 'SSH service is not running'
                systemctl status ssh
            fi
        else
            echo 'SSH server is not installed'
        fi
    "
}

# Function to install Netdata inside the container
install_netdata() {

    local container_name=$1

    echo "Installing Netdata inside $container_name"
    #sudo lxc-attach -n $container_name -- bash -c "
        #wget -O /tmp/netdata-kickstart.sh https://get.netdata.cloud/kickstart.sh
        #yes | bash /tmp/netdata-kickstart.sh --stable-channel --claim-token Xaxob7L5aS9Lml5L18KOGQoU0CSURRXNui_8vVWik6-QckMjI9wNj0izlvyVTg-7Bhb_hTbyIsp9pGuQduJLnJztbcZDVfADH1Mi-OERljl09L42NafCGFn7iLQcoa3jACG2UDI --claim-rooms 1bafb91a-89af-4b1c-a194-93ee725492aa --claim-url https://app.netdata.cloud
    #"
}


# Function to setup honey
setup_honey() {

    local scenario=$1
    local container_name=$2

    case $scenario in
    Weak)
      cat setup_honey_weak.sh | sudo lxc-attach -n $container_name -- bash
      echo "Weak scenario selected and setup complete."
      ;;
    Medium)
      cat setup_honey_med.sh | sudo lxc-attach -n $container_name -- bash
      echo "Medium scenario selected and setup complete."
      ;;
    High)
      cat setup_honey_high.sh | sudo lxc-attach -n $container_name -- bash
      echo "High scenario selected and setup complete."
      ;;
    *)
      cat setup_honey_none.sh | sudo lxc-attach -n $container_name -- bash
      echo "No specific scenario selected (None)."
      ;;
    esac
}


# Countdown function
countdown() {
    secs=$1
    log_file="logs/logouts/${curr_container_name}.log"

    while [ $secs -gt 0 ]; do
        if [ -f "$log_file" ]; then
            if [ -s "$log_file" ]; then
                echo "Attacker has logged out. Exiting countdown and recycling..."
                break
            fi
        fi

        echo -ne "Recycling in $secs seconds...\033[0K\r"
        sleep 1
        : $((secs--))
    done
}

dataCounter=1

increment_counter() {
    counter=$((counter + 1))  # Increment the counter
    dataCounter=$((dataCounter + 1))  # Increment dataCounter

    # Check if counter has reached 10
    if [ "$dataCounter" -eq 10003 ]; then
        echo "Counter reached 10. Saving logs, clearing directories, and resetting counter."
        sudo bash "$log_script_path"
        dataCounter=1  # Reset the counter
    fi

    curr_scenario=$(select_random_scenario)
}


# Function to randomly select a scenario
select_random_scenario() {
    scenarios=("None" "Weak" "Medium" "High")
    selected_scenario=${scenarios[$RANDOM % ${#scenarios[@]}]}
    echo $selected_scenario
}

# Preload the next container in the background while the current one is running
preload_next_container() {

    # Increment the counter to generate the next container name
    increment_counter
    next_container_name="${base_container_name}_${curr_scenario}_$counter"

    echo "Preloading the next container: $next_container_name"

    (
        create_container "$next_container_name"
        setup_firewall "$next_container_name"
        setup_ssh "$next_container_name"
        verify_ssh_setup "$next_container_name"
        install_netdata "$next_container_name"
        setup_honey "$curr_scenario" "$next_container_name"
    ) &  # Run preloading in the background
    preload_pid=$!
}

# Function to check if the "FakeCompany" directory exists
check_fake_company_directory () {

    while ! sudo lxc-attach -n "$next_container_name" -- test -d "$directory"; do
        echo "Directory $directory not found in $next_container_name, checking again..."
        sleep 5  # Wait for 5 seconds before checking again
    done
    echo "Directory $directory found in $next_container_name!"
}

# Function to start recycling the current container
start_recycling_timer() {

    echo "Starting the recycling process for $curr_container_name."
    countdown 300

    # Remove the current container and rules
    remove_existing

    # Check for "FakeCompany" directory in the current container
    check_fake_company_directory
    curr_container_name="$next_container_name"

    # Start MITM and networking after the directory is confirmed
    start_mitm
    setup_networking

    # Preload the next container for future use
    preload_next_container

    # Call the log checking function to continue monitoring
    check_log_and_start_recycling_timer
}

# Start main execution
curr_scenario=$(select_random_scenario)
curr_container_name="${base_container_name}_${curr_scenario}_$counter"
remove_existing
create_container "$curr_container_name"
setup_firewall "$curr_container_name"
setup_ssh "$curr_container_name"
verify_ssh_setup "$curr_container_name"
install_netdata "$curr_container_name"
setup_honey "$curr_scenario" "$curr_container_name"
start_mitm
setup_networking

echo "$curr_container_name is fully set up and waiting for an attack."

# Preload the next container in the background
preload_next_container

# Start monitoring logs and recycling containers based on activity
check_log_and_start_recycling_timer
