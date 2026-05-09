package k8s

import (
	"context"
	"sync"

	log "github.com/gothew/l-og"
	"github.com/karchx/stellardag-core/internal/domain"
	batchv1 "k8s.io/api/batch/v1"
	"k8s.io/client-go/informers"
	batchv1listers "k8s.io/client-go/listers/batch/v1"
	"k8s.io/client-go/tools/cache"
)

type EventRepository struct {
	mu          sync.RWMutex
	subscribers map[chan domain.EventStellar]struct{}
	lister      batchv1listers.JobLister
}

func NewRepository(factory informers.SharedInformerFactory) *EventRepository {
	informer := factory.Batch().V1().Jobs()
	repo := &EventRepository{
		subscribers: make(map[chan domain.EventStellar]struct{}),
		lister:      informer.Lister(),
	}

	informer.Informer().AddEventHandler(cache.ResourceEventHandlerFuncs{
		AddFunc: func(obj any) {
			jobAdd := obj.(*batchv1.Job)
			log.Infof("[ADD]: %v", jobAdd)
			repo.broadcast(*domain.NewEventStellar(jobAdd))
		},
		UpdateFunc: func(oldObj, newObj any) {
			jobUpdate := newObj.(*batchv1.Job)
			log.Infof("[UPDATE]: %v", jobUpdate)
			repo.broadcast(*domain.NewEventStellar(jobUpdate))
		},
		DeleteFunc: func(obj any) {
			jobDelete := obj.(*batchv1.Job)
			log.Infof("[DELETE]: %v", jobDelete)
			repo.broadcast(*domain.NewEventStellar(jobDelete))
		},
	})

	return repo
}

func (r *EventRepository) broadcast(event domain.EventStellar) {
	r.mu.RLock()
	defer r.mu.RUnlock()

	for ch := range r.subscribers {
		select {
		case ch <- event:
		default:
			log.Info("default broadcast")
		}
	}
}

func (r *EventRepository) Subscribe() chan domain.EventStellar {
	r.mu.Lock()
	defer r.mu.Unlock()
	ch := make(chan domain.EventStellar, 100)
	r.subscribers[ch] = struct{}{}
	return ch
}

func (r *EventRepository) UnSubscribe(ch chan domain.EventStellar) {
	r.mu.Lock()
	defer r.mu.Unlock()
	delete(r.subscribers, ch)
	close(ch)
}

func (r *EventRepository) ListAll(ctx context.Context, namespace string) ([]domain.EventStellar, error) {
	var result []domain.EventStellar
	item := domain.EventStellar{
		ID:           "fake1111",
		Name:         "fake",
		Namespace:    "fake",
		Image:        "fake",
		Status:       "fake",
		Predecessors: []string{},
	}
	result = append(result, item)
	return result, nil
}
