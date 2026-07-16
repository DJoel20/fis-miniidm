#!/bin/bash
# 06-setup-ldap-replica.sh
# Crea el contenedor Docker ldap2 (replica), importa el mismo esquema
# Kerberos que el master y configura syncrepl en modo refreshAndPersist.

set -e
source "$(dirname "$0")/lib/common.sh"

if [ -z "${LDAP_ADMIN_PASS:-}" ]; then
    read -rsp "Contrasena de cn=admin,${BASE_DN} (master): " LDAP_ADMIN_PASS
    echo
fi

if [ -z "${REPLICATOR_PASS:-}" ]; then
    read -rsp "Contrasena nueva para la cuenta replicator: " REPLICATOR_PASS
    echo
fi

step "Creando cuenta replicator en el master (solo lectura)"
REPL_HASH=$(slappasswd -s "${REPLICATOR_PASS}")
cat <<EOF > /tmp/replicator.ldif
dn: cn=replicator,${BASE_DN}
objectClass: simpleSecurityObject
objectClass: organizationalRole
cn: replicator
description: Cuenta de servicio para replicacion LDAP
userPassword: ${REPL_HASH}
EOF
ldapadd -x -D "cn=admin,${BASE_DN}" -w "${LDAP_ADMIN_PASS}" -H ldap://127.0.0.1:1388 -f /tmp/replicator.ldif || true

step "Habilitando syncprov en el master"
sudo ldapmodify -Y EXTERNAL -H ldapi:// -f "$(dirname "$0")/../ldap/syncprov-master.ldif" || echo "(syncprov ya podria estar activo)"

step "Creando red y contenedor Docker para ldap2"
docker network create ldap-net 2>/dev/null || true
docker rm -f ldap2 2>/dev/null || true

docker run -d --name ldap2 --network ldap-net --hostname "ldap2.${FIS_DOMAIN:-fis.epn.ec}" \
    -p 1389:389 -p 1636:636 \
    --add-host=host.docker.internal:host-gateway \
    ubuntu:24.04 sleep infinity

step "Instalando y pre-configurando slapd en la replica"
# Permitir a los servicios arrancar dentro del contenedor
docker exec ldap2 bash -c "printf '#!/bin/sh\nexit 0\n' > /usr/sbin/policy-rc.d && chmod +x /usr/sbin/policy-rc.d"
docker exec ldap2 bash -c "apt-get update"

# Pre-cargamos la configuracion ANTES de instalar slapd, para que nazca con dc=fis,dc=epn,dc=ec
docker exec ldap2 bash -c "
debconf-set-selections <<EOF2
slapd slapd/internal/generated_adminpw password ${LDAP_ADMIN_PASS}
slapd slapd/internal/adminpw password ${LDAP_ADMIN_PASS}
slapd slapd/password2 password ${LDAP_ADMIN_PASS}
slapd slapd/password1 password ${LDAP_ADMIN_PASS}
slapd slapd/domain string fis.epn.ec
slapd shared/organization string FIS
slapd slapd/purge_database boolean true
slapd slapd/move_old_database boolean true
slapd slapd/no_configuration boolean false
EOF2

DEBIAN_FRONTEND=noninteractive apt-get install -y slapd ldap-utils krb5-kdc-ldap
"

step "Verificando conectividad con el LDAP Master"
docker exec ldap2 ldapsearch -x -H ldap://host.docker.internal:1388 -b "${BASE_DN}" -s base dn > /dev/null || {
    echo "ERROR: La replica no puede alcanzar al master en host.docker.internal:1388."
    echo "Revisa reglas de firewall local."
    exit 1
}

step "Importando el esquema Kerberos dentro del contenedor"
if [ -f /usr/share/doc/krb5-kdc-ldap/kerberos.openldap.ldif.gz ]; then
    zcat /usr/share/doc/krb5-kdc-ldap/kerberos.openldap.ldif.gz > /tmp/kerberos_replica.ldif
elif [ -f /usr/share/doc/krb5-kdc-ldap/kerberos.openldap.ldif ]; then
    cp /usr/share/doc/krb5-kdc-ldap/kerberos.openldap.ldif /tmp/kerberos_replica.ldif
else
    echo 'ERROR: kerberos.openldap.ldif no se encontro en el host.'
    exit 1
fi

docker cp /tmp/kerberos_replica.ldif ldap2:/tmp/kerberos.openldap.ldif

docker exec ldap2 bash -c "
SCHEMA_OUTPUT=\$(ldapadd -Y EXTERNAL -H ldapi:// -f /tmp/kerberos.openldap.ldif 2>&1) && {
    echo \"\${SCHEMA_OUTPUT}\"
} || {
    echo \"\${SCHEMA_OUTPUT}\"
    if echo \"\${SCHEMA_OUTPUT}\" | grep -qiE 'already exists|Duplicate attributeType|Duplicate objectClass'; then
        echo '(el esquema ya estaba cargado, continuando)'
    else
        echo 'ERROR: fallo al cargar el esquema Kerberos en la replica (ver salida arriba).'
        exit 1
    fi
}

if ! ldapsearch -Y EXTERNAL -H ldapi:// -b cn=schema,cn=config -s one dn 2>/dev/null | grep -qi kerberos; then
    echo 'ERROR: el esquema kerberos no quedo registrado en la replica.'
    exit 1
fi
"

step "Configurando syncrepl en la replica"
docker exec ldap2 bash -c "
cat <<EOF2 > /tmp/syncrepl.ldif
dn: cn=module{0},cn=config
changetype: modify
add: olcModuleLoad
olcModuleLoad: syncprov

dn: cn=config
changetype: modify
add: olcServerID
olcServerID: 2

dn: olcDatabase={1}mdb,cn=config
changetype: modify
add: olcSyncRepl
olcSyncRepl: rid=1
  provider=ldap://host.docker.internal:1388
  bindmethod=simple
  binddn=cn=replicator,${BASE_DN}
  credentials=${REPLICATOR_PASS}
  searchbase=${BASE_DN}
  scope=sub
  schemachecking=on
  type=refreshAndPersist
  retry=\"5 5 60 +\"
  interval=00:00:00:10
-
add: olcUpdateRef
olcUpdateRef: ldap://host.docker.internal:1388
EOF2

ldapmodify -Y EXTERNAL -H ldapi:// -f /tmp/syncrepl.ldif
service slapd restart || true

SLAPD_UP=0
for i in \$(seq 1 10); do
    if pgrep -x slapd >/dev/null; then
        SLAPD_UP=1
        break
    fi
    sleep 1
done

if [ \"\${SLAPD_UP}\" -eq 0 ]; then
    echo 'ERROR: slapd no quedo corriendo en ldap2 despues del restart' >&2
    exit 1
fi
"

step "Esperando la sincronizacion inicial (10s)"
sleep 12

step "Verificacion"
docker exec ldap2 ldapsearch -x -H ldap://localhost -b "${BASE_DN}" "(objectClass=posixAccount)" uid
echo "--- contextCSN master vs replica ---"
ldapsearch -x -H ldap://127.0.0.1:1388 -b "${BASE_DN}" -s base contextCSN
docker exec ldap2 ldapsearch -x -H ldap://localhost -b "${BASE_DN}" -s base contextCSN
echo "Replica LDAP (ldap2) lista y sincronizada."
