#run from crontab, dont use sudo crontab
# 

InstallDir="/home/pi/domoticz/networkdetectz"

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



#--- Main loop ---#
# remove 5 comments markers #
#while [ 1 ] 
#do
	# Get list of available network devices in local file
#	sudo arp-scan --localnet | sort > $DataDir/arp-scan.raw
	cat $DataDir/arp-scan.raw | grep $NetworkTopIP | grep -v "DUP"
	# Get number of devices from local file
	DeviceCount="$(cat $DataDir/arp-scan.raw | grep "packets" | cut -d" " -f1)"
	echo "Number of devices detected: " $DeviceCount
	cat $DataDir/arp-scan.raw | grep $NetworkTopIP | grep -v "DUP" | cut -f1 > $DataDir/arp-scan.ip
	cat $DataDir/arp-scan.raw | grep $NetworkTopIP | grep -v "DUP" | cut -f2 > $DataDir/arp-scan.mac
	cat $DataDir/arp-scan.raw | grep $NetworkTopIP | grep -v "DUP" | cut -f3 > $DataDir/arp-scan.man


	ArpIP=()
	getArray "$DataDir/arp-scan.ip"
	ArpIP=("${array[@]}")

	ArpMAC=()
	getArray "$DataDir/arp-scan.mac"
	ArpMAC=("${array[@]}")
	
	ArpMAN=()
	getArray "$DataDir/arp-scan.man"
	ArpMAN=("${array[@]}")
	
	for (( dev=0; dev<$DeviceCount; dev++))  
	do
		DOM_IDX=$(cat $DataDir/arp-table.dom | grep ${ArpMAC[$dev]} | cut -f2)
		if expr "$DOM_IDX" '>' 0
		then
			echo "Device:    ${ArpMAC[$dev]} - ${ArpMAN[$dev]} - ${ArpIP[$dev]} - $DOM_IDX"
		else
			echo "Not found: ${ArpMAC[$dev]} - ${ArpMAN[$dev]} - ${ArpIP[$dev]}"
			echo "${ArpMAC[$dev]}	xxx	${ArpMAN[$dev]}" >> $DataDir/arp-table.dom
		fi
	done



	
	# Wait before running loop again
#	sleep $LoopSleep
#done

