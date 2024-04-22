# syntax=docker/dockerfile:1

# Comments are provided throughout this file to help you get started.
# If you need more help, visit the Dockerfile reference guide at
# https://docs.docker.com/engine/reference/builder/

################################################################################
# Create a stage for building the application.
ARG GO_VERSION=1.22
FROM golang:${GO_VERSION}-alpine AS build
WORKDIR /src

# Download dependencies as a separate step to take advantage of Docker's caching.
# Leverage a cache mount to /go/pkg/mod/ to speed up subsequent builds.
# Leverage bind mounts to go.sum and go.mod to avoid having to copy them into
# the container.
RUN --mount=type=cache,target=/go/pkg/mod/ \
    --mount=type=bind,source=go.sum,target=go.sum \
    --mount=type=bind,source=go.mod,target=go.mod \
    go mod download -x

RUN apk add --no-cache \
    gcc \
    musl-dev

# Install sqlc-dev/sqlc and generate the Go files.
# Leverage a cache mount to /go/pkg/mod/ to speed up subsequent builds.
# Leverage a bind mount to the current directory to avoid having to copy the
# source code into the container.
RUN --mount=type=cache,target=/go/pkg/mod/ \
    --mount=rw,type=bind,source=./internal/db/,target=./internal/db/ \
    go install github.com/sqlc-dev/sqlc/cmd/sqlc@v1.26.0 && \
    sqlc generate -f ./internal/db/sqlc.yaml

# Build the application.
# Leverage a cache mount to /go/pkg/mod/ to speed up subsequent builds.
# Leverage a bind mount to the current directory to avoid having to copy the
# source code into the container.
RUN --mount=type=cache,target=/go/pkg/mod/ \
    --mount=rw,type=bind,target=. \
    CGO_ENABLED=1 go build -o /bin/server ./cmd/server

################################################################################
# Create a new stage for running the application that contains the minimal
# runtime dependencies for the application. This often uses a different base
# image from the build stage where the necessary files are copied from the build
# stage.
#
# The example below uses the alpine image as the foundation for running the app.
# By specifying the "latest" tag, it will also use whatever happens to be the
# most recent version of that image when you build your Dockerfile. If
# reproducability is important, consider using a versioned tag
# (e.g., alpine:3.17.2) or SHA (e.g., alpine:sha256:c41ab5c992deb4fe7e5da09f67a8804a46bd0592bfdf0b1847dde0e0889d2bff).
FROM alpine:latest AS final

# Install any runtime dependencies that are needed to run your application.
# Leverage a cache mount to /var/cache/apk/ to speed up subsequent builds.
RUN --mount=type=cache,target=/var/cache/apk \
    apk --update add \
    ca-certificates \
    tzdata \
    && \
    update-ca-certificates

# Create a non-privileged user that the app will run under.
# See https://docs.docker.com/develop/develop-images/dockerfile_best-practices/#user
ARG UID=10001
RUN adduser \
    --disabled-password \
    --gecos "" \
    --home "/nonexistent" \
    --shell "/sbin/nologin" \
    --no-create-home \
    --uid "${UID}" \
    voidmesh
USER voidmesh

################################################################################
# Create a stage to finalize the gRPC server image.
FROM final AS final-server
# Copy the executable from the "build" stage.
COPY --chown=voidmesh:voidmesh --from=build /bin/server /opt/voidmesh/

# Expose the port that the application listens on.
EXPOSE 50051

WORKDIR /opt/voidmesh/

# What the container should run when it is started.
ENTRYPOINT [ "/opt/voidmesh/server" ]

################################################################################
# Create a development image that includes what's required to generate the protoc and CSS files
FROM build AS development
RUN apk add --no-cache \
    protobuf

# Copy the executables from the "build" stage.
COPY --chown=voidmesh:voidmesh --from=build /bin/server /opt/voidmesh/

RUN go install google.golang.org/protobuf/cmd/protoc-gen-go@latest
RUN go install google.golang.org/grpc/cmd/protoc-gen-go-grpc@latest
RUN go install github.com/grpc-ecosystem/grpc-gateway/v2/protoc-gen-grpc-gateway@latest
RUN go install github.com/bokwoon95/wgo@latest
RUN go install github.com/grpc-ecosystem/grpc-health-probe@latest

# Set the default target to be the final stage.
FROM final
