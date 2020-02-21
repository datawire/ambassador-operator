package v2

import (
	"encoding/json"
	"time"

	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/apis/meta/v1/unstructured"
	"k8s.io/apimachinery/pkg/runtime"
)

// NOTE: json tags are required.  Any new fields you add must have json tags for the fields to be serialized.

// AmbassadorInstallationSpec defines the desired state of AmbassadorInstallation
type AmbassadorInstallationSpec struct {
	// We are using SemVer for the version number and it can be specified with
	// any level of precision and can optionally end in `*`. These are interpreted as:
	//
	// * `1.0` = exactly version 1.0
	// * `1.1` = exactly version 1.1
	// * `1.1.*` = version 1.1 and any bug fix versions `1.1.1`, `1.1.2`, `1.1.3`, etc.
	// * `2.*` = version 2.0 and any incremental and bug fix versions `2.0`, `2.0.1`,
	//   `2.0.2`, `2.1`, `2.2`, `2.2.1`, etc.
	// * `*` = all versions.
	// * `3.0-ea` = version `3.0-ea1` and any subsequent EA releases on `3.0`.
	//   Also selects the final 3.0 once the final GA version is released.
	// * `4.*-ea` = version `4.0-ea1` and any subsequent EA release on `4.0`.
	//   Also selects the final GA `4.0`. Also selects any incremental and bug
	//   fix versions `4.*` and `4.*.*`. Also selects the most recent `4.*` EA release
	//   i.e., if `4.0.5` is the last GA version and there is a `4.1-EA3`, then this
	//   selects `4.1-EA3` over the `4.0.5` GA.
	//
	//   You can find the reference docs about the SemVer syntax accepted
	//   [here](https://github.com/Masterminds/semver#basic-comparisons).
	//
	Version string `json:"version,omitempty"`

	// An (optional) image to use instead of the image specified in the Helm chart.
	BaseImage string `json:"baseImage,omitempty"`

	// An (optional) Helm repository.
	// +kubebuilder:validation:Pattern=`https?:\/\/(www\.)?[-a-zA-Z0-9@:%._\+~#=]{1,256}\.[a-zA-Z0-9()]{1,6}\b([-a-zA-Z0-9()@:%_\+.~#?&//=]*)`
	HelmRepo string `json:"helmRepo,omitempty"`

	// An (optional) log level: debug, info...
	// +kubebuilder:validation:Enum=info;debug;warn;warning;error;critical;fatal
	LogLevel string `json:"logLevel,omitempty"`

	// `updateWindow` is an optional item that will control when the updates
	// can take place. This is used to force system updates to happen late at
	// night if that’s what the sysadmins want.
	//
	//  * There can be any number of `updateWindow` entries (separated by commas).
	//  * `Never` turns off automatic updates even if there are other entries in the
	//    comma-separated list. `Never` is used by sysadmins to disable all updates
	//    during blackout periods by doing a `kubectl apply` or using our Edge Policy
	//    Console to set this.
	// * Each `updateWindow` is in crontab format (see https://crontab.guru/)
	//   Some examples of `updateWindows` are:
	//    - `* 0-6 * * * SUN`: every Sunday, from _0am_ to _6am_
	//    - `* 5 1 * * *`: every first day of the month, at _5am_
	// * The Operator cannot guarantee minute time granularity, so specifying
	//   a minute in the crontab expression can lead to some updates happening
	//   sooner/later than expected.
	UpdateWindow string `json:"updateWindow,omitempty"`

	// An optional map of configurable parameters of the Ambassador chart with
	// some overridden values. Take a look at the
	// [current list of values](https://github.com/helm/charts/tree/master/stable/ambassador#configuration)
	// and their default values.
	HelmValues map[string]string `json:"helmValues,omitempty"`
}

// AmbassadorInstallationStatus defines the observed state of AmbassadorInstallation
type AmbassadorInstallationStatus struct {
	// List of conditions the installation has experienced.
	Conditions []AmbInsCondition `json:"conditions"`

	// the currently deployed Helm chart
	// +nullable
	DeployedRelease *AmbassadorRelease `json:"deployedRelease,omitempty"`

	// Last time a successful update check was performed.
	// +nullable
	LastCheckTime metav1.Time `json:"lastCheckTime,omitempty"`
}

// +k8s:deepcopy-gen:interfaces=k8s.io/apimachinery/pkg/runtime.Object

