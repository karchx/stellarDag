package v1alpha1

import (
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
)

// BeamWebAppSpec defines the desired state of BeamWebApp
type BeamWebAppSpec struct {
	// Replicas define total nodes
	// +kubebuilder:validation:Minimum=1
	Replicas      int32  `json:"replicas"`
	Image         string `json:"image"`
	CookieSecret  string `json:"cookieSecret"`
	SecretKeyBase string `json:"secretKeyBase"`
	CoreDns       string `json:"coreDns"`
	CoreName      string `json:"coreName"`
}

type BeamWebAppStatus struct {
	ReadyReplicas int32 `json:"readyReplicas"`
}

// +kubebuilder:object:root=true
// +kubebuilder:subresource:status

// BeamWebApp is the Schema for the beamwebapps API
type BeamWebApp struct {
	metav1.TypeMeta   `json:",inline"`
	metav1.ObjectMeta `json:"metadata,omitempty"`

	// spec defines the desired state of BeamWebApp
	// +required
	Spec BeamWebAppSpec `json:"spec"`

	// status defines the observed state of BeamWebApp
	// +optional
	Status BeamWebAppStatus `json:"status,omitzero"`
}

// +kubebuilder:object:root=true

// BeamWebAppList contains a list of BeamWebApp
type BeamWebAppList struct {
	metav1.TypeMeta `json:",inline"`
	metav1.ListMeta `json:"metadata,omitzero"`
	Items           []BeamWebApp `json:"items"`
}

func init() {
	SchemeBuilder.Register(&BeamWebApp{}, &BeamWebAppList{})
}
