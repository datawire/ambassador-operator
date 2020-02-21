# Credentials for the cluster providers

In order to get some valid credentials for
- running the performance tests or the end-to-end tests using the cluster providers, or for
- running things automatically from Travis/Circle-CI

you should get some _credentials_. These can be stored in a file (for using them locally) or
in some environment variables (for CI). 

The following sections describe how to get these credentials for some of the cloud
providers currently supported.
 
## Azure

- Login into azure with `az login`

- Get the list of subscriptions with `az account list`
  ```json
   {
     "cloudName": "AzureCloud",
     "id": "<SUBSCRIPTION_ID>",
     "isDefault": true,
     "name": "<...>",
     "state": "Enabled",
     "tenantId": "<TENANT_ID>",
     "user": {
       "name": "test@datawire.io",
       "type": "user"
     }
   }
  ```

- Set the account with `az account set --subscription="<SUBSCRIPTION_ID>"`

- Run `az ad sp create-for-rbac --role="Contributor" --scopes="/subscriptions/<SUBSCRIPTION_ID>"`. You
  will get an output like:
  ```json
  {
   "appId": "<AZ_USERNAME>",
   "name": "<...>",
   "password": "<AZ_PASSWORD>",
   "tenant": "<AZ_TENANT>"
  }
  ```   
  and save it to `azure-credentials.json`.
  
- Now you can then save the credentials in multiple ways (env vars must be set in Travis/CircleCI/etc):

  a) encrypt the file
    - for Travis, `travis encrypt-file az-credentials.json`
    - commit the encrypted file (the `*.enc` file) in some path in Git
    - set `AZ_AUTH_FILE` in the env vars in `.travis.yaml`
    - add the decryption line in the `.travis.yaml` file

  b) save the file encoded in a variable.
    - encode it with `base64` to a file and save that file in a `AZ_AUTH` env variable.
      For example, for Travis, you could use the command line tool like:
      ```
      $ travis env set AZ_AUTH "$(cat az-credentials.json | base64)"
      ```
  c) copy some of the values in the file to env variables:
    - value of `appId` should be copied to `AZ_USERNAME`
    - value of `password` should be copied to `AZ_PASSWORD`
    - value of `tenant` should be copied to `AZ_TENANT`


## GKE

- Login into the GCloud console

- Create a new service account in https://console.cloud.google.com/iam-admin/serviceaccounts

- Verity the roles assigned in https://console.cloud.google.com/iam-admin/iam

- Assign _"Kubernetes Admin"_ role

- Create a new _Key_. Select `JSON` as the format. The JSON file will be downloaded and
  saved to your computer automatically.

- Then you could:
  a) use some env variables:
    - encode the file with `base64 < gke-credentials.json`
    - save the output in a Travis env var called `GKE_AUTH`
    - for Travis, you can do it with the command line client with:
      ```shell script
      $ travis env set GKE_AUTH "$(cat gke-credentials.json | base64)"
      ```
  b) encrypt the file
    - for Travis, `travis encrypt-file gke-credentials.json`
    - commit the encrypted file (the `*.enc` file) in some path in Git
    - set `GKE_AUTH_FILE` in the env vars in `.travis.yaml`
    - add the decryption line in the `.travis.yaml` file



