package controller

import (
	"context"
	"fmt"

	appsv1 "k8s.io/api/apps/v1"
	corev1 "k8s.io/api/core/v1"
	apierrors "k8s.io/apimachinery/pkg/api/errors"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/runtime"
	ctrl "sigs.k8s.io/controller-runtime"
	"sigs.k8s.io/controller-runtime/pkg/client"
	logf "sigs.k8s.io/controller-runtime/pkg/log"

	beamv1alpha1 "github.com/karchx/stellarDag/api/v1alpha1"
)

// BeamClusterReconciler reconciles a BeamCluster object
type BeamClusterReconciler struct {
	client.Client
	Scheme *runtime.Scheme
}

// +kubebuilder:rbac:groups=beam.stellar.dev,resources=beamclusters,verbs=get;list;watch;create;update;patch;delete
// +kubebuilder:rbac:groups=beam.stellar.dev,resources=beamclusters/status,verbs=get;update;patch
// +kubebuilder:rbac:groups=beam.stellar.dev,resources=beamclusters/finalizers,verbs=update
// +kubebuilder:rbac:groups=apps,resources=statefulsets,verbs=get;list;watch;create;update;patch;delete
// +kubebuilder:rbac:groups=core,resources=services,verbs=get;list;watch;create;update;patch;delete

// Reconcile is part of the main kubernetes reconciliation loop which aims to
// move the current state of the cluster closer to the desired state.
func (r *BeamClusterReconciler) Reconcile(ctx context.Context, req ctrl.Request) (ctrl.Result, error) {
	log := logf.FromContext(ctx)

	var cluster beamv1alpha1.BeamCluster
	if err := r.Get(ctx, req.NamespacedName, &cluster); err != nil {
		return ctrl.Result{}, client.IgnoreNotFound(err)
	}

	svc := r.headlessServiceForCluster(&cluster)
	if err := r.createOrUpdateResource(ctx, &cluster, svc); err != nil {
		return ctrl.Result{}, err
	}

	sts := r.statefulSetForCluster(&cluster)
	if err := r.createOrUpdateResource(ctx, &cluster, sts); err != nil {
		return ctrl.Result{}, err
	}

	log.Info("Reconciliation cycle successfully completed")

	return ctrl.Result{}, nil
}

func (r *BeamClusterReconciler) createOrUpdateResource(ctx context.Context, owner metav1.Object, obj client.Object) error {
	if err := ctrl.SetControllerReference(owner, obj.(metav1.Object), r.Scheme); err != nil {
		return err
	}

	err := r.Create(ctx, obj)
	if err != nil && !apierrors.IsAlreadyExists(err) {
		return fmt.Errorf("error create resource: %w", err)
	}

	// TODO: add update or patch if resource exists
	return nil
}

func (r *BeamClusterReconciler) headlessServiceForCluster(c *beamv1alpha1.BeamCluster) *corev1.Service {
	return &corev1.Service{
		ObjectMeta: metav1.ObjectMeta{
			Name:      c.Name + "-headless",
			Namespace: c.Namespace,
		},
		Spec: corev1.ServiceSpec{
			ClusterIP: "None",
			Selector:  map[string]string{"app": c.Name},
			Ports: []corev1.ServicePort{
				{Name: "epmd", Port: 4369},
			},
		},
	}
}

func (r *BeamClusterReconciler) statefulSetForCluster(c *beamv1alpha1.BeamCluster) *appsv1.StatefulSet {
	replicas := c.Spec.Replicas

	labels := map[string]string{"app": c.Name}

	return &appsv1.StatefulSet{
		ObjectMeta: metav1.ObjectMeta{
			Name:      c.Name,
			Namespace: c.Namespace,
		},
		Spec: appsv1.StatefulSetSpec{
			Replicas:    &replicas,
			ServiceName: c.Name + "-headless",
			Selector:    &metav1.LabelSelector{MatchLabels: labels},
			Template: corev1.PodTemplateSpec{
				ObjectMeta: metav1.ObjectMeta{Labels: labels},
				Spec: corev1.PodSpec{
					Containers: []corev1.Container{{
						Name:  "beam-node",
						Image: c.Spec.Image,
						Env: []corev1.EnvVar{
							{
								Name: "POD_IP",
								ValueFrom: &corev1.EnvVarSource{
									FieldRef: &corev1.ObjectFieldSelector{FieldPath: "status.podIP"},
								},
							},
						},
						Ports: []corev1.ContainerPort{
							{ContainerPort: 4369, Name: "epmd"},
							{ContainerPort: 9000, Name: "dist"},
						},
					}},
				},
			},
		},
	}
}

// SetupWithManager sets up the controller with the Manager.
func (r *BeamClusterReconciler) SetupWithManager(mgr ctrl.Manager) error {
	return ctrl.NewControllerManagedBy(mgr).
		For(&beamv1alpha1.BeamCluster{}).
		Owns(&appsv1.StatefulSet{}).
		Owns(&corev1.Service{}).
		Complete(r)
}
