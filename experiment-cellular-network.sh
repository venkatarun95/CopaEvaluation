#!/bin/bash

trace_dir=~/traces
out_dir=CellularNetworkTraces
rat_file=rats/fig2-linkspeed/bigbertha-100x.dna.5

if [[ ! -d $out_dir ]]; then
		mkdir $out_dir
fi

for trace in "ATT-LTE-driving" #"ATT-LTE-driving" "TMobile-UMTS-driving" "Verizon-EVDO-driving" "Verizon-LTE-driving" "Verizon-LTE-short"
do
		echo "Running on $trace trace"
		trace_path=$trace_dir/$trace
		#./long-run.sh clean $trace
		for delta_conf in "constant_delta:1"; do
				./long-run.sh run markovian $trace_path 1 0 $out_dir/$trace 1:continuous 200000 $delta_conf
		done
		for cc in "sprout" "pcc" "cubic" "remy"; do
				./long-run.sh run $cc $trace_path 1 0 $out_dir/$trace 1:continuous 200000 $rat_file
		done
done
