#!/bin/bash

output_directory=RTTFairness
interface=lo
receiver_ip=100.64.0.1
bin=../bin
trace=~/traces/trace-12Mbps
queue_len=450000
onduration=10 # in sec

if [[ $1 == "run" ]]; then
    if [[ -d $output_directory ]]; then
        echo "Directory $output_directory already exists."
    else
        mkdir $output_directory
    fi

    cat >/tmp/expt-rtt-fairness-script <<EOF
for (( i=15; i <= 15; i=\$i+15 )); do
    mm-delay \$(( \$i / 2 )) iperf -c $receiver_ip -Z \$1 -t $onduration &
done
EOF
    chmod +x /tmp/expt-rtt-fairness-script

    for tcp in "cubic"; do
        if [[ $tcp == "cubic" ]] || [[ $tcp == "reno" ]] || [[ $tcp == "vegas" ]]; then
            mm-link $trace $trace --uplink-queue=droptail --uplink-queue-args=bytes=$queue_len bash /tmp/expt-rtt-fairness-script $tcp
            sender_pids="$sender_pids $!"
        elif [[ $tcp == "copa" ]]; then
            export MIN_RTT=1000000000
            $bin/sender cctype=markovian serverip=$receiver_ip offduration=0 traffic_params=deterministic,num_cycles=1 delta_conf=do_ss:auto:0.5 onduration=`expr $onduration \* 1000` >/dev/null &
            sender_pids="$sender_pids $!"
            echo `expr $onduration \* 1000`
        elif [[ $tcp == "pcc" ]]; then
            export LD_LIBRARY_PATH=$bin/pcc_sender
            printf "`pwd`/$bin/appclient $receiver_ip 9000 & \nid=\$!\n sleep $onduration\n kill \$id" >/tmp/experiment-dynamic-run-pcc
            chmod +x /tmp/experiment-dynamic-run-pcc
            /tmp/experiment-dynamic-run-pcc &
        elif [[ $tcp == "bbr" ]]; then
            if [[ $interface == "lo" ]]; then
                echo "Can't support bbr on lo because the fq will have to be global for all flows"
            fi
            su -c "mm-delay 0 ./run-bbr-sender \"iperf -c $receiver_ip -t $onduration -Z bbr\" $interface &" ubuntu
        fi
    done
else
    echo "Unrecognized command '$1'"
fi
