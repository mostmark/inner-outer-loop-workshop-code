#!/bin/bash
#
# Sends one request per second to the Gateway through the participant's Istio ingress gateway and
# shows which Catalog version (Spring Boot v1 or Go v2) answered.
#
# Usage: gateway_generate_traffic.sh [NAMESPACE]   (default: cn-project-<user>)

DIRECTORY="$(cd "$(dirname "$0")" && pwd)"
. "${DIRECTORY}/workshop-env.sh"

PROJECT_NAME="${1:-${STAGING_PROJECT}}"

GATEWAY_HOST="$(oc get route istio-ingressgateway -n "${PROJECT_NAME}" -o jsonpath='{.spec.host}' 2> /dev/null)"
if [ -z "${GATEWAY_HOST}" ]; then
  APPS_HOSTNAME_SUFFIX="$(oc whoami --show-console | sed 's%.*\(apps.*\)$%\1%g')"
  GATEWAY_HOST="istio-ingressgateway-${PROJECT_NAME}.${APPS_HOSTNAME_SUFFIX}"
fi

url="http://${GATEWAY_HOST}/api/products"
echo "Sending traffic to ${url} (Ctrl+C to stop)"

while true; do
    if curl -s "${url}" | grep -q OFFICIAL
    then
        echo -e "\e[96mGateway => Catalog GoLang (v2)\e[0m";
    else
        echo -e "\e[92mGateway => Catalog Spring Boot (v1)\e[0m";
    fi
    sleep 1
done
