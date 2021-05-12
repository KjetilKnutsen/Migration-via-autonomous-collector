#!/bin/bash
mem=$(free --mega | grep Mem: | awk '{print $7}')
echo '* * * * * touch ~/MVAC/trigger.sh' | crontab -
if [ $mem -lt 1000 ] 
then
	echo "Memory available is less than 1000mb, starting collector"
	echo '' | crontab -
	bash /home/fedora/MVAC/collector.sh
fi
