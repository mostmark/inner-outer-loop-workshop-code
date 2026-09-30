# Gateway Service (.NET)

ASP.NET Core service (.NET 9, `net9.0`) that combines the product list of the Catalog Service with
the availability data of the Inventory Service. It replaces the original Vert.x gateway.

![.NET logo](wwwroot/240px-NET_Core_Logo.png)

## Endpoints

| Path | Description |
|---|---|
| `/api/products` | Products from the Catalog Service, enriched with the quantity from the Inventory Service |
| `/health` | Health check (used by the liveness and readiness probes) |
| `/` | Test page |

## Configuration

The gateway calls the other services through their Kubernetes Service names. Override them with
environment variables if needed:

| Variable | Default |
|---|---|
| `COMPONENT_CATALOG_COOLSTORE_HOST` | `catalog-coolstore` |
| `COMPONENT_CATALOG_COOLSTORE_PORT` | `8080` |
| `COMPONENT_INVENTORY_COOLSTORE_HOST` | `inventory-coolstore` |
| `COMPONENT_INVENTORY_COOLSTORE_PORT` | `8080` |

## Build and deploy on OpenShift (as in the workshop)

The devfile command **Gateway - Build and Deploy Component** runs a binary S2I build with the
`dotnet:9.0` image stream and creates a Deployment, a Service and a Route:

```bash
oc new-build dotnet:9.0 --name gateway-coolstore --labels=component=gateway \
  --env DOTNET_STARTUP_PROJECT=app.csproj --binary=true
oc start-build gateway-coolstore --from-dir=. -w
oc new-app gateway-coolstore:latest --name gateway-coolstore \
  --labels=app=coolstore,app.kubernetes.io/instance=gateway,app.kubernetes.io/part-of=coolstore,app.kubernetes.io/name=gateway,app.openshift.io/runtime=dotnet,component=gateway
oc expose svc gateway-coolstore
```

In the Outer Loop, the `coolstore-dotnet-pipeline` (`labs/pipelines`) builds the same code with the
`s2i-dotnet` Task (`VERSION` `9.0`, `CONTEXT` `labs/gateway-dotnet`).

## Local build

```bash
dotnet restore
dotnet build
export COMPONENT_CATALOG_COOLSTORE_HOST=localhost COMPONENT_CATALOG_COOLSTORE_PORT=8081
export COMPONENT_INVENTORY_COOLSTORE_HOST=localhost COMPONENT_INVENTORY_COOLSTORE_PORT=8082
dotnet run
```

## Container build

The [`Dockerfile`](Dockerfile) builds with `registry.access.redhat.com/ubi8/dotnet-90` and runs on
`registry.access.redhat.com/ubi8/dotnet-90-runtime` (both available without registry login):

```bash
podman build --platform linux/amd64 -t gateway-coolstore .
podman run --rm -p 8080:8080 \
  -e COMPONENT_CATALOG_COOLSTORE_HOST=host.containers.internal \
  -e COMPONENT_INVENTORY_COOLSTORE_HOST=host.containers.internal \
  gateway-coolstore
```
