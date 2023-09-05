#!/bin/bash
# This is a script for upgrading the EdgeRouter X firmware from the CLI.
# It is intended to be run on a fresh install of EdgeRouter X (no configuration)
# with a default password and a default IP address.
# It will:
# 1) Upgrade the device to the (latest) specified firmware version
# 2) Apply the given config file, optionally generating a new subnet
# 3) reboot
# 4) print the new IP address and the WebUI URL

# This script requires the following packages:
# - sshpass

# This script requires the following files in the local directory:
# - settings.ini
# - firmware/<firmware>
# - config/config.boot

# settings.ini contains the following variables:
# - firmwareVersion
# - deviceIP
# - sshOpts

firmware=$(basename $(ls -1 ./firmware/*$firmwareVersion*))
config=$(basename $(ls -1 ./config/config.boot))
deviceIP="";

# Print help message
print_help() {
    echo "Usage: ./setup.sh [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  -h, --help       Display this help message and exit."
    echo "  -c, --config     Specify a custom config file."
    echo "  -s, --shutdown   Shut the device down after setup."
    echo "  --no-config      Do not apply a config file."
    echo "  --no-firmware    Do not upgrade the firmware."
    echo ""
    echo "Example:"
    echo "  ./setup.sh --config config-10.144.216.boot"
}

# Log a message with a timestamp
log() {
    printf "[$(date +"%Y-%m-%d %H:%M:%S")] $1\n"
}

# Ensure that all dependencies are installed
check_dependencies() {
    if ! command -v sshpass &> /dev/null; then
        echo "sshpass is not installed. Please install it and try again."
        exit 1
    fi
}

load_settings() {
    . ./settings.ini

    deviceIP=$defaultIP
}

# Check if all required files are present
check_files() {
    if [ ! -f ./settings.ini ]; then
        log "Missing settings file!"
        exit 1
    fi

    if [[ "$firmware" == "null" ]]; then
        return
    else
        if [ ! -f ./firmware/$firmware ]; then
            log "Specified firmware file ($firmware) not found!"
            exit 1
        fi
    fi


    if [[ "$config" == "null" ]]; then
        return
    else
        if [ ! -f ./config/$config ]; then
            log "Config file ($config) not found!"
            exit 1
        fi    
    fi
}

# Wait for the device to come online
# Pings the device every second until it responds
# $1: IP address to ping
wait_for_ping() {
    local ip=$1
    local counter=0
    local print_interval=3

    log "Waiting for device to come online..."

    while ! ping -c1 $ip &>/dev/null; do
        counter=$((counter + 1))
        
        if ((counter % print_interval == 0)); then
            log "Device is not online yet ..."
        fi

        sleep 1
    done

    log "Device is online!"
}

# Upgrade the firmware
# Will upgrade the firmware if the specified version if newer than the current version
upgrade_firmware() {
    log "==== Firmware Upgrade ===="
    if [[ "$firmware" == "null" ]]; then
        log "--no-firmware specified, skipping firmware update ..."
        return
    fi

    log "Using firmware: $firmware"

    log "Checking firmware version ..."
    local currentVersion=$(sshpass -p "ubnt" ssh $sshOpts ubnt@$deviceIP $run show version 2>&1 | grep 'Version' | awk '{ print $2 }')

    if [ "$currentVersion" != "$firmwareVersion" ]; then
        log "Upgrading firmware to $firmwareVersion (current: $currentVersion)..."
        sshpass -p "ubnt" scp $sshOpts ./firmware/$firmware ubnt@$deviceIP:/tmp
        sshpass -p "ubnt" ssh $sshOpts ubnt@$deviceIP $run add system image /tmp/$firmware > /dev/null 2>&1
        sshpass -p "ubnt" ssh $sshOpts ubnt@$deviceIP sudo /sbin/reboot
        
        log "Rebooting ..."
        sleep 3

        wait_for_ping $deviceIP
    else
        log "No upgrade needed, device is running latest firmware ($currentVersion)"
    fi

    log "Firmware upgrade done!"
}

# Run the configuration script
# Will copy the config file to the device, apply it and reboot
# If --no-config is specified, it will skip this step
run_configure() {
    log "==== Configuration ===="
    if [[ "$config" == "null" ]]; then
        log "--no-config specified, skipping config ..."
        return
    fi

    if [[ "$config" != "config.boot" ]]; then
        log "Using custom config: $config"
    else
        log "Using default config: $config"
        log "Generating new settings ..."
        x=$(shuf -i 0-254 -n 1)
        y=$(shuf -i 0-254 -n 1)
        cp ./config/$config ./config/config-10.$x.$y.boot
        sed -i "s/$defaultSubnet/10.$x.$y/g" ./config/config-10.$x.$y.boot
        config="config-10.$x.$y.boot"
        log "New subnet: 10.$x.$y.0/24"
        log "New config: ./config/$config"
    fi

    deviceIP=$(grep -oE -m 1 '10\.[0-9]{1,3}\.[0-9]{1,3}\.1' ./config/$config)
    
    log "Copying config ..."
    sshpass -p "ubnt" scp $sshOpts ./config/$config ubnt@$deviceIP:/tmp/config.boot > /dev/null 2>&1
    
    apply_config

    log "Waiting for device to reboot ..."
    while ping -c1 $deviceIP &>/dev/null; do
        sleep 1
    done

    log "Add a static IP address to your interface, e.g. ${deviceIP%.*}.2/24"
    log "Then switch to a LAN port, e.g. eth1"
    
    wait_for_ping $deviceIP

    log "Configuration done!"
}

# Will copy the config file to the device and apply it and reboot
apply_config() {
    sshpass -p "ubnt" scp $sshOpts ./apply-config.sh ubnt@$deviceIP:/tmp
    sshpass -p "ubnt" ssh $sshOpts ubnt@$deviceIP sudo /bin/touch /root.dev/www/eula

    log "Applying config and rebooting ..."
    sshpass -p "ubnt" ssh $sshOpts ubnt@$deviceIP 'sudo /bin/vbash /tmp/apply-config.sh &> /dev/null < /dev/null & exit' > /dev/null 2>&1
    sleep 5
}

main() {
    log "==================================="
    log "==== EdgeRouter X Setup Script ===="
    log "==================================="
    log "Checking dependencies ..."
    check_dependencies

    log "Checking files ..."
    check_files

    log "Loading settings ..."
    load_settings

    log "Configuring EdgeRouter X ..."
    log "Default IP-address: $deviceIP"
    
    sleep 1

    log "==== Starting setup ===="
    # Wait for the device to come online
    wait_for_ping $deviceIP

    run=/opt/vyatta/bin/vyatta-op-cmd-wrapper
    mac=$(sshpass -p "ubnt" ssh $sshOpts ubnt@$deviceIP $run show interfaces ethernet switch0 2>&1 | grep 'link/ether' | awk '{ print $2 }')
    log "Device MAC-address: $mac"

    # Upgrade firmware, if needed
    upgrade_firmware

    # Apply config, if needed
    run_configure

    log "==== Setup done ===="
    log "Device IP-address: $deviceIP, Subnet: $deviceIP/24, MAC: $mac"
    log "Web UI: https://$deviceIP"

    if [[ "$shutdown" == true ]]; then
        log "Shutting device down ..."
        sshpass -p "ubnt" ssh $sshOpts ubnt@$deviceIP sudo /sbin/shutdown -h now > /dev/null 2>&1

        while ping -c1 $deviceIP &>/dev/null; do
            sleep 1
        done

        log "Device has been shut down."
    else 
        log "You can now shut the device down."
        log "After that, you can connect the device to your network."
    fi

    exit 0
}

# Parse arguments
while [[ "$#" -gt 0 ]]; do
    case $1 in
        -h|--help)
            print_help
            exit 0
            ;;
        -c|--config)
            if [[ -n "$2" ]]; then
                config="$2"
                shift
            else
                echo "Error: No config file specified."
                exit 1
            fi
            ;;
        -s|--shutdown)
            shutdown=true
            ;;
        --no-firmware)
            firmware="null"
            ;;
        --no-config)
            config="null"
            ;;
        *)
            echo "Unknown option: $1"
            print_help
            exit 1
            ;;
    esac
    shift
done

main
