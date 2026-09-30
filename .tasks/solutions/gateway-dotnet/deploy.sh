#!/bin/bash
###########################
# gateway-dotnet Solution #
###########################
#
# Usage: deploy.sh [PROJECT]   (default: my-project-<user>)

DIRECTORY="$(cd "$(dirname "$0")" && pwd)"
. "${DIRECTORY}/../../workshop-env.sh"
CONTEXT_FOLDER="${WORKSHOP_DIR}/labs/gateway-dotnet"
PROJECT_NAME="${1:-${DEV_PROJECT}}"

oc project "${PROJECT_NAME}" > /dev/null || exit 1
cd "${CONTEXT_FOLDER}" || exit 1

oc new-build dotnet:9.0 --name gateway-coolstore -n "${PROJECT_NAME}" \
  --labels=component=gateway \
  --env DOTNET_STARTUP_PROJECT=app.csproj --binary=true || exit 1
oc start-build gateway-coolstore --from-dir=. -w -n "${PROJECT_NAME}" || exit 1

oc new-app gateway-coolstore:latest --name gateway-coolstore -n "${PROJECT_NAME}" \
  --labels=app=coolstore,app.kubernetes.io/instance=gateway,app.kubernetes.io/part-of=coolstore,app.kubernetes.io/name=gateway,app.openshift.io/runtime=dotnet,component=gateway || exit 1

oc expose svc gateway-coolstore -n "${PROJECT_NAME}"

oc annotate --overwrite deployment/gateway-coolstore app.openshift.io/connects-to='catalog,inventory' -n "${PROJECT_NAME}"

echo "Gateway .NET Deployed"
