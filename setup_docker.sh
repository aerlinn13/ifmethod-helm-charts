#!/bin/bash
if [ "$EUID" -ne 0 ]; then
  echo "❌ Please run as root (e.g., sudo su first)"
  exit 1
fi
# Record start time
start_time=$(date +%s)

# Formatting
BOLD='\033[1m'
NC='\033[0m'
BLUE='\033[0;34m'
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[0;33m'

# Variables for spinner animation
spinner=('⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏')
spinner_i=0

# Function to show spinner and elapsed time
function show_progress() {
  local message=$1
  local pid=$!
  local delay=0.1
  local elapsed=0
  
  while ps -p $pid > /dev/null; do
    elapsed=$(( $(date +%s) - start_time ))
    minutes=$((elapsed / 60))
    seconds=$((elapsed % 60))
    
    printf "\r${YELLOW}${spinner[$spinner_i]} ${message} (${minutes}m ${seconds}s)${NC}  "
    spinner_i=$(( (spinner_i + 1) % ${#spinner[@]} ))
    sleep $delay
  done
  
  printf "\r%s\n" "$(printf ' %.0s' {1..80})"  # Clear the line
}

function print_step() {
  echo -e "\n${BLUE}🔧 $1${NC}"
}

function print_success() {
  echo -e "${GREEN}✅ $1${NC}"
}

function print_error() {
  echo -e "${RED}❌ $1${NC}"
}

echo -e "${BOLD}IFMethod Full Setup Script${NC}"
echo -e "Provision Docker, generate configs, get SSL certs, launch services.\n"

# Ensure Docker is installed
print_step "Checking Docker..."
if ! command -v docker &> /dev/null; then
  print_step "Docker not found. Installing..."
  curl -fsSL https://get.docker.com -o get-docker.sh
  sh get-docker.sh &
  show_progress "Installing Docker"
  if [ $? -ne 0 ]; then
    print_error "Docker installation failed"; exit 1;
  fi
  print_success "Docker installed."
else
  print_success "Docker is installed."
fi

# Ensure Docker Compose is installed
print_step "Checking Docker Compose..."
if ! command -v docker-compose &> /dev/null; then
  print_step "Installing Docker Compose..."
  curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose &
  show_progress "Downloading Docker Compose"
  chmod +x /usr/local/bin/docker-compose
  ln -s /usr/local/bin/docker-compose /usr/bin/docker-compose
  print_success "Docker Compose installed."
else
  print_success "Docker Compose is installed."
fi

# Input prompts
print_step "Domain Setup"
while true; do
  read -p "App domain (e.g., app.ifmethod.ru): " APP_DOMAIN
  [ -n "$APP_DOMAIN" ] && break || print_error "Required."
done

while true; do
  read -p "API domain (e.g., api.ifmethod.ru): " API_DOMAIN
  [ -n "$API_DOMAIN" ] && break || print_error "Required."
done

while true; do
  read -p "Image tag (e.g., 4.25.1): " TAG
  [ -n "$TAG" ] && break || print_error "Required."
done

while true; do
read -p "Your email for Let's Encrypt (required): " EMAIL
[ -n "$EMAIL" ] && break || print_error "Required."
done

# Create folder structure
mkdir -p nginx/conf.d certbot/conf certbot/www

# Extract subdomain parts for filenames
APP_SUBDOMAIN=$(echo ${APP_DOMAIN} | cut -d '.' -f 1)
API_SUBDOMAIN=$(echo ${API_DOMAIN} | cut -d '.' -f 1)

# Step: Write HTTP NGINX config for cert issuance
print_step "Writing HTTP NGINX configs for certificate issuance..."

# Create HTTP-only config for app domain
cat > nginx/conf.d/${APP_SUBDOMAIN}.conf <<EOF
server {
    listen 80;
    server_name ${APP_DOMAIN};

    location ^~ /.well-known/acme-challenge/ {
        root /var/www/certbot;
        default_type text/plain;
        try_files \$uri =404;
    }

    location / {
        return 200 'Temporary HTTP server for SSL issuance';
        add_header Content-Type text/plain;
    }
}
EOF

# Create HTTP-only config for api domain
cat > nginx/conf.d/${API_SUBDOMAIN}.conf <<EOF
server {
    listen 80;
    server_name ${API_DOMAIN};

    location ^~ /.well-known/acme-challenge/ {
        root /var/www/certbot;
        default_type text/plain;
        try_files \$uri =404;
    }

    location / {
        return 200 'Temporary HTTP server for SSL issuance';
        add_header Content-Type text/plain;
    }
}
EOF

# Step: Start NGINX for HTTP
print_step "Starting temporary NGINX for HTTP..."
docker-compose up -d nginx &
show_progress "Starting NGINX"
print_step "Waiting for NGINX to start..."
sleep 5

# Step: Run Certbot
print_step "Requesting SSL certificates..."
docker-compose run --rm certbot &
show_progress "Obtaining SSL certificates"

# Verify certificates were actually created
if [ ! -f "certbot/conf/live/${APP_DOMAIN}/fullchain.pem" ]; then
  print_error "Certbot failed. Certificates were not issued."
  print_error "Check the logs for errors:"
  docker-compose logs certbot
  exit 1
fi
print_success "Certificates obtained successfully."

# Step: Update configs with HTTPS
print_step "Adding HTTPS config to NGINX..."

# Update app domain config
cat > nginx/conf.d/${APP_SUBDOMAIN}.conf <<EOF
server {
    listen 80;
    server_name ${APP_DOMAIN};

    location /.well-known/acme-challenge/ {
        root /var/www/certbot;
    }

    location / {
        return 301 https://\$host\$request_uri;
    }
}

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
EOF

# Update api domain config
cat > nginx/conf.d/${API_SUBDOMAIN}.conf <<EOF
server {
    listen 80;
    server_name ${API_DOMAIN};

    location /.well-known/acme-challenge/ {
        root /var/www/certbot;
    }

    location / {
        return 301 https://\$host\$request_uri;
    }
}

server {
    listen 443 ssl;
    server_name ${API_DOMAIN};

    ssl_certificate /etc/letsencrypt/live/${APP_DOMAIN}/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/${APP_DOMAIN}/privkey.pem;

    location / {
        proxy_pass http://server:5050;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}
EOF

# Step: Generate Docker Compose
print_step "Generating docker-compose.yml..."
cat > docker-compose.yml <<EOF

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
      - MONGODB_URI=mongodb://admin:j6M7N3eo1Heu1BTx@mongodb:27017/swinlanes?authSource=admin
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
      ${EMAIL:+--email $EMAIL} \
      --agree-tos \
      --no-eff-email \
      -d ${APP_DOMAIN} \
      -d ${API_DOMAIN}

volumes:
  mongodb_data:
  postgres_data:
EOF

# Step: Restart all services with HTTPS
print_step "Restarting all services with HTTPS enabled..."
docker-compose down &
show_progress "Stopping services"
docker-compose up -d &
show_progress "Starting all services with HTTPS"

# Calculate total time
end_time=$(date +%s)
total_time=$((end_time - start_time))
minutes=$((total_time / 60))
seconds=$((total_time % 60))

print_success "IFMethod is up and running at:"
echo -e "🌐 https://${APP_DOMAIN}"
echo -e "\n${BOLD}Total setup time: ${minutes}m ${seconds}s${NC}"
