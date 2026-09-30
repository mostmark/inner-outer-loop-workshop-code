#!/bin/bash
##############################
# inventory-quarkus Solution #
##############################

DIRECTORY="$(cd "$(dirname "$0")" && pwd)"

cp -R "${DIRECTORY}/src" "${DIRECTORY}/../../../labs/inventory-quarkus"

echo "Inventory Quarkus Solved"
