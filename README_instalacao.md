# Instalação Offline — RHEL 7
## Pacotes incluídos: `openscap-scanner` · `scap-security-guide` · `ansible` · `puppet-agent`

---

## Pré-requisitos

| Requisito | Detalhe |
|---|---|
| Sistema Operativo | Red Hat Enterprise Linux 7 (x86_64) |
| Permissões | root ou sudo |
| Espaço em disco | Mínimo 4 GB livres em `/opt` |
| Acesso à internet | **Não necessário** |

---

## Passo 1 — Transferir o bundle

Escolher um dos métodos:

**Via SCP:**
```bash
scp offline_bundle_rhel7.tar.gz user@maquina-offline:/tmp/
```

**Via USB/Pendrive:**
```bash
cp /media/usb/offline_bundle_rhel7.tar.gz /tmp/
```

---

## Passo 2 — Extrair

```bash
cd /tmp
tar -xzf offline_bundle_rhel7.tar.gz
cd offline_bundle_rhel7
```

---

## Passo 3 — Instalar

```bash
sudo ./install_offline.sh
```

O script trata de tudo automaticamente:
- Copia o repositório para `/opt/offline_repo`
- Cria o ficheiro de repo em `/etc/yum.repos.d/`
- Desativa repositórios externos
- Instala os pacotes

---

## Passo 4 — Verificar

```bash
rpm -q openscap-scanner scap-security-guide ansible puppet-agent
```

Saída esperada:
```
openscap-scanner-x.x.x-x.el7.x86_64
scap-security-guide-x.x.x-x.el7.noarch
ansible-x.x.x-x.el7.noarch
puppet-agent-x.x.x-x.el7.x86_64
```

---

## Resolução de problemas

| Erro | Causa provável | Solução |
|---|---|---|
| `No package X available` | Dependência em falta | Contactar quem gerou o bundle |
| `conflicts with package Y` | Versão incompatível | Contactar quem gerou o bundle |
| `Permission denied` | Não é root | `sudo ./install_offline.sh` ou `su -` |
| `No space left on device` | Pouco espaço em `/opt` | Libertar espaço ou contactar administrador |

---

## Restaurar repositórios originais (opcional)

Após a instalação, para reativar os repos originais do RHEL:

```bash
rm -f /etc/yum.repos.d/offline.repo
yum-config-manager --enable rhel-7-server-rpms
yum clean all
```

---

> **Nota:** Este bundle é para arquitetura `x86_64` em RHEL 7.
> Não é compatível com RHEL 8/9 nem com arquiteturas ARM.
