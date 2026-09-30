#!/bin/bash
###################
# GitOps Solution #
###################
#
# Exports the Coolstore resources of my-project-<user>, pushes them to the Gitea repositories
# <svc>-gitops and creates the Argo CD Applications <svc>-<user> for all four services.
#
# Usage: solve.sh [USER]   (default: the workspace user)

DIRECTORY="$(cd "$(dirname "$0")" && pwd)"
. "${DIRECTORY}/../../workshop-env.sh"
workshop_set_user "$1"

"${WORKSHOP_DIR}/.tasks/gitops_export_coolstore.sh" "${DEV_PROJECT}" "${STAGING_PROJECT}" || exit 1

"${WORKSHOP_DIR}/.tasks/gitops_commit_configure_coolstore.sh" "${WORKSHOP_USER}" inventory catalog gateway web || exit 1
