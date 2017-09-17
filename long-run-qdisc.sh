#!/bin/bash

# Global configuration constants
# Note: Do not put a / after directory names
bin_dir=../bin
receiver_ip="127.0.0.1"
source_ip="127.0.0.1"
on_duration=60000 # in ms
off_duration=1 # in ms
HZ=100 # HZ value of kernel

output_file_name() {
    if [[ $cc_type == "markovian" ]]; then
	of_dir=$output_directory/markovian
	of_name=$of_dir/markovian
    elif [[ $cc_type == "remy" ]]; then
	of_dir=$output_directory/remy # Not giving rat name as of now
	of_name=$of_dir/remy
    elif [[ $cc_type == "sprout" ]] || [ $cc_type == "pcc" ] || [[ $cc_type == "pcp" ]] || [[ $cc_type == "cubic" ]] || [[ $cc_type == "reno" ]] || [[ $cc_type == "vegas" ]] || [[ $cc_type == "bbr" ]]; then
	of_dir=$output_directory/$cc_type
	of_name=$of_dir/$cc_type
    else
	echo "Control shouldn't reach here"
	exit
    fi
}

if [[ $1 == "run" ]]; then
    # Read arguments
    cc_type=$2
    link_rate=$3
    min_delay=$4
    loss_rate=$5
    output_directory=$6
    nsrc=`expr "$7" : '\(.*\):.*'`
    traffic_type=`expr "$7" : '.*:\(.*\)'`
    queue_length=$8
    run_time=$9
    delta_conf=${10} # If present

    # Set up appropriate qdiscs
    op_netem=add
    op_tbf=add
    if tc qdisc show dev lo | grep -q netem; then op_netem=change; fi
    if tc qdisc show dev lo | grep -q tbf; then op_tbf=change; fi
    # if tc qdisc show dev lo | grep -q fq; then
    #     sudo tc qdisc del dev lo parent 10: handle 11: fq
    # fi
    
    burst=`awk -v r=$link_rate -v hz=$HZ 'END{print 2*r*1e6/(hz*8)}' /dev/null`
    sudo ifconfig lo mtu 1600 # Otherwise MTU is 100kbytes in local loopback, which can cause problems in tbf
    sudo tc qdisc $op_netem dev lo root handle 1:1 netem delay $(echo $min_delay)ms loss $loss_rate
    sudo tc qdisc $op_tbf   dev lo parent 1:1 handle 10: tbf rate $(echo $link_rate)mbit limit $queue_length burst $queue_length
    # if [[ $cc_type == "bbr" ]]; then
    #     sudo tc qdisc add dev lo parent 10: handle 11: fq limit $queue_length flow_limit `expr $queue_length / 1000`
    # fi

    # Setup output files
    output_file_name # sets of_name and of_dir
    if [[ ! -d $of_dir ]]; then
	mkdir $of_dir
    fi

    if [[ -f /tmp/long-run-qdisc.pcap ]]; then
        rm /tmp/long-run-qdisc.pcap
    fi
    tcpdump -w /tmp/long-run-qdisc.pcap -i lo -n &
    ping $receiver_ip > $of_name.ping &
    if [[ $cc_type == "markovian" ]]; then
	echo "Assuming receiver is available at $receiver_ip"

	#export MIN_RTT=`awk -v min_delay=$min_delay 'END{print 2*min_delay;}' /dev/null`
	export MIN_RTT=10000000

	./run-genericcc-sender.sh "$bin_dir/sender sourceip=$source_ip serverip=$receiver_ip cctype=markovian delta_conf=$delta_conf" $nsrc $traffic_type $run_time $on_duration $off_duration \
				  1> $of_name.stdout 2> $of_name.stderr

    elif [[ $cc_type == "remy" ]]; then
	rat_file=$9
	echo "Assuming receiver is available at $receiver_ip"
	export MIN_RTT=1
	./run-genericcc-sender.sh "$bin_dir/sender sourceip=$source_ip serverip=$receiver_ip cctype=remy if=$rat_file" $nsrc $traffic_type $run_time $on_duration $off_duration \
				  1> $of_name.stdout 2> $of_name.stderr

    elif [[ $cc_type == "sprout" ]]; then
	echo "Assuming sprout server is available at $receiver_ip"
	$bin_dir/sproutbt2 $receiver_ip 60001 \
			   1> $of_name.stdout 2> $of_name.stderr &
	child_pid=$!
	echo $child_pid
	sleep $(( $run_time / 1000 + 35 ))
	kill $child_pid
	# Remove the part where the link was doing nothing, waiting for sprout precomputation
	awk -F ' ' 'BEGIN {x=0} {if(x==1 || ($1 == "#" && $2 != "base"))print $0; else {if($2=="+"){print "# base timestamp:", $1;print $0; x=1;}}}' $of_name.uplink >$of_name.uplink2
	mv $of_name.uplink2 $of_name.uplink

    elif [[ $cc_type == "pcp" ]]; then
	echo "Assuming 'pcp-server' was run at $receiver_ip:8745"
	./run-pcc-sender.sh "$bin_dir/pcp $receiver_ip 8745 1000000000 1 0.00001 1" $nsrc $traffic_type $run_time $on_duration $off_duration
	> $of_name.stdout 2> $of_name.stderr

    elif [[ $cc_type == "cubic" ]] || [[ $cc_type == "reno" ]] || [[ $cc_type == "vegas" ]]; then
	      echo "Assuming 'iperf -s' was run at $receiver_ip"
	#sudo sysctl -w net.ipv4.tcp_congestion_control=$cc_type
	#echo "Using default kernel TCP as root priviledges are required to change TCP"
	./run-iperf-sender.sh $receiver_ip $on_duration $cc_type $nsrc \
				                1> $of_name.stdout 2> $of_name.stderr

    elif [[ $cc_type == "bbr" ]]; then
        if [[ ! $nsrc -eq 1 ]]; then
            echo "Support for multiple BBR flows not yet available"
        fi
        iperf -c $receiver_ip -t `expr $on_duration / 1000` -Z bbr > $of_name.stdout 2> $of_name.stderr

    elif [[ $cc_type == "pcc" ]]; then
	echo "Assuming pcc receiver was run at $receiver_ip"
	./run-pcc-sender.sh "$bin_dir/appclient $receiver_ip 9000" $nsrc $traffic_type $run_time $on_duration $off_duration \
			    1> $of_name.stdout 2> $of_name.stderr
    else
	echo "Could not find cc_type '$cc_type'. It is either unsupported or not yet implemented"
    fi
    pkill tcpdump
    pkill tcpdump
    pkill ping
    pkill ping
    tcptrace -lu /tmp/long-run-qdisc.pcap > $of_name.pcap-trace
    rm /tmp/long-run-qdisc.pcap
    
