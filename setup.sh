#!/bin/bash
InstallDir=$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )

writesetting () {
		cp nwd-config.own nwd-config.tmp ; cat nwd-config.tmp | grep -v "${1}" > nwd-config.own
		echo "Configuring ${1}=${2}"
		echo "${1}=${2}" >> nwd-config.own
}

mkdir ${InstallDir}/data
mkdir ${InstallDIr}/log
mkdir /var/tmp/nwd


echo "Lets set up NWD"
echo " First we'll install arpscan, please confirm:" 
sudo apt-get install arp-scan

echo " Detecting Domoticz" 
if [ "$( sudo service domoticz status | grep -i 'Home Automation System' )" != "" ] ; then 
	echo "Domoticz detected, using Domoticz (UseDomoticz=YES)" 
	writesetting "UseDomoticz" "YES"







DomoIP='127.0.0.1'             # Domoticz default IP Address
DomoPort=$( sudo service domoticz status | grep -i ' -www ' | tr ' ' '\n' | grep -A1 "\-www" | tail -n1 )                # Domoticz Port
echo "Check Domoticz status"
DomoticzStatus=$(curl -m 10 -s "http://${DomoIP}:${DomoPort}/json.htm?type=command&param=getSunRiseSet" | grep "\"status\" : \"OK\"")
while [ "$DomoticzStatus" == "" ] ; do
    echo "Domoticz not found on ${DomoIP}:${DomoPort}"
	echo " Please provide ip-address" 
	read DomoIP
	echo " Please provide port" 
	read DomoPort
	DomoticzStatus=$(curl -m 10 -s "http://${DomoIP}:${DomoPort}/json.htm?type=command&param=getSunRiseSet" | grep "\"status\" : \"OK\"")

done
writesetting "DomoIP" "'${DomoIP}'" 
writesetting "DomoPort" "'${DomoPort}'" 

echo " Please provide pin" 
read DomoPin
writesetting "DomoPIN" "'${DomoPin}'" 


HardwareIDX=$( curl -m 10 -s "http://${DomoIP}:${DomoPort}/json.htm?type=command&param=addhardware&htype=15&port=1&name=NWDhardware&enabled=true" | tr ',' '\n' | grep idx | cut -d'"' -f4 )
writesetting "HardwareIDX" "${HardwareIDX}" 

NewDevicesFoundIDX=$( curl -m 10 -G "http://${DomoIP}:${DomoPort}/json.htm" --data "type=createvirtualsensor" --data "idx=$HardwareIDX" --data-urlencode "sensorname=New Device Detected"  --data "sensortype=6"  | tr ',' '\n' | grep idx | cut -d'"' -f4 )
writesetting "NewDevicesFoundIDX" "${NewDevicesFoundIDX}" 

NWDScriptRunning=$( curl -m 10 -G "http://${DomoIP}:${DomoPort}/json.htm" --data "type=createvirtualsensor" --data "idx=$HardwareIDX" --data-urlencode "sensorname=NWDScriptRunning"  --data "sensortype=6"  | tr ',' '\n' | grep idx | cut -d'"' -f4 )
writesetting "NWDScriptRunning" "${NWDScriptRunning}" 

else
	echo "Domoticz NOT detected (UseDomoticz=NO)" 
	writesetting "UseDomoticz" "NO"
fi



#todo
#run from crontab, dont use sudo crontab:
#crontab -e
#*/1 * * * * /home/pi/domoticz/scripts/arp-detect.sh >> /dev/null 2>&1

if [ "$( crontab -l | grep 'nwd-arpscan.sh'  | grep -v '^#' )" == "" ] ; then 
	echo "No entry yet"
	(crontab -l 2>/dev/null; echo "*/1 * * * * sleep 15 ; ${InstallDir}/nwd-arpscan.sh >> /dev/null 2>&1" ) | crontab -
else
    echo "entry already found" 
fi
 echo "Added scheduled entry to crontab: " 
crontab -l 


# add to sudo crontab
#sudo crontab -e
#@monthly     cd /usr/share/arp-scan/ && get-oui
#@monthly     cd /usr/share/arp-scan/ && get-iab

