#!/bin/bash
. ./settings.ini

interface=$(nmcli dev status | grep ethernet | awk '{ print $1 }')

run=/opt/vyatta/bin/vyatta-op-cmd-wrapper
cfg=/opt/vyatta/sbin/vyatta-cfg-cmd-wrapper


while ! ping -c1 $defaultip &>/dev/null
do
	echo "Ping to $defaultip failed"
	sleep 1
done

switchip=$(curl -k -s -q "$registeraddress?free=1&subnet=$switchsubnet")
mac=$(sshpass -p "ubnt" ssh $sshopts ubnt@$defaultip $run show interfaces ethernet switch0 2>&1 | grep 'link/ether' | awk '{ print $2 }')

echo "register $switchsubnet.$switchip with $mac"

curl -k -s -q "$registeraddress?register=edgerouter%20$mac&subnet=$switchsubnet&ip=$switchip" > /dev/null

echo "checking firmware version"
currentversion=$(sshpass -p "ubnt" ssh $sshopts ubnt@$defaultip $run show version 2>&1 | grep 'Version' | awk '{ print $2 }')

if [ "$currentversion" != "$firmwareversion" ]
then
	echo "upgrading firmware to $firmwareversion"
	sshpass -p "ubnt" scp $sshopts ./firmware/$firmware ubnt@$defaultip:/tmp

	sshpass -p "ubnt" ssh $sshopts ubnt@$defaultip $run add system image /tmp/$firmware

	sshpass -p "ubnt" ssh $sshopts ubnt@$defaultip sudo /sbin/reboot
	echo "rebooting ..."
	sleep 10
else
	echo "no firmware upgrade needed"
fi

while ! ping -c1 $defaultip &>/dev/null
do
	echo "Ping to $defaultip failed"
	sleep 1
done

echo "applying config"
###
sshpass -p "ubnt" scp $sshopts ./config/$config.$switchsubnet.$switchip ubnt@$defaultip:/tmp/config.boot
sshpass -p "ubnt" scp $sshopts ./apply-config.sh ubnt@$defaultip:/tmp
sshpass -p "ubnt" ssh $sshopts ubnt@$defaultip sudo /bin/touch /root.dev/www/eula
sshpass -p "ubnt" ssh $sshopts ubnt@$defaultip sudo /bin/vbash /tmp/apply-config.sh


