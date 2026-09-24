# shellcheck shell=bash
#
# Workshop environment for devfile commands and .tasks scripts. Source it, do not run it:
#
#   . /projects/workshop/.tasks/workshop-env.sh
#
# The users chart mounts the ConfigMap `workshop-env` and the Secret `workshop-credentials` as
# environment variables into every workspace container (WORKSHOP_USER, WORKSHOP_DEV_PROJECT,
# WORKSHOP_STAGING_PROJECT, WORKSHOP_GITEA_URL, MAVEN_MIRROR_URL, ARGOCD_SERVER, ARGOCD_OPTS,
# ARGOCD_AUTH_TOKEN, WORKSHOP_PASSWORD, GIT_AUTHOR_*/GIT_COMMITTER_*). Everything below falls back
# to values derived from the Dev Spaces namespace (devspaces-<user>) when a variable is missing.

WORKSHOP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")/.." 2> /dev/null && pwd)"
[ -d "${WORKSHOP_DIR}/.tasks" ] || WORKSHOP_DIR=/projects/workshop
export WORKSHOP_DIR

if [ -z "${WORKSHOP_USER}" ] && [ -n "${DEVWORKSPACE_NAMESPACE}" ]; then
  WORKSHOP_USER="${DEVWORKSPACE_NAMESPACE#devspaces-}"
fi
if [ -z "${WORKSHOP_USER}" ]; then
  WORKSHOP_USER="$(oc whoami 2> /dev/null | grep -v '^system:' || true)"
fi
export WORKSHOP_USER

export DEV_PROJECT="${WORKSHOP_DEV_PROJECT:-my-project-${WORKSHOP_USER}}"
export STAGING_PROJECT="${WORKSHOP_STAGING_PROJECT:-cn-project-${WORKSHOP_USER}}"
export GITEA_URL="${WORKSHOP_GITEA_URL:-http://gitea-server.gitea.svc:3000}"
GITEA_URL="${GITEA_URL%/}"
export ARGOCD_SERVER="${ARGOCD_SERVER:-argocd-server.argocd.svc}"
export ARGOCD_OPTS="${ARGOCD_OPTS:---plaintext}"
export MAVEN_MIRROR_URL="${MAVEN_MIRROR_URL:-http://nexus.nexus.svc:8081/repository/maven-all-public/}"
export CODE_REPO_URL="${CODE_REPO_URL:-https://github.com/mostmark/inner-outer-loop-workshop-code.git}"
export CODE_REPO_REVISION="${CODE_REPO_REVISION:-main}"

# Git identity (the chart sets it; needed when the scripts commit)
export GIT_AUTHOR_NAME="${GIT_AUTHOR_NAME:-${WORKSHOP_USER}}"
export GIT_AUTHOR_EMAIL="${GIT_AUTHOR_EMAIL:-${WORKSHOP_USER}@example.com}"
export GIT_COMMITTER_NAME="${GIT_COMMITTER_NAME:-${GIT_AUTHOR_NAME}}"
export GIT_COMMITTER_EMAIL="${GIT_COMMITTER_EMAIL:-${GIT_AUTHOR_EMAIL}}"

# ---------------------------------------------------------------------------------------------
# Output helpers
# ---------------------------------------------------------------------------------------------
info() { printf '\033[0;36m%s\033[0m\n' "$*"; }
ok()   { printf '\033[0;32m%s\033[0m\n' "$*"; }
warn() { printf '\033[0;33m%s\033[0m\n' "$*" >&2; }
fail() { printf '\033[0;31m%s\033[0m\n' "$*" >&2; return 1; }

# Switch all derived names to another participant (used by scripts that take a username argument).
workshop_set_user() {
  [ -n "$1" ] || return 0
  WORKSHOP_USER="$1"
  DEV_PROJECT="my-project-$1"
  STAGING_PROJECT="cn-project-$1"
  export WORKSHOP_USER DEV_PROJECT STAGING_PROJECT
}

