package grpc

import (
	"fmt"
	"net"

	"google.golang.org/grpc"
	"google.golang.org/grpc/reflection"

	stellarv1 "github.com/karchx/stellardag-core/gen/stellar/v1"
)

func NewServer(h *Handler, port int) (*grpc.Server, net.Listener, error) {
	lis, err := net.Listen("tcp", fmt.Sprintf(":%d", port))
	if err != nil {
		return nil, nil, fmt.Errorf("net.Liste: %w", err)
	}

	srv := grpc.NewServer()
	stellarv1.RegisterStellarServiceServer(srv, h)
	reflection.Register(srv)

	return srv, lis, nil
}
