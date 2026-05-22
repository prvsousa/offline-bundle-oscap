# Criação do Bundle Offline — RHEL 7
## Para administradores / equipa de build

---

## Pré-requisitos

| Requisito | Detalhe |
|---|---|
| Sistema Operativo | Red Hat Enterprise Linux 7 (x86_64) |
| Permissões | root ou sudo |
| Acesso à internet | **Obrigatório** |
| Espaço em disco | Mínimo 6 GB livres em `/tmp` |

> A versão do RHEL 7 desta máquina deve ser igual ou próxima da máquina de destino (ex: ambas 7.9).

---

## Passo 1 — Guardar e executar o script de build

```bash
chmod +x create_bundle.sh
sudo ./create_bundle.sh
```

O script irá automaticamente:
1. Instalar ferramentas necessárias (`yum-utils`, `createrepo`, `repotrack`)
2. Adicionar o repo **EPEL** (necessário para `ansible`)
3. Adicionar o repo **Puppet 7** (necessário para `puppet-agent`)
4. Fazer download de todos os pacotes e dependências via `repotrack`
5. Criar metadados do repositório com `createrepo`
6. Gerar o script `install_offline.sh`
7. Compactar tudo num ficheiro `.tar.gz`

---

## Passo 2 — Resultado esperado

```
/tmp/offline_bundle_rhel7.tar.gz
```

Estrutura interna do bundle:
```
offline_bundle_rhel7/
├── repo/                  # RPMs + metadados do repositório
│   ├── repodata/
│   └── *.rpm
└── install_offline.sh     # Script de instalação (para o utilizador final)
```

---

## Passo 3 — Entregar o bundle

Entregar o ficheiro `offline_bundle_rhel7.tar.gz` à equipa de destino juntamente com o `README_instalacao.md`.

As pessoas que recebem o bundle **não precisam de correr este script** — apenas o `install_offline.sh` que já vem incluído dentro do bundle.

---

## Resolução de problemas (build)

| Erro | Causa provável | Solução |
|---|---|---|
| `repotrack: command not found` | `yum-utils` não instalado | `yum install -y yum-utils` |
| `Cannot retrieve repo EPEL` | Sem acesso à internet | Verificar conectividade |
| `createrepo: command not found` | `createrepo` não instalado | `yum install -y createrepo` |
| Bundle muito pequeno (< 500 MB) | `repotrack` não capturou dependências | Verificar logs e repetir |

---

> **Nota:** Recriar o bundle se a versão do RHEL de destino for significativamente diferente
> ou se passarem mais de 3 meses desde a última geração (pacotes de segurança desatualizados).
