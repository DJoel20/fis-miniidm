#!/bin/bash
# 07-setup-kerberos-secondary.sh
set -e
source "$(dirname "$0")/lib/common.sh"
PRIMARY_FQDN="krb5.${FIS_DOMAIN}"
SECONDARY_FQDN="kdc2.${FIS_DOMAIN}"
HOST_IP=$(get_host_ip)

step "Registrando el hostname del primario en /etc/hosts"
add_hosts_entry "${HOST_IP}" "${PRIMARY_FQDN}"

# El secundario corre en Docker con port-mapping (-p 2088:88), por lo que
# desde el HOST (donde corre kprop) se accede via 127.0.0.1, no via la IP
# interna del contenedor. Sin esta entrada, kprop no puede resolver el
# nombre y falla con "Name or service not known".
step "Registrando el hostname del secundario en /etc/hosts (via 127.0.0.1, por port-mapping)"
add_hosts_entry "127.0.0.1" "${SECONDARY_FQDN}"

step "Creando principals de host"
sudo kadmin.local -q "addprinc -randkey host/${PRIMARY_FQDN}@${REALM}" || true
sudo kadmin.local -q "addprinc -randkey host/${SECONDARY_FQDN}@${REALM}" || true

# --- FIX: kprop se autentica usando el hostname *real* de la maquina local
# (el que devuelve `hostname -f`), NO necesariamente PRIMARY_FQDN. Si ese
# principal no existe en el keytab, kprop falla con:
#   "Key table entry not found while getting initial credentials"
# Lo agregamos siempre, incluso si coincide con PRIMARY_FQDN (no hace daño).
LOCAL_FQDN="$(hostname -f)"
LOCAL_FQDN="${LOCAL_FQDN,,}"
step "Creando principal de propagacion para el hostname local real (${LOCAL_FQDN})"
sudo kadmin.local -q "addprinc -randkey host/${LOCAL_FQDN}@${REALM}" || true

step "Extrayendo el keytab de propagacion"
sudo rm -f /etc/krb5kdc/kprop.keytab
# Extraemos primario, secundario y el hostname local real para que kprop
# pueda autenticarse sin importar cual use el sistema para resolverse a si mismo.
sudo kadmin.local -q "ktadd -k /etc/krb5kdc/kprop.keytab host/${PRIMARY_FQDN}@${REALM}"
sudo kadmin.local -q "ktadd -k /etc/krb5kdc/kprop.keytab host/${SECONDARY_FQDN}@${REALM}"
sudo kadmin.local -q "ktadd -k /etc/krb5kdc/kprop.keytab host/${LOCAL_FQDN}@${REALM}"
sudo chmod 644 /etc/krb5kdc/kprop.keytab

step "Extrayendo el keytab propio del secundario"
sudo kadmin.local -q "ktadd -k /tmp/kdc2.keytab host/${SECONDARY_FQDN}@${REALM}"
sudo chmod 644 /tmp/kdc2.keytab

step "Creando contenedor Docker para el KDC secundario"
docker network create ldap-net 2>/dev/null || true
docker rm -f kdc2 2>/dev/null || true
docker run -d --name kdc2 --network ldap-net --hostname "${SECONDARY_FQDN}" \
    -p 2088:88 -p 2088:88/udp -p 2749:749 -p 754:754 \
    --add-host=host.docker.internal:host-gateway \
    ubuntu:24.04 sleep infinity

step "Instalando paquetes en el contenedor"
docker exec kdc2 bash -c "apt update && DEBIAN_FRONTEND=noninteractive apt install -y krb5-user krb5-kdc krb5-kpropd netbase iproute2"

step "Generando y copiando configuraciones al contenedor"
docker exec kdc2 mkdir -p /etc/krb5kdc
cat <<EOF > /tmp/kdc2_krb5.conf
[libdefaults]
    default_realm = ${REALM}
    dns_lookup_realm = false
    dns_lookup_kdc = false
    rdns = false
