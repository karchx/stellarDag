package main

import (
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
		return "status not found"
	}
	return fmt.Sprintf("%v", status)
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
			fmt.Printf("ADD: [%s] %s\n", u.GetNamespace(), u.GetName())
		},
		UpdateFunc: func(oldObj, newObj any) {
			u := newObj.(*unstructured.Unstructured)
			status := getStatusDynamic(u.Object)
			fmt.Printf("UPDATE: [%s] %s - status: %s\n", u.GetNamespace(), u.GetName(), status)
		},
		DeleteFunc: func(obj any) {
			u := obj.(*unstructured.Unstructured)
			fmt.Printf("DELETE: [%s] %s\n", u.GetNamespace(), u.GetName())
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
