#!/bin/bash
#install arp-scan:
#sudo apt-get install arp-scan

#run from crontab, dont use sudo crontab:
#crontab -e
#*/1 * * * * /home/pi/domoticz/scripts/arp-detect.sh >> /dev/null 2>&1

# add to sudo crontab
#sudo crontab -e
#@monthly     cd /usr/share/arp-scan/ && get-oui
#@monthly     cd /usr/share/arp-scan/ && get-iab


#Configuration file for Domoticz NetworkDetectz
echo "Read configuration"
#--- Configuration ---#
cd "$(dirname "$0")"
InstallDir=$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )
#InstallDir=$(pwd)
#pwd
#echo "$InstallDir"
DomoIP='127.0.0.1'		# Domoticz IP Address
DomoPort='8080'			# Domoticz Port

#--- Update configuration ---#
while read confline ; do
	config=$(echo "$confline" | cut -d"=" -f1)
	if ! grep -q "$config" $InstallDir/nwd-config.own ; then
		echo "$confline" >> $InstallDir/nwd-config.own
	fi
done < $InstallDir/nwd-config
source $InstallDir/nwd-config.own

# not used:	curl -s "http://$DOMO_USER:$DOMO_PASS@$DomoIP:$DomoPort/json.htm?...
# used: 	curl -s "http://$DomoIP:$DomoPort/json.htm?...

#--- Initiation ---#
DataDir="$InstallDir/data"
LogDir="$InstallDir/log"
CurrentDateTime=$(date)
CurrentDateYmd=$(date +"%Y%m%d")
umask 000

#source $InstallDir/nwd-functions


# Check if Domoticz is online to continue, else suspend
echo "Check Domoticz status"
DomoticzStatus=$(curl -s "http://$DomoIP:$DomoPort/json.htm?type=command&param=getSunRiseSet" | grep "\"status\" : \"OK\"")
if [ -z "$DomoticzStatus" ] ; then
	echo "Domoticz is offline. Retry later"
else
	# Part 1: Execute ARP-SCAN and detect devices
	# Get list of available network devices in local file
	echo "Execute Arp-Scan"
#	sudo arp-scan --localnet -timeout=5000 | grep $NetworkTopIP | grep -v "DUP" | grep -v "hosts"| grep -v "kernel" | sort > $DataDir/arp-scan.lst
	sudo arp-scan -l -r10 -g -R | grep $NetworkTopIP | grep -v "DUP" | grep -v "hosts"| grep -v "kernel" | sort > $DataDir/arp-scan.lst
	# intermediate is used to keep content of arp-scan.raw highly available
	ArpLines=$(wc -l $DataDir/arp-scan.lst)
	if expr "$ArpLines" '>=' "0" ; 	then
		cp $DataDir/arp-scan.lst $DataDir/arp-scan.raw
	else
		exit
	fi

	NewDevices=""

	echo "lets start"
	# determine per device in the arp-scan if it exists. If it doesn't add it to Domoticz
	while read arpscanline ; do
	if [ "$arpscanline" != "" ] ; then
#		echo "Check for $arpscanline"
		mac=$(echo "$arpscanline" | cut -f2)
		ip=$(echo "$arpscanline" | cut -f1)
		man=$(echo "$arpscanline" | cut -f3)

		if ! grep -q $mac $DataDir/arp-table.dom ; then
			echo "new device found"
			#add mac to arp-table
				curl -G "$DomoIP:$DomoPort/json.htm" --data "type=createvirtualsensor" --data "idx=$HardwareIDX" --data-urlencode "sensorname=New Device By $man"  --data "sensortype=6"
				echo "$createdevice"
				# Get IDX of the newly created sensor
				NewDevIDX=""
				NewDevIDX=$(curl -s "$DomoIP:$DomoPort/json.htm?type=devices&filter=all" | grep "idx" | cut -d"\"" -f4 | sort -g | sed '1,${$!d}')
				echo "$NewDevIDX	$mac	0	$man	$ip	NEW" >> $DataDir/arp-table.dom

				# switch on NewDeviceFound notifier in Domoticz:
				curl -s -i -H "Accept: application/json" "http://$DomoIP:$DomoPort/json.htm?type=command&param=switchlight&idx=$NewDevIDX&switchcmd=On"
		fi
	fi
	done < $DataDir/arp-scan.raw

	# Part 2: Determine and update device statusses

	curl -s "http://$DomoIP:$DomoPort/json.htm?type=devices&filter=Dummy&used=true&order=HardwareID" | grep -B 4 -A 35 "\"HardwareID\" : $HardwareIDX" | grep -A 39 '"Data" : "Off"\|"Data" : "On"' | grep  '"Data" : "Off"\|"Data" : "On"\|"idx"' > $DataDir/DomoticzStatus.dat
	cat $DataDir/DomoticzStatus.dat | grep -A 1 '"Data" : "On"' | grep 'idx' | cut -d"\"" -f4 > $DataDir/DomoticzStatus.on
	cat $DataDir/DomoticzStatus.dat | grep -A 1 '"Data" : "Off"' | grep 'idx' | cut -d"\"" -f4 > $DataDir/DomoticzStatus.off

	# Create seperate files to fill arrays
	while read arptableline ; do
	if [ "$arptableline" != "" ] ; then
		echo "$arptableline"
		idx=$(echo "$arptableline" | cut -f1)
		mac=$(echo "$arptableline" | cut -f2)
		RetryCounter=$(echo "$arptableline" | cut -f3)
		DeviceName=$(echo "$arptableline" | cut -f4)
		ip=$(echo "$arptableline" | cut -f5)

