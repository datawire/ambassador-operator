# Releasing procedure

In order to release a new version of the Ambassador Operator we should:

- Switch to the master branch
  ```shell script
  $ git co master
  ```
- Create a new tag:
  ```shell script
  $ git tag -a v1.0
  ```
- Push tags
  ```shell script
  $ git push --tags
  ```

This should trigger the following processes:

- A new Ambassador Operator image will be built and pushed to `quay.io`.
- New CRDs and Deployment manifests will be generated and published
  in the [releases page](https://github.com/datawire/ambassador-operator/releases).
- A new version of the Helm chart will be packaged and published to
  the https://getambassador.io Helm repository.
