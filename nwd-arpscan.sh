#!/bin/bash

#run from crontab, dont use sudo crontab
# 

#--- Configuration ---#
DomoIP='127.0.0.1'		# Domoticz IP Address
DomoPort='8080'			# Domoticz Port
HardwareIDX=14
InstallDir="/home/pi/domoticz/networkdetectz"
RetryAttempts=4			# retry 5 times (5 minutes)


# not used:	curl -s "http://$DOMO_USER:$DOMO_PASS@$DomoIP:$DomoPort/json.htm?...
# used: 	curl -s "http://$DomoIP:$DomoPort/json.htm?...

curl -s "http://192.168.0.41:8080/json.htm?type=command&param=getSunRiseSet" | grep "\"status\" : \"OK\""
if [ $? -eq 0 ] ; then


#--- Initiation ---#
DataDir="$InstallDir/data"
LoopSleep=30
NetworkTopIP="192"
echo "$DataDir"


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

#--- Startup delay ---#
#sleep 60      


#--- Main loop ---#
# remove 5 comments markers #
#while [ 1 ] 
#do
	# Part 1: Execute ARP-SCAN and detect devices
	# Get list of available network devices in local file
	echo "execute arp-scan"
	sudo arp-scan --localnet | grep $NetworkTopIP | grep -v "DUP" | sort > $DataDir/arp-scan.raw
#remove	cat $DataDir/arp-scan.raw | grep $NetworkTopIP | grep -v "DUP"
#remove	# Get number of devices from local file
#remove	DeviceCount="$(cat $DataDir/arp-scan.raw | grep "packets" | cut -d" " -f1)"
#remove	echo "Number of devices detected: " $DeviceCount
	
	# Create seperate files to fill arrays
