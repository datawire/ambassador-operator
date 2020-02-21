
# Packages

* <a id="getambassador.io/v2">getambassador.io/v2</a>
  <p>Package v2 contains API Schema definitions for the getambassador v2 API group</p>

# Resource Types

## <a name="getambassador.io/v2.AmbInsCondition">`AmbInsCondition`
   _(Appears on:<a href="#getambassador.io/v2.AmbassadorInstallationStatus">AmbassadorInstallationStatus</a>)_

<p>AmbInsCondition defines an Ambassador installation condition, as well as
the last time there was a transition to this condition..</p>

* `type` - <a href="#getambassador.io/v2.AmbInsConditionType">AmbInsConditionType</a>  

* `status` - <a href="#getambassador.io/v2.AmbInsConditionStatus">AmbInsConditionStatus</a>  

* `reason` - <a href="#getambassador.io/v2.AmbInsConditionReason">AmbInsConditionReason</a>  

* `message` - string  

* `lastTransitionTime` - <a href="https://kubernetes.io/docs/reference/generated/kubernetes-api/v1.13/#time-v1-meta">Kubernetes meta/v1.Time</a>  

## <a name="getambassador.io/v2.AmbInsConditionReason">`AmbInsConditionReason`(`string` alias)
   _(Appears on:<a href="#getambassador.io/v2.AmbInsCondition">AmbInsCondition</a>)_

## <a name="getambassador.io/v2.AmbInsConditionStatus">`AmbInsConditionStatus`(`string` alias)
   _(Appears on:<a href="#getambassador.io/v2.AmbInsCondition">AmbInsCondition</a>)_

## <a name="getambassador.io/v2.AmbInsConditionType">`AmbInsConditionType`(`string` alias)
   _(Appears on:<a href="#getambassador.io/v2.AmbInsCondition">AmbInsCondition</a>)_

## <a name="getambassador.io/v2.AmbassadorInstallation">`AmbassadorInstallation`

<p>AmbassadorInstallation is the Schema for the ambassadorinstallations API</p>

* `metadata` - <a href="https://kubernetes.io/docs/reference/generated/kubernetes-api/v1.13/#objectmeta-v1-meta">Kubernetes meta/v1.ObjectMeta</a>  
   Refer to the Kubernetes API documentation for the fields of the `metadata` field.

* `spec` - <a href="#getambassador.io/v2.AmbassadorInstallationSpec">AmbassadorInstallationSpec</a>  

* `status` - <a href="#getambassador.io/v2.AmbassadorInstallationStatus">AmbassadorInstallationStatus</a>  

## <a name="getambassador.io/v2.AmbassadorInstallationSpec">`AmbassadorInstallationSpec`
   _(Appears on:<a href="#getambassador.io/v2.AmbassadorInstallation">AmbassadorInstallation</a>)_

<p>AmbassadorInstallationSpec defines the desired state of AmbassadorInstallation</p>

* `version` - string  <p>We are using SemVer for the version number and it can be specified with
  any level of precision and can optionally end in <code>*</code>. These are interpreted as:</p>

  <ul>
  <li><code>1.0</code> = exactly version 1.0</li>
  <li><code>1.1</code> = exactly version 1.1</li>
  <li><code>1.1.*</code> = version 1.1 and any bug fix versions <code>1.1.1</code>, <code>1.1.2</code>, <code>1.1.3</code>, etc.</li>
  <li><code>2.*</code> = version 2.0 and any incremental and bug fix versions <code>2.0</code>, <code>2.0.1</code>,
  <code>2.0.2</code>, <code>2.1</code>, <code>2.2</code>, <code>2.2.1</code>, etc.</li>
  <li><code>*</code> = all versions.</li>
  <li><code>3.0-ea</code> = version <code>3.0-ea1</code> and any subsequent EA releases on <code>3.0</code>.
  Also selects the final 3.0 once the final GA version is released.</li>
  <li><code>4.*-ea</code> = version <code>4.0-ea1</code> and any subsequent EA release on <code>4.0</code>.
  Also selects the final GA <code>4.0</code>. Also selects any incremental and bug
  fix versions <code>4.*</code> and <code>4.*.*</code>. Also selects the most recent <code>4.*</code> EA release
  i.e., if <code>4.0.5</code> is the last GA version and there is a <code>4.1-EA3</code>, then this
  selects <code>4.1-EA3</code> over the <code>4.0.5</code> GA.</li>
  </ul>

  <p>You can find the reference docs about the SemVer syntax accepted
    <a href="https://github.com/Masterminds/semver#basic-comparisons">here</a>.</p>

* `baseImage` - string  <p>An (optional) image to use instead of the image specified in the Helm chart.</p>

* `helmRepo` - string  <p>An (optional) Helm repository.</p>

* `logLevel` - string  <p>An (optional) log level: debug, info&hellip;</p>

* `updateWindow` - string  <p><code>updateWindow</code> is an optional item that will control when the updates
  can take place. This is used to force system updates to happen late at
  night if that’s what the sysadmins want.</p>

  <ul>
  <li>There can be any number of <code>updateWindow</code> entries (separated by commas).</li>
  <li><code>Never</code> turns off automatic updates even if there are other entries in the
  comma-separated list. <code>Never</code> is used by sysadmins to disable all updates
  during blackout periods by doing a <code>kubectl apply</code> or using our Edge Policy
  Console to set this.</li>
  <li>Each <code>updateWindow</code> is in crontab format (see <a href="https://crontab.guru/">https://crontab.guru/</a>)
  Some examples of <code>updateWindows</code> are:

  <ul>
  <li><code>* 0-6 * * * SUN</code>: every Sunday, from <em>0am</em> to <em>6am</em></li>
  <li><code>* 5 1 * * *</code>: every first day of the month, at <em>5am</em></li>
  </ul></li>
  <li>The Operator cannot guarantee minute time granularity, so specifying
  a minute in the crontab expression can lead to some updates happening
  sooner/later than expected.</li>
  </ul>

* `helmValues` - map[string]string  <p>An optional map of configurable parameters of the Ambassador chart with
  some overridden values. Take a look at the
  <a href="https://github.com/helm/charts/tree/master/stable/ambassador#configuration">current list of values</a>
  and their default values.</p>

## <a name="getambassador.io/v2.AmbassadorInstallationStatus">`AmbassadorInstallationStatus`
   _(Appears on:<a href="#getambassador.io/v2.AmbassadorInstallation">AmbassadorInstallation</a>)_

<p>AmbassadorInstallationStatus defines the observed state of AmbassadorInstallation</p>

* `conditions` - <a href="#getambassador.io/v2.AmbInsCondition">[]AmbInsCondition</a>  <p>List of conditions the installation has experienced.</p>

* `deployedRelease` - <a href="#getambassador.io/v2.AmbassadorRelease">AmbassadorRelease</a>  <p>the currently deployed Helm chart</p>

* `lastCheckTime` - <a href="https://kubernetes.io/docs/reference/generated/kubernetes-api/v1.13/#time-v1-meta">Kubernetes meta/v1.Time</a>  <p>Last time a successful update check was performed.</p>

## <a name="getambassador.io/v2.AmbassadorRelease">`AmbassadorRelease`
   _(Appears on:<a href="#getambassador.io/v2.AmbassadorInstallationStatus">AmbassadorInstallationStatus</a>)_

<p>AmbassadorRelease defines a release of an Ambassador Helm chart</p>

* `name` - string  

* `version` - string  

* `appVersion` - string  

* `manifest` - string  
