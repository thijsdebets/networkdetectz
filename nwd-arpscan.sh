#!/bin/bash

#run from crontab, dont use sudo crontab
# 

#--- Configuration ---#
DomoIP='127.0.0.1'		# Domoticz IP Address
DomoPort='8080'			# Domoticz Port
HardwareIDX=14
NewDevicesFoundIDX=111
InstallDir=$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )
RetryAttempts=4			# retry 5 times (5 minutes)
Log="Low"			# High: Almost everything (huge logfile), Low: New devices and errors, Error: Only errors, Not: Nothing


# not used:	curl -s "http://$DOMO_USER:$DOMO_PASS@$DomoIP:$DomoPort/json.htm?...
# used: 	curl -s "http://$DomoIP:$DomoPort/json.htm?...


#--- Initiation ---#
DataDir="$InstallDir/data"
LoopSleep=30
NetworkTopIP="192"
CurrentDate=$(date)


#--- Functions ---#

	#--- Array Function Begin ---#
	# Read the file in parameter and fill the array named "array"
	array=()
	getArray() {
	    i=0
	    while read line # Read a line
	    do
	        array[i]=$line # Put it into the array
	        i=$(($i + 1))
	    done < $1
	}
	#--- Array Function End   ---#

#--- Main loop ---#
	umask 000
	# Part 1: Execute ARP-SCAN and detect devices
	if [ "$Log" == "High" ]  ; then
		echo "$CurrentDate execute arp-scan" >> $DataDir/nwd.log
	fi
	
	# Check if Domoticz is online to continue, else suspend
	DomoticzStatus=$(curl -s "http://$DomoIP:$DomoPort/json.htm?type=command&param=getSunRiseSet" | grep "\"status\" : \"OK\"")
	if [ -z "$DomoticzStatus" ]
	then
		echo "Domoticz is offline. Retry later"
	else
		# Get list of available network devices in local file
		sudo arp-scan --localnet | grep $NetworkTopIP | grep -v "DUP" | grep -v "hosts"| sort > $DataDir/arp-scan.raw

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
				echo "$CurrentDate Check if ${ArpMAC[$dev]} - ${ArpMAN[$dev]} exists" >> $DataDir/nwd.log
			fi

			DOM_IDX=""
			DOM_IDX=$(cat $DataDir/arp-table.dom | grep -m 1 ${ArpMAC[$dev]} | cut -f2)
			if expr "$DOM_IDX" '>' 0
			then
				echo "$CurrentDate Existing Device:    ${ArpMAC[$dev]} - ${ArpMAN[$dev]} - $DOM_IDX - ${ArpIP[$dev]}"
				if [ "$Log" == "High" ] ; then
					echo "$CurrentDate Existing Device:    ${ArpMAC[$dev]} - ${ArpMAN[$dev]} - $DOM_IDX - ${ArpIP[$dev]}" >> $DataDit/nwd.log
				fi
			else
				if [ "$Log" == "High" ] ; then
					echo "$CurrentDate Not found: ${ArpMAC[$dev]} - ${ArpMAN[$dev]}" >> $DataDir/nwd.log
					cat $DataDir/arp-table.dom >> $DataDir/nwd.log
				fi
				# Get the latest version of the MAC -> Manufacturer mapping table
				wget -c -N -O $DataDir/oui.txt http://standards-oui.ieee.org/oui.txt

				MACIdentification=${ArpMAC[$dev]} 
				MACIdentification=${MACIdentification:0:8} 
				MACIdentification=`echo $MACIdentification | tr '[:lower:]' '[:upper:]'` 
				MACIdentification=`echo $MACIdentification | tr ":" "-"` 
				DeviceMan=""
				DeviceMan=$(cat $DataDir/oui.txt | grep -m 1 $MACIdentification | cut -f3)

				#Check for double entries using log
				MacLoggedBefore=$(cat $DataDir/nwd.log | grep -m 1 ${ArpMAC[$dev]})
				if [ -z $MacLoggedBefore ]
				then
					# Create new Domoticz Hardware sensor
					curl -s "$DomoIP:$DomoPort/json.htm?type=createvirtualsensor&idx=$HardwareIDX&sensortype=6"
					# Get IDX of the newly created sensor
					NewDevIDX=""
					NewDevIDX="$(curl -s "$DomoIP:$DomoPort/json.htm?type=devices&filter=all&used=false&order=Name" | grep "idx" | cut -d"\"" -f4 | sort -g | sed '1,${$!d}')"
					if [ "$Log" == "High" ] || [ "$Log" == "Low" ] ; then
						echo "###########################################################################################" >> $DataDir/nwd.log
						echo "$CurrentDate New device added: ${ArpMAC[$dev]}	$NewDevIDX	${ArpMAN[$dev]} by $DeviceMan " >> $DataDir/nwd.log
					fi
					echo "$NewDevIDX	${ArpMAC[$dev]}	0	--- NEW DEVICE by Manufacturer $DeviceMan ---	" >> $DataDir/arp-table.dom
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
		for (( idx = 0; idx < ${#DomMAC[@]}; idx++ ))
		do
			# get device status and name from Domoticz
			RetryCounter=${DomCnt[$idx]}
			
			DeviceName=[$idx]=""
			DeviceName[$idx]=$(curl -s "http://$DomoIP:$DomoPort/json.htm?type=devices&rid=${DomIDX[$idx]}" | grep -m 1 "\"Name\"" | cut -d"\"" -f4)
			if [ "${DeviceName[$idx]}" == "" ] || [ "${DeviceName[$idx]}" == "Unknown" ]; then
				DeviceName[$idx]=${DomName[$idx]}
			fi

			# Check if the device is ON in Domoticz
			curl -s "http://$DomoIP:$DomoPort/json.htm?type=devices&rid=${DomIDX[$idx]}" | grep -m 1 "Status" | grep "On" > /dev/null
			if [ $? -eq 0 ] ; then
				DeviceDomStatus="On"
			else
				DeviceDomStatus="Off"
			fi
			
			if [ "$Log" == "High" ] ; then
				echo "$CurrentDate Status of ${DomMAC[$idx]} - ${DomIDX[$idx]} - ${DomCnt[$idx]} - ${DomName[$idx]} (DOM-Name: ${DeviceName[$idx]} ) in Domoticz is $DeviceDomStatus" >> $DataDir/nwd.log
			fi
			echo "$CurrentDate Status of ${DomMAC[$idx]} - ${DomIDX[$idx]} - ${DomCnt[$idx]} - ${DomName[$idx]} (DOM-Name: ${DeviceName[$idx]} ) in Domoticz is $DeviceDomStatus"

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
					curl -s -i -H "Accept: application/json" "http://$DomoIP:$DomoPort/json.htm?type=command&param=switchlight&idx=${DomIDX[$idx]}&switchcmd=On"
				fi
				RetryCounter=0
			else
				DeviceDetectStatus="Off"
				if [ "$DeviceDomStatus" == "$DeviceDetectStatus" ]; then
					echo "Device is already Off"
					RetryCounter=0
				else
					echo "Device might be turned OFF"
					if [ "${DomCnt[$idx]}" == "$RetryAttempts" ]; then
						echo "Device is reallly off"
						# Switch in Domoticz OFGF
						curl -s -i -H "Accept: application/json" "http://$DomoIP:$DomoPort/json.htm?type=command&param=switchlight&idx=${DomIDX[$idx]}&switchcmd=Off"
						#reset retrycounter
						RetryCounter=0
					else
						echo "Will retry later"
						RetryCounter=$((RetryCounter+1))
					fi
				fi
			# End of processing based on presence of IP in ARP-SCAN 
			fi

			DomCnt[$idx]=$RetryCounter
			echo "Counter is ${DomCnt[$idx]}"

			# Update internal table with names and retrycounts
	
			# If it is the first device, then rebuild the arp-table.tmp else add device to arp-table.tmp
			if [ "$idx" == "0" ] ; then
				if [ "$Log" == "High" ] ; then
					echo "$CurrentDate arp-table opnieuw opbouwen" >> $DataDir/nwd.log
					echo "$CurrentDate ${DomIDX[$idx]}	${DomMAC[$idx]}	${DomCnt[$idx]}	${DeviceName[$idx]}	$DeviceIP" >> $DataDir/nwd.log
				fi
				echo "${DomIDX[$idx]}	${DomMAC[$idx]}	${DomCnt[$idx]}	${DeviceName[$idx]}	$DeviceIP" > $DataDir/arp-table.tmp
			else
				if [ "$Log" == "High" ] ; then
					echo "$CurrentDate device aan arp-table toevoegen" >> $DataDir/nwd.log
					echo "$CurrentDate ${DomIDX[$idx]}	${DomMAC[$idx]}	${DomCnt[$idx]}	${DeviceName[$idx]}	$DeviceIP" >> $DataDir/nwd.log
				fi
				echo "${DomIDX[$idx]}	${DomMAC[$idx]}	${DomCnt[$idx]}	${DeviceName[$idx]}	$DeviceIP" >> $DataDir/arp-table.tmp
			#end of rebuilding arp-table.tmp
			fi
			
		# done checking and switching per device 
		done


		if [ "$Log" == "High" ] ; then
			cat $DataDir/arp-table.tmp >> $DataDir/nwd.log
		fi
		if [ "$Log" == "High" ] ; then
			echo "$CurrentDate -----" >> $DataDir/nwd.log
			cat $DataDir/arp-table.dom >> $DataDir/nwd.log
		fi

		# cleanup result in from arp-table.tmp to arp-table.dom
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