#remove	cat $DataDir/arp-scan.raw | grep $NetworkTopIP | grep -v "DUP" | cut -f1 > $DataDir/arp-scan.ip
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
	echo "lets start"
	for (( dev = 0; dev < ${#ArpMAC[@]}; dev++ ))
	do
		echo $dev
		echo "Check if ${ArpMAC[$dev]} - ${ArpMAN[$dev]} exists"
		DOM_IDX=$(cat $DataDir/arp-table.dom | grep ${ArpMAC[$dev]} | cut -f2)
		if expr "$DOM_IDX" '>' 0
		then
			echo "Device:    ${ArpMAC[$dev]} - ${ArpMAN[$dev]} - $DOM_IDX - ${ArpIP[$dev]}"
		else
			echo "Not found: ${ArpMAC[$dev]} - ${ArpMAN[$dev]}"
			curl -s "$DomoIP:$DomoPort/json.htm?type=createvirtualsensor&idx=$HardwareIDX&sensortype=6"
			NewDevIDX="$(curl -s "$DomoIP:$DomoPort/json.htm?type=devices&filter=all&used=false&order=Name" | grep "idx" | cut -d"\"" -f4 | sort -g | sed '1,${$!d}')"
			echo "${ArpMAC[$dev]}	$NewDevIDX	${ArpMAN[$dev]}"
			if [ "$dev" == "0" ] ; then
				echo "arp-table opnieuw opbouwen"
 				echo "${ArpMAC[$dev]}	$NewDevIDX	0	${ArpMAN[$dev]}" > $DataDir/arp-table.dom
			else
				echo "arp-table aanvullen"
 				echo "${ArpMAC[$dev]}	$NewDevIDX	0	${ArpMAN[$dev]}" >> $DataDir/arp-table.dom
			fi
		fi
#		((dev++))
	done
	

	# Part 2: Determine and update device statusses

	# Create seperate files to fill arrays
	cat $DataDir/arp-table.dom | cut -f1 > $DataDir/arp-table.mac
	cat $DataDir/arp-table.dom | cut -f2 > $DataDir/arp-table.idx
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

	DeviceName=()

#	idx=0	
#	for i in "${DomMAC[@]}"
	for (( idx = 0; idx < ${#DomMAC[@]}; idx++ ))
	do
		# get device status and name from Domoticz
		RetryCounter=${DomCnt[$idx]}
		DeviceName[$idx]=$(curl -s "http://$DomoIP:$DomoPort/json.htm?type=devices&rid=${DomIDX[$idx]}" | grep "\"Name\"" | cut -d"\"" -f4)
		if [ "${DeviceName[$idx]}" == "" ] ; then
			DeviceName[$idx]=${DomName[$idx]}
		fi

		curl -s "http://$DomoIP:$DomoPort/json.htm?type=devices&rid=${DomIDX[$idx]}" | grep "Status" | grep "On" > /dev/null
		if [ $? -eq 0 ] ; then
			DeviceDomStatus="On"
		else
			DeviceDomStatus="Off"
		fi
		echo "Status of ${DomMAC[$idx]} - ${DomIDX[$idx]} - ${DomCnt[$idx]} - ${DomName[$idx]} (DOM-Name: ${DeviceName[$idx]} ) in Domoticz is $DeviceDomStatus"

		# get ip address for device from arp-scan
		DeviceIP=$(cat $DataDir/arp-scan.raw | grep ${DomMAC[$idx]} | cut -f1)
		# PINGTIME=`ping -c 1 -q $DeviceIP | awk -F"/" '{print $5}' | xargs`
		# echo $PINGTIME

		if expr "$DeviceIP" '>' 0
		then
			DeviceDetectStatus="On"
			if [ "$DeviceDomStatus" == "$DeviceDetectStatus" ]; then
				echo "Device is already ON"
			else
				echo "Device is turned ON"
				# Send data
				curl -s -i -H "Accept: application/json" "http://$DomoIP:$DomoPort/json.htm?type=command&param=switchlight&idx=${DomIDX[$idx]}&switchcmd=On"
			fi
			RetryCounter=0
		else
			DeviceDetectStatus="Off"
			if [ "$DeviceDomStatus" == "$DeviceDetectStatus" ]; then
				echo "Device is already Off"
			else
				echo "Device might be turned OFF"
				if [ "${DomCnt[$idx]}" == "$RetryAttempts" ]; then
					echo "Device is reallly off"
					# Send data
					curl -s -i -H "Accept: application/json" "http://$DomoIP:$DomoPort/json.htm?type=command&param=switchlight&idx=${DomIDX[$idx]}&switchcmd=Off"
					#reset retrycounter
					RetryCounter=0
				else
					echo "Will retry later"
					RetryCounter=$((RetryCounter+1))
					# DomCnt[$idx]=$((${DomCnt[$idx]} + 1))
				fi
			fi
		fi
		DomCnt[$idx]=$RetryCounter
		echo "Counter is ${DomCnt[$idx]}"

		# Update internal table with names and retrycounts

		if [ "$idx" == "0" ] ; then
			echo "arp-table opnieuw opbouwen"
			echo "${DomMAC[$idx]}	${DomIDX[$idx]}	${DomCnt[$idx]}	${DeviceName[$idx]}	$DeviceIP" 
			echo "${DomMAC[$idx]}	${DomIDX[$idx]}	${DomCnt[$idx]}	${DeviceName[$idx]}	$DeviceIP" > $DataDir/arp-table.tmp
		else
			echo "device aan arp-table toevoegen"
			echo "${DomMAC[$idx]}	${DomIDX[$idx]}	${DomCnt[$idx]}	${DeviceName[$idx]}	$DeviceIP" 
			echo "${DomMAC[$idx]}	${DomIDX[$idx]}	${DomCnt[$idx]}	${DeviceName[$idx]}	$DeviceIP" >> $DataDir/arp-table.tmp
		fi
	
#		((idx++))
	done
	cp $DataDir/arp-table.tmp $DataDir/arp-table.dom

	# Wait before running loop again
#	echo "Sleep for a moment"
#	sleep $LoopSleep
#done

fi
