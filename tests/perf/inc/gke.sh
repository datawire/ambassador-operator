#!/bin/sh

# define some default values for GKE (if they have not been defined)

export CLUSTER_SIZE="${CLUSTER_SIZE:-3}"

# see https://cloud.google.com/compute/docs/machine-types?hl=en
export CLUSTER_MACHINE="${CLUSTER_MACHINE:-}"
