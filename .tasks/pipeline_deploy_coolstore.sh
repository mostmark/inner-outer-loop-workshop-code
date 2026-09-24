#!/bin/bash
#
# Builds and deploys Catalog, Gateway and Web to the staging project with OpenShift Pipelines:
#   - applies labs/pipelines (Argo CD Task, ImageStreams, PVCs, Pipelines),
#   - pushes the solved Catalog Service (labs/catalog-spring-boot + solution) to the participant's
#     Gitea repository catalog-spring-boot and builds it from there,
#   - builds Gateway and Web from the workshop code repository (branch main),
#   - each pipeline syncs the Argo CD Application <svc>-<user> and waits for the rollout.
#
# Usage: pipeline_deploy_coolstore.sh [NAMESPACE]   (default: cn-project-<user>)

DIRECTORY="$(cd "$(dirname "$0")" && pwd)"
. "${DIRECTORY}/workshop-env.sh"

NAMESPACE="${1:-${STAGING_PROJECT}}"
case "${NAMESPACE}" in
  cn-project-*) workshop_set_user "${NAMESPACE#cn-project-}" ;;
esac

oc apply -n "${NAMESPACE}" -f "${WORKSHOP_DIR}/labs/pipelines" || exit 1

# The Argo CD task needs the ConfigMap (created in the Continuous Delivery lab) and the
# pre-created Secret with the Argo CD API token.
if ! oc get configmap argocd-env-configmap -n "${NAMESPACE}" > /dev/null 2>&1; then
  oc create configmap argocd-env-configmap -n "${NAMESPACE}" --from-literal=ARGOCD_SERVER="${ARGOCD_SERVER}" || exit 1
fi
oc get secret argocd-env-secret -n "${NAMESPACE}" > /dev/null || { fail "Secret argocd-env-secret is missing in ${NAMESPACE}"; exit 1; }

# Catalog: the code repository only contains the skeleton, so push the solved service to Gitea
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "${TMP_DIR}"' EXIT
CATALOG_DIR="${TMP_DIR}/catalog-spring-boot"
mkdir -p "${CATALOG_DIR}"
cp -R "${WORKSHOP_DIR}/labs/catalog-spring-boot/." "${CATALOG_DIR}/"
rm -rf "${CATALOG_DIR}/.git" "${CATALOG_DIR}/target"
cp "${DIRECTORY}"/solutions/catalog-spring-boot/*.java "${CATALOG_DIR}/src/main/java/com/redhat/cloudnative/catalog/"
gitea_ensure_repo catalog-spring-boot || exit 1
git_push_dir "${CATALOG_DIR}" catalog-spring-boot "Catalog Service" || exit 1

# start_pipeline PIPELINE APP_NAME GIT_URL GIT_CONTEXT -> prints the PipelineRun name
start_pipeline() {
  oc create -n "${NAMESPACE}" -o name -f - << YAML
apiVersion: tekton.dev/v1
kind: PipelineRun
metadata:
  generateName: ${2}-
  labels:
    app.kubernetes.io/part-of: coolstore
    app.kubernetes.io/instance: ${2}
spec:
  pipelineRef:
    name: ${1}
  params:
    - name: APP_NAME
      value: ${2}
    - name: APP_GIT_URL
      value: ${3}
    - name: APP_GIT_CONTEXT
      value: ${4}
    - name: APP_GIT_REVISION
      value: main
    - name: NAMESPACE
      value: ${NAMESPACE}
    - name: ARGOCD_APP_NAME
      value: ${2}-${WORKSHOP_USER}
  workspaces:
    - name: shared-workspace
      persistentVolumeClaim:
        claimName: ${2}-pipeline-pvc
YAML
}

RUNS=()
RUNS+=("$(start_pipeline coolstore-java-pipeline catalog "$(gitea_repo_url catalog-spring-boot)" .)") || exit 1
RUNS+=("$(start_pipeline coolstore-dotnet-pipeline gateway "${CODE_REPO_URL}" labs/gateway-dotnet)") || exit 1
RUNS+=("$(start_pipeline coolstore-nodejs-pipeline web "${CODE_REPO_URL}" labs/web-nodejs)") || exit 1
info "Started: ${RUNS[*]}"

# Wait until no PipelineRun of the namespace is running any more
while true; do
  RUNNING="$(oc get pipelineruns.tekton.dev -n "${NAMESPACE}" \
    -o jsonpath='{range .items[*]}{.metadata.name}={.status.conditions[?(@.type=="Succeeded")].status}{"\n"}{end}' \
    | grep -E '=(Unknown)?$' | cut -d= -f1 | xargs)"
  [ -z "${RUNNING}" ] && break
  echo "Waiting for the pipelines to complete: ${RUNNING}"
  sleep 10
done

FAILED=""
for run in "${RUNS[@]}"; do
  status="$(oc get -n "${NAMESPACE}" "${run}" -o jsonpath='{.status.conditions[?(@.type=="Succeeded")].status}')"
  [ "${status}" = "True" ] || FAILED="${FAILED} ${run#*/}"
done

if [ -n "${FAILED}" ]; then
  fail "The following PipelineRuns failed:${FAILED} (see: tkn pipelinerun logs <name> -n ${NAMESPACE})"
  exit 1
fi

ok "The deployment of the Coolstore Application by OpenShift Pipeline has succeeded"
