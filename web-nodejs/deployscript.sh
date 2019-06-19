oc new-app nodejs:8~https://github.com/mcouliba/cloud-native-labs.git#ocp-3.11 \
        --context-dir=web-nodejs \
        --name=web \
        --labels=app=web,version=1.0
oc expose svc/web

oc new-app postgresql-persistent \
    --param=DATABASE_SERVICE_NAME=inventory-postgresql \
    --param=POSTGRESQL_DATABASE=inventory \
    --param=POSTGRESQL_USER=inventory \
    --param=POSTGRESQL_PASSWORD=inventory \
    --labels=app=inventory
    
oc new-app postgresql-persistent \
    --param=DATABASE_SERVICE_NAME=catalog-postgresql \
    --param=POSTGRESQL_DATABASE=catalog \
    --param=POSTGRESQL_USER=catalog \
    --param=POSTGRESQL_PASSWORD=catalog \
    --labels=app=catalog
    
cat <<EOF > /projects/labs/project-defaults.yml
swarm:
  datasources:
    data-sources:
      InventoryDS:
        driver-name: postgresql
        connection-url: jdbc:postgresql://inventory-postgresql:5432/inventory
        user-name: inventory
        password: inventory
EOF
        
oc create configmap inventory --from-file=/projects/labs/project-defaults.yml 
oc rollout pause dc/inventory 
oc set volume dc/inventory --add --configmap-name=inventory --mount-path=/app/config 
oc set env dc/inventory JAVA_ARGS="-s /app/config/project-defaults.yml" 
oc rollout resume dc/inventory         

cat <<EOF > /projects/labs/application.properties
spring.datasource.url=jdbc:postgresql://catalog-postgresql:5432/catalog
spring.datasource.username=catalog
spring.datasource.password=catalog
spring.datasource.driver-class-name=org.postgresql.Driver
spring.jpa.hibernate.ddl-auto=create
EOF
oc create configmap catalog --from-file=/projects/labs/application.properties

oc delete pod -l deploymentconfig=catalog

oc set triggers dc/inventory --manual
oc set env dc/inventory AB_PROMETHEUS_OFF=true
oc new-app jenkins-ephemeral --param=MEMORY_LIMIT="2Gi"
cd labs/inventory-thorntail
oc new-app . --name=inventory-pipeline --strategy=pipeline
