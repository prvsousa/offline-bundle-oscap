#!/bin/bash
set -e

BASE_DIR="/tmp/offline_bundle_rhel7"
REPO_DIR="$BASE_DIR/repo"

echo "[+] Criar diretórios..."
mkdir -p "$REPO_DIR"

echo "[+] Instalar ferramentas necessárias..."
yum install -y yum-utils createrepo

# EPEL (necessário para ansible)
if ! rpm -q epel-release &>/dev/null; then
  echo "[+] Instalar EPEL..."
  yum install -y https://dl.fedoraproject.org/pub/epel/epel-release-latest-7.noarch.rpm
fi

# Puppet repo (necessário para puppet-agent)
if ! rpm -q puppet7-release &>/dev/null; then
  echo "[+] Instalar repo Puppet..."
  rpm -Uvh https://yum.puppet.com/puppet7-release-el-7.noarch.rpm
fi

echo "[+] Limpar cache yum..."
yum clean all
yum makecache

echo "[+] Download de pacotes e dependências (com repotrack)..."
PACKAGES=(
  openscap-scanner
  scap-security-guide
  ansible
  puppet-agent
)

for pkg in "${PACKAGES[@]}"; do
  echo "  -> $pkg"
  repotrack -a x86_64 -p "$REPO_DIR" "$pkg"
done

echo "[+] Criar repositório local..."
createrepo "$REPO_DIR"

echo "[+] Criar script de instalação offline..."
cat << 'EOF' > "$BASE_DIR/install_offline.sh"
#!/bin/bash
set -e

REPO_SRC="$(dirname "$0")/repo"
REPO_DST="/opt/offline_repo"

echo "[+] Copiar repo para $REPO_DST..."
mkdir -p "$REPO_DST"
cp -r "$REPO_SRC"/. "$REPO_DST/"

echo "[+] Criar ficheiro repo local..."
cat << EOL > /etc/yum.repos.d/offline.repo
[offline-repo]
name=Offline Repo
baseurl=file://${REPO_DST}
enabled=1
gpgcheck=0
priority=1
EOL

# Desativar outros repos para evitar conflitos
echo "[+] Desativar repos externos..."
yum-config-manager --disable \* 2>/dev/null || true
yum-config-manager --enable offline-repo

echo "[+] Limpar cache yum..."
yum clean all

echo "[+] Instalar pacotes..."
yum install -y openscap-scanner scap-security-guide ansible puppet-agent

echo "[+] Instalação concluída com sucesso!"
EOF
chmod +x "$BASE_DIR/install_offline.sh"

echo "[+] Compactar bundle..."
tar -czf /tmp/offline_bundle_rhel7.tar.gz -C /tmp offline_bundle_rhel7/

echo "[+] Bundle criado: /tmp/offline_bundle_rhel7.tar.gz"
echo "[+] Próximo passo: transferir para a máquina offline e executar install_offline.sh como root"
