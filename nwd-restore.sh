#!/bin/bash

InstallDir=$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )
echo $InstallDir
DataDir="$InstallDir/data"
echo $DataDir

umask 000
LastBackup=$(find $DataDir -maxdepth 1 -type f -name "arp-table.*.bak" -print0 | xargs -0 stat --printf "%Y %n\n" | sort -n | tail -1 | sed 's/[0-9]\+[[:space:]]//' | tr '\n' '\0' )


Instruct="cp $LastBackup $DataDir/arp-table.dom"
echo $Instruct

for i in {1..10}
do
	$Instruct
	sleep 5
done



