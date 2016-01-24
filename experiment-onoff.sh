#!/bin/bash

trace_file=~/traces/trace-32Mbps
min_delay=25 # One way delay in ms
queue_length=`expr $min_delay \* 32000000 / 8000`
output_directory=OnOff
nsrc=3
rat_file=../evaluations/rats/fig2-linkspeed/bigbertha-100x.dna.5

if [[ ! -d $output_directory ]]; then
		mkdir $output_directory
fi

for delta_conf in "constant_delta:0.1" "constant_delta:0.5" "constant_delta:1"; do
	  ./long-run.sh run markovian $trace_file $min_delay 0 $output_directory $nsrc:exponential $queue_length $delta_conf
done

for cc_type in "pcc"; do #"pcc" "cubic" "remy"; do
		./long-run.sh run $cc_type $trace_file $min_delay 0 $output_directory $nsrc:exponential $queue_length $rat_file
done
