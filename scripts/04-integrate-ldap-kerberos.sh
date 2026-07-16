#!/bin/bash
# 04-integrate-ldap-kerberos.sh
# Importa el esquema LDAP de Kerberos y anota el krbPrincipalName
# correspondiente en cada usuario. LDAP y Kerberos mantienen bases de datos
# independientes; esta es la sincronizacion de atributos que las enlaza.
set -e
source "$(dirname "$0")/lib/common.sh"
if [ -z "${LDAP_ADMIN_PASS:-}" ]; then
    read -rsp "Contrasena de cn=admin,${BASE_DN}: " LDAP_ADMIN_PASS
    echo
fi

step "Localizando kerberos.openldap.ldif.gz"
SCHEMA_GZ="/usr/share/doc/krb5-kdc-ldap/kerberos.openldap.ldif.gz"
if [ ! -f "${SCHEMA_GZ}" ]; then
    echo "ERROR: no se encontro ${SCHEMA_GZ}. Verifica que krb5-kdc-ldap este instalado (script 00)."
    exit 1
fi
gunzip -k -f "${SCHEMA_GZ}" -c > /tmp/kerberos.openldap.ldif

step "Cargando el esquema en el LDAP master"
# IMPORTANTE: si un intento anterior de cargar este esquema fallo DESPUES
# de que slapd parseara los OIDs (p.ej. por un error de permisos), esos OIDs
# quedan registrados en la memoria del proceso slapd aunque nunca se hayan
# guardado en disco. Un reintento posterior, aunque ya tenga permisos
# correctos, choca con "Duplicate attributeType" porque slapd cree que ya
# existen. Reiniciamos slapd primero para descartar ese estado en memoria
# y partir solo de lo que esta realmente persistido en cn=config.
sudo systemctl restart slapd
sleep 2

# IMPORTANTE: -Y EXTERNAL -H ldapi:// autentica segun el usuario de SO que
# abre el socket. Sin sudo, eso es el usuario normal (uid != 0), y las ACLs
# de cn=config solo permiten escritura a root -> "Insufficient access (50)".
# Ademas: NO usamos "|| echo" generico, porque eso oculta tambien errores
# de permisos reales (como el que causo este bug). Distinguimos "ya existe"
# de cualquier otro fallo.
SCHEMA_OUTPUT=$(sudo ldapadd -Y EXTERNAL -H ldapi:// -f /tmp/kerberos.openldap.ldif 2>&1) && {
    echo "${SCHEMA_OUTPUT}"
} || {
    echo "${SCHEMA_OUTPUT}"
    if echo "${SCHEMA_OUTPUT}" | grep -qiE "already exists|Duplicate attributeType|Duplicate objectClass"; then
        echo "(el esquema ya estaba cargado, continuando)"
    else
        echo "ERROR: fallo al cargar el esquema Kerberos en LDAP (ver salida arriba)."
        exit 1
    fi
}

step "Anotando krbPrincipalName en cada usuario"
for user in jperez malvan dnoboa; do
cat <<EOF > /tmp/krb_attr_${user}.ldif
dn: uid=${user},ou=usuarios,${BASE_DN}
changetype: modify
add: objectClass
objectClass: krbPrincipalAux
-
add: krbPrincipalName
krbPrincipalName: ${user}@${REALM}
EOF
MODIFY_OUTPUT=$(ldapmodify -x -D "cn=admin,${BASE_DN}" -w "${LDAP_ADMIN_PASS}" -H ldap://127.0.0.1:1388 -f /tmp/krb_attr_${user}.ldif 2>&1) && {
    echo "${MODIFY_OUTPUT}"
} || {
    echo "${MODIFY_OUTPUT}"
    if echo "${MODIFY_OUTPUT}" | grep -qi "type or value exists"; then
        echo "(${user} ya tenia el atributo krbPrincipalName, continuando)"
    else
        echo "ERROR: fallo al anotar krbPrincipalName en ${user} (ver salida arriba)."
        exit 1
    fi
}
done

step "Verificacion"
VERIFY_OUTPUT=$(ldapsearch -x -H ldap://127.0.0.1:1388 -b "${BASE_DN}" "(uid=jperez)" krbPrincipalName)
echo "${VERIFY_OUTPUT}"
if ! echo "${VERIFY_OUTPUT}" | grep -q "^krbPrincipalName:"; then
    echo "ERROR: la verificacion no encontro krbPrincipalName en jperez. La integracion NO quedo completa."
    exit 1
fi
echo "Integracion LDAP-Kerberos completa."
