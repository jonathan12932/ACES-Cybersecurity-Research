#!/bin/bash

# Define the log file path
LOG_FILE="/home/lxc_list_log_hour.txt"

# Print the current date and time as a header for each entry
echo "----- $(date +'%Y-%m-%d %H:%M:%S') -----" >> "$LOG_FILE"

# Run 'sudo lxc-ls' and append the output to the log file
sudo lxc-ls >> "$LOG_FILE"

# Add a newline for readability
echo "" >> "$LOG_FILE"
