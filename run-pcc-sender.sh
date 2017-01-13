#!/bin/bash

run_str=$1
nsrc=$2
traffic_type=$3
run_time=$4
on_duration=$5
off_duration=$6

echo $nsrc $traffic_type $run_time $on_duration $off_duration

if [[ $traffic_type == "exponential" ]]; then
		run_str="mm-onoff uplink $on_duration $off_duration $run_str"
elif [[ $traffic_type == "continuous" ]]; then
		run_str="$run_str" # Do nothing
else
		echo "Unidentified traffic_type. Control shouldn't reach here."
fi

export LD_LIBRARY_PATH=../pcc/sender/src/

for (( i=0; $i < $nsrc; i++ )); do
		echo "$run_str $i"
		$run_str &
		pids="$pids $!"
done
sleep `expr $run_time / 1000 + 1`
kill $pids
