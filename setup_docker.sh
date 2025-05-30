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

# Function to load saved config
function load_config() {
  if [ -f "config.json" ]; then
    APP_DOMAIN=$(jq -r '.app_domain // empty' config.json)
    API_DOMAIN=$(jq -r '.api_domain // empty' config.json)
    TAG=$(jq -r '.tag // empty' config.json)
    EMAIL=$(jq -r '.email // empty' config.json)
  fi
}

# Function to save config
function save_config() {
  jq -n \
    --arg app_domain "$APP_DOMAIN" \
    --arg api_domain "$API_DOMAIN" \
    --arg tag "$TAG" \
    --arg email "$EMAIL" \
    '{
      app_domain: $app_domain,
      api_domain: $api_domain,
      tag: $tag,
      email: $email
    }' > config.json
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

# Check for required tools
print_step "Checking for required tools..."
if ! command -v jq &> /dev/null; then
  print_step "Installing jq..."
  apt-get update && apt-get install -y jq
  if [ $? -ne 0 ]; then
    print_error "Failed to install jq"; exit 1;
  fi
  print_success "jq installed."
fi

# Load existing config if available
load_config

# Input prompts with defaults
print_step "Domain Setup"
while true; do
  read -p "App domain (e.g., app.ifmethod.com)${APP_DOMAIN:+ [${APP_DOMAIN}]}: " input
  APP_DOMAIN=${input:-$APP_DOMAIN}
  [ -n "$APP_DOMAIN" ] && break || print_error "Required."
done

while true; do
  read -p "API domain (e.g., api.ifmethod.com)${API_DOMAIN:+ [${API_DOMAIN}]}: " input
  API_DOMAIN=${input:-$API_DOMAIN}
  [ -n "$API_DOMAIN" ] && break || print_error "Required."
done

while true; do
  read -p "Image tag (e.g., 5.25.3)${TAG:+ [${TAG}]}: " input
  TAG=${input:-$TAG}
  [ -n "$TAG" ] && break || print_error "Required."
done

while true; do
  read -p "Your email for Let's Encrypt (required)${EMAIL:+ [${EMAIL}]}: " input
  EMAIL=${input:-$EMAIL}
  [ -n "$EMAIL" ] && break || print_error "Required."
done

# Save the new config
save_config

# Create folder structure
mkdir -p nginx/conf.d certbot/conf certbot/www

# Extract subdomain parts for filenames
APP_SUBDOMAIN=$(echo ${APP_DOMAIN} | cut -d '.' -f 1)
API_SUBDOMAIN=$(echo ${API_DOMAIN} | cut -d '.' -f 1)

# Step: Write HTTP NGINX config for cert issuance
print_step "Writing HTTP NGINX configs for certificate issuance..."

cat > nginx/conf.d/default.conf <<EOF
server {
    listen 80;
    server_name ${APP_DOMAIN} ${API_DOMAIN};

    location ^~ /.well-known/acme-challenge/ {
        root /var/www/certbot;
        default_type text/plain;
        try_files \$uri =404;
    }
}
EOF

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
      - DEMO_ENABLED=true
    expose:
      - "8080"
    ports:
      - "8080:8080" 
    networks:
      - internal-network

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
    ports:
      - "5050:5050" 
    depends_on:
      - mongodb
      - supertokens
    networks:
      - internal-network

  mongodb:
    image: mongo:8.0.6
    container_name: ifmethod-mongo
    environment:
      - MONGO_INITDB_ROOT_USERNAME=admin
      - MONGO_INITDB_ROOT_PASSWORD=j6M7N3eo1Heu1BTx
    volumes:
      - mongodb_data:/data/db
    command: mongod --bind_ip 0.0.0.0 --port 27017
    networks:
      - internal-network

  postgres:
    image: postgres:15
    container_name: ifmethod-postgres
    environment:
      - POSTGRES_USER=supertokens
      - POSTGRES_PASSWORD=supertokens
      - POSTGRES_DB=supertokens
    volumes:
      - postgres_data:/var/lib/postgresql/data
    command: postgres -c listen_addresses=0.0.0.0
    networks:
      - internal-network

  supertokens:
    image: registry.supertokens.io/supertokens/supertokens-postgresql:10.1.0
    container_name: ifmethod-supertokens
    environment:
      - API_KEYS=Hs7Kp9Lm2Qr5Vx8Zc3Jf
      - POSTGRESQL_CONNECTION_URI=postgresql://supertokens:supertokens@postgres:5432/supertokens
    expose:
      - "3567"
    depends_on:
      - postgres
    networks:
      - internal-network

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
    networks:
      - internal-network

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
    networks:
      - internal-network

