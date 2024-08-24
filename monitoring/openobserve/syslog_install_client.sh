#!/bin/bash

# Check if password is provided
if [ "$#" -ne 1 ]; then
    echo "Usage: $0 <password>"
    echo "Please provide the OpenObserve password as an argument."
    exit 1
fi

OPENOBSERVE_PASSWORD="$1"

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to install a package
install_package() {
    if command_exists apt-get; then
        sudo apt-get update
        sudo apt-get install -y "$1"
    elif command_exists yum; then
        sudo yum install -y "$1"
    else
        echo "ERROR: Unable to install packages. Neither apt-get nor yum found."
        exit 1
    fi
}

# Check and install syslog-ng if not present
if ! command_exists syslog-ng; then
    echo "syslog-ng not found. Installing..."
    install_package syslog-ng
fi

# Create the OpenObserve configuration file
CONFIG_FILE="/etc/syslog-ng/conf.d/openobserve.conf"
OPENOBSERVE_CONFIG=$(cat <<EOF
destination d_openobserve_http {
    http(
        url("https://logs.elashri.net/api/default/syslog-ng/_json")
        method("POST")
        user-agent("syslog-ng User Agent")
        headers("Content-Type: application/json")
        # body('{"stream":"syslog-ng","message":$(format-json --scope rfc5424 --exclude DATE --key ISODATE @timestamp=${ISODATE}),"host":"${HOST}"}')
        body('{"stream":"syslog-ng","host":"${HOST}","@timestamp":"${ISODATE}","message":"${MSGHDR}${MSG}","program":"${PROGRAM}","pid":"${PID}","priority":"${PRIORITY}"}')
        user("admin@example.com")
        password("$OPENOBSERVE_PASSWORD")
        timeout(10)
        accept-redirects(yes)
        tls(
            peer-verify(no)
        )
    );
};
log {
    source(s_src);
    destination(d_openobserve_http);
    flags(flow-control);
};
EOF
)

# Write the configuration to the file
echo "$OPENOBSERVE_CONFIG" | sudo tee "$CONFIG_FILE" > /dev/null

if [ $? -ne 0 ]; then
    echo "ERROR: Failed to write configuration file."
    exit 1
fi

echo "OpenObserve configuration file created at $CONFIG_FILE"

# Verify syslog-ng configuration
if ! sudo syslog-ng -s; then
    echo "ERROR: syslog-ng configuration test failed."
    exit 1
fi

# Restart syslog-ng service
if command_exists systemctl; then
    sudo systemctl restart syslog-ng
    if ! sudo systemctl is-active --quiet syslog-ng; then
        echo "ERROR: Failed to restart syslog-ng service."
        exit 1
    fi
elif command_exists service; then
    sudo service syslog-ng restart
    if ! service syslog-ng status | grep -q "is running"; then
        echo "ERROR: Failed to restart syslog-ng service."
        exit 1
    fi
else
    echo "ERROR: Unable to restart syslog-ng service. Neither systemctl nor service command found."
    exit 1
fi

echo "syslog-ng service restarted successfully."

# Test log generation
logger "Test message for OpenObserve via syslog-ng"

echo "Installation and configuration completed successfully."
echo "A test log message has been generated. Please check your OpenObserve dashboard to confirm receipt."
