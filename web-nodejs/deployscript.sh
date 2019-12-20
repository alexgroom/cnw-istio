
oc login -u user1 -p openshift
oc project coolstore1

cd /projects/labs/inventory-thorntail
mvn clean fabric8:deploy 
cd /projects/labs/catalog-spring-boot
mvn clean fabric8:deploy 
cd /projects/labs/gateway-vertx
mvn clean fabric8:deploy 

cd /projects/labs

oc new-app nodejs:8~https://github.com/alexgroom/cnw-istio.git \
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
cd /projects/labs/inventory-thorntail
oc new-app . --name=inventory-pipeline --strategy=pipeline --context-dir='inventory-thorntail'

oc delete pod -l deploymentconfig=inventory

cd /projects/labs

oc rollout pause dc/catalog 
oc set probe dc/catalog --readiness --liveness --remove 
oc patch dc/catalog --patch '{"spec": {"template": {"metadata": {"annotations": {"sidecar.istio.io/inject": "true"}}}}}' 
oc patch dc/catalog --patch '{"spec": {"template": {"spec": {"containers": [{"name": "spring-boot", "command" : ["/bin/bash"], "args": ["-c", "until $(curl -o /dev/null -s -I -f http://localhost:15000); do echo \"Waiting for Istio Sidecar...\"; sleep 1; done; sleep 10; /usr/local/s2i/run"]}]}}}}' 
oc rollout resume dc/catalog

oc rollout pause dc/inventory
oc set probe dc/inventory --readiness --liveness --remove
oc patch dc/inventory --patch '{"spec": {"template": {"metadata": {"annotations": {"sidecar.istio.io/inject": "true"}}}}}'
oc patch dc/inventory --patch '{"spec": {"template": {"spec": {"containers": [{"name": "thorntail-v2", "command" : ["/bin/bash"], "args": ["-c", "until $(curl -o /dev/null -s -I -f http://localhost:15000); do echo \"Waiting for Istio Sidecar...\"; sleep 1; done; sleep 10; /usr/local/s2i/run"]}]}}}}'
oc rollout resume dc/inventory

oc rollout pause dc/gateway
oc set probe dc/gateway --readiness --liveness --remove
oc patch dc/gateway --patch '{"spec": {"template": {"metadata": {"annotations": {"sidecar.istio.io/inject": "true"}}}}}'
oc patch dc/gateway --patch '{"spec": {"template": {"spec": {"containers": [{"name": "vertx", "command" : ["/bin/bash"], "args": ["-c", "until $(curl -o /dev/null -s -I -f http://localhost:15000); do echo \"Waiting for Istio Sidecar...\"; sleep 1; done; sleep 10; /usr/local/s2i/run"]}]}}}}'
oc rollout resume dc/gateway

oc create -f /projects/labs/gateway-vertx/openshift/istio-gateway.yml
sed s/COOLSTORE_PROJECT/coolstore1/g /projects/labs/gateway-vertx/openshift/virtualservice.yml | oc create -f -

CATALOGHOST=$(oc get routes catalog -o jsonpath='{.spec.host}')
oc set env dc/web COOLSTORE_GW_ENDPOINT="${CATALOGHOST/catalog-coolstore1/http://istio-ingressgateway-istio-system}"/coolstore1
