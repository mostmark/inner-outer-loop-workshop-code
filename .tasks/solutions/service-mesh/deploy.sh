#!/bin/bash
#########################
# Service Mesh Solution #
#########################
#
# Adds catalog, inventory and gateway to the mesh (sidecar injection label), deploys a per-user
# ingress gateway (gateway injection) with Gateway/VirtualService, points the web front end to it,
# deploys the Go Catalog Service v2 and routes all catalog traffic to v2.
#
# Usage: deploy.sh [USER]   (default: the workspace user)

DIRECTORY="$(cd "$(dirname "$0")" && pwd)"
. "${DIRECTORY}/../../workshop-env.sh"
workshop_set_user "$1"
NS="${STAGING_PROJECT}"
GATEWAY_LABEL="ingressgateway-${WORKSHOP_USER}"

oc project "${NS}" > /dev/null || exit 1

INJECT_PATCH='{"spec": {"template": {"metadata": {"labels": {"sidecar.istio.io/inject": "true"}}}}}'
for deployment in catalog-coolstore inventory-coolstore gateway-coolstore; do
  oc patch "deployment/${deployment}" --patch "${INJECT_PATCH}" -n "${NS}" || exit 1
done

## Create the local gateway
oc apply -n "${NS}" -f - << YAML || exit 1
apiVersion: v1
kind: Service
metadata:
  name: istio-ingressgateway
spec:
  type: ClusterIP
  selector:
    istio: ${GATEWAY_LABEL}
  ports:
  - name: http2
    port: 80
    targetPort: 8080
  - name: https
    port: 443
    targetPort: 8443
YAML

oc get route istio-ingressgateway -n "${NS}" > /dev/null 2>&1 ||
  oc expose service istio-ingressgateway --port=http2 -n "${NS}" || exit 1

oc apply -n "${NS}" -f - << YAML || exit 1
apiVersion: apps/v1
kind: Deployment
metadata:
  name: istio-ingressgateway
spec:
  selector:
    matchLabels:
      istio: ${GATEWAY_LABEL}
  template:
    metadata:
      annotations:
        # Select the gateway injection template (rather than the default sidecar template)
        inject.istio.io/templates: gateway
      labels:
        # Set a unique label for the gateway. This is required to ensure Gateways can select this workload
        istio: ${GATEWAY_LABEL}
        # Enable gateway injection. If connecting to a revisioned control plane, replace with "istio.io/rev: revision-name"
        sidecar.istio.io/inject: "true"
    spec:
      containers:
      - name: istio-proxy
        image: auto # The image will automatically update each time the pod starts.
YAML

oc apply -n "${NS}" -f - << YAML || exit 1
apiVersion: networking.istio.io/v1
kind: Gateway
metadata:
  name: ingressgateway
spec:
  selector:
    istio: ${GATEWAY_LABEL}
  servers:
    - port:
        number: 8080
        name: http
        protocol: HTTP
      hosts:
        - "*"
---
apiVersion: networking.istio.io/v1
kind: VirtualService
metadata:
  name: gateway-coolstore
spec:
  hosts:
    - "*"
  gateways:
    - ingressgateway
  http:
    - route:
        - destination:
            port:
              number: 8080
            host: gateway-coolstore
YAML

GATEWAY_HOST="$(oc get route istio-ingressgateway -n "${NS}" -o jsonpath='{.spec.host}')"
oc set env deployment/web-coolstore COOLSTORE_GW_ENDPOINT="http://${GATEWAY_HOST}" -n "${NS}" || exit 1

if ! oc get deployment catalog-coolstore-v2 -n "${NS}" > /dev/null 2>&1; then
  oc new-app "${CODE_REPO_URL}#${CODE_REPO_REVISION}" -n "${NS}" \
      --strategy=docker \
      --context-dir=labs/catalog-go \
      --name=catalog-coolstore-v2 \
      --labels=app.kubernetes.io/part-of=coolstore,app.kubernetes.io/name=golang || exit 1
fi

oc apply -n "${NS}" -f - << YAML || exit 1
apiVersion: networking.istio.io/v1
kind: VirtualService
metadata:
  name: catalog-coolstore
spec:
  hosts:
    - catalog-coolstore
  http:
  - route:
    - destination:
        host: catalog-coolstore
      weight: 0
    - destination:
        host: catalog-coolstore-v2
      weight: 100
YAML

echo "Service Mesh Done"
