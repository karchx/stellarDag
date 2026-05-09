package main

import (
	"os"
	"os/signal"
	"path/filepath"
	"syscall"
	"time"

	log "github.com/gothew/l-og"
	"github.com/karchx/stellardag-core/internal/application"
	"github.com/karchx/stellardag-core/internal/infrastructure/k8s"
	grpctransport "github.com/karchx/stellardag-core/internal/transport/grpc"
	"k8s.io/client-go/informers"
	"k8s.io/client-go/kubernetes"
	"k8s.io/client-go/tools/clientcmd"
)

const port = 50051

func main() {
	factory := initFactoryk8s()
	repo := k8s.NewRepository(factory)
	svc := application.NewEventService(repo)
	handler := grpctransport.NewHandler(svc)

	srv, lis, err := grpctransport.NewServer(handler, port)
	if err != nil {
		log.Errorf("Failed to initialize server %v", err)
		os.Exit(1)
	}

	stopCh := make(chan struct{})
	quit := make(chan os.Signal, 1)
	signal.Notify(quit, syscall.SIGINT, syscall.SIGTERM)

	factory.Start(stopCh)
	for v, ok := range factory.WaitForCacheSync(stopCh) {
		if !ok {
			panic("sync cache factory k8s " + v.String())
		}
	}

	go func() {
		log.Infof("gRPC server started %s", lis.Addr().String())
		if err := srv.Serve(lis); err != nil {
			log.Errorf("serve error %v", err)
			os.Exit(1)
		}
	}()
	<-quit
	log.Info("shutting down gracefully...")
	srv.GracefulStop()
}

func homeDir() string {
	home, err := os.UserHomeDir()
	if err != nil {
		panic("could not determine home directory")
	}
	return home
}

func initFactoryk8s() informers.SharedInformerFactory {
	kubeconfig := filepath.Join(homeDir(), ".kube", "config")
	config, err := clientcmd.BuildConfigFromFlags("", kubeconfig)
	if err != nil {
		panic(err.Error())
	}
	clientset, err := kubernetes.NewForConfig(config)
	if err != nil {
		// TODO panic ?
		panic(err.Error())
	}

	factory := informers.NewSharedInformerFactoryWithOptions(
		clientset,
		15*time.Second,
		informers.WithNamespace("de"),
	)
	return factory
}