networks:
  internal-network:
    driver: bridge

volumes:
  mongodb_data:
  postgres_data:
EOF

# Clean up any orphaned containers before starting
print_step "Cleaning up any existing containers..."
docker-compose down --remove-orphans &> /dev/null || true
docker rm -f $(docker ps -a --filter "name=certbot-run" --format "{{.ID}}") &> /dev/null || true

# Step: Start NGINX for HTTP
print_step "Starting temporary NGINX for HTTP..."
docker-compose up -d nginx &
show_progress "Starting NGINX"
print_step "Waiting for NGINX to start..."
sleep 20

# Step: Run Certbot
print_step "Running Certbot to obtain SSL certificates..."

# Check if certificates already exist
if [ -d "certbot/conf/live/${APP_DOMAIN}" ]; then
  print_step "Existing certificates found. Running in interactive mode..."
  # Run in foreground for interactive prompt
  docker-compose run --rm certbot
  CERTBOT_EXIT=$?
else
  # First-time issuance, can run in background
  docker-compose run --rm certbot > certbot.log 2>&1 &
  show_progress "Obtaining SSL certificates"
  wait $!
  CERTBOT_EXIT=$?
  
  echo -e "\n📄 Certbot log:"
  cat certbot.log
fi

if [ $CERTBOT_EXIT -ne 0 ]; then
  echo -e "\n❌ Certbot failed. Check above logs or see certbot.log"
  exit 1
else
  echo -e "\n✅ Certbot succeeded."
fi

# Clean up certbot container to avoid orphans
CERTBOT_CONTAINER=$(docker ps -a --filter "name=_certbot_" --format "{{.ID}}" | head -n 1)
if [ -n "$CERTBOT_CONTAINER" ]; then
  docker rm "$CERTBOT_CONTAINER" > /dev/null 2>&1
  echo "🧹 Cleaned up certbot container: $CERTBOT_CONTAINER"
fi

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


# Step: Restart all services with HTTPS
print_step "Restarting all services with HTTPS enabled..."
docker-compose down --remove-orphans &
show_progress "Stopping services"
docker-compose up -d --remove-orphans &
show_progress "Starting all services with HTTPS"

# Calculate total time
end_time=$(date +%s)
total_time=$((end_time - start_time))
minutes=$((total_time / 60))
seconds=$((total_time % 60))

# Add SSL renewal script and cron job
print_step "Setting up automatic SSL renewal..."

# Create renewal script
cat > renew-ssl.sh <<EOF
#!/bin/bash
set -e

# Path to the docker-compose directory
cd "$(pwd)"

# Run certbot renewal
docker-compose run --rm certbot renew --quiet

# Reload nginx to use the new certificates
docker-compose exec nginx nginx -s reload

# Log successful renewal
echo "Certificates renewed at \$(date)" >> renewal.log
EOF

# Make the script executable
chmod +x renew-ssl.sh

# Add to crontab if not already present
CRON_JOB="0 0,12 * * * $(pwd)/renew-ssl.sh >> /var/log/cron-ssl-renewal.log 2>&1"
if ! (crontab -l 2>/dev/null | grep -q "renew-ssl.sh"); then
  (crontab -l 2>/dev/null; echo "$CRON_JOB") | crontab -
  print_success "Added certificate renewal to crontab (runs twice daily)."
else
  print_success "Certificate renewal cron job already exists."
fi

print_success "IFMethod is up and running at:"
echo -e "🌐 https://${APP_DOMAIN}"
echo -e "\n${BOLD}Total setup time: ${minutes}m ${seconds}s${NC}"