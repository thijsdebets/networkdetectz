# networkdetectz
Detect network devices for Domoticz installation. For Linux on Raspberry Pi

# created by Thijs Debets
Domoticz does not support dynamic detection of network devices.
This script will detect, register and track network devices.

nwd-arpscan.sh: First an arp-scan will be executed into arp-scan.raw
From the arp-scan file, the mac-addresses and currecnt ip-address is stored into 3 arp-arrays.
Per per mac address from the arp-array, it is checked if that mac address exists in arp-table.dom
If the mac address does not exits, oui.txt is used to get the name of the network device.
Then the device name (default to 'unknown device') is added to Domoticz devices list as on/off switch. The MAC address and Domoticz IDX are added to arp-table.dom
At last for every mac address in arp-table.dom, it is checked if there is a ip-address in arp-scan.rst. If an ip address exists, it is pinged. With result, the device is on. On no result, or no ip-address, the device is off. 
The device state is requested from Domoticz. On state change, Domoticz is updated.

#Setup
->install arp-scan:
>sudo apt-get install arp-scan

->Create a hardware or type Dummy, register the IDX in nwd-config
HardwareIDX=14
->Create a Hardware switch for NewDevicedFound and add the IDX in nwd-config
NewDevicesFoundIDX=111

-> set other configuration items in nwd-config:
DomoPIN='1234'
RetryAttempts=1                 # 3 = retry 4 times (5 minutes), 1 = retry 2 = 3 minutes
Log="Low"                       # High: Almost everything (huge logfile), Low: New devices and errors, Error: Only errors, Not: Nothing
NetworkTopIP="192"              # used to filet the relevant items from arpscan results

Copy nwd-config to nwd-config.own te prevent loss of settings in future updates (always validate config after updates):
cp nwd-config nwd-config.own



->create arp-detect.sh in /home/pi/domoticz/scripts with following lines:

#!/bin/bash

#run from crontab, dont use sudo crontab
/home/pi/domoticz/networkdetectz/nwd-arpscan.sh
cp /home/pi/domoticz/networkdetectz/data/arp-scan.raw /home/pi/domoticz/scripts/arp-temp
cp /home/pi/domoticz/networkdetectz/data/arp-table.dom /home/pi/domoticz/www/devices.txt
cat /home/pi/domoticz/networkdetectz/data/nwd.log >> /home/pi/domoticz/www/devices.txt


-> make file executable
>chmod 777 /home/pi/domoticz/scripts/arp-detect.sh

->add arp-detect to crontab:
>crontab -e
*/1 * * * * /home/pi/domoticz/scripts/arp-detect.sh >> /dev/null 2>&1

