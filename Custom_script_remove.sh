#!/bin/bash

# Initialize script and load variables
initialize_script() {
    local server_list="$1"
    local target_username="$2"

    if [[ $# -ne 2 ]]; then
        echo "Usage: $0 <server_list> <target_username>"
        exit 1
    elif [[ ! -f "$server_list" ]]; then
        echo "Error: Server list '$server_list' not found!"
        exit 1
    else
        readarray -t servers < "$server_list"
        target="$target_username"
        # If this is not configured, comment out the below line and uncomment the prompts.
        load_credentials "$HOME/credential.enc" "${ENCRYPTION_KEY:-}"
        AD_User="$username"
        # read -p "Enter Username: " AD_User
        AD_Pass="$password"
        # read -s -p "Enter Password: " AD_Pass
        output_file="servers_with_custom_scripts.txt"
        > "$output_file"
    fi
}

# Decrypt and load credentials from file, this requires setup ahead of time.
load_credentials() {
    local credentials_file="$1"
    local encryption_key="$2"
    if [[ ! -f "$credentials_file" ]]; then
        echo "Error: Credentials file '$credentials_file' not found!"
        exit 1
    elif [[ -z "$encryption_key" ]]; then
        echo "Error: ENCRYPTION_KEY is not set. Exiting."
        exit 1
    else
        eval "$(openssl enc -aes-256-cbc -d -salt -pbkdf2 -in "$credentials_file" -k "$encryption_key" 2>/dev/null)"
        if [[ -z "$username" || -z "$password" ]]; then
            echo "Error: Failed to load credentials. Check your encrypted file or decryption key."
            exit 1
        fi
    fi
}

# Function to handle exit status and log results for different file types.
exit_status() {
    local server="$1"
    local output_file="$2"
    local file_type="$3"
    local exit_code="$4"

    # Case statement using exit codes.
    case $exit_code in
        0) echo "$server - String '. ~/${file_type}.extra' found and file ${file_type}.extra would be removed." >> "$output_file";;
        1) echo "$server - File ${file_type}.extra does not exist." >> "$output_file";;
        2) echo "$server - String '. ~/${file_type}.extra' not found in ${file_type}." >> "$output_file";;
        3) echo "$server - $target has not logged in to $server." >> "$output_file";;
        4) echo "$server - User $target not found." >> "$output_file";;
        5) echo "$server - $server unreachable or offline." >> "$output_file";;
        *) echo "$server - Unknown error occurred with exit code: $exit_code." >> "$output_file";;
    esac
}

# Function to check for custom scripts and process results
check_file() {
    local server="$1"
    local user="$2"
    local password="$3"
    local target="$4"
    local output_file="$5"
    local file_type="$6"

    sshpass -p "$password" ssh -o StrictHostKeyChecking=no -t "$user@$server" bash -c "'
        echo \"$password\" | sudo -S su && echo &&
        (
            if sudo grep -q \"  . ~/${file_type}.extra\" /home/$target/${file_type} 2>/dev/null || sudo grep -q \"  . ~/${file_type}.extra\" /home/DOMAIN/$target/${file_type} 2>/dev/null; then
                echo \"Found text in ${file_type}\"
                if sudo [ -f /home/$target/${file_type}.extra ]; then
                    echo \"File /home/$target/${file_type}.extra exists, removing...\"
                    # sudo rm /home/$target/${file_type}.extra
                    # sudo sed -i \"/if \\[ -f ~\\/\\${file_type}\\.extra \\]; then/,/^fi\$/d\" /home/$target/${file_type}
                    exit 0
                elif sudo [ -f /home/DOMAIN/$target/${file_type}.extra ]; then
                    echo \"File /home/DOMAIN/$target/${file_type}.extra exists, removing...\"
                    # sudo rm /home/DOMAIN/$target/${file_type}.extra
                    # sudo sed -i \"/if \\[ -f ~\\/\\.${file_type}\\.extra \\]; then/,/^fi\$/d\" /home/DOMAIN/$target/${file_type}
                    exit 0
                else
                    echo \"File ${file_type}.extra does not exist.\"
                    exit 1
                fi
            else
                echo \"String . ~/${file_type}.extra not found in ${file_type}.\"
                exit 2
            fi
        )
        exit \$?'"
    exit_status "$server" "$output_file" "$file_type" "$?"
}

# Function to check if a user has logged in to server
check_login() {
    local server="$1"
    local user="$2"
    local password="$3"
    local target="$4"

    lastlog_output=$(sshpass -p "$password" ssh "$user@$server" lastlog -u "$target" 2>&1)
    if echo "$lastlog_output" | grep -q "Unknown user or range"; then
        echo "dne"
    elif echo "$lastlog_output" | grep -q "\*\*Never logged in\*\*"; then
        echo "false"
    else
        echo "true"
    fi
}

# Loop through the list of servers
initialize_script "$@"
for server in "${servers[@]}"; do
    echo "----------------------------------------------------------------------------------"
    echo "Checking if server $server is online..."

    # Check if the server is online
    if ping -c 1 "$server" &> /dev/null; then

        echo "Server $server is online."
        login_status=$(check_login "$server" "$AD_User" "$AD_Pass" "$target")
        if [[ "$login_status" == "true" ]]; then
            echo "User has logged in to $server. Checking for custom scripts..."
            check_file "$server" "$AD_User" "$AD_Pass" "$target" "$output_file" ".bash_logout"
            check_file "$server" "$AD_User" "$AD_Pass" "$target" "$output_file" ".profile"
        elif [[ "$login_status" == "false" ]]; then
            echo "User has not logged in to $server."
            exit_status "$server" "$output_file" "$null" "3"
        else
            echo "User $target not found."
            exit_status "$server" "$output_file" "$null" "4"    
        fi

    else
        echo "Server $server is offline. Skipping..."
        exit_status "$server" "$output_file" "$null" "5"
    fi

    echo "Done processing server: $server"
done
echo "Processing complete. Check the file '$output_file' for results."