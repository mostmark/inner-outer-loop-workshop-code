#!/bin/bash
################################
# catalog-spring-boot Solution #
################################

DIRECTORY="$(cd "$(dirname "$0")" && pwd)"

cp "${DIRECTORY}"/*.java "${DIRECTORY}/../../../labs/catalog-spring-boot/src/main/java/com/redhat/cloudnative/catalog"

echo "Catalog Spring-Boot Solved"
