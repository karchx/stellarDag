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

// BeamWebAppReconciler reconciles a BeamWebApp object
type BeamWebAppReconciler struct {
	client.Client
	Scheme *runtime.Scheme
}

// +kubebuilder:rbac:groups=beam.stellar.dev,resources=beamwebapps,verbs=get;list;watch;create;update;patch;delete
// +kubebuilder:rbac:groups=beam.stellar.dev,resources=beamwebapps/status,verbs=get;update;patch
// +kubebuilder:rbac:groups=beam.stellar.dev,resources=beamwebapps/finalizers,verbs=update
// +kubebuilder:rbac:groups=apps,resources=deployments,verbs=get;list;watch;create;update;patch;delete
// +kubebuilder:rbac:groups=core,resources=services,verbs=get;list;watch;create;update;patch;delete

// Reconcile is part of the main kubernetes reconciliation loop which aims to
// move the current state of the cluster closer to the desired state.
func (r *BeamWebAppReconciler) Reconcile(ctx context.Context, req ctrl.Request) (ctrl.Result, error) {
	log := logf.FromContext(ctx)

	var cluster beamv1alpha1.BeamWebApp
	if err := r.Get(ctx, req.NamespacedName, &cluster); err != nil {
		return ctrl.Result{}, client.IgnoreNotFound(err)
	}

	dep := r.deploymentForWebApp(&cluster)
	if err := r.createOrUpdateResource(ctx, &cluster, dep); err != nil {
		return ctrl.Result{}, err
	}

	svc := r.serviceForWebApp(&cluster)

	if err := r.createOrUpdateResource(ctx, &cluster, svc); err != nil {
		log.Error(err, "Failed to create or update")
		return ctrl.Result{}, err
	}

	log.Info("Reconciliation cycle successfully completed")

	return ctrl.Result{}, nil
}

func (r *BeamWebAppReconciler) createOrUpdateResource(ctx context.Context, owner metav1.Object, obj client.Object) error {
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

func (r *BeamWebAppReconciler) serviceForWebApp(w *beamv1alpha1.BeamWebApp) *corev1.Service {
	labels := map[string]string{"app": w.Name, "tier": "web"}

	return &corev1.Service{
		ObjectMeta: metav1.ObjectMeta{
			Name:      w.Name + "-svc",
			Namespace: w.Namespace,
		},
		Spec: corev1.ServiceSpec{
			Type:     corev1.ServiceTypeClusterIP,
			Selector: labels,
			Ports: []corev1.ServicePort{
				{
					Name: "http",
					Port: 4000,
				},
			},
		},
	}
}

func (r *BeamWebAppReconciler) deploymentForWebApp(w *beamv1alpha1.BeamWebApp) *appsv1.Deployment {
	replicas := w.Spec.Replicas
	labels := map[string]string{"app": w.Name, "tier": "web"}
	coreNodeDNS := fmt.Sprintf("%s-0.%s-headless.%s.svc.cluster.local", w.Spec.CoreClusterName, w.Spec.CoreClusterName, w.Namespace)

	return &appsv1.Deployment{
		ObjectMeta: metav1.ObjectMeta{
			Name:      w.Name,
			Namespace: w.Namespace,
		},
		Spec: appsv1.DeploymentSpec{
			Replicas: &replicas,
			Selector: &metav1.LabelSelector{MatchLabels: labels},
			Template: corev1.PodTemplateSpec{
				ObjectMeta: metav1.ObjectMeta{Labels: labels},
				Spec: corev1.PodSpec{
					Containers: []corev1.Container{{
						Name:  "elixir-web",
						Image: w.Spec.Image,
						Env: []corev1.EnvVar{
							{
								Name:  "CORE_NODE",
								Value: "stellar@" + coreNodeDNS,
							},
							{
								Name: "RELEASE_COOKIE",
								ValueFrom: &corev1.EnvVarSource{
									SecretKeyRef: &corev1.SecretKeySelector{
										LocalObjectReference: corev1.LocalObjectReference{
											Name: w.Spec.CookieSecret,
										},
										Key: "cookie",
									},
								},
							},
							{
								Name: "SECRET_KEY_BASE",
								ValueFrom: &corev1.EnvVarSource{
									SecretKeyRef: &corev1.SecretKeySelector{
										LocalObjectReference: corev1.LocalObjectReference{
											Name: w.Spec.SecretKeyBase,
										},
										Key: "secret",
									},
								},
							},
						},
						Ports: []corev1.ContainerPort{
							{ContainerPort: 4000, Name: "http"},
							{ContainerPort: 4369, Name: "epmd"},
						},
					}},
				},
			},
		},
	}
}

// SetupWithManager sets up the controller with the Manager.
func (r *BeamWebAppReconciler) SetupWithManager(mgr ctrl.Manager) error {
	return ctrl.NewControllerManagedBy(mgr).
		For(&beamv1alpha1.BeamWebApp{}).
		Named("beamwebapp").
		Complete(r)
}
