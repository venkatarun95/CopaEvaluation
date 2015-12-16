#!/bin/bash

run_str=$1
nsrc=$2
traffic_type=$3
run_time=$4
on_duration=$5
off_duration=$6

echo $run_str $nsrc $traffic_type $run_time $on_duration $off_duration

if [[ $traffic_type == "exponential" ]]; then
		params="traffic_params=exponential onduration=$on_duration offduration=$off_duration"
elif [[ $traffic_type == "continuous" ]]; then
		params="traffic_params=deterministic,num_cycles=1 onduration=$run_time offduration=1"
else
		echo "Unidentified traffic_type. Control shouldn't reach here."
fi
run_str="$run_str $params"

for (( i=0; i < $nsrc; i++ )); do
		$run_str &
		pids="$pids $!"
done
sleep `expr $run_time / 1000 + 1`
kill $pids
