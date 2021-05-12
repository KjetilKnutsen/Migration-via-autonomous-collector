#!/bin/bash
while :
do
	date=$(date)
	mem=$(free | awk '{print $6}' | sed -n 2p)
	echo $date $mem >> logfile
	sleep 135
done

