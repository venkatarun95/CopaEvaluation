#!/bin/bash

servers="iperf.biznetnetworks.com iperf.he.net iperf.scottlinux.com bouygues.testdebit.info iperf.volia.net iperf.it-north.net"

res_dir="IperfPing"

if [[ ! -d $res_dir ]]; then
    mkdir $res_dir
fi

while [[ 1 -eq 1 ]]; do
    for server in $servers; do
        date >>$res_dir/$server.ping
        ping -c 2 $server >>$res_dir/$server.ping
        date >>$res_dir/$server.iperf3
        iperf3 -t 3 -c $server >>$res_dir/$server.iperf3
        date >>$res_dir/$server.traceroute
        traceroute $server >>$res_dir/$server.traceroute
    done
    sleep 600
done
