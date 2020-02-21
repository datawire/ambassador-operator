#!/usr/bin/env python3

import argparse

template = """---
apiVersion: getambassador.io/v2
kind: Host
metadata:
  name: %s
  namespace: %s
  labels:
    generated: "true"
spec:
  acmeProvider:
    authority: none
  hostname: %s
  selector:
    matchLabels:
      hostname: %s
  tlsSecret: {}
"""

parser = argparse.ArgumentParser()
parser.add_argument("--count", "-c", type=int, default=0, help="how many hosts to generate")
parser.add_argument("--id", "-i", type=int, default=0, help="generate a host with a specific ID")
parser.add_argument("--hostname", help="which hostname to target in the Host definition")
parser.add_argument("--namespace", "-n", default="default", help="namespace")
args = parser.parse_args()

hostname = args.hostname
count = args.count + 1
namespace = args.namespace
id = args.id
if id != 0:
    count = id + 1
else:
    id = 1

for i in range(id, count, 1):
    name = "host-%s" % i
    print(template % (name, namespace, hostname, hostname))
