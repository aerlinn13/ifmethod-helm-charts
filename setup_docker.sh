#!/bin/bash

# Text formatting
BOLD='\033[1m'
NC='\033[0m' # No Color
BLUE='\033[0;34m'
GREEN='\033[0;32m'
RED='\033[0;31m'

echo -e "${BOLD}IFMethod Docker Compose Generator${NC}"
echo -e "This script will generate a docker-compose.yml file for IFMethod.\n"

# Prompt for the required values with no defaults
echo -e "${BLUE}Environment Configuration${NC}"

# App Host
while true; do
  read -p "App host (e.g., https://app.example.com): " app_host
  if [ -z "$app_host" ]; then
    echo -e "${RED}App host is required. Please enter a value.${NC}"
  else
    break
  fi
done

# API Host
while true; do
  read -p "API host (e.g., https://api.example.com): " api_host
  if [ -z "$api_host" ]; then
    echo -e "${RED}API host is required. Please enter a value.${NC}"
  else
    break
  fi
done

# Image tag
while true; do
  read -p "Image tag: " image_tag
  if [ -z "$image_tag" ]; then
    echo -e "${RED}Image tag is required. Please enter a value.${NC}"
  else
    break
  fi
done

# Create the docker-compose.yml file
cat > docker-compose.yml << EOF
services:
  client:
    image: aerlinn13/ifmethod-client:${image_tag}
    environment:
      - APP_HOST=${app_host}
      - API_HOST=${api_host}
      - IS_PROD=true
      - DEMO_ENABLED=false
    ports:
      - "8080:8080"

  server:
    image: aerlinn13/ifmethod-server:${image_tag}
    ports:
      - "5050:5050"
    environment:
      - APP_HOST=${app_host}
      - API_HOST=${api_host}
      - PORT=5050
    depends_on:
      - mongodb
      - supertokens

  supertokens:
    image: registry.supertokens.io/supertokens/supertokens-postgresql:10.1.0
    ports:
      - "3567:3567"
    environment:
      - API_KEYS=Hs7Kp9Lm2Qr5Vx8Zc3Jf
      - POSTGRESQL_CONNECTION_URI=postgresql://supertokens:supertokens@postgres:5432/supertokens
    depends_on:
      - postgres

  postgres:
    image: postgres:15
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
    ports:
      - "27017:27017"
    volumes:
      - mongodb_data:/data/db
    environment:
      - MONGO_INITDB_ROOT_USERNAME=admin
      - MONGO_INITDB_ROOT_PASSWORD=j6M7N3eo1Heu1BTx

volumes:
  mongodb_data:
  postgres_data:
EOF

echo -e "\n${GREEN}Success!${NC} Docker compose file created: docker-compose.yml"
echo -e "To start the services, run: ${BOLD}docker-compose up -d${NC}"