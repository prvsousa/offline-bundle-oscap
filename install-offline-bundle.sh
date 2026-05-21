#!/bin/bash
#
# install-offline-bundle.sh
# Instala OpenSCAP, Ansible e Puppet a partir do bundle offline.
# Corre na máquina SEM internet, depois de extrair o tarball.
#
# Uso:  sudo ./install-offline-bundle.sh [caminho-do-bundle]
#       (por defeito: /var/tmp/offline-bundle)
#
set -euo pipefail

BUNDLE_DIR="${1:-/var/tmp/offline-bundle}"

if [[ ! -d "$BUNDLE_DIR" ]]; then
    echo "ERRO: $BUNDLE_DIR não existe. Extrai o tarball primeiro." >&2
    exit 1
fi

# Verificação rápida — as três pastas têm de ter repodata
for d in openscap ansible puppet; do
    if [[ ! -d "$BUNDLE_DIR/$d/repodata" ]]; then
        echo "ERRO: $BUNDLE_DIR/$d não tem repodata. Bundle incompleto?" >&2
        exit 1
    fi
done

echo "==> A configurar repos locais a partir de $BUNDLE_DIR"
cat > /etc/yum.repos.d/offline-bundle.repo <<EOF
[offline-openscap]
name=Offline OpenSCAP bundle
baseurl=file://$BUNDLE_DIR/openscap
enabled=1
gpgcheck=0

[offline-ansible]
name=Offline Ansible bundle
baseurl=file://$BUNDLE_DIR/ansible
enabled=1
gpgcheck=0

[offline-puppet]
name=Offline Puppet bundle
baseurl=file://$BUNDLE_DIR/puppet
enabled=1
gpgcheck=0
EOF

yum clean all
yum makecache --disablerepo="*" --enablerepo="offline-*"

echo "==> A instalar pacotes (apenas dos repos offline)"
yum --disablerepo="*" --enablerepo="offline-*" install -y \
    openscap \
    openscap-scanner \
    openscap-utils \
    scap-security-guide \
    ansible \
    puppet-agent

echo
echo "==================================================================="
echo "Instalação concluída. Verificações:"
echo "-------------------------------------------------------------------"
oscap --version | head -1     || true
ansible --version | head -1   || true
/opt/puppetlabs/bin/puppet --version 2>/dev/null || true
echo "==================================================================="
