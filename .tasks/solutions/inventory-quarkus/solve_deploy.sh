#!/bin/bash
##############################
# inventory-quarkus Solution #
##############################
#
# Usage: solve_deploy.sh [PROJECT]   (default: my-project-<user>)

DIRECTORY="$(cd "$(dirname "$0")" && pwd)"
. "${DIRECTORY}/../../workshop-env.sh"
CONTEXT_FOLDER="${WORKSHOP_DIR}/labs/inventory-quarkus"
PROJECT_NAME="${1:-${DEV_PROJECT}}"

oc project "${PROJECT_NAME}" > /dev/null || exit 1

"${DIRECTORY}/solve.sh"

cd "${CONTEXT_FOLDER}" || exit 1
mvn clean package -Dquarkus.kubernetes.deploy=true -DskipTests -Dquarkus.container-image.group="$(oc project -q)" -Dquarkus.kubernetes-client.trust-certs=true || exit 1

echo "Inventory Quarkus Deployed"
