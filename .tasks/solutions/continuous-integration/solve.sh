#!/bin/bash
###################################
# Continuous Integration Solution #
###################################
#
# Pushes labs/inventory-quarkus to the participant's Gitea repository inventory-quarkus and
# creates the Pipeline inventory-pipeline (git-clone + s2i-java) in cn-project-<user>.
#
# Usage: solve.sh [USER]   (default: the workspace user)

DIRECTORY="$(cd "$(dirname "$0")" && pwd)"
. "${DIRECTORY}/../../workshop-env.sh"
workshop_set_user "$1"
CONTEXT_FOLDER="${WORKSHOP_DIR}/labs/inventory-quarkus"
GIT_URL="$(gitea_repo_url inventory-quarkus)"

oc project "${STAGING_PROJECT}" > /dev/null || exit 1

gitea_recreate_repo inventory-quarkus || exit 1
git_push_dir "${CONTEXT_FOLDER}" inventory-quarkus || exit 1

oc apply -f - << YAML || exit 1
kind: PersistentVolumeClaim
apiVersion: v1
metadata:
  name: inventory-pipeline-pvc
  namespace: ${STAGING_PROJECT}
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 1Gi
  volumeMode: Filesystem
YAML

oc apply -f - << YAML || exit 1
apiVersion: tekton.dev/v1
kind: Pipeline
metadata:
  name: inventory-pipeline
  namespace: ${STAGING_PROJECT}
spec:
  tasks:
    - name: git-clone
      params:
        - name: URL
          value: '${GIT_URL}'
        - name: SUBMODULES
          value: 'true'
        - name: DEPTH
          value: '1'
        - name: SSL_VERIFY
          value: 'true'
        - name: DELETE_EXISTING
          value: 'true'
        - name: REVISION
          value: main
      taskRef:
        resolver: cluster
        params:
          - name: kind
            value: task
          - name: name
            value: git-clone
          - name: namespace
            value: openshift-pipelines
      workspaces:
        - name: output
          workspace: shared-workspace
    - name: s2i-java
      params:
        - name: VERSION
          value: openjdk-21-ubi9
        - name: CONTEXT
          value: .
        - name: TLS_VERIFY
          value: 'false'
        - name: ENV_VARS
          value:
            - 'MAVEN_MIRROR_URL=${MAVEN_MIRROR_URL}'
        - name: IMAGE
          value: >-
            image-registry.openshift-image-registry.svc:5000/${STAGING_PROJECT}/inventory-coolstore
      runAfter:
        - git-clone
      taskRef:
        resolver: cluster
        params:
          - name: kind
            value: task
          - name: name
            value: s2i-java
          - name: namespace
            value: openshift-pipelines
      workspaces:
        - name: source
          workspace: shared-workspace
  workspaces:
    - name: shared-workspace
YAML

echo "Continuous Integration Done"

# Run it with:
#   tkn pipeline start inventory-pipeline -n <cn-project-user> \
#       --workspace name=shared-workspace,claimName=inventory-pipeline-pvc
#   tkn pipeline logs inventory-pipeline -n <cn-project-user> --last -f
