package main

import (
	"context"
	"log"
	"net"

	"github.com/VoidMesh/backend/internal/pkg/services"
	"google.golang.org/grpc"
	"google.golang.org/grpc/reflection"
)

func main() {
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()

	// Create a listener on TCP port for gRPC server
	lis, err := net.Listen("tcp", ":50051")
	if err != nil {
		log.Fatalf("failed to listen: %v\n", err)
	}
	defer lis.Close()

	// Create a new gRPC server
	s := grpc.NewServer()
	defer s.GracefulStop()

	// Register reflection service
	reflection.Register(s)

	// Register V1 services
	services.RegisterV1(ctx, s)

	// Serve the gRPC server
	log.Printf("server listening at %v", lis.Addr())
	if err := s.Serve(lis); err != nil {
		log.Fatalf("failed to serve: %v", err)
	}
}
