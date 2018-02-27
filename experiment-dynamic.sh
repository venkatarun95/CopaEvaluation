#!/bin/bash

num_flows=10
output_directory=Dynamic
interface=eth0
receiver_ip=34.227.114.168
inter_flow_time=1 # In seconds
bin=../bin
HZ=100 # HZ value of kernel

if [[ $1 == "run" ]]; then
    echo
    if [[ -d $output_directory ]]; then
        echo "Directory $output_directory already exists."
    else
        mkdir $output_directory
    fi

    # Set up qdiscs
    op_netem=add
    op_tbf=add
    if tc qdisc show dev $interface | grep -q netem; then op_netem=change; fi
    if tc qdisc show dev $interface | grep -q tbf; then op_tbf=change; fi

    # Note: the variable r here is link rate in Mbits/s
    burst=`awk -v r=100 -v hz=$HZ 'END{print 2*r*1e6/(hz*8)}' /dev/null`
    sudo ifconfig $interface mtu 1600 # Otherwise MTU is 100kbytes in local loopback, which can cause problems in tbf
    sudo tc qdisc $op_netem dev $interface root handle 1:1 netem delay 10ms loss 0
    sudo tc qdisc $op_tbf   dev $interface parent 1:1 handle 10: tbf rate 100mbit limit 250000 burst 250000

    for tcp in "copa" "bbr" "cubic" "pcc"; do # "cubic" "reno" "pcc" "bbr" "vegas"; do
        if [[ -f $output_directory/$tcp-pcap-trace ]]; then
            echo "File for $tcp already exists. Skipping"
            continue
        fi
        tcpdump -w $output_directory/$tcp-pcap-trace -i $interface -n &

        sender_pids=""
        for (( i=0; i < $num_flows; i++ )); do
            onduration=`expr 2 \* $inter_flow_time \* \( $num_flows - $i - 1 \) + 1`
            if [[ $tcp == "cubic" ]] || [[ $tcp == "reno" ]] || [[ $tcp == "vegas" ]]; then
                iperf -c $receiver_ip -Z $tcp -t $onduration &
                sender_pids="$sender_pids $!"
            elif [[ $tcp == "copa" ]]; then
                #export MIN_RTT=1000000000
                $bin/sender cctype=markovian serverip=$receiver_ip offduration=0 traffic_params=deterministic,num_cycles=1 delta_conf=do_ss:auto:0.5 onduration=`expr $onduration \* 1000`  &
                sender_pids="$sender_pids $!"
                #echo `expr $onduration \* 1000`
            elif [[ $tcp == "pcc" ]]; then
                export LD_LIBRARY_PATH=$bin/pcc_sender
                printf "`pwd`/$bin/appclient $receiver_ip 9000 & \nid=\$!\n sleep $onduration\n kill \$id" >/tmp/experiment-dynamic-run-pcc
                chmod +x /tmp/experiment-dynamic-run-pcc
                /tmp/experiment-dynamic-run-pcc &
            elif [[ $tcp == "bbr" ]]; then
                if [[ $interface == "lo" ]]; then
                    echo "Can't support bbr on lo because the fq will have to be global for all flows"
                fi
                su -c "mm-delay 0 ./run-bbr-sender \"iperf -c $receiver_ip -t $onduration -Z bbr\" ingress /tmp/experiment-dynamic-bbr.log &" ubuntu
            fi
            sleep $inter_flow_time
        done
        echo `expr $num_flows \* $inter_flow_time - 1`
        sleep `expr $num_flows \* $inter_flow_time - 1`
        if [[ $tcp == "copa" ]]; then
            sleep 2
        fi
        echo Killing

        kill $sender_pids
        pkill tcpdump
        pkill tcpdump
    done

elif [[ $1 == "graph" ]]; then
    for x in $output_directory/*-pcap-trace; do
        #if [[ ! -f $x-tptpoly.dat ]]; then
            python pcap-tpt-graph.py $x
        #fi
    done
    polyplot=$output_directory/dynamic-polyplot
    cat > $polyplot.gnuplot <<- EOM
set terminal svg fsize 14
set output "$polyplot.svg"
set title "Dynamic Behavior of TCPs"
set style fill transparent solid 0.5 noborder
set xlabel "Time (s)"
set ylabel "Throughput (Mbits/s)"
set xrange [0:19]
set yrange [1:100]
set logscale y

plot 'Dynamic/pcc-pcap-trace-tptpoly.dat' using 1:2 with filledcurves title 'PCC', 'Dynamic/bbr-pcap-trace-tptpoly.dat' using 1:2 with filledcurves title 'BBR', 'Dynamic/vegas-pcap-trace-tptpoly.dat' using 1:2 with filledcurves title 'Vegas' lt -1, 'Dynamic/cubic-pcap-trace-tptpoly.dat' using 1:2 with filledcurves title 'Cubic' lt 7, 'Dynamic/copa-pcap-trace-tptpoly.dat' using 1:2 with filledcurves title 'Copa', 'Ideal' using 1:2 with lines lt -1 title "Ideal"
#plot 'Dynamic/cubic-pcap-trace-tptpoly.dat' using 1:2 with filledcurves title 'Cubic' lt 7, 'Dynamic/copa-pcap-trace-tptpoly.dat' using 1:2 with filledcurves title 'Copa', 'Ideal' using 1:2 with lines lt -1 title "Ideal"
EOM
    gnuplot -p $polyplot.gnuplot
    inkscape -A $polyplot.pdf $polyplot.svg

#    for x in $output_directory/*-tpt.dat; do
#         cat <<EOF
# import numpy as np;
# f = open('$x', 'r');
# outf = open('$x.meanstd', 'w')
# for l in f.readlines():
#     l = l.split(' ')
#     tpts = [float(x) for x in l[1:-1] if float(x) != 0]
#     outf.write("%s %s %s\n" % (l[0], np.mean(tpts), np.std(tpts)))
# outf.close()
        # EOF


#         echo "\
# import numpy as np;\
# f = open('$x', 'r');\
# for l in f.readlines():\
#   l = l.split(' '); print(l[0], np.std([float(x) for x in l[1:] if float(x) != 0]))\
# "
        # while read p; do
        #     python -c "import numpy as np; print(np.std([float(x) for x in '$p'.split(' ') if float(x) != 0]))"
        # done <$x
#    done

else
    echo "Unrecognized command '$1'"
fi
