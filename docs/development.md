# Development guide

## Overview

All contributions are welcome! Bug reports, fixes, new features, documentation improvements
and ideas help us to create the most comprehensive benchmark suite for Kubernetes. 

* The latest API docs are located [here](api/index.md).
* The releases engineering workflow is described in our [releases guide](releases.md). 

## Dev box setup (OS X & Linux)

### Compiler tools

The following software are required to build and run the Ambassador Operator:

- [GoLang](https://golang.org/dl/) v1.11 or greater 
- make
- [kubectl](https://kubernetes.io/docs/reference/kubectl/overview/)

the Ambassador Operator uses the Module feature of Go 1.11. You need to make
sure that you enable it for your environment:

```bash
$ export GO111MODULE=on
```


### Kubernetes setup

If you already have access to Kubernetes (i.e. you can use `kubectl` to interact
with the cluster) then you are good to go. 

If not, you can use [k3d](https://github.com/rancher/k3d), [KinD (Kubernetes in Docker)](https://github.com/kubernetes-sigs/kind),
[MiniKube](https://github.com/kubernetes/minikube) or [K3S](https://k3s.io/) to run
a local 'cluster' in your machine. Please follow the installation steps of your
chosen distribution and make sure you have a working `kubectl` before you proceed
to the next step.

Our CI system uses K3D by default for running the end-to-end test execution, but you can
specify a different environment by setting the `CLUSTER_PROVIDER` variable to one of the
cluster providers in the `ci/infra/providers` directory.


### Build

#### Git Repo Clone

You need to clone the repository to your local machine. This can be done
using [the Ambassador Operator repo](https://github.com/datawire/ambassador-operator)
or your own fork. If you would like to send a PR it is required that you
fork the repository.

```bash
$ git clone https://github.com/datawire/ambassador-operator.git
```

#### Local build

Now you obtained the sources it is time to build the bits:

```bash
$ cd ambassador-operator
$ make build
```

The `make` command will download all the necessary dependencies and build
the go files. End result will be a manager binary located at `build/ambassador-operator`.

You need to generate/update all the required Kubernetes Objects (CRDs, RBAC objects)
every time the API is changed. It can be done with `make generate`.
 
#### Installing the CRDs

Before we start the local build we need to make sure that the Custom Resource
Definitions are created in the cluster. The following command generates the
CRDs from the types and loads them to the server.

```bash
$ make load-crds
```


#### Starting the service locally

Once the the application is built and the corresponding Custom Resource Definitions
are installed to the cluster, you can run the `build/ambassador-operator`
as a regular executable from command line:

```bash
$ ./build/ambassador-operator --kubeconfig ~/.kube/config --zap-devel
```

or from your preferred debugger.

## Tests

The Ambassador Operator has both unit and end-to-end tests. 

### Unit tests

Used to validate the basic logic of the functions. Unit tests can be triggered
with the following command:

```bash
$ make test
```

### End-to-end tests

Used to validate that the operator deployment and the expected behavior
are working. During end-to-end tests the following steps are executed:

- A local Kubernetes deployment is started, using some of the supported
  [cluster providers](https://github.com/datawire/ambassador-operator/tree/master/ci/infra).
  By default, a [`k3d`](https://github.com/rancher/k3d) cluster will be used.
- A Docker image is built for the Operator.
- The provided tests are executed. 
  This step mostly involves executing some installation or upgrade.
  Validation (ie, installations are performed, upgrades are successful) occurs in this phase.

They can be started with:

```bash
$ make e2e
```

End to end tests are located in `tests/e2e/` package.  You can run one of those tests with
the `TEST` variable, like:

```shell script
$ make e2e TEST="01-install-uninstall"
```

Note well that end-to-end tests require more CPU and memory for execution than the unit tests.

See the [documentation there](https://github.com/datawire/ambassador-operator/tree/master/tests/e2e)
for more details.

### Linters

During code build and unit test execution a set of linters are executed
to make sure that the codebase meets formal standards. If you would like
to execute the linting steps the following command can be used:

```bash
$ make lint
```

You should also format your code (before submitting a PR) with:

```bash
$ make format
```

## Contributions

Every contribution is appreciated! 
If you happen to find a bug or added a new feature or improved the
documentation please post a Pull Request for the project. We will do
our best to review it in a timely manner.

For your PRs, please make sure that:

1. It meets the formal standards (`make lint` should pass, and
   you have done `make format`)
2. Have a reasonable amount of tests:
   1. Unit tests where it makes sense
   2. e2e tests for major changes.
3. Have enough documentation for the users to get started




