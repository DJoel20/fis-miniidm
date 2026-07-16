#!/bin/bash
# Punto 9.1: Crash del servidor (kill -9) sobre ldap1 (master)
set -e
BASE="dc=fis,dc=epn,dc=ec"

sudo systemctl start slapd 2>/dev/null || true
sleep 2

echo "== Linea base =="
ldapsearch -x -H ldap://127.0.0.1:1388 -b "$BASE" -s base

PID=$(ps aux | grep "slapd -h ldap://127.0.0.1:1388" | grep -v grep | awk '{print $2}')
echo "== Matando slapd (PID $PID) con kill -9 =="
date +"%H:%M:%S.%N"
sudo kill -9 "$PID"

echo "== Verificando disponibilidad via balanceador =="
ldapsearch -x -H ldap://ldap.fis.epn.edu.ec -b "$BASE" "(objectClass=posixAccount)" uid
date +"%H:%M:%S.%N"

sudo systemctl start slapd
