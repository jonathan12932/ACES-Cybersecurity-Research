#!/bin/bash

# Set the base directory to collect zip files by IP
base_dir="/home"  # Directory where ExternalIP_x folders are located
all_zips_dir="${base_dir}/all_zips"

# Create a base directory to store all ZIP files
sudo mkdir -p "$all_zips_dir"

# Function to collect zip files from a specific ExternalIP directory
collect_zips() {
    local ip_dir="$1"
    local ip_number="$2"
    local target_dir="${all_zips_dir}/ExternalIP_${ip_number}"

    echo "Collecting zip files from $ip_dir..."

    # Check if the source directory exists
    if [ -d "$ip_dir" ]; then
        # Create target directory if it doesn't exist
        sudo mkdir -p "$target_dir"

        # Copy all zip files from the source directory to the target directory
        sudo cp "$ip_dir"/*.zip "$target_dir/"
        echo "Zip files collected to $target_dir"
    else
        echo "Directory $ip_dir does not exist. Skipping..."
    fi
}

# Loop through each ExternalIP directory and collect zip files
for i in {1..5}; do
    ip_dir="${base_dir}/ExternalIP_${i}/MITM/data_zips"
    collect_zips "$ip_dir" "$i"
done

echo "All zip files have been collected into $all_zips_dir"
