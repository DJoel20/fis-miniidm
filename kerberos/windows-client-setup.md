# Configuracion del cliente Windows para SSO Kerberos (MIT Kerberos for Windows + Firefox)

Para que el flujo Browser -> Kerberos Ticket -> Web Service funcione desde un cliente
Windows sin pedir usuario/contrasena, se necesitan tres ajustes. Sin ellos, el navegador
cae a NTLM o construye un Service Principal Name (SPN) incorrecto y el servidor responde
401, aunque el ticket Kerberos se haya obtenido correctamente.

## 1. C:\ProgramData\MIT\Kerberos5\krb5.ini

```ini
[libdefaults]
    default_realm = FIS.EPN.EC
    dns_lookup_kdc = false
    dns_lookup_realm = false
    rdns = false
    dns_canonicalize_hostname = false

[realms]
    FIS.EPN.EC = {
        kdc = <IP_DEL_HOST_WSL>
        admin_server = <IP_DEL_HOST_WSL>
    }

[domain_realm]
    .fis.epn.edu.ec = FIS.EPN.EC
    fis.epn.edu.ec = FIS.EPN.EC
```

`rdns=false` y `dns_canonicalize_hostname=false` evitan que la libreria MIT intente
"corregir" el hostname via resolucion DNS antes de construir el SPN.

## 2. C:\Windows\System32\drivers\etc\hosts

Cada hostname debe estar en su propia linea. Si varios nombres comparten una linea con
la misma IP, Windows puede devolver un nombre canonico distinto al que el navegador
solicita, y el ticket se pide para el SPN equivocado (por ejemplo `HTTP/fis.epn.ec` en
vez de `HTTP/webserver.fis.epn.edu.ec`).

```
<IP_DEL_HOST_WSL>    webserver.fis.epn.edu.ec
<IP_DEL_HOST_WSL>    ldap1.fis.epn.edu.ec
<IP_DEL_HOST_WSL>    kdc1.fis.epn.edu.ec
```

## 3. Firefox — about:config

Por defecto Firefox usa el stack SSPI nativo de Windows para SPNEGO, que puede caer
silenciosamente a NTLM. Como el servidor Apache esta restringido a
`GssapiAllowedMech krb5` (sin NTLM), esos intentos se rechazan con 401 generico.

| Clave | Valor |
|---|---|
| `network.negotiate-auth.trusted-uris` | `webserver.fis.epn.edu.ec` |
| `network.auth.use-sspi` | `false` |
| `network.negotiate-auth.using-native-gsslib` | `false` |
| `network.negotiate-auth.gsslib` | `C:\Program Files\MIT\Kerberos\bin\gssapi64.dll` |

## Verificacion

```cmd
kinit jperez@FIS.EPN.EC
klist
```

Luego, en Firefox: `https://webserver.fis.epn.edu.ec/seguro/` debe cargar directamente
sin prompt de usuario/contrasena.

Para diagnosticar sin pasar por el navegador, `curl --negotiate` desde un cliente Linux
con ticket valido es la forma mas rapida de confirmar que el servidor esta bien
configurado antes de depurar el lado de Windows:

```bash
kinit jperez@FIS.EPN.EC
curl -v --negotiate -u : https://webserver.fis.epn.edu.ec/seguro/ -k
```
