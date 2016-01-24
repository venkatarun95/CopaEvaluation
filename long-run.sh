#!/bin/bash

# Global configuration constants
# Note: Do not put a / after directory names
bin_dir=../bin
receiver_ip="100.64.0.1"
source_ip="100.64.0.5"
run_time=100000 # in ms
on_duration=600000 # in ms
off_duration=1 # in ms

output_file_name() {
		if [[ $cc_type == "markovian" ]]; then
				of_dir=$output_directory/markovian-$delta_conf
				of_name=$of_dir/markovian-$delta_conf
		elif [[ $cc_type == "remy" ]]; then
				of_dir=$output_directory/remy # Not giving rat name as of now
				of_name=$of_dir/remy
		elif [[ $cc_type == "sprout" ]] || [ $cc_type == "pcc" ] || [[ $cc_type == "pcp" ]] || [[ $cc_type == "cubic" ]] || [[ $cc_type == "reno" ]]; then
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
		trace_file=$3
		min_delay=$4
		loss_rate=$5
		output_directory=$6
		nsrc=`expr "$7" : '\(.*\):.*'`
		traffic_type=`expr "$7" : '.*:\(.*\)'`
		queue_length=$8
		delta_conf=$9 # If present

		if [[ -f $trace_file ]]; then
				trace_uplink=$trace_file
				trace_downlink=$trace_file
		else
				trace_uplink=$trace_file.up
				trace_downlink=$trace_file.down
				if [[ ! -f $trace_uplink ]] || [[ ! -f $trace_downlink ]]; then
						echo "Could not find specified trace file"
						exit
				fi
		fi
		if [[ ! -d $output_directory ]]; then
				mkdir $output_directory
		fi

		if [[ $queue_length == "0" ]]; then
				queue_length_params="--uplink-queue=infinite --downlink-queue=infinite"
		else
				queue_length_params="--uplink-queue=droptail --uplink-queue-args=\"bytes=$queue_length\" --downlink-queue=droptail --downlink-queue-args=\"bytes=$queue_length\""
		fi

		output_file_name # sets of_name and of_dir
		if [[ ! -d $of_dir ]]; then
				mkdir $of_dir
		fi

		if [[ $cc_type == "markovian" ]]; then
				delta_conf=$9
				echo "Assuming receiver is available at $receiver_ip"

				export MIN_RTT=`awk -v min_delay=$min_delay 'END{print 2*min_delay;}' /dev/null`
				mm-delay $min_delay \
						mm-loss uplink $loss_rate \
						mm-link $trace_uplink $trace_downlink --uplink-log $of_name.uplink --downlink-log $of_name.downlink $queue_length_params \
						./run-genericcc-sender.sh "$bin_dir/sender sourceip=$source_ip serverip=$receiver_ip cctype=markovian delta_conf=$delta_conf" $nsrc $traffic_type $run_time $on_duration $off_duration \
						1> $of_name.stdout 2> $of_name.stderr

		elif [[ $cc_type == "remy" ]]; then
				rat_file=$9
				echo "Assuming receiver is available at $receiver_ip"
				export MIN_RTT=1
				mm-delay $min_delay \
						mm-loss uplink $loss_rate \
						mm-link $trace_uplink $trace_downlink --uplink-log $of_name.uplink --downlink-log $of_name.downlink $queue_length_params \
						./run-genericcc-sender.sh "$bin_dir/sender sourceip=$source_ip serverip=$receiver_ip cctype=remy if=$rat_file" $nsrc $traffic_type $run_time $on_duration $off_duration \
						1> $of_name.stdout 2> $of_name.stderr

		elif [[ $cc_type == "sprout" ]]; then
				echo "Assuming sprout server is available at $receiver_ip"
				mm-delay $min_delay \
						mm-loss uplink $loss_rate \
						mm-link $trace_uplink $trace_downlink --uplink-log $of_name.uplink --downlink-log $of_name.downlink $queue_length_params \
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
				mm-delay $min_delay \
						mm-loss uplink $loss_rate \
						mm-link $trace_uplink $trace_downlink --uplink-log $of_name.uplink --downlink-log $of_name.downlink $queue_length_params \
						./run-pcc-sender.sh "$bin_dir/pcp $receiver_ip 8745 1000000000 1 0.00001 1" $nsrc $traffic_type $run_time $on_duration $off_duration
				    > $of_name.stdout 2> $of_name.stderr

		elif [[ $cc_type == "cubic" ]] || [[ $cc_type == "reno" ]]; then
				echo "Assuming 'iperf -s' was run at $receiver_ip"
				#sudo sysctl -w net.ipv4.tcp_congestion_control=$cc_type
				echo "Using default kernel TCP as root priviledges are required to change TCP"
				mm-delay $min_delay \
						mm-loss uplink $loss_rate \
						mm-link $trace_uplink $trace_downlink --uplink-log $of_name.uplink --downlink-log $of_name.downlink $queue_length_params \
						./run-genericcc-sender.sh "$bin_dir/sender sourceip=$source_ip serverip=$receiver_ip cctype=kernel offduration=1 onduration=$run_time traffic_params=deterministic,num_cycles=1" $nsrc $traffic_type $run_time $on_duration $off_duration \
						1> $of_name.stdout 2> $of_name.stderr

		elif [[ $cc_type == "pcc" ]]; then
				echo "Assuming pcc receiver was run at $receiver_ip"
				mm-delay $min_delay \
						mm-loss uplink $loss_rate \
						mm-link $trace_uplink $trace_downlink --uplink-log $of_name.uplink --downlink-log $of_name.downlink $queue_length_params \
						./run-pcc-sender.sh "$bin_dir/appclient $receiver_ip 9000" $nsrc $traffic_type $run_time $on_duration $off_duration \
						1> $of_name.stdout 2> $of_name.stderr
		else
				echo "Could not find cc_type '$cc_type'. It is either unsupported or not yet implemented"
		fi

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
				#mm-throughput-graph 1000 $dir/$nice_name.uplink >$dir/$nice_name.tpt-graph 2>$dir/$nice_name.stats
				echo $nice_name `grep throughput $dir/$nice_name.stats | awk -F ' ' '{print $3}'` `grep queueing $dir/$nice_name.stats | awk -F ' ' '{print $6}'` >> $output_directory/graphdir/tpt-del.data
		done

		echo "set terminal svg fsize 14; set output '$output_directory/graphdir/tpt-del.svg'; 
          set xlabel '95th Percentile Queuing Delay (ms)'; set ylabel 'Throughput (Mbps)';
          set title 'Performance on an Emulated Cellular Network'; 
          set xrange [] reverse; set logscale x 2;
          plot '$output_directory/graphdir/tpt-del.data' using 3:2:1 with labels point  pt 7 offset char 1,1 notitle;" > $output_directory/graphdir/tpt-del.gnuplot
		gnuplot -p $output_directory/graphdir/tpt-del.gnuplot
		inkscape --export-png $output_directory/graphdir/tpt-del.png -b '#ffffff' -D $output_directory/graphdir/tpt-del.svg
elif [[ $1 == "clean" ]]; then
		echo "Not yet implemented"
else
		echo "Usage: long-run command [args]"
		echo "  Commands:"
		echo "    run - Run emulation. Usage: 'run cc_type trace_file min_delay loss_rate output_directory nsrc:exponential|continuous queue_length [delta_conf|rat_file]'"
    echo "    graph - Graph results from directory. Usage: 'graph output_directory'"
    echo "    clean - Clean directory. Usage: 'clean output_directory'"
		echo "  Explanation:"
		echo "    cc_type: One of markovian, remy, sprout, pcc, pcp, cubic and reno."
		echo "    trace_file: If found, used for both uplink and downlink, else filename.up and filename.down are used."
		echo "    min_delay: Minimum delay in ms."
		echo "    loss_rate: Fraction of packets lost between 0 and 1."
		echo "    output_directory: Directory where both raw data and graphs are dumped."
		echo "    nsrc: Number of senders + type of traffic. If exponential, predetermined exponential distribution will be used, else a predetermined continuous run will be used."
		echo "    queue_length: Droptail queue length in bytes. If 0, infinite queue will be used."
fi
