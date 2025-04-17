#!/bin/bash

# Text formatting
BOLD='\033[1m'
NC='\033[0m'
BLUE='\033[0;34m'
GREEN='\033[0;32m'
RED='\033[0;31m'

echo -e "${BOLD}IFMethod Docker Compose Generator with HTTPS${NC}"
echo -e "This script will generate a docker-compose.yml file for IFMethod with NGINX + Certbot.\n"

# Prompt for environment configuration
echo -e "${BLUE}Environment Configuration${NC}"

while true; do
  read -p "App host (e.g., app.ifmethod.ru): " app_host
  if [ -z "$app_host" ]; then
    echo -e "${RED}App host is required. Please enter a value.${NC}"
  else
    break
  fi
done

while true; do
  read -p "API host (e.g., api.ifmethod.ru): " api_host
  if [ -z "$api_host" ]; then
    echo -e "${RED}API host is required. Please enter a value.${NC}"
  else
    break
  fi
done

while true; do
  read -p "Image tag: " image_tag
  if [ -z "$image_tag" ]; then
    echo -e "${RED}Image tag is required. Please enter a value.${NC}"
  else
    break
  fi
done

read -p "Email for Let's Encrypt notifications (e.g., you@example.com): " email

mkdir -p nginx/conf.d certbot/conf certbot/www

# Write docker-compose.yml
cat > docker-compose.yml << EOF
version: '3'

services:
  client:
    image: aerlinn13/ifmethod-client:${image_tag}
    container_name: ifmethod-client
    environment:
      - APP_HOST=https://${app_host}
      - API_HOST=https://${api_host}
      - IS_PROD=true
      - DEMO_ENABLED=false
    expose:
      - "8080"

  server:
    image: aerlinn13/ifmethod-server:${image_tag}
    container_name: ifmethod-server
    ports:
      - "5050:5050"
    environment:
      - APP_HOST=https://${app_host}
      - API_HOST=https://${api_host}
      - PORT=5050
    depends_on:
      - mongodb
      - supertokens

  supertokens:
    image: registry.supertokens.io/supertokens/supertokens-postgresql:10.1.0
    container_name: ifmethod-supertokens
    ports:
      - "3567:3567"
    environment:
      - API_KEYS=Hs7Kp9Lm2Qr5Vx8Zc3Jf
      - POSTGRESQL_CONNECTION_URI=postgresql://supertokens:supertokens@postgres:5432/supertokens
    depends_on:
      - postgres

  postgres:
    image: postgres:15
    container_name: ifmethod-postgres
    ports:
      - "5432:5432"
    environment:
      - POSTGRES_USER=supertokens
      - POSTGRES_PASSWORD=supertokens
      - POSTGRES_DB=supertokens
    volumes:
      - postgres_data:/var/lib/postgresql/data

  mongodb:
    image: mongo:8.0.6
    container_name: ifmethod-mongo
    ports:
      - "27017:27017"
    volumes:
      - mongodb_data:/data/db
    environment:
      - MONGO_INITDB_ROOT_USERNAME=admin
      - MONGO_INITDB_ROOT_PASSWORD=j6M7N3eo1Heu1BTx

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

  certbot:
    image: certbot/certbot
    container_name: ifmethod-certbot
    volumes:
      - ./certbot/conf:/etc/letsencrypt
      - ./certbot/www:/var/www/certbot
    entrypoint: >
      sh -c "sleep 10 && certbot certonly --webroot
      --webroot-path=/var/www/certbot
      --email ${email}
      --agree-tos
      --no-eff-email
      -d ${app_host}"

volumes:
  mongodb_data:
  postgres_data:
EOF

# Write NGINX config
cat > nginx/conf.d/${app_host}.conf << EOF
server {
    listen 80;
    server_name ${app_host};

    location /.well-known/acme-challenge/ {
        root /var/www/certbot;
    }

    location / {
        return 301 https://\$host\$request_uri;
    }
}

server {
    listen 443 ssl;
    server_name ${app_host};

    ssl_certificate /etc/letsencrypt/live/${app_host}/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/${app_host}/privkey.pem;

    location / {
        proxy_pass http://client:8080;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}
EOF

echo -e "\n${GREEN}Success!${NC} Docker Compose + NGINX + HTTPS config created."
echo -e "To request your cert: ${BOLD}docker-compose run --rm certbot${NC}"
echo -e "Then: ${BOLD}docker-compose up -d nginx client server supertokens postgres mongodb${NC}"