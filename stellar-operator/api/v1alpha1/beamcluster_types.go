package v1alpha1

import (
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
)

// BeamClusterSpec defines the desired state of BeamCluster
type BeamClusterSpec struct {
	// Replicas define total nodes
	// +kubebuilder:validation:Minimum=1
	Replicas int32 `json:"replicas"`

	Image string `json:"image"`

	CookieSecret string `json:"cookieSecret"`
}

// BeamClusterStatus defines the observed state of BeamCluster.
type BeamClusterStatus struct {
	ReadyReplicas int32 `json:"readyReplicas"`
}

// +kubebuilder:object:root=true
// +kubebuilder:subresource:status

// BeamCluster is the Schema for the beamclusters API
type BeamCluster struct {
	metav1.TypeMeta   `json:",inline"`
	metav1.ObjectMeta `json:"metadata,omitempty"`

	// spec defines the desired state of BeamCluster
	// +required
	Spec BeamClusterSpec `json:"spec"`

	// status defines the observed state of BeamCluster
	Status BeamClusterStatus `json:"status,omitempty"`
}

// +kubebuilder:object:root=true

// BeamClusterList contains a list of BeamCluster
type BeamClusterList struct {
	metav1.TypeMeta `json:",inline"`
	metav1.ListMeta `json:"metadata,omitempty"`
	Items           []BeamCluster `json:"items"`
}

func init() {
	SchemeBuilder.Register(&BeamCluster{}, &BeamClusterList{})
}
