# networkdetectz
Detect network devices for Domoticz installation. For Linux on Raspberry Pi

# created by Thijs Debets
Domoticz does not support dynamic detection of network devices.
This script will detect, register and track network devices.

nwd-arpscan.sh: First an arp-scan will be executed into arp-scan.raw
From the arp-scan file, the mac-addresses and currecnt ip-address is stored into 3 arp-arrays.
Per per mac address from the arp-array, it is checked if that mac address exists in arp-table.dom
If the mac address does not exits, snmp is used to get the name of the network device.
Then the device name (default to 'unknown device') is added to Domoticz devices list as on/off switch. The MAC address and Domoticz IDX are added to arp-table.dom
At last for every mac address in arp-table.dom, it is checked if there is a ip-address in arp-scan.rst. If an ip address exists, it is pinged. With result, the device is on. On no result, or no ip-address, the device is off. 
The device state is requested from Domoticz. On state change, Domoticz is updated.
 


