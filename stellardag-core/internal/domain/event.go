package domain

import (
	"errors"

	batchv1 "k8s.io/api/batch/v1"
	corev1 "k8s.io/api/core/v1"
)

var (
	ErrEventNotFound = errors.New("event not found")
	ErrEventExists   = errors.New("event already exists")
)

// EventStellar canonical domain
type EventStellar struct {
	ID           string
	Name         string
	Namespace    string
	Image        string
	Status       string
	Predecessors []string
}

func NewEventStellar(job *batchv1.Job) *EventStellar {
	status := statusJob(job)
	var image string

	if len(job.Spec.Template.Spec.Containers) > 0 {
		image = job.Spec.Template.Spec.Containers[0].Image
	}

	return &EventStellar{
		ID:           string(job.GetUID()),
		Name:         job.Name,
		Namespace:    job.Namespace,
		Image:        image,
		Status:       status,
		Predecessors: []string{},
	}
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
