#!/bin/bash
# Funciones compartidas por los scripts scripts/NN-*.sh
# shellcheck disable=SC2034

step() { echo -e "\n=== $1 ===\n"; }

# Agrega (o actualiza) una entrada en /etc/hosts, UNA linea por hostname.
# Evita el problema real encontrado durante el desarrollo: cuando varios
# hostnames comparten una linea con la misma IP, la resolucion de nombre
# canonico de Kerberos/GSSAPI puede devolver el hostname equivocado.
add_hosts_entry() {
    local ip="$1"
    local hostname="$2"
    if grep -qE "^\s*[0-9.]+\s+${hostname}\s*$" /etc/hosts; then
        sudo sed -i "s|^\s*[0-9.]\+\s\+${hostname}\s*$|${ip}  ${hostname}|" /etc/hosts
    else
        echo "${ip}  ${hostname}" | sudo tee -a /etc/hosts > /dev/null
    fi
}

get_host_ip() {
    ip addr show eth0 2>/dev/null | grep "inet " | awk '{print $2}' | cut -d/ -f1 \
        || hostname -I | awk '{print $1}'
}

REALM="FIS.EPN.EC"
BASE_DN="dc=fis,dc=epn,dc=ec"
FIS_DOMAIN="fis.epn.edu.ec"
