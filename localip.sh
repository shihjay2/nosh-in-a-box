myip=$(ifconfig -a | awk '/(cast)/ {print $2}' | cut -d: -f2)
if [[ -n $myip ]]; then
	for i in $myip; do
		if [[ ! -z $i ]]; then
			target=$(echo $i | cut -d"." -f1-3)
			target1=$target".1"
			count=$( ping -c 1 $target1 | grep ttl_* | wc -l )
			if [ $count -ne 0 ]; then
				DOMAIN_NOSH=$i
			fi
		fi
	done
fi
echo $DOMAIN_NOSH
