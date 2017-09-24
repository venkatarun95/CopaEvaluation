#!/bin/bash

output_directory=FCT
num_on_off=2
user=venkat

if [[ $# != 2 ]] && [[ $1 == "run" ]]; then
    echo "Usage: ./experiment-fct [run|graph] [receiver_ip]"
    exit
fi
receiver_ip=$2

if [[ $1 == "run" ]]; then
    if [[ ! -d $output_directory ]]; then
        mkdir $output_directory
    fi

    for tcp in "copa" "cubic" "bbr"; do
        if [[ -d $output_directory/$tcp ]]; then
            echo "Results for $tcp exist. Skipping"
            continue
        fi
        mkdir $output_directory/$tcp
        sudo sysctl -w net.core.default_qdisc=pfifo_fast
        if [[ $tcp == "bbr" ]]; then
            sudo sysctl -w net.ipv4.tcp_congestion_control=bbr
        elif [[ $tcp == "cubic" ]]; then
             sudo sysctl -w net.ipv4.tcp_congestion_control=cubic
        fi

        helper_pids=""
        for (( i=0; $i < $num_on_off; i++ )); do
            outfile=$output_directory/$tcp/`python -c "import random; print(random.randint(0, 1e9))"`.log
            chown -R $user $output_directory
            su -c "mm-delay 0 ./experiment-fct-helper.sh $tcp $receiver_ip $outfile &" $user
            helper_pids="$helper_pids $!"
        done
        sleep 100
        pkill -9 $helper_pids
    done

elif [[ $1 == "graph" ]]; then
    if [[ -d $output_directory/graphdir ]]; then 
        trash $output_directory/graphdir
    fi
    mkdir $output_directory/graphdir
    for tcp_dir in $output_directory/*; do
        echo $tcp_dir
        tcp=`expr "$tcp_dir" : '.*/\([^/]*\)'`
        if [[ $tcp == "copa" ]]; then
            for file in $tcp_dir/*.log; do
                while read p; do
                    tmp_tpt=`echo $p | grep '^\s*Throughput:\ ' | grep -o '[0-9.]*'`
                    if [[ ! -z "$tmp_tpt" ]]; then
                        if [[ ! -z "$tpt" ]]; then
                            echo "Got two throughput values at once. '$tmp_tpt' and '$tpt'"
                        fi
                        tpt=$tmp_tpt
                    fi
                    fct=`echo $p | grep '^\s*Completion time:\ ' | grep -o '[0-9.]*'`
                    if [[ ! -z "$fct" ]]; then
                        bytes=`awk "BEGIN{print($fct * $tpt)}"`
                        echo " $bytes $fct" >>$output_directory/graphdir/$tcp.dat
                        tpt=""
                        fct=""
                    fi
                    echo $p
                done < $file
            done
            cat $output_directory/graphdir/$tcp.dat | sort -n > /tmp/copa-sorted
            mv /tmp/copa-sorted $output_directory/graphdir/$tcp.dat
        else
            cat $tcp_dir/* | grep -v Command | sort -n >$output_directory/graphdir/$tcp.dat
        fi
    done

    for tcp_dat in $output_directory/graphdir/*.dat; do
        awk 'BEGIN{bucket_start=100}{ \
if ($1 < 2*bucket_start) { \
  bucket_sum += $2; \
  bucket_sum_sq += $2 * $2; \
  bucket_size += 1; \
} \
else { \
  if (bucket_size > 0) { \
    print bucket_start, bucket_sum / bucket_size, sqrt(bucket_sum_sq / bucket_size - bucket_sum * bucket_sum / (bucket_size * bucket_size)); \
  } \
  bucket_start += 1000; \
  bucket_size = 0; bucket_sum = 0; bucket_sum_sq = 0; \
} \
}' $tcp_dat >$tcp_dat.bkts
    done
else
    echo "Unrecognized command '$1'"
fi
