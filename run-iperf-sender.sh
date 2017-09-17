#!/bin/bash

receiver_ip=$1
run_time=$2
cc_type=$3
nsrc=$4

if [[ ! $nsrc -eq 1 ]]; then
    echo "Running more than one iperf sender is not yet supported"
    exit
fi

#for (( i=0; i < $nsrc; i++ )); do
    iperf -c $receiver_ip -t `expr $run_time / 1000` -Z $cc_type
    # pids="$pids $!"
#done
# sleep `expr $run_time / 1000 + 1`
# kill $pids

