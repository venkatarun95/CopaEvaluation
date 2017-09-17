import numpy as np
import os
import re
import sys

def parse_tcptrace(num_tcp, num_x, udp_x, filename):
    assert(type(num_tcp) is int)
    assert(type(num_x) is int)
    assert(type(udp_x) is bool)
    assert(type(filename) is str)

    # Compile various regexes
    re_address = re.compile('\s*host \w*:\s*(?P<addr>[\d\w.-]*):(?P<port>[0-9]+)')
    re_conn_type = re.compile('(?P<type>TCP|UDP) connection [\d]*:')
    re_throughput = re.compile('\s*throughput:\s*(?P<tpt1>\d*) Bps\s*throughput:\s*(?P<tpt2>\d*) Bps.*')
    re_elapsed_time = re.compile('\s*elapsed time:\s*(?P<hrs>\d+):(?P<mins>\d+):(?P<secs>[\d.]+)')

    connections = []
    cur_conn = {}
    f = open(filename, 'r')
    for line in f.readlines():
        mtch_address = re_address.match(line)
        mtch_conn_type = re_conn_type.match(line)
        mtch_throughput = re_throughput.match(line)
        mtch_elapsed_time = re_elapsed_time.match(line)
        if mtch_conn_type != None:
            if cur_conn != {}:
                connections += [cur_conn]
            cur_conn = {'type': mtch_conn_type.group('type')}
        elif mtch_address != None:
            if mtch_address.group('port') not in ['5010', '5011'] and cur_conn['type'] == 'TCP':
                continue
            if mtch_address.group('port') not in ['8888', '9000'] and cur_conn['type'] == 'UDP':
                continue
            assert('port' not in cur_conn or cur_conn['type'] == 'UDP')
            if mtch_address.group('addr') not in ["128.52.160.214", "52-160-214.openstack.csail.mit.edu"]:
                print(mtch_address.group('addr'))
                continue
            #assert(mtch_address.group('addr') == 'localhost')
            cur_conn['port'] = int(mtch_address.group('port'))
        elif mtch_throughput != None:
            tpt = max(int(mtch_throughput.group('tpt1')), int(mtch_throughput.group('tpt2')))
            cur_conn['tpt'] = int(tpt) * 8e-6
        elif mtch_elapsed_time != None:
            hrs = int(mtch_elapsed_time.group('hrs'))
            mins = int(mtch_elapsed_time.group('mins'))
            secs = float(mtch_elapsed_time.group('secs'))
            cur_conn['elapsed_time'] = 3600 * hrs + 60 * mins + secs

    if cur_conn != {}:
        connections += [cur_conn]

    tcp_tpts, x_tpts = [], []
    for conn in connections:
        if 'type' not in conn or 'port' not in conn or 'tpt' not in conn or 'elapsed_time' not in conn:
            #print("Incompletely extracted flow: '%s'" % conn)
            continue
        if conn['elapsed_time'] < 40: continue
        if conn['type'] == 'TCP' and conn['port'] == 5010:
            tcp_tpts += [conn['tpt']]
        elif conn['type'] == 'UDP' and udp_x:
            x_tpts += [conn['tpt']]
        elif conn['type'] == 'TCP' and conn['port'] == 5011 and not udp_x:
            assert(not udp_x)
            x_tpts += [conn['tpt']]
        else:
            pass #print("Stray connection '%s'" % str(conn))

    tcp_tpts.sort(reverse=True)
    x_tpts.sort(reverse=True)
    if len(tcp_tpts) < num_tcp or len(x_tpts) < num_x:
        #print("Insufficient connections found for '%s'" % filename)
        #print(len(tcp_tpts), len(x_tpts))
        #print(connections)
        return ([], [])
    tcp_tpts = tcp_tpts[:num_tcp]
    x_tpts = x_tpts[:num_x]
    #print(connections)
    #print(tcp_tpts, x_tpts, filename)
    return (tcp_tpts, x_tpts)

def parse_experiment(dirname):
    re_dirname = re.compile(".*net-(?P<num_tcp>\d+)-(?P<num_x>\d+)-(?P<delay>\d+)-(?P<tpt>\d+)-(?P<buf>\d+)")
    mtch_dirname = re_dirname.match(dirname)
    num_tcp = int(mtch_dirname.group('num_tcp'))
    num_x = int(mtch_dirname.group('num_x'))
    tpt = float(mtch_dirname.group('tpt'))
    
    ideal_tpt = tpt / (num_tcp + num_x)

    dirs = [f for f in os.listdir(dirname) if os.path.isdir(os.path.join(dirname, f))]
    res = {}
    for alg in dirs:
        if alg not in ["copa", "pcc", "bbr", "cubic"]:
            print("Unrecognized directory '%s'" % alg)
            continue
        if not os.path.isfile(os.path.join(dirname, alg, 'pcap-trace')):
            print("Could not find file '%s/%s'" % (dirname, alg))
            continue
        tcp_tpts, x_tpts = parse_tcptrace(num_tcp,
                                          num_x,
                                          alg in ["copa", "pcc"],
                                          os.path.join(dirname, alg, 'pcap-trace'))
        res[alg] = [x / ideal_tpt for x in x_tpts]
        res[alg + "-cubic"] = [x / ideal_tpt for x in tcp_tpts]
        # if alg == "copa":
        #     print(os.path.join(dirname, alg, 'pcap-trace'), res[alg], res[alg+"-cubic"])
        #     print("=" * 15)
    return res
        
if __name__ == "__main__":
    #re_filename = re.compile(".*net-(?P<num_tcp>\d+)-(?P<num_x>\d+)-(?P<delay>\d+)-(?P<tpt>\d+)-(?P<buf>\d+)/(?P<cong_alg>\w+)/.*")
    # mtch_filename = re_filename.match(sys.argv[1])
    # num_tcp = int(mtch_filename.group('num_tcp'))
    # num_x = int(mtch_filename.group('num_x'))
    # cong_alg = mtch_filename.group('cong_alg')
    # udp_x = (cong_alg in ["copa"])

    dirname = sys.argv[1]
    dirs = [f for f in os.listdir(dirname) if os.path.isdir(os.path.join(dirname, f))]
    res = {}
    for d in dirs:
        parsed = parse_experiment(os.path.join(dirname, d))
        for alg in parsed:
              if alg not in res:
                  res[alg] = parsed[alg]
              else:
                  res[alg].extend(parsed[alg])
    for x in res:
        res[x].sort()
        #print(x, res[x])
    for alg in res:
        print(alg,
              np.mean(res[alg]),
              np.std(res[alg]),
              len(res[alg]))
