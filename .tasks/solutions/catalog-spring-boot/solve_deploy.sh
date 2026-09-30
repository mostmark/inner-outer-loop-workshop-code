#!/bin/bash
################################
# catalog-spring-boot Solution #
################################
#
# Usage: solve_deploy.sh [PROJECT]   (default: my-project-<user>)

DIRECTORY="$(cd "$(dirname "$0")" && pwd)"
. "${DIRECTORY}/../../workshop-env.sh"
CONTEXT_FOLDER="${WORKSHOP_DIR}/labs/catalog-spring-boot"
PROJECT_NAME="${1:-${DEV_PROJECT}}"

oc project "${PROJECT_NAME}" > /dev/null || exit 1

"${DIRECTORY}/solve.sh"

cd "${CONTEXT_FOLDER}" || exit 1
mvn clean package -DskipTests oc:build oc:resource oc:apply || exit 1

echo "Catalog Spring-Boot Deployed"
