#!/bin/bash
while :
do
	stress-ng --vm-bytes $(awk '/MemAvailable/{printf "%d\n", $2 * 0.4;}' < /proc/meminfo)k --vm-keep -m 1 -t 25
	sleep 15
done
