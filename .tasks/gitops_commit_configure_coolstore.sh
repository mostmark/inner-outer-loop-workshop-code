#!/bin/bash
#
# Pushes the exported GitOps manifests (labs/gitops/<svc>-coolstore) to the participant's Gitea
# repositories <svc>-gitops and creates the Argo CD Applications <svc>-<user> (AppProject and
# destination namespace cn-project-<user>, manual sync). The Argo CD CLI authenticates with the
# participant's API token (ARGOCD_AUTH_TOKEN).
#
# Usage: gitops_commit_configure_coolstore.sh [USER] [COMPONENT...]
#        (defaults: the workspace user; catalog gateway web)

DIRECTORY="$(cd "$(dirname "$0")" && pwd)"
. "${DIRECTORY}/workshop-env.sh"
workshop_set_user "$1"
shift
CONTEXT_FOLDER="${WORKSHOP_DIR}/labs/gitops"

declare -a COMPONENTS=("$@")
[ ${#COMPONENTS[@]} -gt 0 ] || COMPONENTS=("catalog" "gateway" "web")

echo "--- Argo CD Applications for GitOps ---"

argocd_env || exit 1

for COMPONENT_NAME in "${COMPONENTS[@]}"
do
    echo "Creating '${COMPONENT_NAME}-${WORKSHOP_USER}' Argo CD Application ..."

    REPO_NAME="${COMPONENT_NAME}-gitops"
    REPO_URL="$(gitea_repo_url "${REPO_NAME}")"

    [ -d "${CONTEXT_FOLDER}/${COMPONENT_NAME}-coolstore" ] ||
      { fail "${CONTEXT_FOLDER}/${COMPONENT_NAME}-coolstore not found. Run 'GitOps - Export Coolstore' first."; exit 1; }

    gitea_recreate_repo "${REPO_NAME}" || exit 1
    git_push_dir "${CONTEXT_FOLDER}/${COMPONENT_NAME}-coolstore" "${REPO_NAME}" || exit 1

    workshop_argocd repo add "${REPO_URL}" --project "${STAGING_PROJECT}" --upsert ||
      warn "Could not register ${REPO_URL} in Argo CD (public repositories work without it)"

    workshop_argocd app create "${COMPONENT_NAME}-${WORKSHOP_USER}" \
        --project "${STAGING_PROJECT}" \
        --sync-policy manual \
        --repo "${REPO_URL}" \
        --revision "HEAD" \
        --path "." \
        --dest-server "https://kubernetes.default.svc" \
        --dest-namespace "${STAGING_PROJECT}" \
        --upsert || exit 1
done

ok "--- Argo CD Applications have been created! ---"
