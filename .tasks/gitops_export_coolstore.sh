#!/bin/bash
#
# Exports the Kubernetes resources of the Coolstore services from the development project into
# labs/gitops/<svc>-coolstore/*.yaml, adapted for the staging project (GitOps with Argo CD):
#   - cluster-specific metadata and status removed,
#   - Service selectors and pod labels set to app=<svc> (Service Mesh),
#   - port names 8080-tcp/port-8080 renamed to http (Istio protocol selection),
#   - images pointed to the staging ImageStreams (built by the pipelines),
#   - env, volumes, init containers and service accounts of the dev deployments removed.
#
# Usage: gitops_export_coolstore.sh [DEV_PROJECT] [STAGING_PROJECT]
#        (default: my-project-<user> cn-project-<user>)

DIRECTORY="$(cd "$(dirname "$0")" && pwd)"
. "${DIRECTORY}/workshop-env.sh"

DEV="${1:-${DEV_PROJECT}}"
PROJECT="${2:-${STAGING_PROJECT}}"
GITOPS_DIR="${WORKSHOP_DIR}/labs/gitops"

declare -a COMPONENTS=("inventory" "catalog" "gateway" "web")

yq --version 2> /dev/null | grep -q 'version v4' || { fail "yq v4 is required"; exit 1; }

echo "--- Export Kubernetes resources for GitOps from ${DEV} to ${PROJECT} ---"

# Metadata and status that must not go into Git
CLEAN='del(.metadata) | del(
  .items[].metadata.namespace, .items[].metadata.uid, .items[].metadata.selfLink,
  .items[].metadata.creationTimestamp, .items[].metadata.resourceVersion, .items[].metadata.generation,
  .items[].metadata.ownerReferences, .items[].metadata.managedFields,
  .items[].metadata.annotations."kubectl.kubernetes.io/last-applied-configuration",
  .items[].status)'

SERVICE='del(.items[].spec.clusterIP, .items[].spec.clusterIPs)
  | .items[].spec.selector = {"app": strenv(COMPONENT)}
  | .items[].metadata.labels.app = strenv(COMPONENT)
  | (.items[].spec.ports[] | select(.name == "8080-tcp" or .name == "port-8080") | .name) = "http"'

ROUTE='del(.items[].spec.host)
  | (.items[] | select(.spec.port.targetPort == "8080-tcp" or .spec.port.targetPort == "port-8080") | .spec.port.targetPort) = "http"'

# resolve-names (added by the Quarkus OpenShift extension) makes OpenShift rewrite the image tag
# to a digest in the live Deployment, which Argo CD would report as permanent drift.
DEPLOYMENT='del(
    .items[].metadata.annotations."deployment.kubernetes.io/revision",
    .items[].metadata.annotations."image.openshift.io/triggers",
    .items[].spec.template.metadata.annotations."alpha.image.policy.openshift.io/resolve-names",
    .items[].spec.template.spec.initContainers,
    .items[].spec.template.spec.containers[].command,
    .items[].spec.template.spec.containers[].args,
    .items[].spec.template.spec.containers[].volumeMounts,
    .items[].spec.template.spec.containers[].env,
    .items[].spec.template.spec.volumes,
    .items[].spec.template.spec.serviceAccount,
    .items[].spec.template.spec.serviceAccountName)
  | .items[].metadata.labels.app = strenv(COMPONENT)
  | .items[].spec.selector.matchLabels.app = strenv(COMPONENT)
  | .items[].spec.template.metadata.labels.app = strenv(COMPONENT)
  | .items[].spec.template.metadata.labels."app.kubernetes.io/instance" = strenv(COMPONENT)
  | .items[].spec.template.spec.containers[].image = strenv(IMAGE)
  | (.items[].spec.template.spec.containers[].ports[] | select(.name == "8080-tcp" or .name == "port-8080") | .name) = "http"'

# The web front end builds the gateway URL from the namespace it runs in
WEB_DEPLOYMENT='.items[].spec.template.spec.containers[0].env =
  [{"name": "OPENSHIFT_BUILD_NAMESPACE", "valueFrom": {"fieldRef": {"fieldPath": "metadata.namespace"}}}]'

# export_kind KIND FILE [YQ_EXPRESSION]: writes FILE only if the component has resources of KIND
export_kind() {
  local kind="$1" file="$2" expression="${3:-.}" tmp
  tmp="$(mktemp)"
  if oc get "${kind}" -n "${DEV}" -l "app.kubernetes.io/instance=${COMPONENT}" -o yaml > "${tmp}" &&
    [ "$(yq '.items | length' "${tmp}")" -gt 0 ]; then
    yq "${CLEAN} | ${expression}" "${tmp}" > "${file}" || { rm -f "${tmp}"; return 1; }
    echo "  $(basename "${file}"): $(yq -r '[.items[].metadata.name] | join(", ")' "${file}")"
  fi
  rm -f "${tmp}"
}

mkdir -p "${GITOPS_DIR}"

for COMPONENT in "${COMPONENTS[@]}"
do
    export COMPONENT
    export IMAGE="image-registry.openshift-image-registry.svc:5000/${PROJECT}/${COMPONENT}-coolstore:latest"
    COMPONENT_DIR="${GITOPS_DIR}/${COMPONENT}-coolstore"

    echo "Exporting resources for ${COMPONENT}-coolstore..."
    mkdir -p "${COMPONENT_DIR}"
    rm -f "${COMPONENT_DIR}"/{secret,service,route,configmap,deployment}.yaml

    export_kind secret "${COMPONENT_DIR}/secret.yaml" || exit 1
    export_kind service "${COMPONENT_DIR}/service.yaml" "${SERVICE}" || exit 1
    export_kind route "${COMPONENT_DIR}/route.yaml" "${ROUTE}" || exit 1
    export_kind configmap "${COMPONENT_DIR}/configmap.yaml" || exit 1
    if [ "${COMPONENT}" = "web" ]; then
      export_kind deployment "${COMPONENT_DIR}/deployment.yaml" "${DEPLOYMENT} | ${WEB_DEPLOYMENT}" || exit 1
    else
      export_kind deployment "${COMPONENT_DIR}/deployment.yaml" "${DEPLOYMENT}" || exit 1
    fi

    [ -f "${COMPONENT_DIR}/deployment.yaml" ] || warn "  No Deployment found for ${COMPONENT} in ${DEV}"
done

echo "--- Kubernetes resources have been exported to ${GITOPS_DIR} ---"
