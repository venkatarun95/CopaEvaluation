#!/bin/bash

trace_file=~/traces/trace-32Mbps
min_delay=25 # One way delay in ms
queue_length=`expr 2 \* $min_delay \* 32000000 / 8000`
output_directory=LongRun
nsrc=3
rat_file=rats/fig2-linkspeed/bigbertha-100x.dna.5

if [[ ! -d $output_directory ]]; then
		mkdir $output_directory
fi

for delta_conf in "constant_delta:0.01" "constant_delta:0.1" "constant_delta:0.5" "constant_delta:1"; do
		runstr="./long-run.sh run markovian $trace_file $min_delay 0 $output_directory $nsrc:continuous $queue_length $delta_conf"
		echo $runstr
		$runstr
done

for cc_type in "remy" "pcc" "cubic"; do
		runstr="./long-run.sh run $cc_type $trace_file $min_delay 0 $output_directory $nsrc:continuous $queue_length $rat_file"
		echo $runstr
		$runstr
done
