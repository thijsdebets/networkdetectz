# networkdetectz
Detect network devices for Domoticz installation. For Linux on Raspberry Pi

# created by Thijs Debets
Domoticz does not support dynamic detection of network devices.
This script will detect, register and track network devices.

nwd-arpscan.sh: First an arp-scan will be executed into arp-scan.raw
From the arp-scan file, per mac address, it is checked if that mac address exists in arp-table.dom
If the mac address does not exits, the device name is added to Domoticz devices list as on/off switch. The MAC address and Domoticz IDX are added to arp-table.dom
At last for every mac address in arp-table.dom, it is checked if there is a ip-address in arp-scan.raw. If an ip address exists,the device is on. On no result, abd there is no respons to ping or BlueTooth, the device is off. 
The device state is requested from Domoticz. On state change, Domoticz is updated.

Bluetooth address can be registered in the bluetooth.dom file.

#Setup
->install arp-scan:
>sudo apt-get install arp-scan

->Create a hardware or type Dummy, register the IDX in nwd-config
HardwareIDX=999
->Create a Hardware switch for NewDevicedFound and add the IDX in nwd-config
NewDevicesFoundIDX=999
->Create a Harwdare switch for Running indicator, to see if the script is up. set this indicator on 'Off-delay' 10 minutes
NWDScriptRunning=999

-> set other configuration items in nwd-config:
DomoPIN='1234'
RetryAttempts=1                 # 3 = retry 4 times (5 minutes), 1 = retry 2 = 3 minutes
Log="Low"                       # High: Almost everything (huge logfile), Low: New devices and errors, Error: Only errors, Not: Nothing
NetworkTopIP="192"              # used to filet the relevant items from arpscan results

Any updates to the configuration file will be automtically copied to the nwd-config.own, also for future changes, nwd will use your local settings stored in nwd-config.own


-> make file executable
>chmod 777 /home/pi/domoticz/networkdetectz/nwd-arpscan.sh

->add nwd-arpscan to crontab:
>crontab -e
*/1 * * * * /home/pi/domoticz/networkdetectz/nwd-arpscan.sh >> /dev/null 2>&1

Make sur your arp-scan will be updated with manufaturer information. Add to sudo crontab:
>sudo crontab -e
@weekly     cd /usr/share/arp-scan/ && get-oui
@weekly     cd /usr/share/arp-scan/ && get-iab
