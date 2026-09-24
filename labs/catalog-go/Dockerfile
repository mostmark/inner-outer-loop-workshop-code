# Catalog Service v2 (Go) for the Service Mesh lab.
# Built on OpenShift with the Docker build strategy (oc new-app --strategy=docker).

FROM registry.access.redhat.com/ubi9/go-toolset:latest AS builder
WORKDIR /opt/app-root/src
# Dependencies are pinned by go.sum
COPY --chown=1001:0 go.mod go.sum ./
RUN go mod download && go mod verify
COPY --chown=1001:0 . .
RUN CGO_ENABLED=0 GOOS=linux go build -buildvcs=false -trimpath -o catalog-go .

FROM registry.access.redhat.com/ubi9/ubi-minimal:latest
WORKDIR /app
COPY --from=builder /opt/app-root/src/catalog-go /app/catalog-go
COPY --from=builder /opt/app-root/src/templates /app/templates
COPY --from=builder /opt/app-root/src/static /app/static
USER 1001
EXPOSE 8080
CMD ["/app/catalog-go"]
