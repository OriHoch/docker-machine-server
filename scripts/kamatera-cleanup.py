#!/usr/bin/env python3.6
import os
import subprocess
import json
import sys
import time


if not os.environ.get('KAMATERA_API_CLIENT_ID') or not os.environ.get('KAMATERA_API_SECRET'):
    print('Missing required env vars: KAMATERA_API_CLIENT_ID KAMATERA_API_SECRET')
    exit(1)


assert len(sys.argv) == 2, 'usage: cleanup.py "PREFIX"'
prefix = sys.argv[1]

print('prefix =', prefix)

while True:
    returncode, output = subprocess.getstatusoutput(
        'curl -s -H "AuthClientId: ${KAMATERA_API_CLIENT_ID}" -H "AuthSecret: ${KAMATERA_API_SECRET}" '
        '"https://console.kamatera.com/service/servers"')
    assert returncode == 0, output
    num_errors = 0
    num_deleted = 0
    for server in json.loads(output):
        if not server['name'].startswith(prefix): continue
        print(server)
        returncode, output = subprocess.getstatusoutput(
            'curl -s -H "AuthClientId: ${KAMATERA_API_CLIENT_ID}" -H "AuthSecret: ${KAMATERA_API_SECRET}" '
            '-X DELETE -d "confirm=1" -d "force=1" '
            '"https://console.kamatera.com/service/server/' + str(server['id']) + '/terminate"'
        )
        print('returncode = ', returncode)
        print(output)
        if returncode == 0:
            num_deleted += 1
        else:
            num_errors += 1
    if num_deleted > 0:
        print('retrying until no machines returned in list')
        time.sleep(5)
    else:
        break


if num_errors > 0:
    print('Failed!')
    exit(1)
else:
    print('Great Success!')
    exit(0)