// AmbassadorInstallation is the Schema for the ambassadorinstallations API
//
// +kubebuilder:subresource:status
// +kubebuilder:resource:path=ambassadorinstallations,scope=Namespaced
// +kubebuilder:printcolumn:name="VERSION",type=string,JSONPath=`.spec.version`
// +kubebuilder:printcolumn:name="UPDATE-WINDOW",type=integer,JSONPath=`.spec.updateWindow`
// +kubebuilder:printcolumn:name="LAST-CHECK",type="string",JSONPath=".status.lastCheckTime",priority=0,description="Last time checked"
// +kubebuilder:printcolumn:name="DEPLOYED",type="string",JSONPath=".status.conditions[?(@.type=='Deployed')].status",priority=0,description="Indicates if deployment has completed"
// +kubebuilder:printcolumn:name="REASON",type="string",JSONPath=".status.conditions[?(@.type=='Deployed')].reason",priority=1,description="Reason for deployment completed"
// +kubebuilder:printcolumn:name="MESSAGE",type="string",JSONPath=".status.conditions[?(@.type=='Deployed')].message",priority=1,description="Message for deployment completed"
// +kubebuilder:printcolumn:name="DEPLOYED-VERSION",type="string",JSONPath=".status.deployedRelease.appVersion",priority=0,description="Deployed version of Ambassador"
type AmbassadorInstallation struct {
	metav1.TypeMeta   `json:",inline"`
	metav1.ObjectMeta `json:"metadata,omitempty"`

	Spec   AmbassadorInstallationSpec   `json:"spec,omitempty"`
	Status AmbassadorInstallationStatus `json:"status,omitempty"`
}

// +k8s:deepcopy-gen:interfaces=k8s.io/apimachinery/pkg/runtime.Object

// AmbassadorInstallationList contains a list of AmbassadorInstallation
type AmbassadorInstallationList struct {
	metav1.TypeMeta `json:",inline"`
	metav1.ListMeta `json:"metadata,omitempty"`
	Items           []AmbassadorInstallation `json:"items"`
}

type AmbInsConditionType string
type AmbInsConditionStatus string
type AmbInsConditionReason string

// AmbInsCondition defines an Ambassador installation condition, as well as
// the last time there was a transition to this condition..
type AmbInsCondition struct {
	Type    AmbInsConditionType   `json:"type"`
	Status  AmbInsConditionStatus `json:"status"`
	Reason  AmbInsConditionReason `json:"reason,omitempty"`
	Message string                `json:"message,omitempty"`

	LastTransitionTime metav1.Time `json:"lastTransitionTime,omitempty"`
}

// AmbassadorRelease defines a release of an Ambassador Helm chart
type AmbassadorRelease struct {
	Name       string `json:"name,omitempty"`
	Version    string `json:"version,omitempty"`
	AppVersion string `json:"appVersion,omitempty"`
	Manifest   string `json:"manifest,omitempty"`
}

const (
	ConditionInitialized    AmbInsConditionType = "Initialized"
	ConditionDeployed       AmbInsConditionType = "Deployed"
	ConditionReleaseFailed  AmbInsConditionType = "Failed"
	ConditionIrreconcilable AmbInsConditionType = "Irreconcilable"

	StatusTrue    AmbInsConditionStatus = "True"
	StatusFalse   AmbInsConditionStatus = "False"
	StatusUnknown AmbInsConditionStatus = "Unknown"

	ReasonInstallSuccessful   AmbInsConditionReason = "InstallSuccessful"
	ReasonUpdateSuccessful    AmbInsConditionReason = "UpdateSuccessful"
	ReasonUninstallSuccessful AmbInsConditionReason = "UninstallSuccessful"
	ReasonInstallError        AmbInsConditionReason = "InstallError"
	ReasonUpdateError         AmbInsConditionReason = "UpdateError"
	ReasonReconcileError      AmbInsConditionReason = "ReconcileError"
	ReasonUninstallError      AmbInsConditionReason = "UninstallError"
	ReasonParametersError     AmbInsConditionReason = "ParametersError"
	ReasonDuplicateError      AmbInsConditionReason = "DuplicateError"
)

func (s *AmbassadorInstallationStatus) ToMap() (map[string]interface{}, error) {
	var out map[string]interface{}
	jsonObj, err := json.Marshal(&s)
	if err != nil {
		return nil, err
	}
	if err := json.Unmarshal(jsonObj, &out); err != nil {
		return nil, err
	}
	return out, nil
}

