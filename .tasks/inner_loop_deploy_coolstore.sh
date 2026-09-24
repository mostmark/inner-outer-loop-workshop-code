#!/bin/bash
####################################
# Coolstore Application Deployment #
####################################
#
# Fast-forward of the Inner Loop: deploys the solved Coolstore application (Inventory, Catalog,
# Gateway, Web, health probes, externalized configuration) into the development project.
#
# Usage: inner_loop_deploy_coolstore.sh [PROJECT]   (default: my-project-<user>)

DIRECTORY="$(cd "$(dirname "$0")" && pwd)"
. "${DIRECTORY}/workshop-env.sh"

PROJECT_NAME="${1:-${DEV_PROJECT}}"

workshop_login || exit 1
workshop_use_project "${PROJECT_NAME}" || exit 1

# Starting from scratch: the project is pre-created, so remove previous Coolstore resources instead
workshop_clean_project "${PROJECT_NAME}"

# Revert local changes of the lab sources to their Git versions
info "Revert any local file changes in labs/"
rm -rf "${WORKSHOP_DIR}/labs/inventory-quarkus/.git"
git -C "${WORKSHOP_DIR}" checkout -- labs
git -C "${WORKSHOP_DIR}" clean -fdq -- labs/inventory-quarkus labs/catalog-spring-boot

"${DIRECTORY}/solutions/inventory-quarkus/solve_deploy.sh" "${PROJECT_NAME}" &&
  "${DIRECTORY}/solutions/catalog-spring-boot/solve_deploy.sh" "${PROJECT_NAME}" &&
  "${DIRECTORY}/solutions/gateway-dotnet/deploy.sh" "${PROJECT_NAME}" &&
  "${DIRECTORY}/solutions/web-nodejs/deploy.sh" "${PROJECT_NAME}" &&
  "${DIRECTORY}/solutions/health-probes/deploy.sh" "${PROJECT_NAME}" &&
  "${DIRECTORY}/solutions/app-config/deploy.sh" "${PROJECT_NAME}" ||
  { fail "The deployment of the Coolstore Application in ${PROJECT_NAME} by Inner Loop has failed"; exit 1; }

ok "The deployment of the Coolstore Application in ${PROJECT_NAME} by Inner Loop has succeeded"
