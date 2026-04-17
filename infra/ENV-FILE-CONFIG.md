# Docker Compose Environment File Configuration

## Overview

All docker-compose files in this project are configured to load environment variables from the **root project directory**.

## Path Strategy

### Main docker-compose.yml (Root Level)
Located at: `/project-root/docker-compose.yml`

Uses relative paths from root:
```yaml
env_file:
  - .env
  - ./.env.backend
  - ./.env.devops
```

### Infra docker-compose files (infra/ folder)
Located at: `/project-root/infra/docker-compose.*.yml`

Uses parent directory reference:
```yaml
env_file:
  - ../.env
  - ../.env.backend
  - ../.env.devops
```

## File Structure

```
project-root/
├── .env                          # Main environment file
├── .env.backend                  # Backend-specific config
├── .env.devops                   # DevOps/monitoring config
├── docker-compose.yml            # Main services (uses .env)
└── infra/
    ├── docker-compose.devops.yml          # Grafana, Loki, Prometheus (uses ../.env)
    ├── docker-compose.devops.exporter.yml # Exporters (uses ../.env)
    ├── docker-compose.portainer.yml       # Portainer (no env_file)
    └── docker-compose.step-ca.yml         # Step CA (uses environment vars)
```

## Why This Approach?

1. **Single Source of Truth**: All services read from the same `.env` files in root
2. **Consistency**: No duplicate `.env` files in subdirectories
3. **Easy Management**: Update environment variables in one place
4. **Version Control**: Gitignore `.env` at root level protects all environments

## Running Services

### From Root Directory
```bash
# Main application
docker compose up -d

# DevOps services (from root)
docker compose -f infra/docker-compose.devops.yml up -d
```

### From Infra Directory
```bash
cd infra

# DevOps services (paths resolve to ../.env)
docker compose -f docker-compose.devops.yml up -d

# Exporters
docker compose -f docker-compose.devops.exporter.yml up -d
```

### Using Run Scripts
```bash
# Interactive menu
./run.sh

# Or run scripts directly
./scripts/run/run.app.sh
./scripts/run/run.devops.sh
./scripts/run/run.devops.exporter.sh
```

All run scripts automatically resolve to root `.env` files.

## Environment File Priority

When multiple env files are specified, Docker Compose processes them in order:

1. `.env` - Base configuration
2. `.env.backend` - Backend/Laravel specific
3. `.env.devops` - Monitoring/DevOps specific

Later files override earlier ones for duplicate keys.

## Validation

Check if env files are correctly resolved:

```bash
# From root
docker compose config | grep -A5 "environment:"

# From infra
cd infra
docker compose -f docker-compose.devops.yml config | grep -A5 "environment:"
```

## Troubleshooting

### Issue: "env file not found"

**Cause**: Running docker-compose from wrong directory or incorrect path

**Solution**:
- Main compose: Run from root directory
- Infra compose: Ensure `../.env` paths are correct
- Scripts: Use provided run scripts which handle paths automatically

### Issue: Environment variables not loaded

**Cause**: `.env` file doesn't exist or has wrong name

**Solution**:
```bash
# Copy example env file
cp .env.example .env
cp .env.example.backend .env.backend
cp .env.example.devops .env.devops

# Edit with your values
nano .env
```

## Best Practices

1. ✅ **Never commit** `.env` files (already in `.gitignore`)
2. ✅ **Update** `.env.example` files when adding new variables
3. ✅ **Use** provided run scripts for consistency
4. ✅ **Validate** config with `docker compose config` before running
5. ✅ **Document** new environment variables in this file

## Environment Variables Structure

### Core Variables (.env)
- `COMPOSE_PROJECT_NAME`
- `APP_NAME`, `APP_ENV`, `APP_DEBUG`
- `APP_URL`, `API_URL`
- Port mappings
- SSL configuration

### Backend Variables (.env.backend)
- Database configuration
- Redis configuration
- Laravel-specific settings
- API keys and secrets

### DevOps Variables (.env.devops)
- Grafana, Prometheus, Loki settings
- Exporter configurations
- Resource limits (CPU, Memory)
- Monitoring ports and hosts

## Related Documentation

- [Setup Scripts](../scripts/setup/README.md)
- [Run Scripts](../scripts/run/README.md)
- [SSL Configuration](STEP-CA.md)
- [Production SSL](LETSENCRYPT.md)

---

**Maintained by**: Akterma Technology [AT] - ItsJiran  
**Last Updated**: 2026-02-24
