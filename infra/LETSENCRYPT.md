# Let's Encrypt - Production SSL Setup

## Overview

App Boilerplate uses **Let's Encrypt** for SSL certificates in **PRODUCTION** environment.

Let's Encrypt provides free, automated, and trusted SSL/TLS certificates for public domains.

## 🎯 Environment Strategy

| Environment | SSL Provider | Certificate Type | Trust Level |
|:------------|:-------------|:-----------------|:------------|
| **Development** | Step CA or mkcert | Self-signed | Local only |
| **Production** | Let's Encrypt | CA-signed | Globally trusted |

## Prerequisites

1. **Public Domain**: You must own a domain (e.g., `jiran.test`)
2. **DNS Configuration**: Domain must point to your server's IP
3. **Port 80 & 443**: Must be open and accessible from internet
4. **Email Address**: For certificate expiration notifications

## Setup Options

### Option 1: Certbot with Nginx (Recommended for VPS)

#### Installation

```bash
# Ubuntu/Debian
sudo apt update
sudo apt install certbot python3-certbot-nginx

# CentOS/RHEL
sudo yum install certbot python3-certbot-nginx
```

#### Get Certificate

```bash
# For single domain
sudo certbot --nginx -d jiran.test -d www.jiran.test

# For wildcard (requires DNS challenge)
sudo certbot --nginx -d jiran.test -d *.jiran.test --manual --preferred-challenges dns
```

#### Auto-Renewal

Certbot automatically sets up a cron job. Test it:

```bash
sudo certbot renew --dry-run
```

### Option 2: Docker + Certbot

#### Docker Compose Configuration

Create `infra/docker-compose.letsencrypt.yml`:

```yaml
version: '3.8'

services:
  certbot:
    image: certbot/certbot:latest
    container_name: app-boilerplate-certbot
    volumes:
      - ./ssl/certbot/conf:/etc/letsencrypt
      - ./ssl/certbot/www:/var/www/certbot
    entrypoint: "/bin/sh -c 'trap exit TERM; while :; do certbot renew; sleep 12h & wait $${!}; done;'"

  nginx:
    # ... your nginx config
    volumes:
      - ./ssl/certbot/conf:/etc/letsencrypt:ro
      - ./ssl/certbot/www:/var/www/certbot:ro
```

#### Initial Certificate Request

```bash
# Get certificate
docker-compose run --rm certbot certonly --webroot \
  -w /var/www/certbot \
  -d jiran.test \
  -d www.jiran.test \
  --email admin@jiran.test \
  --agree-tos \
  --no-eff-email

# Reload nginx
docker-compose exec nginx nginx -s reload
```

### Option 3: Traefik (Recommended for Docker/Kubernetes)

#### Traefik Configuration

```yaml
version: '3.8'

services:
  traefik:
    image: traefik:v2.10
    container_name: app-boilerplate-traefik
    restart: unless-stopped
    ports:
      - "80:80"
      - "443:443"
    command:
      # Enable Docker provider
      - "--providers.docker=true"
      - "--providers.docker.exposedbydefault=false"
      
      # Entrypoints
      - "--entrypoints.web.address=:80"
      - "--entrypoints.websecure.address=:443"
      
      # Let's Encrypt
      - "--certificatesresolvers.letsencrypt.acme.email=admin@jiran.test"
      - "--certificatesresolvers.letsencrypt.acme.storage=/letsencrypt/acme.json"
      - "--certificatesresolvers.letsencrypt.acme.httpchallenge=true"
      - "--certificatesresolvers.letsencrypt.acme.httpchallenge.entrypoint=web"
      
      # Redirect HTTP to HTTPS
      - "--entrypoints.web.http.redirections.entryPoint.to=websecure"
      - "--entrypoints.web.http.redirections.entryPoint.scheme=https"
    
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock:ro
      - ./ssl/letsencrypt:/letsencrypt
    
    labels:
      - "traefik.enable=true"

  # Your application
  app:
    image: your-app
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.app.rule=Host(`jiran.test`)"
      - "traefik.http.routers.app.entrypoints=websecure"
      - "traefik.http.routers.app.tls.certresolver=letsencrypt"
```

## Nginx Configuration for Let's Encrypt

### Production Nginx Config

```nginx
# /etc/nginx/sites-available/jiran.test

# HTTP - Redirect to HTTPS
server {
    listen 80;
    server_name jiran.test www.jiran.test;
    
    # Let's Encrypt challenge
    location /.well-known/acme-challenge/ {
        root /var/www/certbot;
    }
    
    # Redirect all other traffic to HTTPS
    location / {
        return 301 https://$host$request_uri;
    }
}

# HTTPS
server {
    listen 443 ssl http2;
    server_name jiran.test www.jiran.test;
    
    # SSL Configuration
    ssl_certificate /etc/letsencrypt/live/jiran.test/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/jiran.test/privkey.pem;
    
    # SSL Security Settings
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers 'ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256';
    ssl_prefer_server_ciphers off;
    
    # HSTS
    add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;
    
    # Your application config
    location / {
        proxy_pass http://localhost:3000;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
```

## Environment Configuration

### Production .env

