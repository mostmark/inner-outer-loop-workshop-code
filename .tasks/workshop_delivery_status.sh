#!/bin/bash
#
# Instructor view of the workshop progress. Participants are derived from the pre-created
# my-project-<user> namespaces. Needs cluster-wide read access (cluster-reader or admin).
#
# Usage: workshop_delivery_status.sh [-v]   (-v: one line per participant)

VERBOSE=false
[ "$1" = "-v" ] && VERBOSE=true

command -v jq > /dev/null || { echo "jq is required" >&2; exit 1; }

USERS=$(oc get namespaces -o name | sed -n 's%^namespace/my-project-%%p' | sort -V)
[ -n "${USERS}" ] || { echo "No my-project-* namespaces found" >&2; exit 1; }

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "${TMP_DIR}"' EXIT

oc get deployments -A -o json > "${TMP_DIR}/deployments.json"
oc get pipelines.tekton.dev -A -o json > "${TMP_DIR}/pipelines.json" 2> /dev/null || echo '{"items":[]}' > "${TMP_DIR}/pipelines.json"
oc get tasks.tekton.dev -A -o json > "${TMP_DIR}/tasks.json" 2> /dev/null || echo '{"items":[]}' > "${TMP_DIR}/tasks.json"
oc get applications.argoproj.io -n argocd -o json > "${TMP_DIR}/applications.json" 2> /dev/null || echo '{"items":[]}' > "${TMP_DIR}/applications.json"
oc get configmaps -A -o json --field-selector metadata.name=argocd-env-configmap > "${TMP_DIR}/configmaps.json"
oc get imagestreams -A -o json --field-selector metadata.name=inventory-coolstore > "${TMP_DIR}/imagestreams.json"
oc get pvc -A -o json --field-selector metadata.name=inventory-pipeline-pvc > "${TMP_DIR}/pvcs.json"

# ready NAMESPACE DEPLOYMENT -> 1 if the Deployment has at least one available replica
ready() {
  jq -r --arg ns "$1" --arg name "$2" \
    '[.items[] | select(.metadata.namespace == $ns and .metadata.name == $name and ((.status.availableReplicas // 0) > 0))] | length' \
    "${TMP_DIR}/deployments.json"
}
# exists FILE NAMESPACE NAME -> 1 if an object with that name exists in the namespace
exists() {
  jq -r --arg ns "$2" --arg name "$3" \
    '[.items[] | select(.metadata.namespace == $ns and .metadata.name == $name)] | length' "${TMP_DIR}/$1"
}
# app_exists NAME -> 1 if the Argo CD Application exists
app_exists() {
  jq -r --arg name "$1" '[.items[] | select(.metadata.name == $name)] | length' "${TMP_DIR}/applications.json"
}

# inc COUNTER VALUE (plain variables C_<counter>, so the script also runs with bash 3 on macOS)
inc() { eval "C_$1=\$(( \${C_$1:-0} + $2 ))"; }

${VERBOSE} && printf '%-16s %-26s %-40s\n' "USER" "INNER inv cat gw web db" "OUTER is pvc ci | apps i c g w | task cm java node | v2"

for user in ${USERS}; do
  dev="my-project-${user}"
  stg="cn-project-${user}"
  inv=$(ready "${dev}" inventory-coolstore); cat=$(ready "${dev}" catalog-coolstore)
  gw=$(ready "${dev}" gateway-coolstore); web=$(ready "${dev}" web-coolstore)
  db=$(( $(ready "${dev}" inventory-mariadb) + $(ready "${dev}" catalog-postgresql) ))
  is=$(exists imagestreams.json "${stg}" inventory-coolstore); pvc=$(exists pvcs.json "${stg}" inventory-pipeline-pvc)
  ci=$(exists pipelines.json "${stg}" inventory-pipeline)
  a_inv=$(app_exists "inventory-${user}"); a_cat=$(app_exists "catalog-${user}")
  a_gw=$(app_exists "gateway-${user}"); a_web=$(app_exists "web-${user}")
  task=$(exists tasks.json "${stg}" argocd-task-sync-and-wait); cm=$(exists configmaps.json "${stg}" argocd-env-configmap)
  java=$(exists pipelines.json "${stg}" coolstore-java-pipeline); node=$(exists pipelines.json "${stg}" coolstore-nodejs-pipeline)
  v2=$(ready "${stg}" catalog-coolstore-v2)

  inc projects 1; inc inv "${inv}"; inc cat "${cat}"; inc gw "${gw}"; inc web "${web}"; [ "${db}" -eq 2 ] && inc db 1
  inc is "${is}"; inc pvc "${pvc}"; inc ci "${ci}"
  inc a_inv "${a_inv}"; inc a_cat "${a_cat}"; inc a_gw "${a_gw}"; inc a_web "${a_web}"
  inc task "${task}"; inc cm "${cm}"; inc java "${java}"; inc node "${node}"; inc v2 "${v2}"

  ${VERBOSE} && printf '%-16s       %s   %s   %s  %s   %s/2   %s  %s   %s  |      %s %s %s %s |    %s  %s    %s    %s  |  %s\n' \
    "${user}" "${inv}" "${cat}" "${gw}" "${web}" "${db}" "${is}" "${pvc}" "${ci}" \
    "${a_inv}" "${a_cat}" "${a_gw}" "${a_web}" "${task}" "${cm}" "${java}" "${node}" "${v2}"
done
${VERBOSE} && echo

echo "--- Current Progress of the Inner Loop Part at $(date) ---"
echo "${C_projects:-0} development projects (my-project-<user>)"
echo "${C_inv:-0} Inventory Service deployed"
echo "${C_cat:-0} Catalog Service deployed"
echo "${C_gw:-0} Gateway Service deployed"
echo "${C_web:-0} Web Service deployed"
echo "${C_db:-0} with both databases (inventory-mariadb, catalog-postgresql)"
echo "------------------------"
echo
echo "--- Current Progress of the Outer Loop Part at $(date) ---"
echo "--- Set up Continuous Integration"
echo "  ${C_is:-0} Inventory ImageStream(s)"
echo "  ${C_pvc:-0} Inventory Tekton Workspace(s)"
echo "  ${C_ci:-0} Inventory Pipeline(s)"
echo
echo "--- Apply GitOps Workflow"
echo "  ${C_a_inv:-0} Inventory Application(s)"
echo "  ${C_a_cat:-0} Catalog Application(s)"
echo "  ${C_a_gw:-0} Gateway Application(s)"
echo "  ${C_a_web:-0} Web Application(s)"
echo
echo "--- Set up Continuous Deployment"
echo "  ${C_task:-0} Argo CD Task(s)"
echo "  ${C_cm:-0} Argo CD ConfigMap(s)"
echo "  ${C_java:-0} Java Pipeline(s)"
echo "  ${C_node:-0} NodeJS Pipeline(s)"
echo
echo "--- Connect and Monitor your Application"
echo "  ${C_v2:-0} Catalog v2 Service(s)"
echo "------------------------"
