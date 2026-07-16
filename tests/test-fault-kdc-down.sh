#!/bin/bash
# Punto 9.4: Fallo del KDC (detener el servicio Kerberos)
set -e

echo "== Ticket valido antes del fallo =="
kdestroy 2>/dev/null || true
kinit jperez@FIS.EPN.EC
klist

echo "== Deteniendo el servicio Kerberos (KDC primario) =="
date +"%H:%M:%S.%N"
sudo systemctl stop krb5-kdc

echo "== Intentando autenticar (debe fallar) =="
kdestroy 2>/dev/null || true
kinit jperez@FIS.EPN.EC && echo "ERROR: no debia responder" || echo "OK: fallo detectado, exit $?"
date +"%H:%M:%S.%N"

echo "== Levantando el KDC de nuevo =="
sudo systemctl start krb5-kdc
kdestroy 2>/dev/null || true
kinit jperez@FIS.EPN.EC
klist
