#!/bin/bash

num_flows=10
output_directory=Dynamic
interface=lo
receiver_ip=127.0.0.1
inter_flow_time=1 # In seconds
bin=../bin
HZ=100 # HZ value of kernel

if [[ -d $output_directory ]]; then
    echo "Directory $output_directory already exists."
    #exit
fi
mkdir $output_directory

# Set up qdiscs
op_netem=add
op_tbf=add
if tc qdisc show dev $interface | grep -q netem; then op_netem=change; fi
if tc qdisc show dev $interface | grep -q tbf; then op_tbf=change; fi

# Note: the variable r here is link rate in Mbits/s
burst=`awk -v r=100 -v hz=$HZ 'END{print 2*r*1e6/(hz*8)}' /dev/null`
sudo ifconfig $interface mtu 1600 # Otherwise MTU is 100kbytes in local loopback, which can cause problems in tbf
sudo tc qdisc $op_netem dev $interface root handle 1:1 netem delay 10ms loss 0
sudo tc qdisc $op_tbf   dev $interface parent 1:1 handle 10: tbf rate 100mbit limit 250000 burst 250000

for tcp in "copa" "cubic" "reno" "pcc"; do
    if [[ -f $output_directory/$tcp-pcap-trace ]]; then
        echo "File for $tcp already exists. Skipping"
        continue
    fi
    tcpdump -w $output_directory/$tcp-pcap-trace -i $interface -n &

    sender_pids=""
    for (( i=0; i < $num_flows; i++ )); do
        onduration=`expr 2 \* $inter_flow_time \* \( $num_flows - $i - 1 \) + 1`
        if [[ $tcp == "cubic" ]] || [[ $tcp == "reno" ]]; then
            iperf -c $receiver_ip -Z $tcp -t $onduration &
            sender_pids="$sender_pids $!"
        elif [[ $tcp == "copa" ]]; then
            export MIN_RTT=1000000000
            $bin/sender cctype=markovian serverip=$receiver_ip offduration=0 traffic_params=deterministic,num_cycles=1 delta_conf=auto onduration=`expr $onduration \* 1000` >/dev/null &
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
        sleep $inter_flow_time
    done
    echo `expr $num_flows \* $inter_flow_time - 1`
    sleep `expr $num_flows \* $inter_flow_time - 1`
    if [[ $tcp == "copa" ]]; then
        sleep 2
    fi
    echo Killing

    kill $sender_pids
    pkill tcpdump
    pkill tcpdump
done
