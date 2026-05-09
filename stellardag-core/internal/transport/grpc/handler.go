package grpc

import (
	"context"
	"errors"

	log "github.com/gothew/l-og"
	stellarv1 "github.com/karchx/stellardag-core/gen/stellar/v1"
	"github.com/karchx/stellardag-core/internal/application"
	"github.com/karchx/stellardag-core/internal/domain"
	"google.golang.org/grpc/codes"
	"google.golang.org/grpc/status"
)

type Handler struct {
	stellarv1.UnimplementedStellarServiceServer
	svc *application.EventService
}

func NewHandler(svc *application.EventService) *Handler {
	return &Handler{svc: svc}
}

func (h *Handler) ListEvents(ctx context.Context, req *stellarv1.ListEventsRequest) (*stellarv1.ListEventsResponse, error) {
	evts, err := h.svc.ListAllEvents(ctx, req.GetNamespace())
	if err != nil {
		return nil, domainErrStatus(err)
	}

	protos := make([]*stellarv1.EventStellar, len(evts))
	for i, e := range evts {
		protos[i] = domainToProto(e)
	}

	return &stellarv1.ListEventsResponse{Events: protos}, nil
}

func (h *Handler) WatchEvents(req *stellarv1.Empty, stream stellarv1.StellarService_WatchEventsServer) error {
	log.Info("Get call")
	ch := h.svc.SubscribeToEvents()
	defer h.svc.UnSubscribe(ch)

	for {
		select {
		case <-stream.Context().Done():
			return stream.Context().Err()
		case evt := <-ch:
			if err := stream.Send(domainToProto(evt)); err != nil {
				return err
			}
		}
	}
}

func domainErrStatus(err error) error {
	switch {
	case errors.Is(err, domain.ErrEventNotFound):
		return status.Error(codes.NotFound, err.Error())
	case errors.Is(err, domain.ErrEventExists):
		return status.Error(codes.AlreadyExists, err.Error())
	default:
		return status.Error(codes.Internal, err.Error())
	}
}
