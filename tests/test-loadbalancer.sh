#!/bin/bash
# Punto 8: Balanceo de Carga y Failover
# Detiene slapd en el master y verifica que el frontend (HAProxy) sigue disponible.
set -e

BASE="dc=fis,dc=epn,dc=ec"

echo "== Linea base via balanceador (ldap.fis.epn.edu.ec:389) =="
ldapsearch -x -H ldap://ldap.fis.epn.edu.ec -b "$BASE" -s base

echo "== Deteniendo slapd en el master =="
date +"%H:%M:%S.%N"
sudo systemctl stop slapd

echo "== Verificando disponibilidad via balanceador (debe servir desde la replica) =="
ldapsearch -x -H ldap://ldap.fis.epn.edu.ec -b "$BASE" "(objectClass=posixAccount)" uid
date +"%H:%M:%S.%N"

echo "== Panel de estadisticas: http://<IP-WSL>:8404/stats =="

echo "== Levantando el master de nuevo =="
sudo systemctl start slapd
sleep 3
ldapsearch -x -H ldap://ldap.fis.epn.edu.ec -b "$BASE" -s base
