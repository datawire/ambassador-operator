# Description

Performance tests runner.

## Basic usage

```shell script
$ ./runner.sh --help                                                                  
runner.sh [OPTIONS...] [COMMAND...]

where OPTION can be (note: some values can also be provided with the 'env:' environment variables):

  --kubeconfig <FILE>       specify the kubeconfig file
                            (def:from cluster provider) (env:DEV_KUBECONFIG)
  --registry <ADDR:PORT>    specify the registry for the Ambassador image
                            (def:from cluster provider) (env:DEV_REGISTRY)
  --cluster-provider <PRV>  the cluster provider to use
                            (available: amazon azure dummy gke k3d kubernaut ) (def:k3d) (env:CLUSTER_PROVIDER)
  --cluster-name <NAME>     cluster provider: name (def: amb-perf-tests-alvaro-0)
  --cluster-size <SIZE>     cluster provider: number of nodes
  --cluster-machine <NAME>  cluster provider: machine size/model
  --cluster-region <NAME>   cluster provider: region
  --image-name <NAME>       the image name (def:ambassador-operator)
  --image-tag <TAG>         the image tag (def:dev)
  --amb-version <VERSION>   the version of Ambassador to install (def:)

...
```

## Workflow

### Step-by-step workflow

* First, create a cluster using your preferred cluster provider. For example, you can create a
  local k3d cluster with:
   
  ```shell script
    $ # create a k3d cluster
    $ runner.sh --cluster-provider=k3d setup
  ```  
  Some important notes:
  - cluster providers will probably require some kind of credentials. Take a look at
    the cluster providers in `/ci/infra/providers` for instructions on getting these
    credentials. They usually need to save them in some file and/or setting some env vars... 
  - You can also use any already existing cluster with the `dummy` cluster provider, with
    `--cluster-provider=dummy`. This provider will just dump any `KUBECONFIG` and `DEV_REGISTRY`
    variables you have defined in your environment. This provider has limited functionality,
    as we cannot configure any parameters like the number of machines or their class.

* Deploy the operator, an `AmbassadorInstallation` and wait for the operator to
  install Ambassador with:
  ```shell script
  $ runner.sh --cluster-provider=k3d deploy ambassador
  ```

* Now we can run some of the benchmarks. For example, we can measure the
  _pod spin-up time_, using one replica of Ambassador and 1000 mappings, with:
  ```shell script
  $ runner.sh --cluster-provider=k3d --num-replicas=1 --num-mappings=1000 bench pod-spinup
  ```
  or you could use `bench all` for running all the benchmarks.

### Quick workflow

Once you are familiar with the basic workflow, you can run all the steps in one
single command.
Examples:
  - this will create a cluster in Azure with `Standard_DS4_v2` machines and run
    all the benchmarks with 100 mappings and 10 hosts:     
    ```shell script
    $ runner.sh --cluster-provider=azure \
                --cluster-machine=Standard_DS4_v2 \
                --cluster-name="perf-h10m100r10-Ds4v8" \
                --num-mappings=100 \
                --num-hosts=10 \
                all
    ```  

### Batched runs

Sometimes it is useful to run several configurations in a sequence but changing the
number of _mappings_, _hosts_ or the machine types. You can do that with the `batch` mode.
Just provide these paramaters in a comma seperated list and use the `batch` command for
running all these configurations in a sequence.

Some notes:
  - the `--cluster-name` will be ignored: a custom cluster name will be
  generated automatically.
  - clusters will be reused between runs and only a new cluster will be created
  for every new `--cluster-machine`. 

Examples       
  - Benchmark all the combinations of `Standard_DS4_v2` and `Standard_DS8_v2` machines
    with 100 and 250 mappings, keeping constant all the other parameters.
    ```shell script
    $ # create a k3d cluster
    $ runner.sh --cluster-provider=azure \
                --cluster-machine=Standard_DS4_v2,Standard_DS8_v2 \
                --num-mappings=100,250 \
                --num-hosts=10 \
                batch
    ```
  - Generate some latency reports on Azure for 100, 500 and 1000 RPS on machines
    `Standard_DS4_v2`,`Standard_F16s_v2` and `Standard_E16_v3`:  
    ```shell script
    ./runner.sh --cluster-provider=azure \
        --cluster-machines=Standard_DS4_v2,Standard_F16s_v2,Standard_E16_v3 \
        --cluster-size=4  --num-replicas=3 \
        --latency-duration=300s --latency-rates=100,500,1000 --latency-reports-dir=/tmp/reports \
        batch latency
`   ```

