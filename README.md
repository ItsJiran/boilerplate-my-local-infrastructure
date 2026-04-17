# 🛠 My Local Infrastructure Setup

This repository is my personal way of setting up and managing local infrastructure. It's designed to keep my computer clean and fresh by ensuring I never have to install complex dependencies like MySQL, Redis, or MinIO directly on my host system.

## 🧠 Why I Use This

The main idea is **"Fresh Host"**. Instead of cluttering my OS with various database versions and background services, I run everything in Docker. 

- **State Persistence**: All data lives in Docker volumes, so I can tear down and rebuild the stack without losing work.
- **Zero Host Impact**: My computer stays fast and free of unnecessary background processes.
- **Cloud & VPS Ready**: While I use this locally, I also use it on cloud VPS instances. It works out of the box for quick deployments.
- **Dev-Prod Parity**: I often add local hostnames (via `/etc/hosts`) for each service. This ensures that the environment I develop in is identical to where the apps will eventually run, making transitions to production seamless.

---

## 🏗 What's Inside

| Service | Port | What it does | UI / Access |
| :--- | :--- | :--- | :--- |
| **MariaDB** | `3306` | SQL Database | [phpMyAdmin](http://localhost:8080) |
| **Redis** | `6379` | Cache / In-memory store | CLI / App Connection |
| **MinIO** | `9000/9001` | S3-compatible Object Storage | [MinIO Console](http://localhost:9001) |
| **Portainer** | `9443/354` | Docker Management | [Portainer HTTPS](https://localhost:9443) |

---

## 🚀 How I Spin It Up

It's set up to work immediately with standard commands:

```bash
docker compose up -d    # Start everything in the background
docker compose ps       # Check what's running
docker compose down     # Stop and clean up
```

---

## 🔐 My Default Credentials

- **MariaDB**: `user` / `user` (Root: `rootpassword`)
- **MinIO**: `minioadmin` / `minioadmin`

---

## 💾 Storage Details

I've mapped these volumes for long-term persistence:
- `mariadb_data` -> DB files
- `minio_data` -> Files stored in S3
- `portainer_data` -> Portainer settings

---

