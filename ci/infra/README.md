# Description

This directory contains the cluster providers used for creating/destroying/something-else
clusters for running tests.

The `providers.sh` script provides the following entry points:

  * **setup**: install any software necessary, usually called in the setup stage of your
  Travis/CircleCI/etc. script. For example, for GKE it should install the _Google Cloud SDK_,
  as well as some other tools like `kubectl`.   
  * **cleanup**: perform any cleanups when we are done with this cluster provider, like
  removing any tools that were downloaded. The cleanup should make sure that no clusters
  are kept alive in the provider. 
  * **exists**: return 0 if the cluster already exists. 
  * **create**: create a cluster that will become the _current cluster_. The _kubeconfig_
  will be returned in `get-env` as `KUBECONFIG`.
  * **delete**: delete the current cluster, previously created with `create`.
  * **create-registry**: create a registry or login into an existing one. The registry
  will be returned in `get-env` as `DEV_REGISTRY`. 
  * **delete-registry**: release the current registry or cleanup any resources.
  * **get-env**: get any environment variables necessary for using the current cluster
  (like `KUBECONFIG` or `DEV_REGISTRY`).

# Using the cluster providers

## How to use the cluster providers

* _running the script_ from command line: just invoke the main script with the right
  entrypoint, like `providers.sh setup`. Get the environment for the current
  cluster with `eval "$(providers.sh get-env)"`.
  
* _including the script_: with `source providers.sh` and then 
  running the `cluster_provider` function with the desired entrypoint,
  like `cluster_provider 'create'`. After creating the cluster you can get the
  environment with `eval "$(cluster_provider 'get-env')"` 

Note that some cluster providers will require some [authentication](#Authentication)
as well as some [customization with environment variables](#Configuring-the-cluster-with-env-variables).

## Authentication

See the [credentials](CREDENTIALS.md) document for more details.

## Configuring the cluster with env variables

* `CLUSTER_NAME`: specifies the name of the cluster. It should be unique, but it should
  be "constant" so that a new execution of the provider could detect if the cluster
  already exists.  
* `CLUSTER_SIZE`: total number of nodes in the cluster (including master and worker nodes).
* `CLUSTER_MACHINE`: node size or _model_, depending on the cluster provider 
  (ie, on Azure it can be something like `Standard_D2s_v3`).
* `CLUSTER_REGION`: cluster location (ie, `us-east1-b` on GKE).


