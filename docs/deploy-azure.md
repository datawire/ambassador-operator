# Deploying the Ambassador Operator in Azure

## Preparing your cluster

You can use the Azure command line client for creating your cluster. We will now show
the steps necessary for creating the same cluster but using the command line client.
Please refer to the documentation for details on customizing the installation.

The Azure CLI's default authentication method uses a web browser and access token to
sign in. You should run the login command

```shell script
$ az login
```

and this will open your default browser and load an Azure sign-in page.

Now you can create a resource group with:

```shell script
$ az group create --name MyGroup --location eastus
```

Then we will create an AKS cluster. The following example creates a cluster
named `MyKubernetesCluster` with four nodes. Azure Monitor for containers
is also enabled using the `--enable-addons monitoring` parameter. This will
take several minutes to complete.

```shell script
$ az aks create --resource-group MyGroup \
    --name MyKubernetesCluster \
    --node-count 4 \
    --node-vm-size Standard_D12_v2 \
    --network-plugin azure \
    --enable-addons monitoring \
    --generate-ssh-keys
```

Some notes:

- The number of nodes as well as the VM size greatly depends on the workload
  of your cluster. 
- Make sure HTTP application routing is not enabled (so you are not passing
  `--enable-addons http_application_routing`)
- Add `--network-policy=azure` if you plan to use _Network Policies_ (recommended).

## Deploying the operator

Once the new Operator is working, you can create a Custom Resource called `ambassador` and apply it
as described in the [users guide](using.md).
  
## Running the performance or end-to-end tests in Azure

In order to run the performance or the end-to-end tests on Azure, you need to obtain some credentials for Azure.
See the [credentials document](https://github.com/datawire/ambassador-operator/blob/master/ci/infra/CREDENTIALS.md#Azure)
and set `AZ_AUTH_FILE` to the credentials file you have downloaded.

