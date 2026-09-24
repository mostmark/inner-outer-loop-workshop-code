#!/bin/bash
##################################
# Continuous Deployment Solution #
##################################
#
# Runs inventory-pipeline and then the pipelines for catalog, gateway and web
# (pipeline_deploy_coolstore.sh, which waits for all PipelineRuns in the namespace).
#
# Usage: deploy.sh [USER]   (default: the workspace user)

DIRECTORY="$(cd "$(dirname "$0")" && pwd)"
. "${DIRECTORY}/../../workshop-env.sh"
workshop_set_user "$1"

oc project "${STAGING_PROJECT}" > /dev/null || exit 1

# Run the inventory pipeline
oc create -n "${STAGING_PROJECT}" -f - << YAML || exit 1
apiVersion: tekton.dev/v1
kind: PipelineRun
metadata:
  generateName: inventory-pipeline-
  labels:
    app.kubernetes.io/part-of: coolstore
spec:
  pipelineRef:
    name: inventory-pipeline
  workspaces:
    - name: shared-workspace
      persistentVolumeClaim:
        claimName: inventory-pipeline-pvc
YAML

# Deploy the whole Coolstore Application
"${WORKSHOP_DIR}/.tasks/pipeline_deploy_coolstore.sh" "${STAGING_PROJECT}"