// LastCondition returns the last condition, optionally filtering by Status, Reason or Type
func (s *AmbassadorInstallationStatus) LastCondition(filter AmbInsCondition) AmbInsCondition {
	var last AmbInsCondition
	for _, c := range s.Conditions {
		if filter.Status != "" && c.Status != filter.Status {
			continue
		}
		if filter.Reason != "" && c.Reason != filter.Reason {
			continue
		}
		if filter.Type != "" && c.Type != filter.Type {
			continue
		}

		if last.LastTransitionTime.IsZero() {
			last = c
		} else if c.LastTransitionTime.After(last.LastTransitionTime.Time) {
			last = c
		}
	}
	return last
}

// SetCondition sets a condition on the status object. If the condition already
// exists, it will be replaced. SetCondition does not update the resource in
// the cluster.
func (s *AmbassadorInstallationStatus) SetCondition(condition AmbInsCondition) *AmbassadorInstallationStatus {
	now := metav1.Now()
	for i := range s.Conditions {
		if s.Conditions[i].Type == condition.Type {
			if s.Conditions[i].Status != condition.Status {
				condition.LastTransitionTime = now
			} else {
				condition.LastTransitionTime = s.Conditions[i].LastTransitionTime
			}
			s.Conditions[i] = condition
			return s
		}
	}

	// If the condition does not exist,
	// initialize the lastTransitionTime
	condition.LastTransitionTime = now
	s.Conditions = append(s.Conditions, condition)
	return s
}

// TimestampCheck updates the timestamp of the last successful install/update
func (s *AmbassadorInstallationStatus) TimestampCheck(now time.Time) *AmbassadorInstallationStatus {
	s.LastCheckTime = metav1.NewTime(now)
	return s
}

// RemoveCondition removes the condition with the passed condition type from
// the status object. If the condition is not already present, the returned
// status object is returned unchanged. RemoveCondition does not update the
// resource in the cluster.
func (s *AmbassadorInstallationStatus) RemoveCondition(conditionType AmbInsConditionType) *AmbassadorInstallationStatus {
	for i := range s.Conditions {
		if s.Conditions[i].Type == conditionType {
			s.Conditions = append(s.Conditions[:i], s.Conditions[i+1:]...)
			return s
		}
	}
	return s
}

// StatusFor safely returns a typed status block from a custom resource.
func StatusFor(cr *unstructured.Unstructured) *AmbassadorInstallationStatus {
	switch s := cr.Object["status"].(type) {
	case *AmbassadorInstallationStatus:
		return s
	case map[string]interface{}:
		var status *AmbassadorInstallationStatus
		if err := runtime.DefaultUnstructuredConverter.FromUnstructured(s, &status); err != nil {
			return &AmbassadorInstallationStatus{}
		}
		return status
	default:
		return &AmbassadorInstallationStatus{}
	}
}

func init() {
	SchemeBuilder.Register(&AmbassadorInstallation{}, &AmbassadorInstallationList{})
}

