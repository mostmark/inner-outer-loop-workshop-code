#!/bin/bash
####################################
# Coolstore Application Deployment #
####################################
#
# Fast-forward of the Outer Loop: Continuous Integration, GitOps, Continuous Deployment and
# Service Mesh solutions for the staging project cn-project-<user>.
# Requires the Inner Loop Coolstore in my-project-<user> (inner_loop_deploy_coolstore.sh).
#
# Usage: outer_loop_deploy_coolstore.sh [USER]   (default: the workspace user)

DIRECTORY="$(cd "$(dirname "$0")" && pwd)"
. "${DIRECTORY}/workshop-env.sh"
workshop_set_user "$1"

"${DIRECTORY}/solutions/continuous-integration/solve.sh" "${WORKSHOP_USER}" &&
  "${DIRECTORY}/solutions/gitops/solve.sh" "${WORKSHOP_USER}" &&
  "${DIRECTORY}/solutions/continuous-deployment/solve.sh" "${WORKSHOP_USER}" &&
  "${DIRECTORY}/solutions/continuous-deployment/deploy.sh" "${WORKSHOP_USER}" &&
  "${DIRECTORY}/solutions/service-mesh/deploy.sh" "${WORKSHOP_USER}" ||
  { fail "The deployment of the Coolstore Application in ${STAGING_PROJECT} by Outer Loop has failed"; exit 1; }

ok "The deployment of the Coolstore Application in ${STAGING_PROJECT} by Outer Loop has succeeded"
