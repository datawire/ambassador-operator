#!/usr/bin/env python3

import argparse

template = """---
apiVersion: getambassador.io/v2
kind: Mapping
metadata:
  name: %s
  namespace: %s
  labels:
    generated: "true"
spec:
  prefix: /%s/
  service: %s
"""

parser = argparse.ArgumentParser()
parser.add_argument("--count", "-c", type=int, default=0, help="how many mappings to generate")
parser.add_argument("--id", "-i", type=int, default=0, help="generate a mapping with a specific ID")
parser.add_argument("--target", "-t", default="void", help="which service to target (echo-a, echo-b)")
parser.add_argument("--namespace", "-n", default="default", help="namespace")
args = parser.parse_args()

target = args.target
count = args.count + 1
namespace = args.namespace
id = args.id
if id != 0:
    count = id + 1
else:
    id = 1

for i in range(id, count, 1):
    name = "echo-%s" % i
    print(template % (name, namespace, name, target))
