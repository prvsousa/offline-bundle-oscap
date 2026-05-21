#!/bin/bash
#
# build-offline-bundle.sh
# Cria um bundle offline para RHEL 7 com OpenSCAP, Puppet e Ansible
# Corre numa máquina RHEL 7 COM internet. Usa repotrack para garantir que
# TODAS as dependências são descarregadas, mesmo as que já estão instaladas.
#
# Uso:  sudo ./build-offline-bundle.sh
#
set -euo pipefail

BUNDLE_DIR="${BUNDLE_DIR:-/var/tmp/offline-bundle}"
ARCH="x86_64"
DATE_TAG="$(date +%Y%m%d)"
TARBALL="/var/tmp/rhel7-offline-bundle-${DATE_TAG}.tar.gz"

echo "==> A preparar diretórios em $BUNDLE_DIR"
mkdir -p "$BUNDLE_DIR"/{openscap,ansible,puppet,repo-bootstrap}

echo "==> A instalar ferramentas (yum-utils, createrepo, wget)"
yum install -y yum-utils createrepo wget

# ----------------------------------------------------------------------
# 1. Garantir que os repos necessários estão configurados
# ----------------------------------------------------------------------

# Repo de extras da RHEL (onde mora o ansible)
echo "==> A activar rhel-7-server-extras-rpms (se aplicável)"
subscription-manager repos --enable=rhel-7-server-extras-rpms 2>/dev/null || \
    echo "    (subscription-manager não disponível ou não-RHEL — ignorar)"

# EPEL — opcional, mas algumas dependências do ansible podem vir daqui
if ! rpm -q epel-release >/dev/null 2>&1; then
    echo "==> A instalar epel-release"
    yum install -y https://dl.fedoraproject.org/pub/epel/epel-release-latest-7.noarch.rpm || true
fi

# Repo do Puppet 7 (última versão com suporte a EL7)
if ! rpm -q puppet7-release >/dev/null 2>&1; then
    echo "==> A instalar puppet7-release"
    rpm -Uvh https://yum.puppet.com/puppet7-release-el-7.noarch.rpm
fi

yum clean all
yum makecache

# ----------------------------------------------------------------------
# 2. Descarregar pacotes + TODAS as dependências
#    (repotrack baixa tudo recursivamente, ao contrário do
#     yumdownloader --resolve que ignora deps já instaladas)
# ----------------------------------------------------------------------

echo "==> A descarregar OpenSCAP + dependências"
repotrack -a "$ARCH" -p "$BUNDLE_DIR/openscap" \
    openscap \
    openscap-scanner \
    openscap-utils \
    scap-security-guide

echo "==> A descarregar Ansible + dependências"
repotrack -a "$ARCH" -p "$BUNDLE_DIR/ansible" ansible

echo "==> A descarregar Puppet agent + dependências"
repotrack -a "$ARCH" -p "$BUNDLE_DIR/puppet" puppet-agent

# ----------------------------------------------------------------------
# 3. Guardar RPMs de bootstrap (releases de repos) — úteis na máquina
#    destino se quiseres mais tarde apontar à internet
# ----------------------------------------------------------------------
echo "==> A guardar pacotes de bootstrap dos repos"
wget -q -P "$BUNDLE_DIR/repo-bootstrap/" \
    https://yum.puppet.com/puppet7-release-el-7.noarch.rpm
wget -q -P "$BUNDLE_DIR/repo-bootstrap/" \
    https://dl.fedoraproject.org/pub/epel/epel-release-latest-7.noarch.rpm || true

# ----------------------------------------------------------------------
# 4. Criar metadata de repositório local em cada pasta
# ----------------------------------------------------------------------
for d in openscap ansible puppet; do
    echo "==> A criar metadata em $BUNDLE_DIR/$d"
    createrepo "$BUNDLE_DIR/$d"
done

# ----------------------------------------------------------------------
# 5. Incluir o script de instalação dentro do bundle
# ----------------------------------------------------------------------
cp -f "$(dirname "$0")/install-offline-bundle.sh" "$BUNDLE_DIR/" 2>/dev/null || true

# ----------------------------------------------------------------------
# 6. Empacotar tudo num tarball
# ----------------------------------------------------------------------
echo "==> A empacotar em $TARBALL"
tar -czf "$TARBALL" -C "$(dirname "$BUNDLE_DIR")" "$(basename "$BUNDLE_DIR")"

echo
echo "==================================================================="
echo "Bundle criado: $TARBALL"
ls -lh "$TARBALL"
echo
echo "Conteúdo:"
du -sh "$BUNDLE_DIR"/*
echo "==================================================================="
echo
echo "Próximos passos:"
echo "  1. Copia $TARBALL para a máquina offline"
echo "  2. Extrai:  tar -xzf $(basename "$TARBALL") -C /var/tmp/"
echo "  3. Corre:   sudo /var/tmp/offline-bundle/install-offline-bundle.sh"
