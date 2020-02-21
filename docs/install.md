# Installation

## Install Manually

Firstly, you must install the Ambassador Operator:

- Load the Ambassador Operator CRD with the following command:
  ```shell script
  $ kubectl apply -f https://github.com/datawire/ambassador-operator/releases/download/latest/ambassador-operator-crds.yaml
  ```
- Install the Ambassador Operator in the `ambassador` namespace with the following command:
  ```shell script
  $ kubectl apply -n ambassador -f https://github.com/datawire/ambassador-operator/releases/download/latest/ambassador-operator.yaml
  ```
  To install the Ambassador Operator in a different namespace, you can specify it in `NS` and then run
  the following command (that will replace the `ambassador` namespace by `$NS`):
  ```shell script
  $ NS="custom-namespace"
  $ curl -L https://github.com/datawire/ambassador-operator/releases/download/latest/ambassador-operator.yaml | \
      sed -e "s/namespace: ambassador/namespace: $NS/g" | \
      kubectl apply -n $NS -f -
  ```

Then you can create a new `AmbasasadorInstallation` _Custom Resource_ named `ambassador`
as described in the [users guide](using.md).

## Install via OperatorHub.io

You can install the AES Operator from the Operator Hub, where makers of Kubernetes operators
can share their configurations with the community. To install from this site:

- Navigate to  operatorhub.io and search for “Ambassador Edge Stack.”
- Click on the tile.
- Click the **Install** button and follow the directions to finish the installation.
- Once the new Operator is working, you can create a Custom Resource called `ambassador` and apply it
  as described in the [usage](usage.md) guide.

## Install via Helm Chart

You can also install the AES Operator from a Helm Chart. 

- Install Helm 3
- Add this Helm repository to your Helm client
  ```shell script
  helm repo add datawire https://getambassador.io
  ```
- Run the following command: 
  ```shell script
  $ helm install stable/ambassador-operator
  ```
  This command deploys the Ambassador Operator in the `ambassador` namespace on the
  Kubernetes cluster in the default configuration (it is recommended to use the `ambassador`
  namespace for easy upgrades).
- Once the new Operator is working, create a new `AmbasasadorInstallation` _Custom Resource_ named `ambassador`
  as described [here](using.md).


