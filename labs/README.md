# Coolstore labs

Source code of the Coolstore online store that participants build, deploy and operate during the
Inner Loop + Outer Loop workshop. It follows a microservices architecture:

| Directory | Service | Technology | State in this repository |
|---|---|---|---|
| `web-nodejs` | Web front end | Node.js 22, Express, AngularJS | complete |
| `gateway-dotnet` | API gateway: combines Catalog and Inventory into `/api/products` | .NET 9 (ASP.NET Core) | complete |
| `catalog-spring-boot` | Product catalog REST API (`/api/catalog`) | Spring Boot 2.1, Java | skeleton, completed in the Inner Loop lab |
| `inventory-quarkus` | Inventory REST API (`/api/inventory`) | Red Hat build of Quarkus 3.27, Java 21 | skeleton, completed in the Inner Loop lab |
| `catalog-go` | Catalog Service v2 for the Service Mesh canary release | Go (UBI 9 Go Toolset) | complete |
| `pipelines` | Tekton resources for the Outer Loop (Argo CD Task, ImageStreams, PVCs, Pipelines) | OpenShift Pipelines (`tekton.dev/v1`) | complete |

```
                    +-------------+
                    |     Web     |
                    |   Node.js   |
                    |  AngularJS  |
                    +------+------+
                           |
                           v
                    +------+------+
                    | API Gateway |
                    |    .NET     |
                    +------+------+
                           |
                +----------+----------+
                v                     v
         +------+------+       +------+------+
         |   Catalog   |       |  Inventory  |
         | Spring Boot |       |   Quarkus   |
         | (Go for v2) |       |             |
         +------+------+       +------+------+
                |                     |
           PostgreSQL              MariaDB
```

The Kubernetes Service names are `web-coolstore`, `gateway-coolstore`, `catalog-coolstore`
(`catalog-coolstore-v2` for the Go version) and `inventory-coolstore`; all listen on port 8080.

## How the labs use it

- **Inner Loop** (project `my-project-<user>`): participants complete the Inventory and Catalog
  services in Dev Spaces, deploy all four services with the devfile commands (Quarkus OpenShift
  extension, JKube, S2I builds), add health probes and move the configuration into ConfigMaps
  with MariaDB and PostgreSQL databases (templates `coolstore-mariadb` / `coolstore-postgresql`).
- **Outer Loop** (project `cn-project-<user>`): the code is pushed to the participant's Gitea,
  built by the Pipelines in [`pipelines`](pipelines), deployed by Argo CD from the manifests that
  `.tasks/gitops_export_coolstore.sh` exports to `labs/gitops/` (generated, not in Git), and put
  into OpenShift Service Mesh together with `catalog-go`.

The reference solutions and the fast-forward scripts are in [`../.tasks`](../.tasks).
