#!/bin/bash
##################################
# Continuous Deployment Solution #
##################################
#
# Creates the Task argocd-task-sync-and-wait and the ConfigMap argocd-env-configmap in
# cn-project-<user>, checks the pre-created Secret argocd-env-secret (Argo CD API token) and
# extends inventory-pipeline with the Argo CD sync and the rollout check.
#
# Usage: solve.sh [USER]   (default: the workspace user)

DIRECTORY="$(cd "$(dirname "$0")" && pwd)"
. "${DIRECTORY}/../../workshop-env.sh"
workshop_set_user "$1"
GIT_URL="$(gitea_repo_url inventory-quarkus)"

oc project "${STAGING_PROJECT}" > /dev/null || exit 1

# Argo CD Tekton Task
oc apply -n "${STAGING_PROJECT}" -f "${WORKSHOP_DIR}/labs/pipelines/00_argocd-task.yaml" || exit 1

# Argo CD ConfigMap (server address)
oc create configmap argocd-env-configmap -n "${STAGING_PROJECT}" \
    --from-literal=ARGOCD_SERVER="${ARGOCD_SERVER}" \
    --dry-run=client -o yaml | oc apply -n "${STAGING_PROJECT}" -f - || exit 1

# Argo CD Secret (API token): pre-created by the workshop provisioning, never stored in Git
if ! oc get secret argocd-env-secret -n "${STAGING_PROJECT}" > /dev/null 2>&1; then
  argocd_env || { fail "Secret argocd-env-secret is missing in ${STAGING_PROJECT}"; exit 1; }
  warn "Secret argocd-env-secret is missing in ${STAGING_PROJECT}; creating it from ARGOCD_AUTH_TOKEN"
  oc create secret generic argocd-env-secret -n "${STAGING_PROJECT}" \
      --from-literal=ARGOCD_AUTH_TOKEN="${ARGOCD_AUTH_TOKEN}" || exit 1
fi

# Expand the existing pipeline
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
    - name: argocd-task-sync-and-wait
      params:
        - name: application-name
          value: inventory-${WORKSHOP_USER}
      runAfter:
        - s2i-java
      taskRef:
        kind: Task
        name: argocd-task-sync-and-wait
    - name: openshift-client
      params:
        - name: SCRIPT
          value: oc rollout status deployment/inventory-coolstore
      runAfter:
        - argocd-task-sync-and-wait
      taskRef:
        resolver: cluster
        params:
          - name: kind
            value: task
          - name: name
            value: openshift-client
          - name: namespace
            value: openshift-pipelines
  workspaces:
    - name: shared-workspace
YAML

echo "Continuous Deployment Done"
