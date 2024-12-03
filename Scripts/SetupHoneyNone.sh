#!/bin/bash

# Variables
BASE_DIR="/FakeCompany"  # Top-level directory name for the fake company
BASH_PROFILE_ENTRY="/etc/profile.d/protect_dir.sh"

# Define a date format for the file names
DATE=$(date +"%Y%m%d")

# Array of department names for directory levels
DEPARTMENTS=("HR" "Finance" "Marketing" "IT" "Sales" "Admin")

# Function to create nested directories and corporate files
create_nested_directories() {
    local current_dir="${BASE_DIR}"

    # Create the base directory
    mkdir -p "${BASE_DIR}"

    # Loop through the levels to create nested directories
    for department in "${DEPARTMENTS[@]}"; do
        current_dir="${current_dir}/${department}"  # Create subfolder for each department
        mkdir -p "${current_dir}"  # Create the current level directory
        chmod 755 "${current_dir}"  # Set permissions

        # Create files with corporate naming convention in the current level
        for j in {1..3}; do  # Create 3 files per level as an example
            # Corporate file naming convention: DEPARTMENT_YYYYMMDD_DESCRIPTION.txt
            file_name="${department}_${DATE}_file_${j}.txt"
            touch "${current_dir}/${file_name}"  # Create the file
            echo "File created: ${current_dir}/${file_name}"
        done
    done
}

# Create the nested directory structure and files
echo "Creating nested directory structure and corporate files..."
create_nested_directories  # This will use the defined department structure

# Function to set up bash profile for directory protection
setup_bash_profile() {
    cat <<EOF > ${BASH_PROFILE_ENTRY}
# Function to change to the protected directory with a password prompt
cd_protected() {
    local target_dir="\$1"
    local input_password
    local correct_password_found=false  # Variable to track if any password matches

    # Define an associative array for passwords
    declare -A PASSWORDS
    PASSWORDS["${BASE_DIR}/HR"]="first"
    PASSWORDS["${BASE_DIR}/HR/Finance"]="second"
    PASSWORDS["${BASE_DIR}/HR/Finance/Marketing"]="third"
    PASSWORDS["${BASE_DIR}/HR/Finance/Marketing/IT"]="fourth"
    PASSWORDS["${BASE_DIR}/HR/Finance/Marketing/IT/Sales"]="fifth"
    PASSWORDS["${BASE_DIR}/HR/Finance/Marketing/IT/Sales/Admin"]="sixth"

    # Convert relative paths to absolute paths using realpath
    target_dir=\$(realpath "\$target_dir" 2>/dev/null)

    # Allow access to the base directory without a password
    if [[ "\$target_dir" == "${BASE_DIR}" ]]; then
        builtin cd "\$@"
        return
    fi

    # Check if the target directory is a substring of any protected directory using grep
    for protected_dir in "\${!PASSWORDS[@]}"; do
        if echo "\$target_dir" | grep -q "\$protected_dir"; then
            echo "Enter password to access the directory:"
            read -s input_password

            # Loop through all passwords in the PASSWORDS array
            for dir_password in "\${PASSWORDS[@]}"; do
                if [[ "\$input_password" == "\$dir_password" ]]; then
                    correct_password_found=true
                    break
                fi
            done

            # If a correct password is found, change directory
            if \$correct_password_found; then
                builtin cd "\$@"
                return
            else
                # If the password is incorrect, deny access
                echo "Access denied."
                return 1
            fi
        fi
    done

    # Allow normal cd for non-protected directories
    builtin cd "\$@"
}

# Override the cd command to use the custom function
alias cd='cd_protected'
EOF

    # Make sure the script is sourced in each login shell
    chmod +x ${BASH_PROFILE_ENTRY}
}

# Set up the bash profile for directory protection

echo "Setup complete. A password is now required to access nested directories under ${BASE_DIR}, while the top-level directory is accessible without a password."
