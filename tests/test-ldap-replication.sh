#!/bin/bash
# Punto 6: Replicacion de LDAP
# Agrega un usuario en el master, verifica que aparezca en la replica,
# detiene el master y confirma que las lecturas siguen funcionando.
set -e

MASTER="ldap://127.0.0.1:1388"
REPLICA="ldap://127.0.0.1:1389"
BASE="dc=fis,dc=epn,dc=ec"
ADMIN="cn=admin,dc=fis,dc=epn,dc=ec"

echo "== Linea base: usuarios actuales en master y replica =="
ldapsearch -x -H "$MASTER" -b "$BASE" "(objectClass=posixAccount)" uid
ldapsearch -x -H "$REPLICA" -b "$BASE" "(objectClass=posixAccount)" uid

echo "== Agregando usuario de prueba en el master =="
TS=$(date +%s)
cat <<EOF > /tmp/test_repl_user.ldif
dn: uid=repltest$TS,ou=usuarios,$BASE
objectClass: inetOrgPerson
objectClass: posixAccount
uid: repltest$TS
sn: Test
cn: Repl Test $TS
uidNumber: 20000
gidNumber: 5000
loginShell: /bin/bash
homeDirectory: /home/repltest$TS
EOF
ldapadd -x -D "$ADMIN" -W -f /tmp/test_repl_user.ldif
date +"%H:%M:%S.%N"

echo "== Verificando propagacion a la replica (espera hasta 10s) =="
sleep 10
ldapsearch -x -H "$REPLICA" -b "$BASE" "(uid=repltest$TS)"
date +"%H:%M:%S.%N"

echo "== Deteniendo el master =="
sudo systemctl stop slapd

echo "== Confirmando que la replica sigue sirviendo lecturas =="
ldapsearch -x -H "$REPLICA" -b "$BASE" "(objectClass=posixAccount)" uid

echo "== Levantando el master de nuevo =="
sudo systemctl start slapd
