#!/bin/bash

trace_file=~/traces/trace-32Mbps
min_delay=25 # One way delay in ms
queue_length=`expr 2 \* $min_delay \* 32000000 / 8000`
output_directory=LossyLink
nsrc=2
rat_file=../evaluations/rats/fig2-linkspeed/bigbertha-100x.dna.5

if [[ ! -d $output_directory ]]; then
		mkdir $output_directory
fi

if [[ $1 == "run" ]]; then
		for (( i = 0; i < 11; i=i+1 )); do
				loss_rate=`awk -v i=$i 'END{if(i < 5)print i * 0.002; else print (i-4) * 0.01}' /dev/null`
				echo "Running on loss rate = $loss_rate"
				for delta_conf in "constant_delta:0.1" "constant_delta:0.5" "constant_delta:1"; do
						runstr="./long-run.sh run markovian $trace_file $min_delay $loss_rate $output_directory $nsrc:continuous $queue_length $delta_conf"
						echo $runstr
						$runstr
						if [[ -d $output_directory/markovian-$delta_conf::$loss_rate ]]; then
								trash $output_directory/markovian-$delta_conf::$loss_rate
						fi
						mv $output_directory/markovian-$delta_conf $output_directory/markovian-$delta_conf::$loss_rate
				done
				
				for cc_type in "remy" "pcc" "cubic"; do
						runstr="./long-run.sh run $cc_type $trace_file $min_delay $loss_rate $output_directory $nsrc:continuous $queue_length $rat_file"
						echo $runstr
						$runstr
						if [[ -d $output_directory/$cc_type::$loss_rate ]]; then
								trash $output_directory/$cc_type::$loss_rate
						fi
						mv $output_directory/$cc_type $output_directory/$cc_type::$loss_rate
				done
		done

elif [[ $1 == "graph" ]]; then
		if [[ -d $output_directory/graphdir ]]; then
				trash $output_directory/graphdir
		fi
		mkdir $output_directory/graphdir

		for tcp_dir in $output_directory/*::*; do
				tcp=`expr "$tcp_dir" : ".*/\([^/]*\)::[0-9.]*"`
				loss_rate=`expr "$tcp_dir" : ".*::\([0-9.]*\)"`
				
				# Gather statistics
				#mm-throughput-graph 100 $tcp_dir/$tcp.uplink >$tcp_dir/$tcp.tpt-graph 2>$tcp_dir/$tcp.stats
				throughput=`grep throughput $tcp_dir/$tcp.stats | awk -F ' ' '{print $3}'`
				delay=`grep 95.*queueing $tcp_dir/$tcp.stats | awk -F ' ' '{print $6}'`
				echo $loss_rate $throughput $delay >>$output_directory/graphdir/$tcp.dat
		done

		# Create gnuplot script
		gnuplot_script="set xlabel 'Loss Rate'; set ylabel 'Throughput (Mbps)';
    set terminal svg fsize 14; set output '$output_directory/graphdir/loss-tpt.svg'; 
    plot " >>$output_directory/graphdir/loss-tpt.gnuplot
		for tcp in $output_directory/graphdir/*.dat; do
				tcp_nice=`expr "$tcp" : ".*/\([^/]*\).dat"`
				echo $tcp $tcp_nice
				gnuplot_script="$gnuplot_script '$tcp' using 1:2 title '$tcp_nice' with lines, "
		done
		echo $gnuplot_script >$output_directory/graphdir/loss-tpt.gnuplot
	
		gnuplot -p $output_directory/graphdir/loss-tpt.gnuplot
		inkscape --export-png=$output_directory/graphdir/loss-tpt.png -b '#ffffff' -D $output_directory/graphdir/loss-tpt.svg
		display $output_directory/graphdir/loss-tpt.png

elif [[ $1 == "clean" ]]; then
		trash $output_directory

else
		echo "Unrecognized command '$1'."
		echo "   Expected one of [run|graph|clean]"
fi
