#!/bin/bash
# 08-setup-haproxy.sh
# Configura HAProxy como balanceador TCP frente a ldap1 (1388) y ldap2 (1389),
# expuesto como ldap.fis.epn.edu.ec en el puerto 389.
set -e
source "$(dirname "$0")/lib/common.sh"

step "Desplegando configuracion de HAProxy"
sudo cp "$(dirname "$0")/../haproxy/haproxy.cfg" /etc/haproxy/haproxy.cfg
sudo haproxy -c -f /etc/haproxy/haproxy.cfg

step "Registrando ldap.${FIS_DOMAIN} en /etc/hosts"
add_hosts_entry "127.0.0.1" "ldap.${FIS_DOMAIN}"

step "Reiniciando HAProxy"
sudo systemctl restart haproxy
sudo systemctl status haproxy --no-pager | head -5

step "Verificacion"
ldapsearch -x -H "ldap://ldap.${FIS_DOMAIN}" -b "${BASE_DN}" -s base

echo "HAProxy activo. Stats: http://$(get_host_ip):8404/stats"
echo "Metricas Prometheus: http://$(get_host_ip):8405/metrics"
