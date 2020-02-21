# Using the Operator

The Ambassador Operator manages and automates many of the repeatable tasks you have to
perform for Ambassador, such as installation and updates.

The first things you must do is to create a `AmbassadorInstallation` resource
in your cluster. You can start with [our generic version](../deploy/crds/getambassador.io_v2_ambassadorinstallation_cr.yaml)
and then customize things like the version constraint, and perhaps an `updateWindow`.

## Initial installation of Ambassador

After the `AmbassadorInstallation` is created for the first time, the Operator will
then use the list of releases available for the Ambassador Helm Chart for determining
the most recent version that can be installed, using the optional [_Version Syntax_](#Version-Syntax-and-Update-Window)
for filtering the release that are acceptable. It will then install
Ambassador, using any extra arguments provided in the `AmbassadorInstallation`, like
the `baseImage`, the `logLevel` or any of the [`helmValues`](#Helm-repo-and-values).

For example, after applying a CR like this in a new cluster:
 
```shell script
$ cat <<EOF | kubectl apply -n ambassador -f -
apiVersion: getambassador.io/v2
kind: AmbassadorInstallation
metadata:
  name: ambassador
spec:
  version: 1.1.0
EOF
```

the operator will install immediately a new instance of Ambassador 1.1.0
in the `ambassador` namespace. Removing this `AmbassadorInstallation` CR will
uninstall Ambassador in this namespace. 

## Keeping your Ambassador updated

After the initial installation of Ambassador, the Operator will check for updates
every 24 hours and delay the update until the [_Update Window_](#Version-Syntax-and-Update-Window)
allow the update to proceed. It will use the [_Version Syntax_](#Version-Syntax-and-Update-Window)
for determining if any new release is acceptable. When a new release is available
and acceptable, the Operator will upgrade the Ambassador installation.

## Custom Configurations

### Version Syntax and Update Window

To specify version numbers, use SemVer for the version number for any level of precision.
This can optionally end in *.  For example:

- `1.0` = exactly version `1.0`
- `1.1` = exactly version `1.1`
- `1.1.*` = version `1.1` and any bug fix versions `1.1.1`, `1.1.2`, `1.1.3`, etc.
- `2.*` = version `2.0` and any incremental and bug fix versions `2.0`, `2.0.1`, `2.0.2`,
   `2.1`, `2.2`, `2.2.1`, etc.
- `*` = all versions.
- `3.0-ea` = version `3.0-ea1` and any subsequent EA releases on `3.0`. Also selects
  the final `3.0` once the final GA version is released.
- `4.*-ea` = version `4.0-ea1` and any subsequent EA release on `4.0`. Also selects
  the final `GA 4.0`. Also selects any incremental and bug fix versions `4.*` and `4...`.
  Also selects the most recent `4.* EA` release i.e., if `4.0.5` is the last GA version
  and there is a `4.1-EA3`, then this selects `4.1-EA3` over the `4.0.5 GA`.

Read more about SemVer [here](https://github.com/Masterminds/semver#basic-comparisons).

`updateWindow` is an optional item that will control when the updates can take place. This is used to
force system updates to happen late at night if that’s what the sysadmins want.

- There can be any number of updateWindow entries (separated by commas).
- `Never` turns off automatic updates even if there are other entries in the comma-separated list.
  `Never` is used by sysadmins to disable all updates during blackout periods by doing a kubectl
  apply or using our Edge Policy Console to set this.
- Each updateWindow is in crontab format (see https://crontab.guru/) Some examples of updateWindows are:
  * `0-6 * * * SUN`: every Sunday, from 0am to 6am
  * `5 1 * * *`: every first day of the month, at 5am
- The Operator cannot guarantee minute time granularity, so specifying a minute in the crontab
  expression can lead to some updates happening sooner/later than expected.
  
## Helm repo and values

- `helmRepo`: an optional URL used for specifying an alternative
  Helm Charts repo. By default, it uses the repo located
  at `https://www.getambassador.io`.
- `helmValues`: an optional map of configurable parameters of
  the Ambassador chart with some overriden values. Take a look at
  the [current list of values](https://github.com/helm/charts/tree/master/stable/ambassador#configuration)
  and their default values. 


