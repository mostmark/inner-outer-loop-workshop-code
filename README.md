# Inner Loop + Outer Loop Workshop: example code

This repository holds the example code of the Red Hat **Inner Loop + Outer Loop** workshop: the
Coolstore microservices, the OpenShift Dev Spaces devfile of the participants' workspace, the
tooling image, the Tekton resources and the scripts behind the devfile commands.

In the hands-on workshop, developers experience both loops on OpenShift:

- **Inner Loop**: code, build, deploy and debug the Coolstore services (Quarkus, Spring Boot,
  .NET, Node.js) from OpenShift Dev Spaces into their development project `my-project-<user>`.
- **Outer Loop**: continuous integration with OpenShift Pipelines, GitOps with Argo CD
  (OpenShift GitOps), continuous delivery into the staging project `cn-project-<user>` and
  observability and traffic management with OpenShift Service Mesh and Kiali.

| Repository | Content |
|---|---|
| [inner-outer-loop-workshop](https://github.com/mostmark/inner-outer-loop-workshop) | Lab guide (Antora, Showroom) |
| [inner-outer-loop-workshop-gitops](https://github.com/mostmark/inner-outer-loop-workshop-gitops) | Cluster provisioning with OpenShift GitOps and Helm |
| inner-outer-loop-workshop-code (this repository) | Example code, devfile, tooling image, pipelines |

All three repositories use the branch `main` only.

## Content

| Path | Description |
|---|---|
| [`devfile.yaml`](devfile.yaml) | Devfile of the workspace `wksp-end-to-end-dev` (tooling container, Maven volume, workshop commands) |
| [`labs/`](labs) | Coolstore services (`inventory-quarkus`, `catalog-spring-boot`, `gateway-dotnet`, `web-nodejs`, `catalog-go`) and Tekton resources (`pipelines`), see [labs/README.md](labs/README.md) |
| [`.tasks/`](.tasks) | Scripts behind the devfile commands, reference solutions (`.tasks/solutions`) and the instructor status script `workshop_delivery_status.sh` |
| [`tools/`](tools) | Containerfile of the tooling image `quay.io/mostmark/workshop-tools:latest`, see [tools/README.md](tools/README.md) |

## Devfile and workspace

The workshop provisioning pre-creates a DevWorkspace `wksp-end-to-end-dev` in each participant's
Dev Spaces namespace `devspaces-<user>`. It references this devfile as its parent
(`https://raw.githubusercontent.com/mostmark/inner-outer-loop-workshop-code/main/devfile.yaml`),
clones this repository (branch `main`) to `/projects/workshop`, and runs the tooling container
`workshop-tools` (Java 21, Maven 3.9, `oc`, `tkn`, `argocd`, `yq`, `git`, `jq`) with the VS Code
editor merged into it.

The devfile commands (Terminal > Run Task... > devfile) are referenced by their labels in the lab
guide. They source [`.tasks/workshop-env.sh`](.tasks/workshop-env.sh), which reads the per-user
environment that the provisioning mounts into the workspace and falls back to values derived from
the namespace `devspaces-<user>`:

| Variable | Source | Value |
|---|---|---|
| `WORKSHOP_USER` | ConfigMap `workshop-env` | OpenShift and Gitea user name |
| `WORKSHOP_DEV_PROJECT` / `WORKSHOP_STAGING_PROJECT` | ConfigMap `workshop-env` | `my-project-<user>` / `cn-project-<user>` |
| `WORKSHOP_GITEA_URL` | ConfigMap `workshop-env` | `http://gitea-server.gitea.svc:3000` |
| `MAVEN_MIRROR_URL` | ConfigMap `workshop-env`, devfile | `http://nexus.nexus.svc:8081/repository/maven-all-public/` |
| `ARGOCD_SERVER`, `ARGOCD_OPTS` | ConfigMap `workshop-env` | `argocd-server.argocd.svc`, `--plaintext` |
| `WORKSHOP_PASSWORD`, `ARGOCD_AUTH_TOKEN` | Secret `workshop-credentials` | Workshop password, Argo CD API token |
| Git credentials for Gitea | Secret `workshop-git-credentials` | DevWorkspace git credential (no password in URLs) |

No password or token is stored in this repository.

## How the workshop is provisioned

[inner-outer-loop-workshop-gitops](https://github.com/mostmark/inner-outer-loop-workshop-gitops)
installs everything with OpenShift GitOps: the operators (Dev Spaces, Pipelines, GitOps, Service
Mesh 3, Kiali), shared services (Gitea, a Nexus Maven mirror, a participant Argo CD instance with
OpenShift login, the database templates `coolstore-mariadb` / `coolstore-postgresql`, the Java 21
S2I builder tag `openshift/java:openjdk-21-ubi9`), the lab guide, and per participant the projects
`my-project-<user>`, `cn-project-<user>` and `devspaces-<user>`, the Argo CD AppProject
`cn-project-<user>`, the Gitea account, the Argo CD token Secret `argocd-env-secret` and the
pre-created workspace.

## Fast-forward scripts

Participants who skip parts of the workshop can catch up with the devfile commands
**Inner Loop - Deploy Coolstore** (`.tasks/inner_loop_deploy_coolstore.sh`) and the scripts
`.tasks/outer_loop_deploy_coolstore.sh` and `.tasks/end_to_end_deploy_coolstore.sh`.
**OpenShift - Cleanup** removes the Coolstore resources from both projects (the projects are kept).

## Tooling image

```bash
cd tools
export QUAY_USER=mostmark
./build-push.sh   # podman build --platform linux/amd64 + push quay.io/$QUAY_USER/workshop-tools:latest
```
