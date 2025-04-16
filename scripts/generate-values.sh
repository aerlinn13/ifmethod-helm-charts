#!/bin/bash

echo "🛠️ Generating Helm values.yaml for Ifmethod..."

read -p "Domain (required, e.g. example.com):" DOMAIN
DOMAIN=${DOMAIN}

read -p "Email for cert-manager (required): " EMAIL
EMAIL=${EMAIL}

read -p "Client Image Tag [4.25.1]: " CLIENT_TAG
CLIENT_TAG=${CLIENT_TAG:-4.25.1}

read -p "Server Image Tag [4.25.1]: " SERVER_TAG
SERVER_TAG=${SERVER_TAG:-4.25.1}

# Start writing the YAML
cat > values.yaml <<EOF
domain: $DOMAIN

certManager:
  email: "$EMAIL"

ingress-nginx:
  controller:
    enabled: true
    ingressClassResource:
      name: nginx
      enabled: true
      default: true
    service:
      type: LoadBalancer

client:
  replicaCount: 1
  image:
    repository: aerlinn13/ifmethod-client
    tag: "$CLIENT_TAG"
    pullPolicy: Always
  containerPort: 8080
  env:
    APP_HOST: "https://app.$DOMAIN"
    API_HOST: "https://api.$DOMAIN"
    IS_PROD: "true"
    DEMO_ENABLED: "true"
  service:
    type: ClusterIP
    port: 8080
    targetPort: 8080
    name: client
  ingress:
    enabled: true
    host: app.$DOMAIN
    annotations:
      kubernetes.io/ingress.class: nginx
      cert-manager.io/cluster-issuer: letsencrypt-production
    tls:
      enabled: true
      secretName: app-ifmethod-tls

server:
  replicaCount: 1
  image:
    repository: aerlinn13/ifmethod-server
    tag: "$SERVER_TAG"
    pullPolicy: Always
  containerPort: 5050
  env:
    PORT: "5050"
    APP_HOST: "https://app.$DOMAIN"
    API_HOST: "https://api.$DOMAIN"
    MONGODB_URI: "mongodb://admin:j6M7N3eo1Heu1BTx@mongodb:27017/ifmethod?authSource=admin"
  service:
    type: ClusterIP
    port: 5050
    targetPort: 5050
    name: server
  ingress:
    enabled: true
    host: api.$DOMAIN
    annotations:
      kubernetes.io/ingress.class: nginx
      cert-manager.io/cluster-issuer: letsencrypt-production
    tls:
      enabled: true
      secretName: api-ifmethod-tls

mongodb:
  image:
    repository: mongo
    tag: "8.0.6"
    pullPolicy: IfNotPresent
  auth:
    username: "admin"
    password: "j6M7N3eo1Heu1BTx"
    database: "ifmethod"
  persistence:
    storageClassName: "local-path"
    size: 1Gi
  service:
    type: ClusterIP
    port: 27017
    targetPort: 27017
    name: mongodb
  replicaCount: 1
  net:
    bindIp: 0.0.0.0
  initContainer:
    enabled: true
    command:
      - mongosh
      - --eval
      - |
        db = db.getSiblingDB('admin');
        if (!db.getUser("admin")) {
          db.createUser({
            user: "admin",
            pwd: "j6M7N3eo1Heu1BTx",
            roles: [
              { role: "userAdminAnyDatabase", db: "admin" },
              { role: "readWriteAnyDatabase", db: "admin" },
              { role: "dbAdminAnyDatabase", db: "admin" }
            ]
          });
        }

postgres:
  name: postgres
  replicas: 1
  image:
    repository: postgres
    tag: "15"
  containerPort: 5432
  service:
    type: ClusterIP
    port: 5432
    targetPort: 5432
    name: postgres
  persistence:
    storageClassName: "local-path"
    size: 512Mi
  env:
    POSTGRES_USER: "supertokens"
    POSTGRES_PASSWORD: "supertokens"
    POSTGRES_DB: "supertokens"

supertokens:
  name: supertokens
  replicas: 1
  image:
    repository: registry.supertokens.io/supertokens/supertokens-postgresql
    tag: "10.1.0"
  containerPort: 3567
  service:
    type: ClusterIP
    port: 3567
    targetPort: 3567
    name: supertokens
  env:
    API_KEYS: "Hs7Kp9Lm2Qr5Vx8Zc3Jf"
    POSTGRESQL_CONNECTION_URI: "postgresql://supertokens:supertokens@postgres:5432/supertokens"
    SUPERTOKENS_PORT: "3567"
EOF

echo "✅ values.yaml generated!"

echo
echo "➡️  You can now install the chart using:"
echo "    helm install ifmethod ifmethod/ifmethod -f values.yaml"