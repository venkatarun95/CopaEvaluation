#!/bin/bash

trace_dir=~/traces
out_dir=CellularNetworkTraces

if [[ ! -d $out_dir ]]; then
		mkdir $out_dir
fi

for trace in "ATT-LTE-driving" "TMobile-UMTS-driving" "Verizon-EVDO-driving" "Verizon-LTE-driving" "Verizon-LTE-short"
do
		echo "Running on $trace trace"
		trace_path=$trace_dir/$trace
		#./long-run.sh clean $trace
		#for delta in "0.1" "0.5" "1"; do
		#		./long-run.sh run markovian $trace_path 0 $out_dir/$trace constant_delta:$delta
		#done
		for cc in "sprout"; do # "pcc" "cubic"; do
				./long-run.sh run $cc $trace_path 0 $out_dir/$trace
		done
done
