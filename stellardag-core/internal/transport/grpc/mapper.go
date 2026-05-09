package grpc

import (
	stellarv1 "github.com/karchx/stellardag-core/gen/stellar/v1"
	"github.com/karchx/stellardag-core/internal/domain"
)

func protoToDomain(p *stellarv1.EventStellar) domain.EventStellar {
	return domain.EventStellar{
		ID:           p.GetId(),
		Name:         p.GetName(),
		Namespace:    p.GetNamespace(),
		Image:        p.GetImage(),
		Status:       p.GetStatus(),
		Predecessors: []string{},
	}
}

func domainToProto(e domain.EventStellar) *stellarv1.EventStellar {
	return &stellarv1.EventStellar{
		Id:           e.ID,
		Name:         e.Name,
		Namespace:    e.Namespace,
		Image:        e.Image,
		Status:       e.Status,
		Predecessors: []string{},
	}
}
