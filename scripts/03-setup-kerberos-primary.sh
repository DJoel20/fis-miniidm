#!/bin/bash
# 03-setup-kerberos-primary.sh
# Crea el realm FIS.EPN.EC, el KDC primario y los principals de usuarios y
# servicios.
set -e
source "$(dirname "$0")/lib/common.sh"

HOST_IP=$(get_host_ip)
step "IP detectada del host: ${HOST_IP}"

if [ -z "${KRB5_MASTER_PASS:-}" ]; then
    read -rsp "Contrasena maestra del KDC (master key): " KRB5_MASTER_PASS
    echo
fi
if [ -z "${JPEREZ_PASS:-}" ]; then
    read -rsp "Contrasena para el principal jperez: " JPEREZ_PASS
    echo
fi

step "Escribiendo /etc/krb5.conf"
sudo tee /etc/krb5.conf > /dev/null <<EOF
[libdefaults]
    default_realm = ${REALM}
    dns_lookup_realm = false
    dns_lookup_kdc = false
    rdns = false

[realms]
    ${REALM} = {
        kdc = 127.0.0.1
        admin_server = 127.0.0.1
    }

[domain_realm]
    .${FIS_DOMAIN} = ${REALM}
    ${FIS_DOMAIN} = ${REALM}
EOF

step "Escribiendo /etc/krb5kdc/kdc.conf"
sudo mkdir -p /etc/krb5kdc
sudo tee /etc/krb5kdc/kdc.conf > /dev/null <<EOF
[kdcdefaults]
    kdc_ports = 750,88

[realms]
    ${REALM} = {
        database_name = /var/lib/krb5kdc/principal
        admin_keytab = FILE:/etc/krb5kdc/kadm5.keytab
        acl_file = /etc/krb5kdc/kadm5.acl
        key_stash_file = /etc/krb5kdc/.k5.${REALM}
        kdc_ports = 750,88
        max_life = 10h 0m 0s
        max_renewable_life = 7d 0h 0m 0s
        default_principal_flags = +preauth
    }
EOF

step "Creando la base de datos del realm (kdb5_util create)"
# 1. Detener servicios
sudo systemctl stop krb5-kdc krb5-admin-server 2>/dev/null || true

# 2. Borrado agresivo: eliminamos el directorio completo para eliminar bloqueos de DB2
sudo rm -rf /var/lib/krb5kdc/
sudo mkdir -p /var/lib/krb5kdc/

# 3. Limpieza de archivos de configuración y estado previos
sudo rm -f /etc/krb5kdc/kadm5.keytab /etc/krb5kdc/.k5.* /etc/krb5kdc/kadm5.acl

# 4. Crear la base de datos
sudo kdb5_util create -s -r "${REALM}" -P "${KRB5_MASTER_PASS}"

step "ACL de administracion"
echo "*/admin@${REALM} *" | sudo tee /etc/krb5kdc/kadm5.acl > /dev/null

step "Arrancando el KDC y el servidor de administracion"
sudo systemctl enable --now krb5-kdc krb5-admin-server

step "Creando principals de usuarios"
sudo kadmin.local -q "addprinc -pw ${JPEREZ_PASS} jperez@${REALM}" || true
sudo kadmin.local -q "addprinc -randkey malvan@${REALM}" || true
sudo kadmin.local -q "addprinc -randkey dnoboa@${REALM}" || true
sudo kadmin.local -q "addprinc -pw ${JPEREZ_PASS} jperez/admin@${REALM}" || true

step "Creando principals de servicio"
sudo kadmin.local -q "addprinc -randkey HTTP/webserver.${FIS_DOMAIN}@${REALM}" || true
sudo kadmin.local -q "addprinc -randkey ldap/ldap1.${FIS_DOMAIN}@${REALM}" || true

step "Verificacion"
sudo kadmin.local -q "listprincs"
kdestroy 2>/dev/null || true
kinit jperez@${REALM} <<< "${JPEREZ_PASS}" && klist && kdestroy

echo "KDC primario listo para el realm ${REALM}."
