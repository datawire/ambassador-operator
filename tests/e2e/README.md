# Description

A poor-man test runner for the Ambassador Operator using simple shell scripts.

# Usage

```shell script
runner.sh [OPTIONS...] [COMMAND...]

where OPTION can be (note: some values can also be provided with the 'env:' environment variables):

  --kubeconfig <FILE>       specify the kubeconfig file (env:DEV_KUBECONFIG)
  --registry <ADDR:PORT>    specify the registry for the Ambassador image (env:DEV_REGISTRY)
  --image-name <NAME>       the image name
  --image-tag <TAG>         the image tag
  --cluster-provider <PRV>  the cluster provider to use (available: amazon azure dummy gke k3d kubernaut ) (env:CLUSTER_PROVIDER)
  --keep                    keep the cluster after a failure (env:CLUSTER_KEEP)
  --reuse                   reuse the cluster between tests (remove the namespace) (env:CLUSTER_REUSE)
  --debug                   debug the shell script
  --help                    show this message

and COMMAND can be:
  build                     builds and pushes the image to the DEV_REGISTRY
  push                      (same as 'build')
  check [TEST ...]          run all tests (or some given test script)
```

Some important flags:

- `--cluster-provider <PRV>`: use some specific cluster provider, like `k3d` or `azure`.  You can also use the
  `dummy` provider and use your own registry (with `--registry`) and kubeconfig (with `--kubeconfig`).
- `--keep` prevents the cluster from being destroyed after running the test(s). 
- `--reuse`: by default, the test runner destroy the cluster after every a test is ran and creates a new
  one for the following test. This flag instructs the test runner to reuse the cluster and just remove
  everything in the namespace.

## Running all the tests

You can run all the tests with just `check`:
 
```shell script
  $ runner.sh --cluster-provider=k3d build check
```
 
## Running some specific test

You can run only some particular tests by passing the file name as an argument for `check`:
  
```shell script
  $ runner.sh --cluster-provider=k3d check tests/03-version-upgrade.sh
```

