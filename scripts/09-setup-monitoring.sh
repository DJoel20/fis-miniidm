#!/bin/bash
# 09-setup-monitoring.sh
# Instala Prometheus + node_exporter (con el textfile collector para el
# retraso de replicacion LDAP) y Grafana. Requiere que 06 (replica) y 08
# (HAProxy) ya esten aplicados, porque scrapea metricas de ambos.
set -e
source "$(dirname "$0")/lib/common.sh"

PROM_VERSION="2.53.0"
NODE_EXP_VERSION="1.12.0"
REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"

step "Descargando Prometheus ${PROM_VERSION}"
cd /tmp
wget -q "https://github.com/prometheus/prometheus/releases/download/v${PROM_VERSION}/prometheus-${PROM_VERSION}.linux-amd64.tar.gz"
tar xzf "prometheus-${PROM_VERSION}.linux-amd64.tar.gz"
sudo mv "prometheus-${PROM_VERSION}.linux-amd64/prometheus" /usr/local/bin/
sudo mv "prometheus-${PROM_VERSION}.linux-amd64/promtool" /usr/local/bin/
sudo useradd --no-create-home --shell /bin/false prometheus 2>/dev/null || true
sudo mkdir -p /etc/prometheus /var/lib/prometheus
sudo cp -r "prometheus-${PROM_VERSION}.linux-amd64/consoles" "prometheus-${PROM_VERSION}.linux-amd64/console_libraries" /etc/prometheus/
sudo cp "${REPO_DIR}/monitoring/prometheus.yml" /etc/prometheus/prometheus.yml
sudo chown -R prometheus:prometheus /etc/prometheus /var/lib/prometheus

sudo tee /etc/systemd/system/prometheus.service > /dev/null <<'EOF'
[Unit]
Description=Prometheus
After=network.target

[Service]
User=prometheus
Group=prometheus
Type=simple
ExecStart=/usr/local/bin/prometheus \
  --config.file=/etc/prometheus/prometheus.yml \
  --storage.tsdb.path=/var/lib/prometheus/ \
  --web.console.templates=/etc/prometheus/consoles \
  --web.console.libraries=/etc/prometheus/console_libraries

[Install]
WantedBy=multi-user.target
EOF

step "Descargando node_exporter ${NODE_EXP_VERSION}"
wget -q "https://github.com/prometheus/node_exporter/releases/download/v${NODE_EXP_VERSION}/node_exporter-${NODE_EXP_VERSION}.linux-amd64.tar.gz"
tar xzf "node_exporter-${NODE_EXP_VERSION}.linux-amd64.tar.gz"
sudo mv "node_exporter-${NODE_EXP_VERSION}.linux-amd64/node_exporter" /usr/local/bin/
sudo useradd --no-create-home --shell /bin/false node_exporter 2>/dev/null || true
sudo mkdir -p /var/lib/node_exporter/textfile_collector
sudo chown prometheus:prometheus /var/lib/node_exporter/textfile_collector
sudo cp "${REPO_DIR}/monitoring/node_exporter.service" /etc/systemd/system/node_exporter.service

step "Instalando el script y el timer de retraso de replicacion LDAP"
sudo cp "${REPO_DIR}/monitoring/ldap_repl_check.sh" /usr/local/bin/ldap_repl_check.sh
sudo chmod +x /usr/local/bin/ldap_repl_check.sh
sudo cp "${REPO_DIR}/monitoring/ldap-repl-check.service" /etc/systemd/system/
sudo cp "${REPO_DIR}/monitoring/ldap-repl-check.timer" /etc/systemd/system/

step "Arrancando Prometheus, node_exporter y el timer de replicacion"
sudo systemctl daemon-reload
sudo systemctl enable --now prometheus node_exporter ldap-repl-check.timer

step "Instalando Grafana"
sudo apt-get install -y apt-transport-https software-properties-common
wget -q -O - https://apt.grafana.com/gpg.key | sudo gpg --dearmor -o /usr/share/keyrings/grafana.gpg
echo "deb [signed-by=/usr/share/keyrings/grafana.gpg] https://apt.grafana.com stable main" \
    | sudo tee /etc/apt/sources.list.d/grafana.list
sudo apt-get update
sudo apt-get install -y grafana
sudo systemctl enable --now grafana-server

step "Verificacion"
sleep 3
curl -s http://localhost:9090/api/v1/targets | grep -o '"job":"[^"]*"' || true
curl -s http://localhost:3000/api/health

HOST_IP=$(get_host_ip)
cat <<EOF

Prometheus: http://${HOST_IP}:9090
Grafana:    http://${HOST_IP}:3000  (usuario/clave por defecto: admin/admin)

Pasos manuales en Grafana (no automatizables via script sin API key):
  1. Connections > Data sources > Add > Prometheus > URL: http://localhost:9090 > Save & Test
  2. Dashboards > New > Add visualization > Prometheus, y crear paneles con:
     - CPU:      100 - (avg(rate(node_cpu_seconds_total{mode="idle"}[1m])) * 100)
     - Memoria:  node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes * 100
     - Backends: haproxy_server_status{proxy="ldap_back", state="UP"}
     - Conexiones LDAP/s: haproxy_server_current_sessions{proxy="ldap_back"}
     - Retraso replicacion: ldap_replication_lag_seconds
EOF
