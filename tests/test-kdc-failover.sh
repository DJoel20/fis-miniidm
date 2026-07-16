#!/bin/bash
# Punto 7: HA de Kerberos
# Obtiene ticket del KDC primario, lo detiene, obtiene ticket del secundario
# y mide el tiempo de conmutacion.
set -e

cat <<'EOF' > /tmp/krb5_test_kdc2.conf
[libdefaults]
    default_realm = FIS.EPN.EC
    dns_lookup_realm = false
    dns_lookup_kdc = false
    rdns = false
[realms]
    FIS.EPN.EC = {
        kdc = 127.0.0.1:2088
    }
[domain_realm]
    .fis.epn.edu.ec = FIS.EPN.EC
EOF

echo "== Ticket desde el KDC primario =="
kdestroy 2>/dev/null || true
kinit jperez@FIS.EPN.EC
klist

echo "== Deteniendo el KDC primario =="
date +"%H:%M:%S.%N"
sudo systemctl stop krb5-kdc

echo "== Confirmando que el primario ya no responde =="
kdestroy 2>/dev/null || true
kinit jperez@FIS.EPN.EC && echo "ERROR: no debia responder" || echo "OK: primario inaccesible"

echo "== Obteniendo ticket desde el KDC secundario =="
KRB5_CONFIG=/tmp/krb5_test_kdc2.conf kinit jperez@FIS.EPN.EC
KRB5_CONFIG=/tmp/krb5_test_kdc2.conf klist
date +"%H:%M:%S.%N"

echo "== Levantando el KDC primario de nuevo =="
sudo systemctl start krb5-kdc