//type HelmStruct struct {
//	NameOverride                         string              `json:"nameOverride,omitempty"`
//	FullnameOverride                     string              `json:"fullnameOverride,omitEmpty"`
//	AdminServiceCreate                   bool                `json:"adminService.create,omitEmpty"`
//	AdminServiceNodePort                 bool                `json:"adminService.nodePort,omitEmpty"`
//	AdminServiceType                     string              `json:"adminService.type,omitEmpty"`
//	AdminServiceAnnotations              map[string]string   `json:"adminService.type,omitEmpty"`
//	AdminServiceLoadBalancerIP           string              `json:"adminService.loadBalancerIP,omitEmpty"`
//	AdminServiceLoadBalancerSourceRanges string              `json:"adminService.loadBalancerSourceRanges,omitEmpty"`
//	AmbassadorConfig                     string              `json:"ambassadorConfig,omitEmpty"`
//	CRDsEnabled                          bool                `json:"crds.enabled,omitEmpty"`
//	CRDsCreate                           bool                `json:"crds.create,omitEmpty"`
//	CRDsKeep                             bool                `json:"crds.keep,omitEmpty"`
//	DaemonSet                            bool                `json:"daemonSet,omitEmpty"`
//	HostNetwork                          bool                `json:"hostNetwork,omitEmpty"`
//	DnsPolicy                            string              `json:"dnsPolicy,omitEmpty"`
//	Env                                  map[string]string   `json:"env,omitEmpty"`
//	ImagePullPolicy                      string              `json:"image.pullPolicy,omitEmpty"`
//	ImageRepository                      string              `json:"image.repository,omitEmpty"`
//	ImageTag                             string              `json:"image.tag,omitEmpty"`
//	ImagePullSecrets                     []string            `json:"imagePullSecrets,omitEmpty"`
//	NamespaceName                        string              `json:"namespace.name,omitEmpty"`
//	ScopeSingleNamespace                 bool                `json:"scope.singleNamespace,omitEmpty"`
//	PodAnnotations                       map[string]string   `json:"podAnnotations,omitEmpty"`
//	DeploymentAnnotations                map[string]string   `json:"deploymentAnnotations,omitEmpty"`
//	PodLabels                            map[string]string   `json:"podLabels,omitEmpty"`
//	Affinity                             map[string]string   `json:"affinity,omitEmpty"`
//	NodeSelector                         map[string]string   `json:"nodeSelector,omitEmpty"`
//	PriorityClassName                    string              `json:"priorityClassName,omitEmpty"`
//	RbacCreate                           bool                `json:"rbac.create,omitEmpty"`
//	RbacPodSecurityPolicies              map[string]string   `json:"rbac.podSecurityPolicies,omitEmpty"`
//	RbacNameOverride                     string              `json:"rbac.nameOverride,omitEmpty"`
//	ReplicaCount                         int                 `json:"replicaCount,omitEmpty"`
//	Resources                            map[string]string   `json:"resources,omitEmpty"`
//	SecurityContext                      map[string]string   `json:"securityContext,omitEmpty"`
//	RestartPolicy                        string              `json:"restartPolicy,omitEmpty"`
//	InitContainers                       []string            `json:"initContainers,omitEmpty"`
//	SidecarContainers                    []string            `json:"sidecarContainers,omitEmpty"`
//	LivenessProbeInitialDelaySeconds     int                 `json:"livenessProbe.initialDelaySeconds,omitEmpty"`
//	LivenessProbePeriodSeconds           int                 `json:"livenessProbe.periodSeconds,omitEmpty"`
//	LivenessProbeFailureThreshold        int                 `json:"livenessProbe.failureThreshold,omitEmpty"`
//	ReadinessProbeInitialDelaySeconds    int                 `json:"readinessProbe.initialDelaySeconds,omitEmpty"`
//	ReadinessProbePeriodSeconds          int                 `json:"readinessProbe.periodSeconds,omitEmpty"`
//	ReadinessProbeFailureThreshold       int                 `json:"readinessProbe.failureThreshold,omitEmpty"`
//	ServiceAnnotations                   map[string]string   `json:"service.annotations,omitEmpty"`
//	ServiceExternalTrafficPolicy         map[string]string   `json:"service.externalTrafficPolicy,omitEmpty"`
//	ServicePorts                         []map[string]string `json:"service.ports,omitEmpty"`
//	ServiceLoadBalancerIP                string              `json:"service.loadBalancerIP,omitEmpty"`
//	ServiceLoadBalancerSourceRanges      []string            `json:"service.loadBalancerSourceRanges,omitEmpty"`
//	ServiceType                          string              `json:"service.type,omitEmpty"`
//	ServiceAccountCreate                 bool                `json:"serviceAccount.create,omitEmpty"`
//	ServiceAccountName                   string              `json:"serviceAccount.name,omitEmpty"`
//	VolumeMounts                         []string            `json:"volumeMounts,omitEmpty"`
//	Volumes                              []string            `json:"volumes,omitEmpty"`
//	EnableAES                            bool                `json:"enableAES,omitEmpty"`
//	LicenseKeyValue                      string              `json:"licenseKey.value,omitEmpty"`
//	LicenseKeyCreateSecret               bool                `json:"licenseKey.createSecret,omitEmpty"`
//	LicenseKeySecretName                 string              `json:"licenseKey.secretName,omitEmpty"`
//	RedisURL                             string              `json:"redisURL,omitEmpty"`
//	RedisCreate                          bool                `json:"redis.create,omitEmpty"`
//	RedisResources                       map[string]string   `json:"redis.resources,omitEmpty"`
//	RedisNodeSelector                    map[string]string   `json:"redis.nodeSelector,omitEmpty"`
//	AuthServiceCreate                    bool                `json:"authService.create,omitEmpty"`
//	AuthServiceOptionalConfigurations    map[string]string   `json:"authService.optional_configurations,omitEmpty"`
//	RateLimitCreate                      bool                `json:"rateLimit.create,omitEmpty"`
//	AutoscalingEnabled                   bool                `json:"autoscaling.enabled,omitEmpty"`
//	AutoscalingMinReplica                int                 `json:"autoscaling.minReplica,omitEmpty"`
//	AutoscalingMaxReplica                int                 `json:"autoscaling.maxReplica,omitEmpty"`
//	AutoscalingMetrics                   map[string]string   `json:"autoscaling.metrics,omitEmpty"`
//	PodDisruptionBudget                  map[string]string   `json:"podDisruptionBudget,omitEmpty"`
//}
