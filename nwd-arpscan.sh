#!/bin/bash

#install arp-scan:
#sudo apt-get install arp-scan

#run from crontab, dont use sudo crontab:
#crontab -e
#*/1 * * * * /home/pi/domoticz/scripts/arp-detect.sh >> /dev/null 2>&1

#Configuration file for Domoticz NetworkDetectz

#--- Configuration ---#
InstallDir=$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )
DomoIP='127.0.0.1'		# Domoticz IP Address
DomoPort='8080'			# Domoticz Port
source $InstallDir/nwd-config
source $InstallDir/nwd-config.own


# not used:	curl -s "http://$DOMO_USER:$DOMO_PASS@$DomoIP:$DomoPort/json.htm?...
# used: 	curl -s "http://$DomoIP:$DomoPort/json.htm?...

#--- Initiation ---#
DataDir="$InstallDir/data"
LogDir="$InstallDir/log"
CurrentDateTime=$(date)
CurrentDateYmd=$(date +"%Y%m%d")
umask 000

source $InstallDir/nwd-functions

	if [ "$Log" == "High" ]  ; then
		echo "$CurrentDateTime execute arp-scan" >> $LogDir/nwd.log.$CurrentDateYmd
	fi

	# Check if Domoticz is online to continue, else suspend
	DomoticzStatus=$(curl -s "http://$DomoIP:$DomoPort/json.htm?type=command&param=getSunRiseSet" | grep "\"status\" : \"OK\"")
	if [ -z "$DomoticzStatus" ]
	then
		echo "Domoticz is offline. Retry later"
	else
	# Part 1: Execute ARP-SCAN and detect devices
		# Get list of available network devices in local file
		sudo arp-scan --localnet | grep $NetworkTopIP | grep -v "DUP" | grep -v "hosts"| grep -v "kernel" | sort > $DataDir/arp-scan.lst
		# intermediate is used to keep content of arp-scan.raw highly available
		ArpLines=$(wc -l $DataDir/arp-scan.lst)
		if expr "$ArpLines" '>=' "0"
		then
			cp $DataDir/arp-scan.lst $DataDir/arp-scan.raw
		fi

		# Create seperate files to fill arrays
		cat $DataDir/arp-scan.raw | grep $NetworkTopIP | cut -f2 > $DataDir/arp-scan.mac
		cat $DataDir/arp-scan.raw | grep $NetworkTopIP | cut -f3 > $DataDir/arp-scan.man
		#	and just for info the ip-address
		cat $DataDir/arp-scan.raw | grep $NetworkTopIP | cut -f1 > $DataDir/arp-scan.ip

		# fill arrays
		ArpMAC=()
		getArray "$DataDir/arp-scan.mac"
		ArpMAC=("${array[@]}")

		ArpMAN=()
		getArray "$DataDir/arp-scan.man"
		ArpMAN=("${array[@]}")

		#	and just for info the ip-address
		ArpIP=()
		getArray "$DataDir/arp-scan.ip"
		ArpIP=("${array[@]}")


		# check for new devices and add them to Domoticz and Internal table if necessary
		#	dev=0
		#	for i in "${ArpMAC[@]}"
		NewDevices=""

		echo "lets start"
		# determine per device in the arp-scan if it exists. If it doesn't add it to Domoticz
		for (( dev = 0; dev < ${#ArpMAC[@]}; dev++ ))
		do
			echo $dev
			if [ "$Log" == "High" ] ; then
				echo "$CurrentDateTime Check if ${ArpMAC[$dev]} - ${ArpMAN[$dev]} exists" >> $LogDir/nwd.log.$CurrentDateYmd
			fi

			DOM_IDX=""
			DOM_IDX=$(cat $DataDir/arp-table.dom | grep -m 1 ${ArpMAC[$dev]} | cut -f2)
			if expr "$DOM_IDX" '>' 0
			then
				echo "$CurrentDateTime Existing Device:    ${ArpMAC[$dev]} - ${ArpMAN[$dev]} - $DOM_IDX - ${ArpIP[$dev]}"
				if [ "$Log" == "High" ] ; then
					echo "$CurrentDateTime Existing Device:    ${ArpMAC[$dev]} - ${ArpMAN[$dev]} - $DOM_IDX - ${ArpIP[$dev]}" >> $LogDir/nwd.log.$CurrentDateYmd
				fi
			else
				echo "$CurrentDateTime Not found: ${ArpMAC[$dev]} - ${ArpMAN[$dev]}" >> $LogDir/nwd.log.$CurrentDateYmd
#				cat $DataDir/arp-table.dom >> $LogDir/nwd.log.$CurrentDateYmd
				#Check for double entries using log
				MacLoggedBefore=$( cat $DataDir/nwd.log | grep -m 1 ${ArpMAC[$dev]} )
				if [ -z $MacLoggedBefore ]
				then

					# Get the latest version of the MAC -> Manufacturer mapping table
					#wget -c -N -O $DataDir/oui.txt http://standards-oui.ieee.org/oui.txt
					#wget -c -N -O $DataDir/oui.txt http://linuxnet.ca/ieee/oui.txt

					MACIdentification=$(cleanMac ${ArpMAC[$dev]} "UP" "-")
					MACIdentification=${MACIdentification:0:8}
					DeviceMan=""
					DeviceMan=$(cat $DataDir/oui.txt | grep -m 1 $MACIdentification | cut -f3)
					DeviceURLName=`echo $DeviceMan | tr "," "."`
					#DeviceURLName=$(curl -s http://www.macvendorlookup.com/api/v2/b4:74:9f:8f:a7:3b/pipe | cut -d"|" -f5- | sed 's/|/_/g' | tr "," ".")

					# Create new Domoticz Hardware sensor
					curl -G "$DomoIP:$DomoPort/json.htm" --data "type=createvirtualsensor" --data "idx=$Hardware" --data-urlencode "sensorname=New Device By $DeviceURLName"  --data "sensortype=6"
					#curl -s "$DomoIP:$DomoPort/json.htm?type=createvirtualsensor&idx=$Hardware&sensorname=NewDeviceBy%20$DeviceURLName&sensortype=6" 
					# Get IDX of the newly created sensor
					NewDevIDX=""
					NewDevIDX="$(curl -s "$DomoIP:$DomoPort/json.htm?type=devices&filter=all" | grep "idx" | cut -d"\"" -f4 | sort -g | sed '1,${$!d}')"
					if [ "$Log" == "High" ] || [ "$Log" == "Low" ] ; then
						echo "###########################################################################################" >> $DataDir/nwd.log.$CurrentDateYmd
						echo "$CurrentDateTime New device added: ${ArpMAC[$dev]}	$NewDevIDX	${ArpMAN[$dev]} by $DeviceMan " >> $DataDir/nwd.log
					fi
					echo "$NewDevIDX	${ArpMAC[$dev]}	0	$DeviceMan	" >> $DataDir/arp-table.dom
#					sqlite3 nwd.db "INSERT INTO device (mac, name, manufacture) VALUES ('${ArpMAC[$dev]}','--- NEW DEVICE by Manufacturer $DeviceMan ---', '$DeviceMan' )";
#					sqlite3 nwd.db "INSERT INTO idx (idx, status, ip) VALUES ($NewDevIDX,'ON', '${ArpIP[$dev]}')";
#					sqlite3 nwd.db "INSERT INTO link (idx, mac) VALUES ($NewDevIDX,'${ArpMAC[$dev]}')";

					# switch on NewDeviceFound notifier in Domoticz:
					curl -s -i -H "Accept: application/json" "http://$DomoIP:$DomoPort/json.htm?type=command&param=switchlight&idx=$NewDevicesFoundIDX&switchcmd=On"
				else
					echo "New MAC address ignored. Already logged nwd.log"
				fi
			# end of 'does device exist in arp-table.dom'
			fi 
		# continue with next device of Arp-scan
		done

	

		# Part 2: Determine and update device statusses

		# Create seperate files to fill arrays
		cat $DataDir/arp-table.dom | cut -f1 > $DataDir/arp-table.idx
		cat $DataDir/arp-table.dom | cut -f2 > $DataDir/arp-table.mac
		cat $DataDir/arp-table.dom | cut -f3 > $DataDir/arp-table.cnt
		# 	and just for info the name
		cat $DataDir/arp-table.dom | cut -f4 > $DataDir/arp-table.nam  


		# fill arrays
		DomMAC=()
		getArray "$DataDir/arp-table.mac"
		DomMAC=("${array[@]}")

		DomIDX=()
		getArray "$DataDir/arp-table.idx"
		DomIDX=("${array[@]}")

		DomCnt=()
		getArray "$DataDir/arp-table.cnt"
		DomCnt=("${array[@]}")

		DomName=()
		getArray "$DataDir/arp-table.nam"
		DomName=("${array[@]}")


		# For every device in the arp-table.dom see if there is an entry in the arp-scan. Switch Domoticz state if necessery
#new generic method
		curl -s "http://$DomoIP:$DomoPort/json.htm?type=devices&filter=Dummy&used=true&order=HardwareID" | grep -B 4 -A 35 "\"HardwareID\" : $HardwareIDX" | grep -A 39 '"Data" : "Off"\|"Data" : "On"' | grep  '"Data" : "Off"\|"Data" : "On"\|"idx"' > $DataDir/DomoticzStatus.dat
		cat $DataDir/DomoticzStatus.dat | grep -A 1 '"Data" : "On"' | grep 'idx' | cut -d"\"" -f4 > $DataDir/DomoticzStatus.on
		cat $DataDir/DomoticzStatus.dat | grep -A 1 '"Data" : "Off"' | grep 'idx' | cut -d"\"" -f4 > $DataDir/DomoticzStatus.off

		for (( idx = 0; idx < ${#DomMAC[@]}; idx++ ))
#		for (( idx = 0; idx < ${#DomMAC[2]}; idx++ ))
		do
			# get device status and name from Domoticz
#			addNic ${DomMAC[$idx]} "lan"



			RetryCounter=${DomCnt[$idx]}

#			DeviceName[$idx]=""
#			DeviceName[$idx]=$(curl -s "http://$DomoIP:$DomoPort/json.htm?type=devices&rid=${DomIDX[$idx]}" | grep -m 1 "\"Name\"" | cut -d"\"" -f4)
#			if [ "${DeviceName[$idx]}" == "" ] || [ "${DeviceName[$idx]}" == "Unknown" ]; then
				DeviceName[$idx]=${DomName[$idx]}
#			fi

			# Check if the device is ON in Domoticz
			grep -x ${DomIDX[$idx]} $DataDir/DomoticzStatus.on
#			curl -s "http://$DomoIP:$DomoPort/json.htm?type=devices&rid=${DomIDX[$idx]}" | grep -m 1 "Status" | grep "On" > /dev/null
			if [ $? -eq 0 ] ; then
				DeviceDomStatus="On"
			else
				DeviceDomStatus="Off"
			fi

			if [ "$Log" == "High" ] ; then
				echo "$CurrentDateTime Status of ${DomMAC[$idx]} - ${DomIDX[$idx]} - ${DomCnt[$idx]} - ${DomName[$idx]} (DOM-Name: ${DeviceName[$idx]} ) in Domoticz is $DeviceDomStatus" >> $LogDir/nwd.log.$CurrentDateYmd
			fi
			echo "$CurrentDateTime Status of ${DomMAC[$idx]} - ${DomIDX[$idx]} - ${DomCnt[$idx]} - ${DomName[$idx]} (DOM-Name: ${DeviceName[$idx]} ) in Domoticz is $DeviceDomStatus"

			# get ip address for device from arp-scan
			DeviceIP=""
			DeviceIP=$(cat $DataDir/arp-scan.raw | grep -m 1 ${DomMAC[$idx]} | cut -f1)
			if expr "$DeviceIP" '>' 0
			then
				DeviceDetectStatus="On"
				if [ "$DeviceDomStatus" == "$DeviceDetectStatus" ]; then
					echo "Device is already ON"
				else
					echo "Device is turned ON"
					# Switch in Domoticz ON
#					sqlite3 nwd.db "update idx set status = 'ON' , statusdate = CURRENT_TIMESTAMP , ip = '$DeviceIP' where idx.idx = '${DomIDX[$idx]}' "; 
#					sqlite3 nwd.db "update idx set status = 'ON', statusdate = CURRENT_TIMESTAMP, ip = '$DeviceIP' where idx = ${DomIDX[$idx]}";
#					echo "curl -s -i -H _Accept: application/json_ _http://$DomoIP:$DomoPort/json.htm?type=command&param=switchlight&idx=${DomIDX[$idx]}&switchcmd=On&passcode=$DomoPIN_"
					curl -s -i -H "Accept: application/json" "http://$DomoIP:$DomoPort/json.htm?type=command&param=switchlight&idx=${DomIDX[$idx]}&switchcmd=On&passcode=$DomoPIN"
					echo "$CurrentDateTime	${DomMAC[$idx]} - ${DomIDX[$idx]} - ${DomCnt[$idx]} - ${DomName[$idx]} (DOM-Name: ${DeviceName[$idx]} ) switched ON" >> $LogDir/nwd.log.$CurrentDateYmd
				fi
				RetryCounter=0
			else
				DeviceDetectStatus="Off"

				if [ "$DeviceDomStatus" == "$DeviceDetectStatus" ]; then
					echo "Device is already Off"
#					RetryCounter=0
				else
					echo "Device might be turned OFF"
	                                DeviceHasBT=$(grep "${DomMAC[$idx]}" $InstallDir/bluetooth.dom)
	                                if [ "$DeviceHasBT" != "" ] ; then
	                                        DeviceBluetooth=$( echo "$DeviceHasBT"  | cut -d";" -f2 )
	                                        BluetoothFound=$( sudo hcitool name $DeviceBluetooth )
	                                        if [ "$BluetoothFound" == "" ] ; then
	                                                DeviceDetectStatus="Off"
	                                        else
	                                                DeviceDetectStatus="On"
							RetryCounter=0
							DeviceIP="BT:$DeviceBluetooth"
	                                        fi
#	                                else
#						if expr "${DomCnt[$idx]}" '>' "$RetryAttempts" 
#						then
#	                                                DeviceDetectStatus="Off"
#	                                        else
#	                                                DeviceDetectStatus="On"
#	                                        fi
					fi
					if [ $DeviceDetectStatus == "Off" ] ; then
						if expr "${DomCnt[$idx]}" '>' "$RetryAttempts" ; then 
							echo "Device is reallly off"
							# Switch in Domoticz OFF
#							sqlite3 nwd.db "update idx set status = 'OFF' where idx.idx = '${DomIDX[$idx]}' "; 

#							sqlite3 nwd.db "update idx set status = 'OFF', statusdate = CURRENT_TIMESTAMP, ip = '$DeviceIP' where idx = ${DomIDX[$idx]}" ;
							curl -s -i -H "Accept: application/json" "http://$DomoIP:$DomoPort/json.htm?type=command&param=switchlight&idx=${DomIDX[$idx]}&switchcmd=Off&passcode=$DomoPIN"
							echo "$CurrentDateTime	${DomMAC[$idx]} - ${DomIDX[$idx]} - ${DomCnt[$idx]} - ${DomName[$idx]} (DOM-Name: ${DeviceName[$idx]} ) switched OFF" >> $LogDir/nwd.log.$CurrentDateYmd						#reset retrycounter
#							RetryCounter=0
						else
							echo "Will retry later"
							RetryCounter=$((RetryCounter+1))
#							sqlite3 nwd.db "update idx set status = '$RetryCounter' where idx.idx = '${DomIDX[$idx]}' "; 

						fi
					fi
				fi
			# End of processing based on presence of IP in ARP-SCAN 
			fi

			DomCnt[$idx]=$RetryCounter
			echo "Counter is ${DomCnt[$idx]}"

			# Update internal table with names and retrycounts
	
			# If it is the first device, then rebuild the arp-table.tmp else add device to arp-table.tmp
			if [ "$idx" == "0" ] ; then
#				echo "$CurrentDateTime arp-table opnieuw opbouwen" >> $LogDir/nwd.log.$CurrentDateYmd
#				echo "$CurrentDateTime ${DomIDX[$idx]}	${DomMAC[$idx]}	${DomCnt[$idx]}	${DeviceName[$idx]}	$DeviceIP" >> $LogDir/nwd.log.$CurrentDateYmd
				echo "${DomIDX[$idx]}	${DomMAC[$idx]}	${DomCnt[$idx]}	${DeviceName[$idx]}	$DeviceIP" > $DataDir/arp-table.tmp
			else
#				echo "$CurrentDateTime device aan arp-table toevoegen" >> $LogDir/nwd.log.$CurrentDateYmd
#				echo "$CurrentDateTime ${DomIDX[$idx]}	${DomMAC[$idx]}	${DomCnt[$idx]}	${DeviceName[$idx]}	$DeviceIP" >> $LogDir/nwd.log.$CurrentDateYmd
				echo "${DomIDX[$idx]}	${DomMAC[$idx]}	${DomCnt[$idx]}	${DeviceName[$idx]}	$DeviceIP" >> $DataDir/arp-table.tmp
			#end of rebuilding arp-table.tmp
			fi
		
		# done checking and switching per device 
		done


		if [ "$Log" == "High" ] ; then
			cat $DataDir/arp-table.tmp >> $LogDir/nwd.log.$CurrentDateYmd
		fi
		if [ "$Log" == "High" ] ; then
			echo "$CurrentDateTime -----" >> $LogDir/nwd.log.$CurrentDateYmd
			cat $DataDir/arp-table.dom >> $LogDir/nwd.log.$CurrentDateYmd
		fi

		# cleanup result from arp-table.tmp to arp-table.dom
		# intermediate .tmp is used to keep content of arp-table.dom highly available	
		TmpLines=$(wc -l $DataDir/arp-table.tmp | cut -d" " -f1)
		DomLines=$(wc -l $DataDir/arp-table.dom | cut -d" " -f1)
		if expr "$TmpLines" '>=' "$DomLines"
		then
			sort -u $DataDir/arp-table.tmp > $DataDir/arp-table.dom
		fi



	# end of 'if domoticz is available'

	fi

# End of NetWorkDetect-ARPSCAN

# clean up old backups
find $LogDir/* -mtime +$LogPeriod -type f -delete
