# EdgeRouter X Config Script

This script aids in automating the setup of an EdgeRouter X. 
It will update the router with the latest firmware, restore a config, and configure the router with a new random subnet.

## Requirements

   - Linux (Should work under Unix, but not tested)
   - sshpass
   - An exported config from an EdgeRouter X with the latest firmware (run with --no-config and export the config from the web interface)

   Can be installed with:
   ```sh
   sudo apt install sshpass
   ```

## Usage

- Download the wanted / latest firmware from https://www.ui.com/download/software/er-x and place it in the firmware folder
- Connect your EdgeRouter X to port 0 (eth0) and configure your interface with a static IP-address of 192.168.1.2/24
- Adjust settings.ini
- Run ./setup.sh

### Arguments

| Argument | Description |
| ------ | ------ |
| -h, --help | Show help |
| -c, --config | Path to custom config file |
| --no-config | Do not restore a config |
| --no-firmware | Do not update the firmware |
| -s, --shutdown | Shut the router down after setup |