#	cat $DataDir/arp-table.dom | cut -f1 > $DataDir/arp-table.idx
		# Check if the device is ON in Domoticz
		grep -x $idx $DataDir/DomoticzStatus.on
		if [ $? -eq 0 ] ; then
			DeviceDomStatus="On"
		else
			DeviceDomStatus="Off"
		fi

		echo "$CurrentDateTime Status of $mac - $idx - $RetryCounter - $DeviceName in Domoticz is $DeviceDomStatus"

		# get ip address for device from arp-scan
		DeviceIP=""
		DeviceIP=$(cat $DataDir/arp-scan.raw | grep -m 1 "$mac" | cut -f1)
		if expr "$DeviceIP" '>' 0
		then
			DeviceDetectStatus="On"
			if [ "$DeviceDomStatus" == "$DeviceDetectStatus" ]; then
				echo "Device is already ON"
			else
				echo "Device is turned ON"
				# Switch in Domoticz ON
				curl -s -i -H "Accept: application/json" "http://$DomoIP:$DomoPort/json.htm?type=command&param=switchlight&idx=$idx&switchcmd=On&passcode=$DomoPIN"
				sed -i -e 's/'"$arptableline"'/'"$idx	$mac	0	$DeviceName	$DeviceIP	ON"'/g' $DataDir/arp-table.dom
#				echo "$CurrentDateTime	${DomMAC[$idx]} - ${DomIDX[$idx]} - ${DomCnt[$idx]} - ${DomName[$idx]} (DOM-Name: ${DeviceName[$idx]} ) switched ON" >> $LogDir/nwd.log.$CurrentDateYmd
			fi
			RetryCounter=0
		else
			DeviceDetectStatus="Off"

			if [ "$DeviceDomStatus" == "$DeviceDetectStatus" ]; then
				echo "Device is already Off"
			else
				echo "Device might be turned OFF"
                                DeviceBluetooth=$(grep "$mac" $InstallDir/bluetooth.dom | cut -d";" -f1)
                                DeviceIP=$(grep "$mac" $DataDir/arp-table.dom | cut -f5)
				echo "$mac on IP $ip and BT $DeviceBluetooth"
				AnswersPing=$(ping -c1 $ip | grep "1 received")
				if [ "$ip" != "" ] && [ "$AnswersPing" != "" ] ; then
					echo "Not in Arp-scan, but responded to Ping"
					DeviceDetectStatus="On"
					RetryCounter=0
				elif [ "$DeviceBluetooth" != "" ] ; then
	                                BluetoothFound=$( sudo hcitool name $DeviceBluetooth )
                                        if [ "$BluetoothFound" != "" ] ; then
                                                DeviceDetectStatus="On"
						echo "Not in Arp-scan, but responded to BlueTooth"
						RetryCounter=0
                                        fi
				fi
				if [ $DeviceDetectStatus == "Off" ] ; then
					echo "is $RetryCounter bigger then $RetryAttempts?"
					if expr "$RetryCounter" '>' "$RetryAttempts" ; then 
						echo "Device is reallly off"
						# Switch in Domoticz OFF

						curl -s -i -H "Accept: application/json" "http://$DomoIP:$DomoPort/json.htm?type=command&param=switchlight&idx=$idx&switchcmd=Off&passcode=$DomoPIN"
						sed -i -e 's/'"$arptableline"'/'"$idx	$mac	$RetryCounter	$DeviceName		Off"'/g' $DataDir/arp-table.dom
#						echo "$CurrentDateTime	${DomMAC[$idx]} - ${DomIDX[$idx]} - ${DomCnt[$idx]} - ${DomName[$idx]} (DOM-Name: ${DeviceName[$idx]} ) switched OFF" >> $LogDir/nwd.log.$CurrentDateYmd						#reset retrycounter
					else
						echo "Will retry later"
						RetryCounter=$((RetryCounter+1))
						sed -i -e 's/'"$arptableline"'/'"$idx	$mac	$RetryCounter	$DeviceName	$ip	pending"'/g' $DataDir/arp-table.dom
					fi
				fi
			fi
			# End of processing based on presence of IP in ARP-SCAN 
		fi

	fi
	done < $DataDir/arp-table.dom

	# end of 'if domoticz is available'

fi

#Let Domoticz know that the script has run
curl -s -i -H "Accept: application/json" "http://$DomoIP:$DomoPort/json.htm?type=command&param=switchlight&idx=$NWDScriptRunning&switchcmd=On&passcode=$DomoPIN"
# End of NetWorkDetect-ARPSCAN

#Make device list available online via domoitczurl/devices.txt
cp /home/pi/domoticz/networkdetectz/data/arp-table.dom /home/pi/domoticz/www/devices.txt

#Make device list available for other scripts that require an IP address
cp /home/pi/domoticz/networkdetectz/data/arp-scan.raw /home/pi/domoticz/scripts/arp-temp
#Other scripts can be create like this"
#	#!/bin/bash
#	DEVICE_MAC='01:23:45:67:89:AB'
#	DEVICE_IP=$(cat /home/pi/domoticz/scripts/arp-temp | grep "$DEVICE_MAC" | cut -f1)
#	echo $DEVICE_IP




# clean up old backups
find $LogDir/* -mtime +$LogPeriod -type f -delete
