package main

import (
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"time"

	"k8s.io/apimachinery/pkg/apis/meta/v1/unstructured"
	"k8s.io/apimachinery/pkg/runtime/schema"
	"k8s.io/client-go/dynamic"
	"k8s.io/client-go/dynamic/dynamicinformer"
	"k8s.io/client-go/tools/cache"
	"k8s.io/client-go/tools/clientcmd"
)

// {id: "1", name: "gaia_source", namespace: "ds", image: "go-parquet:1.0.0", status: "completed", predecessors: [], x: 80, y: 120}
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

func main() {
	stopCh := make(chan struct{})

	kubeconfig := filepath.Join(homeDir(), ".kube", "config")
	config, err := clientcmd.BuildConfigFromFlags("", kubeconfig)
	if err != nil {
		panic(err.Error())
	}

	// clientset, err := kubernetes.NewForConfig(config)
	dynamicClient, err := dynamic.NewForConfig(config)

	if err != nil {
		panic(err.Error())
	}

	factory := dynamicinformer.NewFilteredDynamicSharedInformerFactory(
		dynamicClient,
		15*time.Second,
		"de",
		nil,
	)

	gvr := sparkApp()
	informer := factory.ForResource(gvr).Informer()

	_, err = informer.AddEventHandler(cache.ResourceEventHandlerFuncs{
		AddFunc: func(obj any) {
			u := obj.(*unstructured.Unstructured)
			printEvent(u)
		},
		UpdateFunc: func(oldObj, newObj any) {
			u := newObj.(*unstructured.Unstructured)
			printEvent(u)
		},
		DeleteFunc: func(obj any) {
			u := obj.(*unstructured.Unstructured)
			printEvent(u)
		},
	})

	if err != nil {
		panic(err.Error())
	}

	factory.Start(stopCh)

	if !cache.WaitForCacheSync(stopCh, informer.HasSynced) {
		panic("timout waiting for cache to sync")
	}

	fmt.Println("Cache synced, watching for events...")

	<-stopCh
}

func homeDir() string {
	home, err := os.UserHomeDir()
	if err != nil {
		panic("could not determine home directory")
	}
	return home
}
