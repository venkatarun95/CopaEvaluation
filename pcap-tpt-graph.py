import dpkt
import math
import numpy as np
import os
import sys

bucket_size=0.3 # in seconds

pcap = dpkt.pcap.Reader(open(sys.argv[1]))
bucket_start = -1
buckets, bucket, jain = {}, {}, {}
flows = {}
for ts, buf in pcap:
    if bucket_start + bucket_size <= ts or bucket_start == -1:
        for x in bucket:
            bucket[x] /= ts - bucket_start
        if bucket != []:
            buckets[ts] = bucket
        tpts = [bucket[x] for x in bucket]
        if tpts != []:
            jain[ts] = sum(tpts) ** 2 / (len(tpts) * sum([x ** 2 for x in tpts]))
        else: jain[ts] = 0
        bucket_start = ts
        bucket = {}
    eth = dpkt.ethernet.Ethernet(buf)
    #print(type(eth.data.data))
    if type(eth.data) == str or	type(eth.data.data) == str:
        continue
    if type(eth.data.data) != dpkt.tcp.TCP and type(eth.data.data) != dpkt.udp.UDP:
        continue
    #print(ts, eth.data.data.dport)
    #ip = dpkt.ip.IP(eth.data)
    if eth.data.data.dport in [5001, 8888, 9000]:
        if eth.data.data.sport not in flows:
            flows[eth.data.data.sport] = 1
        if eth.data.data.sport not in bucket:
            bucket[eth.data.data.sport] = 0
        bucket[eth.data.data.sport] += len(buf)

tptfilename = sys.argv[1] + "-tpt.dat"
tptpolyfilename = sys.argv[1] + "-tptpoly.dat"
jainfilename = sys.argv[1] + "-jain.dat"
tptfile = open(tptfilename, 'w')
tptpolyfile = open(tptpolyfilename, 'w')
jainfile = open(jainfilename, 'w')
timestamps = [x for x in buckets]
timestamps.sort()
flows = [x for x in flows]
flows.sort()
start_time = timestamps[0]
for ts in timestamps:
    out = str(ts - start_time) + " "
    for x in flows:
        if x in buckets[ts]:
            out += str(buckets[ts][x] * 8e-6) + " "
        else:
            out += "0 "
    tptfile.write(out + "\n")
    jainfile.write(str(ts - start_time) + " " + str(jain[ts]) + "\n")

for ts in timestamps:
    tpts = [buckets[ts][x] for x in buckets[ts]]
    pltpt = 8e-6 * (np.mean(tpts) + np.std(tpts))
    if math.isnan(pltpt): continue
    if pltpt < 0: pltpt = 0
    tptpolyfile.write("%f %f\n" % (ts - start_time, pltpt))
for ts in timestamps[::-1]:
    tpts = [buckets[ts][x] for x in buckets[ts]]
    pltpt = 8e-6 * (np.mean(tpts) - np.std(tpts))
    if math.isnan(pltpt): continue
    if pltpt < 0: pltpt = 0
    tptpolyfile.write("%f %f\n" % (ts - start_time, pltpt))

tptgnufilename = sys.argv[1] + "-tpt.gnuplot"
tptgnufile = open(tptgnufilename, 'w')
tptgnufile.write("""
set terminal svg fsize 20;
set output '%s';

set title "Dynamic behavior";
set ylabel 'Throughput (Mbit/s)';
set xlabel 'Time (s)';
set xrange [0:20];
set yrange [1:100];

set logscale y;
set key off;
""" % (sys.argv[1] + "-tpt.svg"))
tptgnucmd = "plot "
for i in range(len(flows)):
    tptgnucmd += "'%s' using 1:%d with lines, " % (tptfilename, i+2)
tptgnufile.write(tptgnucmd)
tptgnufile.close

jaingnufilename = sys.argv[1] + "-jain.gnuplot"
jaingnufile = open(jaingnufilename, 'w')
jaingnufile.write("""
set terminal svg fsize 20;
set output '%s';

set title "Dynamic behavior";
set ylabel 'Jain index';
set xlabel 'Time (s)';
set xrange [0:20];
set yrange [0:1];
set key off;

plot '%s' using 1:2 with lines
""" % (sys.argv[1] + "-jain.svg", jainfilename))

print("gnuplot -p %s" % tptgnufilename)
print("inkscape -A %s %s" % (sys.argv[1] + "-tpt.pdf", sys.argv[1] + "-tpt.svg"))
print("gnuplot -p %s" % jaingnufilename)
print("inkscape -A %s %s" % (sys.argv[1] + "-jain.pdf", sys.argv[1] + "-jain.svg"))
