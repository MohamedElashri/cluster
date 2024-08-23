#!/bin/bash

# Script name: n_rkhunter.sh
# Author: Mohamed Elashri

# Color definitions
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# HTML color definitions
HTML_RED='#FF0000'
HTML_GREEN='#00FF00'
HTML_YELLOW='#FFFF00'
HTML_BLUE='#0000FF'

# Load environment variables
if [ -f ".env" ]; then
    source .env
else
    echo -e "${RED}Error: .env file not found${NC}" >> n_rkhunter.log
    exit 1
fi

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to check and install dependencies
check_and_install_dependencies() {
    local dependencies=("jq" "curl")
    local missing_deps=()

    for dep in "${dependencies[@]}"; do
        if ! command_exists "$dep"; then
            missing_deps+=("$dep")
        fi
    done

    if [ ${#missing_deps[@]} -ne 0 ]; then
        echo -e "${YELLOW}The following dependencies are missing: ${missing_deps[*]}${NC}"
        echo -e "${BLUE}Attempting to install missing dependencies...${NC}"
        
        # Update package lists
        sudo apt-get update

        for dep in "${missing_deps[@]}"; do
            echo -e "${BLUE}Installing $dep...${NC}"
            if sudo apt-get install -y "$dep"; then
                echo -e "${GREEN}Successfully installed $dep${NC}"
            else
                echo -e "${RED}Failed to install $dep${NC}"
                echo -e "$(date): ${RED}Error: Failed to install $dep${NC}" >> n_rkhunter.log
                exit 1
            fi
        done
    else
        echo -e "${GREEN}All required dependencies are installed.${NC}"
    fi
}

# Function to install or update rkhunter
install_or_update_rkhunter() {
    if ! command_exists rkhunter; then
        echo -e "${YELLOW}rkhunter not found. Installing...${NC}"
        sudo apt-get update && sudo apt-get install -y rkhunter
        if [ $? -ne 0 ]; then
            echo -e "$(date): ${RED}Error: Failed to install rkhunter${NC}" >> n_rkhunter.log
            exit 1
        fi
    else
        echo -e "${BLUE}Checking for rkhunter updates...${NC}"
        sudo apt-get update && sudo apt-get install --only-upgrade rkhunter
        if [ $? -ne 0 ]; then
            echo -e "$(date): ${YELLOW}Warning: Failed to update rkhunter${NC}" >> n_rkhunter.log
        else
            echo -e "${GREEN}rkhunter updated successfully${NC}"
        fi
    fi
}

# Check and install dependencies
check_and_install_dependencies

# Install or update rkhunter
install_or_update_rkhunter

# Update rkhunter database
echo -e "${BLUE}Updating rkhunter database...${NC}"
sudo rkhunter --update
if [ $? -ne 0 ]; then
    echo -e "$(date): ${YELLOW}Warning: Failed to update rkhunter database${NC}" >> n_rkhunter.log
else
    echo -e "${GREEN}rkhunter database updated successfully${NC}"
fi

# Run rkhunter and capture output
echo -e "${BLUE}Running rkhunter check...${NC}"
rkhunter_output=$(sudo rkhunter --check --skip-keypress --report-warnings-only)

# Escape special characters for HTML
html_escape() {
    echo "$1" | sed 's/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g; s/"/\&quot;/g; s/'"'"'/\&#39;/g'
}


# Add system information
hostname=$(hostname)
kernel_version=$(uname -r)
os_info=$(cat /etc/os-release | grep PRETTY_NAME | cut -d '"' -f 2)
rkhunter_version=$(rkhunter --version | head -n 1)

system_info="## System Information\n\n"
system_info+="| Info | Value |\n|------|-------|\n"
system_info+="| Hostname | <span style=\"color: $HTML_BLUE;\">$hostname</span> |\n"
system_info+="| Kernel Version | <span style=\"color: $HTML_BLUE;\">$kernel_version</span> |\n"
system_info+="| OS | <span style=\"color: $HTML_BLUE;\">$os_info</span> |\n"
system_info+="| RKHunter Version | <span style=\"color: $HTML_BLUE;\">$rkhunter_version</span> |\n\n"

# Create raw output section
raw_output="## Raw RKHunter Output\n\n\`\`\`\n$(html_escape "$rkhunter_output")\n\`\`\`"


# Get current date
current_date=$(date +"%m/%d/%Y")
filename_date=$(date +"%Y%m%d")


# Get current date
current_date=$(date +"%m/%d/%Y")
filename_date=$(date +"%Y%m%d")

# Prepare HTML content
html_content="<style>
body { font-family: Arial, sans-serif; }
table { border-collapse: collapse; width: 100%; }
th, td { border: 1px solid #ddd; padding: 8px; text-align: left; }
th { background-color: #f2f2f2; }
pre { background-color: #f5f5f5; padding: 10px; white-space: pre-wrap; word-wrap: break-word; }
</style>

$system_info\n$raw_output"


# Function to send email
send_email() {
    email_subject="n_rkhunter Results $current_date"
    
    # Encode email body for curl
    encoded_body=$(echo -n "$html_content" | jq -sRr @uri)

    # Send email using curl
    if curl -s --url "$SMTP_URL" \
         --user "$SMTP_USER:$SMTP_PASS" \
         --mail-from "$SMTP_FROM" \
         --mail-rcpt "$SMTP_TO" \
         --ssl-reqd \
         -H "Content-Type: text/html" \
         -T - <<EOF
Subject: $email_subject
From: $SMTP_FROM
To: $SMTP_TO
Content-Type: text/html

$html_content
EOF
    then
        echo -e "$(date): ${GREEN}Email sent successfully${NC}" >> n_rkhunter.log
    else
        echo -e "$(date): ${RED}Error: Failed to send email${NC}" >> n_rkhunter.log
    fi
}

# Function to store results locally
store_locally() {
    results_dir="./results"
    mkdir -p "$results_dir"
    
    # Create new file
    echo -e "$html_content" > "$results_dir/rkhunter_$filename_date.html"
    
    # Remove old files if more than 30
    file_count=$(ls -1 "$results_dir"/rkhunter_*.html | wc -l)
    if [ "$file_count" -gt 30 ]; then
        ls -1t "$results_dir"/rkhunter_*.html | tail -n +31 | xargs rm -f
    fi
    
    echo -e "$(date): ${GREEN}Results stored locally${NC}" >> n_rkhunter.log
}

# Check command line argument and execute appropriate function
if [ "$1" = "email" ]; then
    send_email
elif [ "$1" = "local" ]; then
    store_locally
else
    echo -e "${YELLOW}Usage: $0 [email|local]${NC}"
    echo -e "  ${BLUE}email${NC}: Send results via email"
    echo -e "  ${BLUE}local${NC}: Store results in local HTML files"
    exit 1
fi

# Print a summary to console
echo -e "${BLUE}RKHunter Check Summary:${NC}"
echo "$rkhunter_output"
