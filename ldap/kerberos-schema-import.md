# Importar el esquema de Kerberos en OpenLDAP

Necesario para el punto 4 (Integracion LDAP-Kerberos): agrega el objectClass
`krbPrincipalAux` y el atributo `krbPrincipalName`, que se usan para anotar en cada
entrada de usuario cual es su principal Kerberos correspondiente.

**Debe aplicarse tanto en el master como en la replica.** Si se aplica solo en el
master, `syncrepl` en la replica rechaza las entradas de usuario con un error de
sintaxis sobre `krbPrincipalAux`, visible unicamente en el log de debug de la replica
(`slapd -d sync`).

## Pasos

```bash
sudo apt install -y krb5-kdc-ldap
gunzip -k /usr/share/doc/krb5-kdc-ldap/kerberos.openldap.ldif.gz -c > /tmp/kerberos.openldap.ldif

# Si el paquete no incluye documentacion (imagenes minimalistas / contenedores Docker),
# copiar el archivo desde un host donde si este disponible:
#   docker cp /usr/share/doc/krb5-kdc-ldap/kerberos.openldap.ldif.gz <contenedor>:/tmp/

ldapadd -Y EXTERNAL -H ldapi:// -f /tmp/kerberos.openldap.ldif
```

## Verificar

```bash
ldapsearch -Y EXTERNAL -H ldapi:// -b "cn=schema,cn=config" "(cn=*kerberos*)" dn
```

## Anotar el principal en cada usuario

```ldif
dn: uid=jperez,ou=usuarios,dc=fis,dc=epn,dc=ec
changetype: modify
add: objectClass
objectClass: krbPrincipalAux
-
add: krbPrincipalName
krbPrincipalName: jperez@FIS.EPN.EC
```

```bash
ldapmodify -x -D "cn=admin,dc=fis,dc=epn,dc=ec" -W -f add_krb_attrs.ldif
```
