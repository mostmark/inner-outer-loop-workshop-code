#!/bin/bash
######################################
# Application Configuration Solution #
######################################
#
# Creates the MariaDB (Inventory) and PostgreSQL (Catalog) databases from the workshop templates
# coolstore-mariadb / coolstore-postgresql (namespace openshift; they create Deployments), and
# externalizes the datasource configuration of both services into ConfigMaps.
#
# Usage: deploy.sh [PROJECT]   (default: my-project-<user>)

DIRECTORY="$(cd "$(dirname "$0")" && pwd)"
. "${DIRECTORY}/../../workshop-env.sh"
PROJECT_NAME="${1:-${DEV_PROJECT}}"

oc project "${PROJECT_NAME}" > /dev/null || exit 1

oc policy add-role-to-user view -z default -n "${PROJECT_NAME}"

oc new-app --template=coolstore-postgresql -n "${PROJECT_NAME}" \
    --param=DATABASE_SERVICE_NAME=catalog-postgresql \
    --param=POSTGRESQL_DATABASE=catalogdb --param=POSTGRESQL_USER=catalog \
    --param=POSTGRESQL_PASSWORD=catalog \
    --labels=app=coolstore,app.kubernetes.io/instance=catalog-postgresql,app.kubernetes.io/name=postgresql,app.kubernetes.io/part-of=coolstore,app.openshift.io/runtime=postgresql \
    || exit 1

oc new-app --template=coolstore-mariadb -n "${PROJECT_NAME}" \
    --param=DATABASE_SERVICE_NAME=inventory-mariadb \
    --param=MYSQL_DATABASE=inventorydb --param=MYSQL_USER=inventory \
    --param=MYSQL_PASSWORD=inventory --param=MYSQL_ROOT_PASSWORD=inventoryadmin \
    --labels=app=coolstore,app.kubernetes.io/instance=inventory-mariadb,app.kubernetes.io/name=mariadb,app.kubernetes.io/part-of=coolstore,app.openshift.io/runtime=mariadb \
    || exit 1

cp "${DIRECTORY}/pom.xml" "${WORKSHOP_DIR}/labs/inventory-quarkus"
cp "${DIRECTORY}/application.properties" "${WORKSHOP_DIR}/labs/inventory-quarkus/src/main/resources"
cd "${WORKSHOP_DIR}/labs/inventory-quarkus" || exit 1
mvn clean package -Dquarkus.kubernetes.deploy=true -DskipTests -Dquarkus.container-image.group="$(oc project -q)" -Dquarkus.kubernetes-client.trust-certs=true || exit 1

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "${TMP_DIR}"' EXIT

cat <<EOT > "${TMP_DIR}/inventory-application.properties"
quarkus.datasource.jdbc.url=jdbc:mariadb://inventory-mariadb.${PROJECT_NAME}.svc:3306/inventorydb
quarkus.datasource.username=inventory
quarkus.datasource.password=inventory
EOT

oc create configmap inventory -n "${PROJECT_NAME}" \
    --from-file=application.properties="${TMP_DIR}/inventory-application.properties" \
    --dry-run=client -o yaml | oc apply -n "${PROJECT_NAME}" -f -
oc label configmap inventory app=coolstore app.kubernetes.io/instance=inventory --overwrite -n "${PROJECT_NAME}"

oc delete pod -l component=inventory -n "${PROJECT_NAME}"

cat <<EOT > "${TMP_DIR}/catalog-application.properties"
spring.datasource.url=jdbc:postgresql://catalog-postgresql.${PROJECT_NAME}.svc:5432/catalogdb
spring.datasource.username=catalog
spring.datasource.password=catalog
spring.datasource.driver-class-name=org.postgresql.Driver
spring.jpa.hibernate.ddl-auto=create
spring.jpa.properties.hibernate.jdbc.lob.non_contextual_creation=true
EOT

oc create configmap catalog -n "${PROJECT_NAME}" \
    --from-file=application.properties="${TMP_DIR}/catalog-application.properties" \
    --dry-run=client -o yaml | oc apply -n "${PROJECT_NAME}" -f -
oc label configmap catalog app=coolstore app.kubernetes.io/instance=catalog --overwrite -n "${PROJECT_NAME}"

oc delete pod -l component=catalog -n "${PROJECT_NAME}"

oc annotate --overwrite deployment/catalog-coolstore app.openshift.io/connects-to='catalog-postgresql' -n "${PROJECT_NAME}"
oc annotate --overwrite deployment/inventory-coolstore app.openshift.io/connects-to='inventory-mariadb' -n "${PROJECT_NAME}"

echo "Application Configuration Externalization Done"
