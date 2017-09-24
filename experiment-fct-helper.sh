#!/bin/bash

offduration=1000
onbytes=10000

tcp=$1
receiver_ip=$2
outfile=$3

if [[ $tcp == "bbr" ]]; then
    sudo tc qdisc add dev ingress root fq
fi

# Continue until stopped
if [[ $tcp == "copa" ]]; then
    ../bin/sender serverip=$receiver_ip onduration=$onbytes offduration=$offduration traffic_params=byte_switched cctype=markovian delta_conf=auto:0.5 > $outfile 2>&1

else
    while true; do
        offdurationsample=`python -c "import random; print(random.expovariate(1000.0 / $offduration))"`
        echo "Sleeping for $offdurationsample"
        sleep $offdurationsample
        onbytessample=`python -c "import random; print(int(random.expovariate(1.0 / $onbytes)))"`
        echo "On for $onbytessample bytes"
        /usr/bin/time -f " $onbytessample %e" -a -o $outfile bash -c "head /dev/zero -c $onbytessample | nc $receiver_ip 8989"
    done
fi
