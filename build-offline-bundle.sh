#!/bin/bash
#
# build-offline-bundle.sh
# Cria um bundle offline com OpenSCAP, Ansible e Puppet para instalação
# numa máquina RHEL 7 / Oracle Linux 7 sem internet.
#
# Corre numa máquina Oracle Linux 7 (ou RHEL 7) COM internet.
# Usa repotrack para garantir que TODAS as dependências são descarregadas,
# mesmo as que já estão instaladas na máquina origem.
#
# Uso:  sudo ./build-offline-bundle.sh
#
set -euo pipefail

BASE_DIR="${BASE_DIR:-/var/tmp/offline_bundle_rhel7}"
REPO_DIR="$BASE_DIR/repo"
ARCH="x86_64"
DATE_TAG="$(date +%Y%m%d)"
TARBALL="/var/tmp/offline_bundle_rhel7-${DATE_TAG}.tar.gz"

PACKAGES=(
    openscap
    openscap-scanner
    openscap-utils
    scap-security-guide
    ansible
    puppet-agent
)

# ----------------------------------------------------------------------
# 1. Preparar diretórios e ferramentas
# ----------------------------------------------------------------------
echo "[+] Criar diretórios em $BASE_DIR"
mkdir -p "$REPO_DIR"

echo "[+] Instalar ferramentas necessárias (yum-utils, createrepo)"
yum install -y yum-utils createrepo

# ----------------------------------------------------------------------
# 2. Configurar repos onde moram os pacotes
#    - openscap/scap-security-guide → ol7_latest (já activo por defeito)
#    - ansible                       → ol7_developer_EPEL (precisa do
#                                       pacote oracle-epel-release-el7)
#    - puppet-agent                  → repo oficial yum.puppet.com
# ----------------------------------------------------------------------
echo "[+] Configurar EPEL do Oracle (para o ansible)"
if ! rpm -q oracle-epel-release-el7 &>/dev/null; then
    yum install -y oracle-epel-release-el7
fi
yum-config-manager --enable ol7_developer_EPEL >/dev/null

echo "[+] Configurar repo do Puppet 7"
if ! rpm -q puppet7-release &>/dev/null; then
    rpm -Uvh https://yum.puppet.com/puppet7-release-el-7.noarch.rpm
fi

echo "[+] Limpar cache yum e regenerar"
yum clean all
yum makecache

# Sanity check — todos os pacotes têm de estar visíveis nos repos
echo "[+] Verificar que todos os pacotes estão disponíveis"
for pkg in "${PACKAGES[@]}"; do
    if ! yum -q list "$pkg" &>/dev/null; then
        echo "ERRO: pacote '$pkg' não encontrado em nenhum repo activo." >&2
        echo "      Verifica 'yum repolist' e 'yum list $pkg'." >&2
        exit 1
    fi
done

# ----------------------------------------------------------------------
# 3. Descarregar pacotes + TODAS as dependências (recursivamente)
#    repotrack baixa também o que já está instalado na máquina origem,
#    ao contrário de yumdownloader --resolve.
# ----------------------------------------------------------------------
echo "[+] Download de pacotes e dependências com repotrack"
for pkg in "${PACKAGES[@]}"; do
    echo "  -> $pkg"
    repotrack -a "$ARCH" -p "$REPO_DIR" "$pkg"
done

# ----------------------------------------------------------------------
# 4. Gerar metadata do repositório local
# ----------------------------------------------------------------------
echo "[+] Criar metadata do repositório (createrepo)"
createrepo "$REPO_DIR"

# ----------------------------------------------------------------------
# 5. Embutir script de instalação dentro do bundle
# ----------------------------------------------------------------------
echo "[+] Criar script de instalação offline"
cat > "$BASE_DIR/install_offline.sh" <<'INSTALL_EOF'
#!/bin/bash
#
# install_offline.sh
# Instala OpenSCAP, Ansible e Puppet a partir do bundle offline.
# Corre na máquina RHEL 7 / OL 7 SEM internet, depois de extrair o tarball.
#
# Uso:  sudo ./install_offline.sh
#
set -euo pipefail

# Resolve caminho absoluto da pasta onde está este script
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$SCRIPT_DIR/repo"

if [[ ! -d "$REPO_DIR/repodata" ]]; then
    echo "ERRO: $REPO_DIR não contém repodata. Bundle incompleto?" >&2
    exit 1
fi

echo "[+] Configurar repo local em $REPO_DIR"
cat > /etc/yum.repos.d/offline-bundle.repo <<EOF
[offline-bundle]
name=Offline bundle (OpenSCAP + Ansible + Puppet)
baseurl=file://$REPO_DIR
enabled=1
gpgcheck=0
EOF

echo "[+] Limpar cache yum"
yum clean all

echo "[+] Instalar pacotes (só a partir do repo offline)"
yum --disablerepo='*' --enablerepo='offline-bundle' install -y \
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
oscap --version    2>/dev/null | head -1 || echo "oscap: não encontrado"
ansible --version  2>/dev/null | head -1 || echo "ansible: não encontrado"
/opt/puppetlabs/bin/puppet --version 2>/dev/null \
    || echo "puppet: não encontrado em /opt/puppetlabs/bin"
echo "==================================================================="
INSTALL_EOF
chmod +x "$BASE_DIR/install_offline.sh"

# ----------------------------------------------------------------------
# 6. Empacotar tudo num tarball
# ----------------------------------------------------------------------
echo "[+] Empacotar bundle em $TARBALL"
tar -czf "$TARBALL" -C "$(dirname "$BASE_DIR")" "$(basename "$BASE_DIR")"

# ----------------------------------------------------------------------
# Resumo final
# ----------------------------------------------------------------------
echo
echo "==================================================================="
echo "Bundle criado: $TARBALL"
ls -lh "$TARBALL"
echo
echo "Tamanho do conteúdo:"
du -sh "$BASE_DIR"
echo "Nº de RPMs:"
find "$REPO_DIR" -name '*.rpm' | wc -l
echo "==================================================================="
echo
echo "Próximos passos na máquina offline:"
echo "  1. Copia $TARBALL para a máquina destino"
echo "  2. Extrai:  tar -xzf $(basename "$TARBALL") -C /var/tmp/"
echo "  3. Corre:   sudo /var/tmp/offline_bundle_rhel7/install_offline.sh"
