#!/bin/bash
# 02-setup-ldap-master.sh
# Reconfigura slapd con el DIT de la FIS, lo mueve al puerto 1388 y habilita TLS.
set -e
source "$(dirname "$0")/lib/common.sh"

PKI_DIR="/etc/ssl/fis-pki"

if [ -z "${LDAP_ADMIN_PASS:-}" ]; then
    read -rsp "Contrasena para cn=admin,${BASE_DN}: " LDAP_ADMIN_PASS
    echo
fi

step "Reconfigurando slapd (DIT: ${BASE_DN})"
# Se agrega 'slapd slapd/services string ldap:/// ldapi:///' para evitar conflicto en el puerto 389
sudo debconf-set-selections <<EOF
slapd slapd/internal/generated_adminpw password ${LDAP_ADMIN_PASS}
slapd slapd/internal/adminpw password ${LDAP_ADMIN_PASS}
slapd slapd/password2 password ${LDAP_ADMIN_PASS}
slapd slapd/password1 password ${LDAP_ADMIN_PASS}
slapd slapd/domain string fis.epn.ec
slapd shared/organization string FIS
slapd slapd/purge_database boolean true
slapd slapd/move_old_database boolean true
slapd slapd/no_configuration boolean false
slapd slapd/services string ldap:/// ldapi:///
EOF

sudo systemctl stop slapd || true

sudo rm -rf /etc/ldap/slapd.d
sudo rm -rf /var/lib/ldap

sudo DEBIAN_FRONTEND=noninteractive dpkg-reconfigure slapd

if [ ! -f /etc/ldap/slapd.d/cn=config.ldif ]; then
    echo "ERROR: No se creó cn=config"
    exit 1
fi

# Aseguramos que esté detenido para proceder con la configuración manual del puerto
sudo systemctl stop slapd || true

step "Moviendo slapd al puerto 1388 (HAProxy tomara el 389)"
sudo sed -i \
    's|SLAPD_SERVICES=.*|SLAPD_SERVICES="ldap://:1388/ ldapi:/// ldaps:///"|' \
    /etc/default/slapd

step "Habilitando TLS con el certificado de la PKI"
sudo cp "${PKI_DIR}/ca/ca.crt" /etc/ldap/ca.crt
	sudo cp "${PKI_DIR}/certs/ldap1.crt" /etc/ldap/ldap1.crt
sudo cp "${PKI_DIR}/certs/ldap1.key" /etc/ldap/ldap1.key
sudo chown openldap:openldap /etc/ldap/ldap1.key /etc/ldap/ldap1.crt /etc/ldap/ca.crt
sudo chmod 640 /etc/ldap/ldap1.key

cat <<EOF > /tmp/tls_config.ldif
dn: cn=config
changetype: modify
replace: olcTLSCACertificateFile
olcTLSCACertificateFile: /etc/ldap/ca.crt
-
replace: olcTLSCertificateFile
olcTLSCertificateFile: /etc/ldap/ldap1.crt
-
replace: olcTLSCertificateKeyFile
olcTLSCertificateKeyFile: /etc/ldap/ldap1.key
EOF

# Reiniciamos para que tome el puerto 1388 definido en /etc/default/slapd
sudo systemctl daemon-reload

sudo systemctl enable slapd

sudo systemctl restart slapd

for i in {1..20}; do

    if [ -S /var/run/slapd/ldapi ]; then
        break
    fi

    sleep 1

done

if [ ! -S /var/run/slapd/ldapi ]; then
    echo "ERROR: ldapi no apareció"
    exit 1
fi
sudo ldapmodify -Y EXTERNAL -H ldapi:// -f /tmp/tls_config.ldif

step "Creando estructura de OUs"
cat <<EOF > /tmp/base_structure.ldif
dn: ou=usuarios,${BASE_DN}
objectClass: organizationalUnit
ou: usuarios

dn: ou=grupos,${BASE_DN}
objectClass: organizationalUnit
ou: grupos
EOF
ldapadd -x -D "cn=admin,${BASE_DN}" -w "${LDAP_ADMIN_PASS}" -H ldap://127.0.0.1:1388 -f /tmp/base_structure.ldif || true

step "Creando usuarios de ejemplo (jperez, malvan, dnoboa)"
cat <<EOF > /tmp/users.ldif
dn: uid=jperez,ou=usuarios,${BASE_DN}
objectClass: inetOrgPerson
objectClass: posixAccount
uid: jperez
sn: Perez
givenName: Juan
cn: Juan Perez
uidNumber: 10001
gidNumber: 5000
loginShell: /bin/bash
homeDirectory: /home/jperez
mail: jperez@${FIS_DOMAIN}

dn: uid=malvan,ou=usuarios,${BASE_DN}
objectClass: inetOrgPerson
objectClass: posixAccount
uid: malvan
sn: Alvan
givenName: M
cn: M Alvan
uidNumber: 10002
gidNumber: 5000
loginShell: /bin/bash
homeDirectory: /home/malvan
mail: malvan@${FIS_DOMAIN}

dn: uid=dnoboa,ou=usuarios,${BASE_DN}
objectClass: inetOrgPerson
objectClass: posixAccount
uid: dnoboa
sn: Noboa
givenName: D
cn: D Noboa
uidNumber: 10003
gidNumber: 5000
loginShell: /bin/bash
homeDirectory: /home/dnoboa
mail: dnoboa@${FIS_DOMAIN}
EOF
ldapadd -x -D "cn=admin,${BASE_DN}" -w "${LDAP_ADMIN_PASS}" -H ldap://127.0.0.1:1388 -f /tmp/users.ldif || true

step "Verificacion"
ldapsearch -x -H ldap://127.0.0.1:1388 -b "${BASE_DN}" "(objectClass=posixAccount)" uid
openssl s_client -connect 127.0.0.1:636 -showcerts </dev/null 2>/dev/null | openssl x509 -noout -subject -issuer

echo "LDAP master listo en el puerto 1388 (ldaps en 636)."
