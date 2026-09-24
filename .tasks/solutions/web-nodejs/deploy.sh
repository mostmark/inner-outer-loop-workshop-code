#!/bin/bash
#######################
# web-nodejs Solution #
#######################
#
# Usage: deploy.sh [PROJECT]   (default: my-project-<user>)

DIRECTORY="$(cd "$(dirname "$0")" && pwd)"
. "${DIRECTORY}/../../workshop-env.sh"
PROJECT_NAME="${1:-${DEV_PROJECT}}"

oc project "${PROJECT_NAME}" > /dev/null || exit 1

oc new-app "nodejs:22-ubi9~${CODE_REPO_URL}#${CODE_REPO_REVISION}" -n "${PROJECT_NAME}" \
        --context-dir=labs/web-nodejs \
        --name=web-coolstore \
        --labels=app=coolstore,app.kubernetes.io/instance=web,app.kubernetes.io/part-of=coolstore,app.kubernetes.io/name=nodejs || exit 1

oc expose svc/web-coolstore -n "${PROJECT_NAME}"
oc annotate --overwrite deployment/web-coolstore app.kubernetes.io/component-source-type=git -n "${PROJECT_NAME}"
oc annotate --overwrite deployment/web-coolstore app.openshift.io/connects-to=gateway -n "${PROJECT_NAME}"

echo "Web Node.js Deployed"
