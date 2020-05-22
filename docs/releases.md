# Releasing procedure

In order to release a new version of the Ambassador Operator we should:

- Switch to the master branch
  ```shell script
  git co master
  ```
- Create a new tag:
  ```shell script
  git tag -a v1.0
  ```
- Push tags
  ```shell script
  git push --tags
  ```

This should trigger the following processes:

- A new Ambassador Operator image will be built and pushed to `quay.io` and to
  a private repo in Azure.
- New CRDs and Deployment manifests will be generated and published
  in the [releases page](https://github.com/datawire/ambassador-operator/releases).
- A new version of the Helm chart will be packaged and published to
  the https://getambassador.io Helm repository.

## Running some things manually

This section explains how to do some things manually, just in case you must
release something from your laptop.

### Publishing the image to the Azure registry

- Determine the tag we will use for the image version, `AMB_OPER_TAG`.
- Get a credentials file for Azure, as described in the
  [credentials document](https://github.com/datawire/ambassador-operator/blob/master/ci/cluster-providers/CREDENTIALS.md#Azure).
- Go to https://portal.azure.com/ and create a _Resource Group_, or use an existing one
  (like the default ones, like `DefaultResourceGroup-EUS`).
- Run the following command:
  ```shell script
  AZ_RES_GRP="DefaultResourceGroup-EUS" \
  CLUSTER_REGISTRY="datawire" \
  CLUSTER_PROVIDER="azure" \
  AZ_AUTH_FILE=<AUTHENTICATION_FILE> \
  TRAVIS=true \
  AMB_OPER_TAG=<TAG> \
  make ci/publish-image-cloud
  ```



