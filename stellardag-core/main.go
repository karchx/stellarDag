package main

import (
	"encoding/json"
	"flag"
	"fmt"
	"os"
	"path/filepath"
	"time"

	batchv1 "k8s.io/api/batch/v1"
	corev1 "k8s.io/api/core/v1"
	"k8s.io/apimachinery/pkg/apis/meta/v1/unstructured"
	"k8s.io/apimachinery/pkg/runtime/schema"
	"k8s.io/client-go/informers"
	"k8s.io/client-go/kubernetes"
	"k8s.io/client-go/tools/cache"
	"k8s.io/client-go/tools/clientcmd"
)

type EventStellar struct {
	ID           string   `json:"id"`
	Name         string   `json:"name"`
	Namespace    string   `json:"namespace"`
	Image        string   `json:"image"`
	Status       string   `json:"status"`
	Predecessors []string `json:"predecessors"`
	X            int      `json:"x"`
	Y            int      `json:"y"`
}

func sparkApp() schema.GroupVersionResource {
	return schema.GroupVersionResource{
		Group:    "sparkoperator.k8s.io",
		Version:  "v1beta2",
		Resource: "sparkapplications",
	}
}

func getStatusDynamic(object map[string]any) string {
	status, found, err := unstructured.NestedString(object, "status", "applicationState", "state")
	if err != nil || !found {
		return "IN_QUEUE"
	}
	return fmt.Sprintf("%v", status)
}

func statusJob(job *batchv1.Job) string {
	for _, c := range job.Status.Conditions {
		if c.Status == corev1.ConditionTrue {
			return string(c.Type)
		}
	}
	if job.Status.Active > 0 {
		return "RUNNING"
	}
	return "IN_QUEUE"
}

func printEventJob(job *batchv1.Job, simpleFormat *bool) {
	status := statusJob(job)

	var image string
	if len(job.Spec.Template.Spec.Containers) > 0 {
		image = job.Spec.Template.Spec.Containers[0].Image
	}

	event := EventStellar{
		ID:           string(job.GetUID()),
		Name:         job.Name,
		Namespace:    job.Namespace,
		Image:        image,
		Status:       status,
		Predecessors: []string{},
		X:            80,
		Y:            120,
	}

	if simpleFormat != nil && *simpleFormat {
		jsonData, err := json.Marshal(event)
		if err != nil {
			fmt.Printf("Error marshaling event: %v\n", err)
			return
		}

		fmt.Printf("%s\n", string(jsonData))
	} else {
		jsonData, err := json.MarshalIndent(event, "", "    ")
		if err != nil {
			fmt.Printf("Error marshaling event: %v\n", err)
			return
		}

		fmt.Printf("Event: %s\n", string(jsonData))
	}
}

func printEvent(u *unstructured.Unstructured) {
	status := getStatusDynamic(u.Object)

	image, _, _ := unstructured.NestedString(u.Object, "spec", "image")

	event := EventStellar{
		ID:           string(u.GetUID()),
		Name:         u.GetName(),
		Namespace:    u.GetNamespace(),
		Image:        image,
		Status:       status,
		Predecessors: []string{},
		X:            80,
		Y:            120,
	}

	jsonData, err := json.MarshalIndent(event, "", "    ")
	if err != nil {
		fmt.Printf("Error marshaling event: %v\n", err)
		return
	}

	fmt.Printf("Event: %s\n", string(jsonData))
}

// func main() {
// 	stopCh := make(chan struct{})
//
// 	kubeconfig := filepath.Join(homeDir(), ".kube", "config")
// 	config, err := clientcmd.BuildConfigFromFlags("", kubeconfig)
// 	if err != nil {
// 		panic(err.Error())
// 	}
//
// 	// clientset, err := kubernetes.NewForConfig(config)
// 	dynamicClient, err := dynamic.NewForConfig(config)
//
// 	if err != nil {
// 		panic(err.Error())
// 	}
//
// 	factory := dynamicinformer.NewFilteredDynamicSharedInformerFactory(
// 		dynamicClient,
// 		15*time.Second,
// 		"de",
// 		nil,
// 	)
//
// 	gvr := sparkApp()
// 	informer := factory.ForResource(gvr).Informer()
//
// 	_, err = informer.AddEventHandler(cache.ResourceEventHandlerFuncs{
// 		AddFunc: func(obj any) {
// 			u := obj.(*unstructured.Unstructured)
// 			printEvent(u)
// 		},
// 		UpdateFunc: func(oldObj, newObj any) {
// 			u := newObj.(*unstructured.Unstructured)
// 			printEvent(u)
// 		},
// 		DeleteFunc: func(obj any) {
// 			u := obj.(*unstructured.Unstructured)
// 			printEvent(u)
// 		},
// 	})
//
// 	if err != nil {
// 		panic(err.Error())
// 	}
//
// 	factory.Start(stopCh)
//
// 	if !cache.WaitForCacheSync(stopCh, informer.HasSynced) {
// 		panic("timout waiting for cache to sync")
// 	}
//
// 	fmt.Println("Cache synced, watching for events...")
//
// 	<-stopCh
// }

func main() {
	simpleFormat := flag.Bool("simple", false, "Use simple format for events")
	flag.Parse()

	stopCh := make(chan struct{})

	kubeconfig := filepath.Join(homeDir(), ".kube", "config")
	config, err := clientcmd.BuildConfigFromFlags("", kubeconfig)
	if err != nil {
		panic(err.Error())
	}

	clientset, err := kubernetes.NewForConfig(config)
	if err != nil {
		panic(err.Error())
	}

	factory := informers.NewSharedInformerFactoryWithOptions(
		clientset,
		15*time.Second,
		informers.WithNamespace("de"),
	)

	informer := factory.Batch().V1().Jobs().Informer()

	_, err = informer.AddEventHandler(cache.ResourceEventHandlerFuncs{
		AddFunc: func(obj any) {
			job := obj.(*batchv1.Job)
			printEventJob(job, simpleFormat)
		},
		UpdateFunc: func(oldObj, newObj any) {
			job := newObj.(*batchv1.Job)
			printEventJob(job, simpleFormat)
		},
		DeleteFunc: func(obj any) {
			job := obj.(*batchv1.Job)
			printEventJob(job, simpleFormat)
		},
	})

	if err != nil {
		panic(err.Error())
	}

	factory.Start(stopCh)

	if !cache.WaitForCacheSync(stopCh, informer.HasSynced) {
		panic("timout waiting for cache to sync")
	}

	<-stopCh
}

func homeDir() string {
	home, err := os.UserHomeDir()
	if err != nil {
		panic("could not determine home directory")
	}
	return home
}
