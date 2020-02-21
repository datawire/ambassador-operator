#!/bin/bash

# define some default values for Azure (if they have not been defined)

export CLUSTER_SIZE="${CLUSTER_SIZE:-3}"

# see https://docs.microsoft.com/en-us/azure/virtual-machines/windows/sizes-general
export CLUSTER_MACHINE="${CLUSTER_MACHINE:-Standard_D8s_v3}"
