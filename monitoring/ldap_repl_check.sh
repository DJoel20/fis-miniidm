#!/bin/bash
# Calcula el retraso de replicacion LDAP comparando el contextCSN del master
# y de la replica, y lo expone como metrica de Prometheus via textfile collector.
OUTPUT_FILE="/var/lib/node_exporter/textfile_collector/ldap_repl.prom"
TMP_FILE="${OUTPUT_FILE}.$$"

CSN_MASTER=$(ldapsearch -x -H ldap://127.0.0.1:1388 -b "dc=fis,dc=epn,dc=ec" -s base contextCSN 2>/dev/null | grep contextCSN | awk '{print $2}')
CSN_REPLICA=$(ldapsearch -x -H ldap://127.0.0.1:1389 -b "dc=fis,dc=epn,dc=ec" -s base contextCSN 2>/dev/null | grep contextCSN | awk '{print $2}')

parse_csn_epoch() {
    local csn="$1"
    local ts="${csn:0:14}"
    date -u -d "${ts:0:4}-${ts:4:2}-${ts:6:2} ${ts:8:2}:${ts:10:2}:${ts:12:2}" +%s 2>/dev/null
}

MASTER_UP=0
REPLICA_UP=0
LAG=0

if [ -n "$CSN_MASTER" ]; then MASTER_UP=1; fi
if [ -n "$CSN_REPLICA" ]; then REPLICA_UP=1; fi

if [ -n "$CSN_MASTER" ] && [ -n "$CSN_REPLICA" ]; then
    T_MASTER=$(parse_csn_epoch "$CSN_MASTER")
    T_REPLICA=$(parse_csn_epoch "$CSN_REPLICA")
    LAG=$((T_MASTER - T_REPLICA))
fi

cat > "$TMP_FILE" <<EOF
# HELP ldap_replication_lag_seconds Diferencia de tiempo entre contextCSN de master y replica
# TYPE ldap_replication_lag_seconds gauge
ldap_replication_lag_seconds ${LAG}
# HELP ldap_master_up Estado del servidor LDAP master (1=up, 0=down)
# TYPE ldap_master_up gauge
ldap_master_up ${MASTER_UP}
# HELP ldap_replica_up Estado del servidor LDAP replica (1=up, 0=down)
# TYPE ldap_replica_up gauge
ldap_replica_up ${REPLICA_UP}
EOF

mv "$TMP_FILE" "$OUTPUT_FILE"
