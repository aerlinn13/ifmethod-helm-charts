#!/bin/bash

# Formatting
BOLD='\033[1m'
NC='\033[0m'
BLUE='\033[0;34m'
GREEN='\033[0;32m'
RED='\033[0;31m'

echo -e "${BOLD}IFMethod Docker Compose Generator with SSL for app + api${NC}"
echo -e "This script generates docker-compose.yml + nginx + certbot config\n"

# Input prompts
echo -e "${BLUE}Domain Setup${NC}"

while true; do
  read -p "App domain (e.g., app.ifmethod.ru): " APP_DOMAIN
  [ -n "$APP_DOMAIN" ] && break || echo -e "${RED}Required.${NC}"
done

while true; do
  read -p "API domain (e.g., api.ifmethod.ru): " API_DOMAIN
  [ -n "$API_DOMAIN" ] && break || echo -e "${RED}Required.${NC}"
done

while true; do
  read -p "Image tag: " TAG
  [ -n "$TAG" ] && break || echo -e "${RED}Required.${NC}"
done

read -p "Your email for Let's Encrypt: " EMAIL

# Create required folders
mkdir -p nginx/conf.d certbot/conf certbot/www

# Write temporary HTTP-only NGINX config
cat > nginx/conf.d/default.conf <<EOF
server {
    listen 80;
    server_name ${APP_DOMAIN} ${API_DOMAIN};

    location /.well-known/acme-challenge/ {
        root /var/www/certbot;
    }

    location / {
        return 301 https://\$host\$request_uri;
    }
}
EOF

# Write docker-compose.yml with temporary setup
cat > docker-compose.yml <<EOF
version: '3'

services:
  client:
    image: aerlinn13/ifmethod-client:${TAG}
    container_name: ifmethod-client
    environment:
      - APP_HOST=https://${APP_DOMAIN}
      - API_HOST=https://${API_DOMAIN}
      - IS_PROD=true
      - DEMO_ENABLED=false
    expose:
      - "8080"

  server:
    image: aerlinn13/ifmethod-server:${TAG}
    container_name: ifmethod-server
    environment:
      - APP_HOST=https://${APP_DOMAIN}
      - API_HOST=https://${API_DOMAIN}
      - PORT=5050
    expose:
      - "5050"
    depends_on:
      - mongodb
      - supertokens

  mongodb:
    image: mongo:8.0.6
    container_name: ifmethod-mongo
    environment:
      - MONGO_INITDB_ROOT_USERNAME=admin
      - MONGO_INITDB_ROOT_PASSWORD=j6M7N3eo1Heu1BTx
    volumes:
      - mongodb_data:/data/db
    ports:
      - "27017:27017"

  postgres:
    image: postgres:15
    container_name: ifmethod-postgres
    environment:
      - POSTGRES_USER=supertokens
      - POSTGRES_PASSWORD=supertokens
      - POSTGRES_DB=supertokens
    volumes:
      - postgres_data:/var/lib/postgresql/data
    ports:
      - "5432:5432"

  supertokens:
    image: registry.supertokens.io/supertokens/supertokens-postgresql:10.1.0
    container_name: ifmethod-supertokens
    environment:
      - API_KEYS=Hs7Kp9Lm2Qr5Vx8Zc3Jf
      - POSTGRESQL_CONNECTION_URI=postgresql://supertokens:supertokens@postgres:5432/supertokens
    ports:
      - "3567:3567"
    depends_on:
      - postgres

  nginx:
    image: nginx:latest
    container_name: ifmethod-nginx
    restart: unless-stopped
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - ./nginx/conf.d:/etc/nginx/conf.d
      - ./certbot/conf:/etc/letsencrypt
      - ./certbot/www:/var/www/certbot
    depends_on:
      - client
      - server

  certbot:
    image: certbot/certbot
    container_name: ifmethod-certbot
    volumes:
      - ./certbot/conf:/etc/letsencrypt
      - ./certbot/www:/var/www/certbot
    command: certonly --webroot \
      --webroot-path=/var/www/certbot \
      --email ${EMAIL} \
      --agree-tos \
      --no-eff-email \
      -d ${APP_DOMAIN} \
      -d ${API_DOMAIN}

volumes:
  mongodb_data:
  postgres_data:
EOF

# Start nginx to serve challenge
echo -e "\n${BLUE}Starting NGINX in HTTP-only mode...${NC}"
docker-compose up -d nginx
sleep 5

# Run certbot
echo -e "\n${BLUE}Requesting SSL certs via Certbot...${NC}"
docker-compose run --rm certbot

if [ $? -ne 0 ]; then
  echo -e "\n${RED}Certbot failed. Exiting script.${NC}"
  exit 1
fi

# Append HTTPS config
cat >> nginx/conf.d/default.conf <<EOF

server {
    listen 443 ssl;
    server_name ${APP_DOMAIN};

    ssl_certificate /etc/letsencrypt/live/${APP_DOMAIN}/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/${APP_DOMAIN}/privkey.pem;

    location / {
        proxy_pass http://client:8080;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}

server {
    listen 443 ssl;
    server_name ${API_DOMAIN};

    ssl_certificate /etc/letsencrypt/live/${API_DOMAIN}/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/${API_DOMAIN}/privkey.pem;

    location / {
        proxy_pass http://server:5050;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}
EOF

# Restart nginx with SSL
echo -e "\n${GREEN}✅ Certificates obtained successfully! Restarting all services with HTTPS...${NC}"
docker-compose up -d