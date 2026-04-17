#!/bin/sh

# ! ==============================
# ! CONFIG
# ! ==============================
OUTPUT="prometheus.yml"

# ! ==============================
# ! JOB REGISTRY
# ! job_name|port|scrape_interval
# ! ==============================
JOBS=$(cat <<'EOF'
cadvisor_monitor|8080|5s
node_monitor|9100|5s
redis_monitor|9121|5s
nginx_monitor|8085|5s
mariadb_monitor|9104|5s
EOF
)

# ! ==============================
# ! HOST INVENTORY
# ! ip|alias|role|job1,job2
# ! Ganti IP dan alias sesuai environment Anda
# ! ==============================
HOSTS=$(cat <<'EOF'
192.168.1.10|Worker-Node-1|worker|cadvisor_monitor,node_monitor,nginx_monitor
192.168.1.20|Master-Node-1|master|cadvisor_monitor,node_monitor,redis_monitor,nginx_monitor,mariadb_monitor
EOF
)

# ! ==============================
# ! WRITE GLOBAL CONFIG
# ! ==============================
cat > "$OUTPUT" <<EOF
global:
  scrape_interval: 15s
  external_labels:
    origin_host: 'central-server'

scrape_configs:
EOF

# ! ==============================
# ! RENDER PER JOB
# ! ==============================
echo "$JOBS" | while IFS='|' read -r JOB_NAME PORT INTERVAL; do

  # ! start job block
  cat >> "$OUTPUT" <<EOF

  - job_name: '$JOB_NAME'
    scrape_interval: $INTERVAL
    static_configs:
EOF

  # ! find hosts that contain this job
  echo "$HOSTS" | while IFS='|' read -r IP ALIAS ROLE JOB_LIST; do
    echo "$JOB_LIST" | tr ',' '\n' | grep -qx "$JOB_NAME" || continue

    # ! add target
    cat >> "$OUTPUT" <<EOF
      - targets: ['$IP:$PORT']
        labels:
          alias: '$ALIAS'
          role: '$ROLE'
EOF
  done

done

# ! ==============================
# ! STATIC JOB (NON-IP BASED)
# ! ==============================
cat >> "$OUTPUT" <<EOF

  - job_name: 'loki'
    static_configs:
      - targets: ['loki:3100']
EOF

# ! ==============================
# ! DONE
# ! ==============================
echo "prometheus.yml generated successfully"
