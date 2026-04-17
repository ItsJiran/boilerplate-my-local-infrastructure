# Step CA - Certificate Authority Setup (Development Only)

## ⚠️ Important Notice

**This Step CA setup is ONLY for DEVELOPMENT environment.**

For **PRODUCTION**, we use **Let's Encrypt** for automatic SSL certificate management.

## Overview

Step CA is an open-source certificate authority server that provides automated certificate management for local development.

## Features

- 🔐 Automated certificate issuance and renewal
- 🌐 ACME protocol support (similar to Let's Encrypt)
- 🔑 Custom PKI (Public Key Infrastructure)
- 📜 Certificate lifecycle management
- �️ Perfect for local development and testing

## Environment Usage

| Environment | Certificate Provider | Purpose |
|:------------|:---------------------|:--------|
| **Development** | Step CA (This) | Local SSL certificates for development |
| **Production** | Let's Encrypt | Trusted SSL certificates for public domains |

## Quick Start

### 1. Configure Environment

Add to your `.env` file (or copy from `.env.example`):

```bash
# Step CA Configuration
STEP_CA_PORT=9000
STEP_CA_NAME="App Boilerplate CA"
STEP_CA_DNS="step-ca,localhost"
STEP_CA_PROVISIONER="admin"
STEP_CA_PASSWORD="changeme"           # ⚠️ CHANGE THIS IN PRODUCTION!
STEP_CA_ADMIN="admin@jiran.test"
STEP_CA_ADDRESS=":9000"
```

### 2. Start Step CA Server

#### Using the interactive menu:
```bash
./run.sh
# Then select: run.step-ca.sh
```

#### Or directly:
```bash
./scripts/run/run.step-ca.sh
```

#### Or using docker-compose:
```bash
cd infra
docker-compose -f docker-compose.step-ca.yml up -d
```

### 3. Initialize Step CLI (First Time Only)

Get the CA fingerprint:
```bash
docker exec step-ca step certificate fingerprint /home/step/certs/root_ca.crt
```

Bootstrap your Step CLI:
```bash
step ca bootstrap \
  --ca-url https://localhost:9000 \
  --fingerprint <fingerprint-from-above>
```

## Usage

### Check CA Health
```bash
curl -k https://localhost:9000/health
```

### View CA Certificates
```bash
docker exec step-ca step certificate inspect /home/step/certs/root_ca.crt
```

### Request a New Certificate
```bash
step ca certificate jiran.local jiran.crt jiran.key
```

### Renew a Certificate
```bash
step ca renew jiran.crt jiran.key
```

### List Active Certificates
```bash
docker exec step-ca step ca provisioner list
```

## Management Commands

### View Logs
```bash
docker logs -f step-ca
```

### Stop Server
```bash
cd infra
docker-compose -f docker-compose.step-ca.yml down
```

### Restart Server
```bash
cd infra
docker-compose -f docker-compose.step-ca.yml restart
```

### Remove All Data (⚠️ Warning: Destructive!)
```bash
cd infra
docker-compose -f docker-compose.step-ca.yml down -v
```

## Integration with Applications

### Laravel Application

Add to `config/app.php`:
```php
'ca_cert_path' => env('STEP_CA_CERT_PATH', '/path/to/root_ca.crt'),
```

Configure SSL verification in HTTP client:
```php
$client = new \GuzzleHttp\Client([
    'verify' => env('STEP_CA_CERT_PATH'),
]);
```

### Frontend Application

Add CA certificate to Node.js:
```bash
export NODE_EXTRA_CA_CERTS=/path/to/root_ca.crt
```

Or in `.env`:
```
NODE_EXTRA_CA_CERTS=/path/to/root_ca.crt
```

## Production SSL - Let's Encrypt

**⚠️ DO NOT use Step CA in production!**

For production deployment, this application uses **Let's Encrypt** for SSL certificates:

### Why Let's Encrypt for Production?

- ✅ **Trusted by all browsers** - No certificate warnings
- ✅ **Free and automatic** - No manual certificate management
- ✅ **Auto-renewal** - Certificates renew automatically before expiration
- ✅ **Wildcard support** - Single cert for *.jiran.test
- ✅ **Industry standard** - Used by millions of websites

### Production Setup (Let's Encrypt)

1. **Using Certbot with Nginx**:
   ```bash
   # Install certbot
   sudo apt install certbot python3-certbot-nginx
   
   # Get certificate
   sudo certbot --nginx -d jiran.test -d www.jiran.test
   
   # Auto-renewal (cron job is set automatically)
   sudo certbot renew --dry-run
   ```

2. **Using Docker + Certbot**:
   ```yaml
   # Add to production docker-compose.yml
   certbot:
     image: certbot/certbot
     volumes:
       - ./certbot/conf:/etc/letsencrypt
       - ./certbot/www:/var/www/certbot
     entrypoint: "/bin/sh -c 'trap exit TERM; while :; do certbot renew; sleep 12h & wait $${!}; done;'"
   ```

3. **Using Traefik (Recommended)**:
   ```yaml
   traefik:
     image: traefik:v2.10
     command:
       - "--certificatesresolvers.letsencrypt.acme.email=admin@jiran.test"
       - "--certificatesresolvers.letsencrypt.acme.storage=/letsencrypt/acme.json"
       - "--certificatesresolvers.letsencrypt.acme.httpchallenge.entrypoint=web"
   ```

### Environment-Specific SSL Configuration

```bash
# .env.development
USE_STEP_CA=true
SSL_PROVIDER=step-ca
CA_URL=https://localhost:9000

# .env.production
USE_STEP_CA=false
SSL_PROVIDER=letsencrypt
CERTBOT_EMAIL=admin@jiran.test
DOMAIN=jiran.test
```

## Security Notes

### Development (Step CA)

1. **Default Password**: Using `changeme` is OK for local development
2. **Self-Signed Certs**: Browser warnings are expected and normal
3. **Local Only**: Don't expose Step CA to the internet
4. **Easy Reset**: Can delete volume and start fresh anytime

### Backup CA Data

```bash
# Backup
docker run --rm -v step-ca-data:/data -v $(pwd):/backup \
  alpine tar czf /backup/step-ca-backup.tar.gz -C /data .

# Restore
docker run --rm -v step-ca-data:/data -v $(pwd):/backup \
  alpine tar xzf /backup/step-ca-backup.tar.gz -C /data
```

## Troubleshooting

### CA Server Won't Start

1. Check if port 9000 is available:
   ```bash
   netstat -tulpn | grep 9000
   ```

2. View logs:
   ```bash
   docker logs step-ca
   ```

3. Verify network exists:
   ```bash
   docker network inspect ${APP_NETWORK:-app_boilerplate_network}
   ```

### Certificate Verification Failed

1. Ensure CA certificate is in system trust store
2. Check certificate expiration:
   ```bash
   step certificate inspect jiran.crt
   ```

### Unable to Connect

1. Verify container is running:
   ```bash
   docker ps | grep step-ca
   ```

2. Check health:
   ```bash
   curl -k https://localhost:9000/health
   ```

## Resources

- [Step CA Documentation](https://smallstep.com/docs/step-ca)
- [Step CLI Documentation](https://smallstep.com/docs/step-cli)
- [ACME Protocol](https://smallstep.com/docs/step-ca/acme-basics)
- [Certificate Management Best Practices](https://smallstep.com/docs/step-ca/certificate-authority-server-production)

## Support

For issues or questions:
1. Check logs: `docker logs step-ca`
2. Review [Step CA Troubleshooting Guide](https://smallstep.com/docs/step-ca/troubleshooting)
3. Contact: Akterma Technology [AT] - ItsJiran