```bash
# Production SSL Configuration
APP_ENV=production
USE_SSL=true
SSL_PROVIDER=letsencrypt

# Let's Encrypt
CERTBOT_EMAIL=admin@jiran.test
DOMAIN=jiran.test
CERTBOT_WEBROOT=/var/www/certbot

# SSL Certificate Paths (Let's Encrypt default)
SSL_CERT_PATH=/etc/letsencrypt/live/jiran.test/fullchain.pem
SSL_KEY_PATH=/etc/letsencrypt/live/jiran.test/privkey.pem

# Force HTTPS
FORCE_HTTPS=true
```

## Certificate Management

### Check Certificate Status

```bash
# View certificate details
sudo certbot certificates

# Check expiration
openssl x509 -in /etc/letsencrypt/live/jiran.test/cert.pem -noout -dates
```

### Manual Renewal

```bash
# Test renewal
sudo certbot renew --dry-run

# Force renewal
sudo certbot renew --force-renewal

# Renew and reload nginx
sudo certbot renew && sudo systemctl reload nginx
```

### Revoke Certificate

```bash
# If compromised
sudo certbot revoke --cert-path /etc/letsencrypt/live/jiran.test/cert.pem
```

## Monitoring & Alerts

### Certificate Expiration Monitoring

1. **Certbot Email Alerts**: Automatic from Let's Encrypt (30, 7, 1 day before expiry)

2. **Custom Monitoring Script**:

```bash
#!/bin/bash
# check-ssl-expiry.sh

DOMAIN="jiran.test"
DAYS_THRESHOLD=30

expiry_date=$(openssl s_client -connect $DOMAIN:443 -servername $DOMAIN 2>/dev/null \
  | openssl x509 -noout -dates | grep notAfter | cut -d= -f2)

expiry_epoch=$(date -d "$expiry_date" +%s)
now_epoch=$(date +%s)
days_left=$(( ($expiry_epoch - $now_epoch) / 86400 ))

if [ $days_left -lt $DAYS_THRESHOLD ]; then
    echo "WARNING: SSL certificate expires in $days_left days!"
    # Send alert (email, Slack, etc.)
fi
```

3. **Add to Crontab**:

```bash
# Run daily at 3 AM
0 3 * * * /path/to/check-ssl-expiry.sh
```

## Troubleshooting

### Issue: Rate Limit Exceeded

Let's Encrypt has rate limits (50 certificates per domain per week).

**Solution**:
- Use staging environment for testing: `--staging` flag
- Wait for rate limit to reset
- Request fewer certificates

### Issue: DNS Challenge Failed

**Solution**:
```bash
# Verify DNS propagation
dig jiran.test
nslookup jiran.test

# Wait for DNS to propagate (can take up to 48 hours)
```

### Issue: Port 80/443 Not Accessible

**Solution**:
```bash
# Check firewall
sudo ufw status
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp

# Check if port is in use
sudo netstat -tulpn | grep :80
sudo netstat -tulpn | grep :443
```

### Issue: Certificate Not Renewed

**Solution**:
```bash
# Check certbot timer
sudo systemctl status certbot.timer

# Restart timer
sudo systemctl restart certbot.timer

# Manual renewal
sudo certbot renew --force-renewal
```

## Security Best Practices

1. ✅ **Always use HTTPS in production**
2. ✅ **Enable HSTS** (HTTP Strict Transport Security)
3. ✅ **Use strong SSL ciphers** (TLSv1.2+)
4. ✅ **Set up auto-renewal** (certbot handles this)
5. ✅ **Monitor certificate expiration**
6. ✅ **Keep certbot updated**
7. ✅ **Backup `/etc/letsencrypt`** directory

## Migration from Development to Production

### 1. Update Environment

```bash
# Switch from development
cp .env.example .env.production

# Update SSL config
sed -i 's/USE_STEP_CA=true/USE_STEP_CA=false/' .env.production
sed -i 's/SSL_PROVIDER=step-ca/SSL_PROVIDER=letsencrypt/' .env.production
```

### 2. Update Nginx Config

```bash
# Copy production nginx config
cp infra/nginx/default.conf.vps.template /etc/nginx/sites-available/jiran.test

# Enable site
sudo ln -s /etc/nginx/sites-available/jiran.test /etc/nginx/sites-enabled/

# Test and reload
sudo nginx -t
sudo systemctl reload nginx
```

### 3. Get Certificate

```bash
sudo certbot --nginx -d jiran.test -d www.jiran.test
```

### 4. Verify

```bash
# Test HTTPS
curl -I https://jiran.test

# Check SSL certificate
openssl s_client -connect jiran.test:443 -servername jiran.test
```

## Resources

- [Let's Encrypt Documentation](https://letsencrypt.org/docs/)
- [Certbot Documentation](https://certbot.eff.org/docs/)
- [SSL Configuration Generator](https://ssl-config.mozilla.org/)
- [SSL Labs Test](https://www.ssllabs.com/ssltest/)
- [Certificate Transparency Search](https://crt.sh/)

## Support

For issues:
1. Check Let's Encrypt status: https://letsencrypt.status.io/
2. Review certbot logs: `/var/log/letsencrypt/letsencrypt.log`
3. Test with staging first: `--staging` flag
4. Contact: Akterma Technology [AT] - ItsJiran
