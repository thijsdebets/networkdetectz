#!/bin/bash

InstallDir=$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )
echo $InstallDir
DataDir="$InstallDir/data"
echo $DataDir
CurrentDateYmd=$(date +"%Y%m%d")

umask 000
Instruct="cp $DataDir/arp-table.dom $DataDir/arp-table.$CurrentDateYmd.bak"
echo $Instruct
$Instruct

# clean up old backups
find $DataDir/*.bak -mtime +90 -type f -delete