elif [[ $1 == "graph" ]]; then

    output_directory=$2
    if [[ -d $output_directory/graphdir ]]; then
	rm -r $output_directory/graphdir
    fi
    mkdir $output_directory/graphdir
    for dir in $output_directory/*; do
	if [[ ! -d $dir ]] || [[ $dir == *graphdir ]]; then
	    continue
	fi
	nice_name=`expr "$dir" : '.*/\([^/]*\)'`

        if [[ `grep throughput $dir/$nice_name.pcap-trace | wc -l` -ge 2 ]]; then
            echo "Error: multiple connections found in trace. Skipping"
            continue
        fi

        tpt=`grep throughput $dir/$nice_name.pcap-trace | awk '{if ($2 > $5) print $2*1e-6; else print $5*1e-6}'`
        echo $nice_name $tpt >> $output_directory/graphdir/tpt.data
	#echo $nice_name `grep throughput $dir/$nice_name.stats | awk -F ' ' '{print $3}'` `grep queueing $dir/$nice_name.stats | awk -F ' ' '{print $6}'` >> $output_directory/graphdir/tpt-del.data
    done

elif [[ $1 == "clean" ]]; then
    echo "Not yet implemented"
else
    echo "Usage: long-run command [args]"
    echo "  Commands:"
    echo "    run - Run emulation. Usage: 'run cc_type link_rate min_delay loss_rate output_directory nsrc:exponential|continuous queue_length run_time [delta_conf|rat_file]'"
    echo "    graph - Graph results from directory. Usage: 'graph output_directory'"
    echo "    clean - Clean directory. Usage: 'clean output_directory'"
    echo "  Explanation:"
    echo "    cc_type: One of markovian, remy, sprout, pcc, pcp, cubic and reno."
    echo "    link_rate: Rate for both up- and down-link in Mbits/s."
    echo "    min_delay: Minimum delay in ms."
    echo "    loss_rate: % packet loss."
    echo "    output_directory: Directory where both raw data and graphs are dumped."
    echo "    nsrc: Number of senders + type of traffic. If exponential, predetermined exponential distribution will be used, else a predetermined continuous run will be used."
    echo "    queue_length: Droptail queue length in bytes. If 0, infinite queue will be used."
    echo "    run_time: Time (in ms) to run the sender."
fi
