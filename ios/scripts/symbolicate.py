#!/usr/bin/env python3
"""Print the crashed thread of an .ips file. Usage: symbolicate.py crash.ips binary"""
import json, subprocess, sys
j = json.loads(open(sys.argv[1]).read().split('\n', 1)[1])
print(j['exception'], j.get('asi'))
th = [x for x in j['threads'] if x.get('triggered')][0]
for f in th['frames'][:25]:
    i = j['usedImages'][f['imageIndex']]
    s = f.get('symbol')
    if i.get('name') == 'SliceSpike':
        s = subprocess.run(['atos', '-arch', 'arm64', '-o', sys.argv[2], hex(0x100000000 + f['imageOffset'])],
                           capture_output=True, text=True).stdout.strip()[:130]
    print(i.get('name'), s)
