#!/bin/bash

InstallDir=$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )
echo $InstallDir
DataDir="$InstallDir/data"
echo $DataDir

Instruct="cp $DataDir/arp-table.dom $DataDir/arp-table.bak"
echo $Instruct
$Instruct