# ---------------------------------------------------------------------------------------------
# OpenShift login: keeps an existing session of the participant, otherwise logs in with the
# workshop password (never stored in Git; comes from the Secret workshop-credentials).
# ---------------------------------------------------------------------------------------------
workshop_login() {
  local current server
  [ -n "${WORKSHOP_USER}" ] || { fail "Cannot determine the workshop user (WORKSHOP_USER is empty)"; return 1; }
  current="$(oc whoami 2> /dev/null || true)"
  if [ "${current}" = "${WORKSHOP_USER}" ]; then
    info "Logged in to $(oc whoami --show-server) as ${WORKSHOP_USER}"
    return 0
  fi
  if [ -z "${WORKSHOP_PASSWORD}" ]; then
    fail "Not logged in as ${WORKSHOP_USER} and WORKSHOP_PASSWORD is not set. Run: oc login -u ${WORKSHOP_USER}"
    return 1
  fi
  server="$(oc whoami --show-server 2> /dev/null || true)"
  [ -n "${server}" ] || server="https://kubernetes.default.svc"
  oc login "${server}" --username="${WORKSHOP_USER}" --password="${WORKSHOP_PASSWORD}" --insecure-skip-tls-verify > /dev/null \
    || { fail "oc login as ${WORKSHOP_USER} failed"; return 1; }
  info "Logged in to ${server} as ${WORKSHOP_USER}"
}

# Switch to a project; create it only if it does not exist (the chart pre-creates the workshop projects).
workshop_use_project() {
  local ns="$1"
  if oc get project "${ns}" > /dev/null 2>&1; then
    oc project "${ns}" > /dev/null && info "Using project ${ns}"
  else
    oc new-project "${ns}" > /dev/null && info "Created project ${ns}"
  fi
}

# ---------------------------------------------------------------------------------------------
# Gitea (API calls use basic auth with the participant's own account inside their workspace;
# git pushes use the DevWorkspace git credential, with an env-based credential helper as fallback)
# ---------------------------------------------------------------------------------------------
gitea_api() {
  # gitea_api METHOD PATH [JSON]  -> prints the HTTP status code
  local method="$1" path="$2" data="$3"
  [ -n "${WORKSHOP_PASSWORD}" ] || { fail "WORKSHOP_PASSWORD is not set (needed for the Gitea API)"; return 1; }
  curl -sS -o /dev/null -w '%{http_code}' -X "${method}" \
    -u "${WORKSHOP_USER}:${WORKSHOP_PASSWORD}" \
    -H 'accept: application/json' -H 'Content-Type: application/json' \
    ${data:+-d "${data}"} "${GITEA_URL}/api/v1${path}"
}

# Create the repository <user>/<name> if it does not exist yet.
gitea_ensure_repo() {
  local name="$1" code
  code="$(gitea_api GET "/repos/${WORKSHOP_USER}/${name}")" || return 1
  if [ "${code}" = "200" ]; then
    info "Gitea repository ${WORKSHOP_USER}/${name} exists"
    return 0
  fi
  code="$(gitea_api POST /user/repos "{\"name\": \"${name}\", \"private\": false, \"default_branch\": \"main\"}")" || return 1
  case "${code}" in
    201|409) info "Gitea repository ${WORKSHOP_USER}/${name} created" ;;
    *) fail "Creating Gitea repository ${name} failed (HTTP ${code})"; return 1 ;;
  esac
}

# Delete and re-create the repository <user>/<name> (fast-forward scripts start from a clean repository).
gitea_recreate_repo() {
  local name="$1"
  gitea_api DELETE "/repos/${WORKSHOP_USER}/${name}" > /dev/null || return 1
  gitea_ensure_repo "${name}"
}

gitea_repo_url() { echo "${GITEA_URL}/${WORKSHOP_USER}/$1.git"; }

