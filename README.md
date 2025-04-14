# IFMethod Helm Chart

A Helm chart for deploying the complete IFMethod application stack, including client, server, MongoDB, PostgreSQL, and SuperTokens authentication.

## Quick start

```bash
# Add the Helm repository
helm repo add ifmethod https://aerlinn13.github.io/ifmethod-helm-charts
helm repo update

# Install the chart with default values
helm install my-release ifmethod/ifmethod

# Or install with custom values file
helm install my-release ifmethod/ifmethod -f my-values.yaml
```

## Architecture

This Helm chart deploys:

- Client application (Next.js frontend)
- Server application (API backend)
- MongoDB database for API
- SuperTokens authentication service
- PostgreSQL database for SuperTokens instance

All components are configured to work together out of the box.

## Configuration

Create a my-values.yaml file to customize the installation:

```yaml
# my-values.yaml
# Basic configuration
environment: production # or staging, development
domain: example.com # your main domain

# Certificate Manager
certManager:
  email: "your-email@example.com" # Required for Let's Encrypt

# Client configuration
client:
  replicaCount: 2
  image:
    repository: aerlinn13/ifmethod-client
    tag: "4.25.1" # Specify your desired version
    pullPolicy: Always
  env:
    APP_HOST: "https://app.example.com" # Change to your domain
    API_HOST: "https://api.example.com" # Change to your domain
    IS_PROD: "true"
  ingress:
    enabled: true
    host: app.example.com # Change to your domain

# Server configuration
server:
  replicaCount: 2
  image:
    repository: aerlinn13/ifmethod-server
    tag: "4.25.1" # Specify your desired version
  env:
    APP_HOST: "https://app.example.com" # Change to your domain
    API_HOST: "https://api.example.com" # Change to your domain
    # Do not change this value
    MONGODB_URI: "mongodb://admin:j6M7N3eo1Heu1BTx@mongodb:27017/ifmethod?authSource=admin"
  ingress:
    enabled: true
    host: api.example.com # Change to your domain

# MongoDB configuration
mongodb:
  auth:
    username: "admin"
    password: "j6M7N3eo1Heu1BTx" # Change this!
    database: "ifmethod"
  persistence:
    size: 10Gi # Adjust based on your needs

# PostgreSQL configuration
postgres:
  env:
    POSTGRES_USER: "supertokens"
    POSTGRES_PASSWORD: "supertokens"
    POSTGRES_DB: "supertokens"
  persistence:
    size: 512Mi # Adjust based on your needs

# SuperTokens configuration
supertokens:
  env:
    API_KEYS: "Hs7Kp9Lm2Qr5Vx8Zc3Jf" # Change this!
    POSTGRESQL_CONNECTION_URI: "postgresql://supertokens:supertokens@postgres:5432/supertokens"
```

## Upgrading

To upgrade your release:

```bash
helm upgrade ifmethod ifmethod/ifmethod -f my-values.yaml
```

## Uninstalling

To uninstall your release:

```bash
helm uninstall ifmethod
```

## Support

For issues and feature requests, please open an issue on our [GitHub repository](https://github.com/aerlinn13/ifmethod-helm-charts/issues).