[realms]
    ${REALM} = {
        kdc = 127.0.0.1
        admin_server = host.docker.internal
    }
[domain_realm]
    .${FIS_DOMAIN} = ${REALM}
    ${FIS_DOMAIN} = ${REALM}
EOF
cat <<EOF > /tmp/kdc2_kdc.conf
[kdcdefaults]
    kdc_ports = 750,88
[realms]
    ${REALM} = {
        database_name = /var/lib/krb5kdc/principal
        admin_keytab = FILE:/etc/krb5kdc/kadm5.keytab
        acl_file = /etc/krb5kdc/kadm5.acl
        key_stash_file = /etc/krb5kdc/.k5.${REALM}
        kdc_ports = 750,88
    }
EOF
docker cp /tmp/kdc2_krb5.conf kdc2:/etc/krb5.conf
docker cp /tmp/kdc2_kdc.conf kdc2:/etc/krb5kdc/kdc.conf

# Generamos el ACL dinamicamente en vez de copiar un archivo estatico:
# kprop se autentica con el principal host/<hostname-local-real>, que
# varia segun la maquina (ver LOCAL_FQDN mas arriba). Un kpropd.acl fijo
# con un solo hostname hardcodeado rompe en cualquier maquina distinta.
step "Generando kpropd.acl dinamicamente"
cat <<EOF > /tmp/kdc2_kpropd.acl
host/${PRIMARY_FQDN}@${REALM}
host/${LOCAL_FQDN}@${REALM}
EOF
docker cp /tmp/kdc2_kpropd.acl kdc2:/etc/krb5kdc/kpropd.acl

docker cp /tmp/kdc2.keytab kdc2:/etc/krb5.keytab
sudo docker cp /etc/krb5kdc/kprop.keytab kdc2:/etc/krb5kdc/kprop.keytab
docker exec kdc2 chmod 600 /etc/krb5.keytab /etc/krb5kdc/kprop.keytab

step "Copiando la clave maestra"
sudo cp /etc/krb5kdc/.k5.${REALM} /tmp/stash_temp
sudo chmod 644 /tmp/stash_temp
docker cp /tmp/stash_temp kdc2:/etc/krb5kdc/.k5.${REALM}
sudo rm -f /tmp/stash_temp
docker exec kdc2 chmod 600 /etc/krb5kdc/.k5.${REALM}

step "Iniciando kpropd en el secundario"
docker exec -d kdc2 /usr/sbin/kpropd

# --- Espera activa en vez de "sleep 5" fijo: evita condicion de carrera
# si el contenedor tarda mas en levantar el proceso kpropd.
# IMPORTANTE: no basta con pgrep (un proceso puede arrancar y morir
# quedando "defunct"/zombie, y pgrep lo seguiria detectando). Verificamos
# que el puerto 754 este realmente escuchando.
TRIES=0
until docker exec kdc2 bash -c "ss -tln 2>/dev/null | grep -q ':754 '"; do
    TRIES=$((TRIES + 1))
    if [ "${TRIES}" -ge 20 ]; then
        echo "ERROR: timeout esperando a que kpropd escuche en el puerto 754 en kdc2" >&2
        echo "Diagnostico: docker exec -it kdc2 /usr/sbin/kpropd -d" >&2
        exit 1
    fi
    sleep 1
done

step "Realizando la primera propagacion"
sudo kdb5_util dump /var/lib/krb5kdc/replica_datatrans
# Ejecución limpia del comando kprop sin opciones inválidas
sudo kprop -f /var/lib/krb5kdc/replica_datatrans -s /etc/krb5kdc/kprop.keytab "${SECONDARY_FQDN}"

step "Arrancando krb5-kdc en el secundario"
docker exec -d kdc2 /usr/sbin/krb5kdc -n -r "${REALM}" -d /var/lib/krb5kdc/principal
echo "KDC secundario (kdc2) listo."
