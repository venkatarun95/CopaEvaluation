import re
import sys

def parse_tcptrace(num_tcp, num_x, udp_x, filename):
    assert(type(num_tcp) is int)
    assert(type(num_x) is int)
    assert(type(udp_x) is bool)
    assert(type(filename) is str)

    # Compile various regexes
    re_address = re.compile('\s*host .:\s*(?P<addr>[\d\w.]*):(?P<port>[0-9]+)')
    re_conn_type = re.compile('(?P<type>TCP|UDP) connection [\d]*:')
    re_throughput = re.compile('\s*throughput:\s*(?P<tpt1>\d*) Bps\s*throughput:\s*(?P<tpt2>\d*) Bps')

    connections = []
    cur_conn = {}
    f = open(filename, 'r')
    for line in f.readlines():
        mtch_address = re_address.match(line)
        mtch_conn_type = re_conn_type.match(line)
        mtch_throughput = re_throughput.match(line)
        if mtch_conn_type != None:
            if cur_conn != {}:
                connections += [cur_conn]
            cur_conn = {'type': mtch_conn_type.group('type')}
        elif mtch_address != None:
            if mtch_address.group('port') not in ['5010', '5011'] and cur_conn['type'] == 'TCP':
                continue
            assert('port' not in cur_conn or cur_conn['type'] == 'UDP')
            assert(mtch_address.group('addr') == 'localhost')
            cur_conn['port'] = int(mtch_address.group('port'))
        elif mtch_throughput != None:
            tpt = max(mtch_throughput.group('tpt1'), mtch_throughput.group('tpt2'))
            cur_conn['tpt'] = int(tpt) * 8e-6

    if cur_conn != {}:
        connections += [cur_conn]

    tcp_tpts, x_tpts = [], []
    for conn in connections:
        if conn['type'] == 'TCP' and conn['port'] == 5010:
            tcp_tpts += [conn['tpt']]
        elif conn['type'] == 'UDP' and udp_x:
            x_tpts += [conn['tpt']]
        elif conn['type'] == 'TCP' and conn['port'] == 5011:
            assert(not udp_x)
            x_tpts += [conn['tpt']]

    tcp_tpts.sort(reverse=True)
    x_tpts.sort(reverse=True)
    tcp_tpts = tcp_tpts[:num_tcp]
    x_tpts = x_tpts[:num_x]
    print(connections)
    print(tcp_tpts, x_tpts)

if __name__ == "__main__":
    re_filename = re.compile(".*net-(?P<num_tcp>\d+)-(?P<num_x>\d+)-(?P<delay>\d+)-(?P<tpt>\d+)-(?P<buf>\d+)/(?P<cong_alg>\w+)/.*")
    mtch_filename = re_filename.match(sys.argv[1])
    num_tcp = int(mtch_filename.group('num_tcp'))
    num_x = int(mtch_filename.group('num_x'))
    cong_alg = mtch_filename.group('cong_alg')
    udp_x = (cong_alg in ["copa"])
    parse_tcptrace(num_tcp,
                   num_x,
                   udp_x,
                   str(sys.argv[1]))
