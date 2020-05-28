package ambassadorinstallation

import (
	"testing"

	"k8s.io/apimachinery/pkg/apis/meta/v1/unstructured"
)

func TestHasChangedSpec(t *testing.T) {

	stringToUnstr := func(data string) *unstructured.Unstructured {
		unstruct := &unstructured.Unstructured{}
		_, _, err := unstructured.UnstructuredJSONScheme.Decode([]byte(data), nil, unstruct)
		if err != nil {
			panic("could not decode data")
		}
		return unstruct
	}

	// obtained with:
	// kubectl get ambassadorinstallations -n ambassador ambassador -o json

	tests := []struct {
		description string
		instance    *unstructured.Unstructured
		hasChanged  bool
	}{
		{
			description: "configuration has not changed",
			instance: stringToUnstr(`
{
    "apiVersion": "getambassador.io/v2",
    "kind": "AmbassadorInstallation",
    "metadata": {
        "annotations": {
            "kubectl.kubernetes.io/last-applied-configuration": "{\"apiVersion\":\"getambassador.io/v2\",\"kind\":\"AmbassadorInstallation\",\"metadata\":{\"annotations\":{},\"name\":\"ambassador\",\"namespace\":\"ambassador\"},\"spec\":{\"helmValues\":{\"image\":{\"pullPolicy\":\"Always\"},\"namespace\":{\"name\":\"ambassador\"},\"service\":{\"ports\":[{\"name\":\"http\",\"port\":80,\"targetPort\":8080}],\"type\":\"NodePort\"}},\"version\":\"1.*\"}}\n"
        },
        "creationTimestamp": "2020-05-28T09:12:59Z",
        "generation": 1,
        "name": "ambassador",
        "namespace": "ambassador",
        "resourceVersion": "1586",
        "selfLink": "/apis/getambassador.io/v2/namespaces/ambassador/ambassadorinstallations/ambassador",
        "uid": "f5e70521-837b-4891-84c1-2e713ae6e3da"
    },
    "spec": {
        "helmValues": {
            "image": {
                "pullPolicy": "Always"
            },
            "namespace": {
                "name": "ambassador"
            },
            "service": {
                "ports": [
                    {
                        "name": "http",
                        "port": 80,
                        "targetPort": 8080
                    }
                ],
                "type": "NodePort"
            }
        },
        "version": "1.*"
    }
}
`),
			hasChanged: false,
		},
		{
			description: "changed version number to 2.*",
			instance: stringToUnstr(`
{
    "apiVersion": "getambassador.io/v2",
    "kind": "AmbassadorInstallation",
    "metadata": {
        "annotations": {
            "kubectl.kubernetes.io/last-applied-configuration": "{\"apiVersion\":\"getambassador.io/v2\",\"kind\":\"AmbassadorInstallation\",\"metadata\":{\"annotations\":{},\"name\":\"ambassador\",\"namespace\":\"ambassador\"},\"spec\":{\"helmValues\":{\"image\":{\"pullPolicy\":\"Always\"},\"namespace\":{\"name\":\"ambassador\"},\"service\":{\"ports\":[{\"name\":\"http\",\"port\":80,\"targetPort\":8080}],\"type\":\"NodePort\"}},\"version\":\"1.*\"}}\n"
        },
        "creationTimestamp": "2020-05-28T09:12:59Z",
        "generation": 1,
        "name": "ambassador",
        "namespace": "ambassador",
        "resourceVersion": "1586",
        "selfLink": "/apis/getambassador.io/v2/namespaces/ambassador/ambassadorinstallations/ambassador",
        "uid": "f5e70521-837b-4891-84c1-2e713ae6e3da"
    },
    "spec": {
        "helmValues": {
            "image": {
                "pullPolicy": "Always"
            },
            "namespace": {
                "name": "ambassador"
            },
            "service": {
                "ports": [
                    {
                        "name": "http",
                        "port": 80,
                        "targetPort": 8080
                    }
                ],
                "type": "NodePort"
            }
        },
        "version": "2.*"
    }
}
`),
			hasChanged: true,
		},
		{
			description: "changed image.pullpolicy",
			instance: stringToUnstr(`
{
    "apiVersion": "getambassador.io/v2",
    "kind": "AmbassadorInstallation",
    "metadata": {
        "annotations": {
            "kubectl.kubernetes.io/last-applied-configuration": "{\"apiVersion\":\"getambassador.io/v2\",\"kind\":\"AmbassadorInstallation\",\"metadata\":{\"annotations\":{},\"name\":\"ambassador\",\"namespace\":\"ambassador\"},\"spec\":{\"helmValues\":{\"image\":{\"pullPolicy\":\"Always\"},\"namespace\":{\"name\":\"ambassador\"},\"service\":{\"ports\":[{\"name\":\"http\",\"port\":80,\"targetPort\":8080}],\"type\":\"NodePort\"}},\"version\":\"1.*\"}}\n"
        },
        "creationTimestamp": "2020-05-28T09:12:59Z",
        "generation": 1,
        "name": "ambassador",
        "namespace": "ambassador",
        "resourceVersion": "1586",
        "selfLink": "/apis/getambassador.io/v2/namespaces/ambassador/ambassadorinstallations/ambassador",
        "uid": "f5e70521-837b-4891-84c1-2e713ae6e3da"
    },
    "spec": {
        "helmValues": {
            "image": {
                "pullPolicy": "Never"
            },
            "namespace": {
                "name": "ambassador"
            },
            "service": {
                "ports": [
                    {
                        "name": "http",
                        "port": 80,
                        "targetPort": 8080
                    }
                ],
                "type": "NodePort"
            }
        },
        "version": "1.*"
    }
}
`),
			hasChanged: true,
		},
		{
			description: "no previous configuration",
			instance: stringToUnstr(`
{
    "apiVersion": "getambassador.io/v2",
    "kind": "AmbassadorInstallation",
    "metadata": {
        "creationTimestamp": "2020-05-28T09:12:59Z",
        "generation": 1,
        "name": "ambassador",
        "namespace": "ambassador",
        "resourceVersion": "1586",
        "selfLink": "/apis/getambassador.io/v2/namespaces/ambassador/ambassadorinstallations/ambassador",
        "uid": "f5e70521-837b-4891-84c1-2e713ae6e3da"
    },
    "spec": {
        "helmValues": {
            "image": {
                "pullPolicy": "Never"
            },
            "namespace": {
                "name": "ambassador"
            },
            "service": {
                "ports": [
                    {
                        "name": "http",
                        "port": 80,
                        "targetPort": 8080
                    }
                ],
                "type": "NodePort"
            }
        },
        "version": "1.*"
    }
}
`),
			hasChanged: false,
		},
	}

	for _, tt := range tests {
		t.Run(tt.description, func(t *testing.T) {
			if got := hasChangedSpec(tt.instance); got != tt.hasChanged {
				t.Errorf("hasChangedSpec() = %v, want %v, when %s", got, tt.hasChanged, tt.description)
			}
		})
	}
}