# git with a fallback credential helper that reads the workshop credentials from the environment
# (only used if the DevWorkspace git credential does not answer). No password ends up in a URL.
workshop_git() {
  # shellcheck disable=SC2016
  git -c credential.helper='!f() { test "$1" = get && test -n "$WORKSHOP_PASSWORD" && echo "username=$WORKSHOP_USER" && echo "password=$WORKSHOP_PASSWORD"; }; f' "$@"
}

# Commit the content of a directory as a new repository and push it to <user>/<repo> (branch main).
git_push_dir() {
  local dir="$1" repo="$2" message="${3:-Initial}" url
  url="$(gitea_repo_url "${repo}")"
  (
    cd "${dir}" || exit 1
    rm -rf .git
    git init -q -b main &&
      git add -A &&
      git commit -q -m "${message}" &&
      git remote add origin "${url}" &&
      workshop_git push -q --force -u origin main
  ) || { fail "Pushing ${dir} to ${url} failed"; return 1; }
  info "Pushed ${dir} to ${url}"
}

# ---------------------------------------------------------------------------------------------
# Argo CD CLI: token authentication (ARGOCD_AUTH_TOKEN from the workspace credentials, or from
# the pre-created Secret argocd-env-secret in the staging project), plain HTTP inside the cluster.
# ---------------------------------------------------------------------------------------------
argocd_env() {
  if [ -z "${ARGOCD_AUTH_TOKEN}" ]; then
    ARGOCD_AUTH_TOKEN="$(oc get secret argocd-env-secret -n "${STAGING_PROJECT}" \
      -o jsonpath='{.data.ARGOCD_AUTH_TOKEN}' 2> /dev/null | base64 -d 2> /dev/null || true)"
  fi
  [ -n "${ARGOCD_AUTH_TOKEN}" ] || { fail "No Argo CD token (ARGOCD_AUTH_TOKEN) found"; return 1; }
  export ARGOCD_AUTH_TOKEN
}

workshop_argocd() {
  argocd_env || return 1
  argocd --server "${ARGOCD_SERVER}" --plaintext "$@"
}

# ---------------------------------------------------------------------------------------------
# Remove the Coolstore resources from a workshop project, keeping the (pre-created) project, its
# service accounts, role bindings and the pre-created Secret argocd-env-secret.
# ---------------------------------------------------------------------------------------------
workshop_clean_project() {
  local ns="$1"
  info "Deleting the Coolstore resources in ${ns}"
  # Pipeline runs first: their pods keep the pipeline PVCs in use, so deleting the PVCs first would
  # wait forever. PVCs are deleted without waiting; they go once the run pods are gone.
  oc delete pipelineruns.tekton.dev,taskruns.tekton.dev,pipelines.tekton.dev,tasks.tekton.dev \
    --all -n "${ns}" --ignore-not-found > /dev/null 2>&1
  oc delete deployment,buildconfig,build,imagestream,route,service \
    --all -n "${ns}" --ignore-not-found > /dev/null 2>&1
  oc delete pvc --all -n "${ns}" --ignore-not-found --wait=false > /dev/null 2>&1
  oc delete gateways.networking.istio.io,virtualservices.networking.istio.io,destinationrules.networking.istio.io \
    --all -n "${ns}" --ignore-not-found > /dev/null 2>&1
  oc delete configmap inventory catalog argocd-env-configmap -n "${ns}" --ignore-not-found > /dev/null 2>&1
  oc delete secret inventory-mariadb catalog-postgresql -n "${ns}" --ignore-not-found > /dev/null 2>&1
  oc delete configmap,secret -n "${ns}" --ignore-not-found \
    -l 'app.kubernetes.io/instance in (inventory,catalog,gateway,web,inventory-mariadb,catalog-postgresql)' > /dev/null 2>&1
  oc delete serviceaccount inventory-quarkus -n "${ns}" --ignore-not-found > /dev/null 2>&1
  oc delete rolebinding inventory-coolstore-view -n "${ns}" --ignore-not-found > /dev/null 2>&1
  return 0
}
