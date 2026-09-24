#!/bin/bash
####################################
# Coolstore Application Deployment #
####################################
#
# Runs the Inner Loop and the Outer Loop fast-forward scripts.
#
# Usage: end_to_end_deploy_coolstore.sh [USER]   (default: the workspace user)

DIRECTORY="$(cd "$(dirname "$0")" && pwd)"
. "${DIRECTORY}/workshop-env.sh"
workshop_set_user "$1"

"${DIRECTORY}/inner_loop_deploy_coolstore.sh" "${DEV_PROJECT}" &&
  "${DIRECTORY}/outer_loop_deploy_coolstore.sh" "${WORKSHOP_USER}"
