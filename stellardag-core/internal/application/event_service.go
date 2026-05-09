package application

import (
	"context"

	"github.com/karchx/stellardag-core/internal/domain"
)

type EventService struct {
	repo domain.EventRepository
}

func NewEventService(repo domain.EventRepository) *EventService {
	return &EventService{repo: repo}
}

func (s *EventService) SubscribeToEvents() chan domain.EventStellar {
	return s.repo.Subscribe()
}

func (s *EventService) UnSubscribe(ch chan domain.EventStellar) {
	s.repo.UnSubscribe(ch)
}

func (s *EventService) ListAllEvents(ctx context.Context, namespace string) ([]domain.EventStellar, error) {
	return s.repo.ListAll(ctx, namespace)
}
