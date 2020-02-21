# Deploying the Ambassador Operator in GKE
 
## Preparing your cluster

You can use the Google Cloud command line client for creating your cluster. We will now show
the steps necessary for creating the same cluster but using the command line client.
Please refer to the documentation for details on customizing the installation.

First you should login with:
```shell script
$ gcloud login
```

This will open a browser window for authenticating in the Google login page.

Get some info from GKE with:
```shell script
$ gcloud info
```

Then you can create your cluster in GKE. The following example creates a cluster
named `MyKubernetesCluster` with four nodes. This will take several minutes to complete.

```shell script
$ gcloud container clusters create MyKubernetesCluster \
		--num-nodes 4 \
		--machine-type n2-standard-2 \
		--region us-east1-b \
		--enable-ip-alias \
		--enable-autorepair \
		--enable-autoupgrade
```

Some notes:

- The number of nodes as well as the VM size greatly depends on the workload
  of your cluster.

## Deploying the operator

Once the new Operator is working, you can create a Custom Resource called `ambassador` and apply it
as described in the [users guide](using.md).
  
## Running the performance or end-to-end tests in GKE

In order to run the performance or the end-to-end tests on GKE, you need to obtain some credentials for GKE.
See the [credentials document](https://github.com/datawire/ambassador-operator/blob/master/ci/infra/CREDENTIALS.md#GKE)
and set `GKE_AUTH_FILE` to the credentials file you have downloaded.

