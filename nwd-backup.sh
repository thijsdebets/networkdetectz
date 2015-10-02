#!/bin/bash

InstallDir=$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )
echo $InstallDir
DataDir="$InstallDir/data"
echo $DataDir
CurrentDate=$(date +"%Y%m%d")

umask 000
Instruct="cp $DataDir/arp-table.dom $DataDir/arp-table.$CurrentDate.bak"
echo $Instruct
$Instruct


