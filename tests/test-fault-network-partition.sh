#!/bin/bash
# Punto 9.2: Particion de red (iptables DROP) sobre el puerto de ldap1
set -e
BASE="dc=fis,dc=epn,dc=ec"

echo "== Linea base =="
ldapsearch -x -H ldap://127.0.0.1:1388 -b "$BASE" -s base

echo "== Aplicando particion de red (DROP puerto 1388) =="
date +"%H:%M:%S.%N"
sudo iptables -A INPUT -p tcp --dport 1388 -j DROP

echo "== Acceso directo a ldap1 debe hacer timeout =="
timeout 3 ldapsearch -x -H ldap://127.0.0.1:1388 -b "$BASE" -s base || echo "Timeout confirmado (exit $?)"

echo "== Verificando disponibilidad via balanceador =="
ldapsearch -x -H ldap://ldap.fis.epn.edu.ec -b "$BASE" "(objectClass=posixAccount)" uid
date +"%H:%M:%S.%N"

echo "== Retirando la regla de particion =="
sudo iptables -D INPUT -p tcp --dport 1388 -j DROP
ldapsearch -x -H ldap://127.0.0.1:1388 -b "$BASE" -s base
