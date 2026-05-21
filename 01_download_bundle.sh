#!/usr/bin/env bash
# =============================================================================
# 01_download_bundle.sh
# Executar numa máquina RHEL 7 com acesso à internet e subscrição ativa.
# Faz download de todos os RPMs necessários para instalar offline:
#   - OpenSCAP (openscap-scanner, scap-security-guide, openscap-utils)
#   - Puppet Agent (puppet-agent via repo Puppetlabs)
#   - Ansible (via rhel-7-server-ansible-2.9-rpms ou Extras + EPEL fallback)
#
# Uso:
#   chmod +x 01_download_bundle.sh
#   sudo ./01_download_bundle.sh
#
# Output:
#   offline-bundle-rhel7-<data>.tar.gz  (diretório atual)
# =============================================================================

set -euo pipefail

# ---------- cores e helpers --------------------------------------------------
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'

info()    { echo -e "${CYAN}[INFO]${NC}  $*"; }
ok()      { echo -e "${GREEN}[OK]${NC}    $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC}  $*"; }
die()     { echo -e "${RED}[ERRO]${NC}  $*" >&2; exit 1; }
section() { echo -e "\n${BOLD}══════════════════════════════════════════${NC}";
            echo -e "${BOLD}  $*${NC}";
            echo -e "${BOLD}══════════════════════════════════════════${NC}"; }

# ---------- pré-condições ----------------------------------------------------
section "Verificações iniciais"

[[ $EUID -eq 0 ]] || die "Execute este script como root (sudo)."

# Verificar RHEL 7
if ! grep -q 'release 7' /etc/redhat-release 2>/dev/null; then
    die "Este script foi concebido para RHEL 7. Sistema: $(cat /etc/redhat-release 2>/dev/null)"
fi
ok "Sistema detectado: $(cat /etc/redhat-release)"

ARCH=$(uname -m)
info "Arquitectura: $ARCH"

# Verificar ligação à internet
if ! curl -s --max-time 8 https://yum.puppet.com > /dev/null 2>&1; then
    die "Sem acesso à internet. Este script requer conectividade para download."
fi
ok "Conectividade à internet confirmada."

# Verificar espaço em disco (mínimo 2GB livres)
FREE_KB=$(df /tmp --output=avail | tail -1)
if [[ $FREE_KB -lt 2097152 ]]; then
    warn "Menos de 2GB livres em /tmp. Pode não ser suficiente para o bundle."
fi

# Instalar yum-utils se necessário (para --downloadonly)
if ! rpm -q yum-utils &>/dev/null; then
    info "A instalar yum-utils (necessário para --downloadonly)..."
    yum install -y yum-utils || die "Falhou instalação de yum-utils."
fi

# ---------- diretórios -------------------------------------------------------
BUNDLE_DATE=$(date +%Y%m%d_%H%M%S)
BUNDLE_DIR="/tmp/offline-bundle-rhel7"
DIR_OPENSCAP="$BUNDLE_DIR/openscap"
DIR_PUPPET="$BUNDLE_DIR/puppet"
DIR_ANSIBLE="$BUNDLE_DIR/ansible"
DIR_METADATA="$BUNDLE_DIR/metadata"

info "Diretório de trabalho: $BUNDLE_DIR"
rm -rf "$BUNDLE_DIR"
mkdir -p "$DIR_OPENSCAP" "$DIR_PUPPET" "$DIR_ANSIBLE" "$DIR_METADATA"

cat > "$DIR_METADATA/source_system.txt" << EOF
Data do bundle: $(date)
Sistema: $(cat /etc/redhat-release)
Arquitectura: $ARCH
Kernel: $(uname -r)
Hostname: $(hostname)
EOF

# ---------- 1. OpenSCAP ------------------------------------------------------
section "1/3 — OpenSCAP"

info "A descarregar openscap-scanner, openscap-utils, scap-security-guide..."
yumdownloader --resolve --destdir="$DIR_OPENSCAP" \
    openscap-scanner \
    openscap-utils \
    scap-security-guide \
    2>&1 | grep -v "^$" || true

COUNT_OSCAP=$(find "$DIR_OPENSCAP" -name "*.rpm" | wc -l)
if [[ $COUNT_OSCAP -eq 0 ]]; then
    # fallback: tentar com --downloadonly
    yum install --downloadonly --downloaddir="$DIR_OPENSCAP" -y \
        openscap-scanner openscap-utils scap-security-guide 2>&1 || true
    COUNT_OSCAP=$(find "$DIR_OPENSCAP" -name "*.rpm" | wc -l)
fi
ok "OpenSCAP: $COUNT_OSCAP RPMs → $DIR_OPENSCAP"

# ---------- 2. Puppet Agent --------------------------------------------------
section "2/3 — Puppet Agent"

PUPPET_REPO_URL="https://yum.puppet.com/puppet7-release-el-7.noarch.rpm"
PUPPET_REPO_RPM="/tmp/puppet7-release-el-7.noarch.rpm"

info "A adicionar repositório Puppetlabs..."
curl -sSL "$PUPPET_REPO_URL" -o "$PUPPET_REPO_RPM" \
    || die "Falhou download do repo Puppetlabs."
rpm -Uvh "$PUPPET_REPO_RPM" 2>/dev/null || true
# Incluir o RPM do repo no bundle (necessário para registar o repo na máquina offline)
cp "$PUPPET_REPO_RPM" "$DIR_PUPPET/puppet7-release-el-7.noarch.rpm"
ok "Repositório Puppetlabs adicionado."

info "A descarregar puppet-agent (pacote all-in-one)..."
yumdownloader --resolve --destdir="$DIR_PUPPET" puppet-agent 2>&1 | grep -v "^$" || true

COUNT_PUPPET=$(find "$DIR_PUPPET" -name "puppet-agent*.rpm" | wc -l)
if [[ $COUNT_PUPPET -eq 0 ]]; then
    warn "yumdownloader falhou. A tentar com --downloadonly..."
    yum install --downloadonly --downloaddir="$DIR_PUPPET" -y puppet-agent 2>&1 || true
    COUNT_PUPPET=$(find "$DIR_PUPPET" -name "puppet-agent*.rpm" | wc -l)
fi

if [[ $COUNT_PUPPET -eq 0 ]]; then
    warn "Não foi possível descarregar puppet-agent via yum. A tentar download direto..."
    # Listar versão disponível e fazer download direto
    PUPPET_RPM=$(curl -s "https://yum.puppet.com/puppet7/el/7/${ARCH}/" \
        | grep -oP 'puppet-agent-[0-9\.\-]+\.el7\.'${ARCH}'\.rpm' \
        | sort -V | tail -1)
    if [[ -n "$PUPPET_RPM" ]]; then
        curl -sSL "https://yum.puppet.com/puppet7/el/7/${ARCH}/${PUPPET_RPM}" \
            -o "$DIR_PUPPET/${PUPPET_RPM}" \
            && ok "Download direto: $PUPPET_RPM" \
            || warn "Falhou download direto de puppet-agent."
    fi
fi

COUNT_PUPPET_TOTAL=$(find "$DIR_PUPPET" -name "*.rpm" | wc -l)
ok "Puppet: $COUNT_PUPPET_TOTAL RPMs → $DIR_PUPPET"

# ---------- 3. Ansible -------------------------------------------------------
section "3/3 — Ansible"

ANSIBLE_OK=false

# Tentativa 1: Canal Red Hat Ansible Engine 2.9
info "Tentativa 1: canal rhel-7-server-ansible-2.9-rpms..."
if subscription-manager repos --enable=rhel-7-server-ansible-2.9-rpms 2>/dev/null; then
    subscription-manager repos --enable=rhel-7-server-extras-rpms 2>/dev/null || true
    yumdownloader --resolve --destdir="$DIR_ANSIBLE" \
        ansible python-jmespath python-six sshpass python2-cryptography 2>&1 | grep -v "^$" || true
    COUNT=$(find "$DIR_ANSIBLE" -name "*.rpm" | wc -l)
    [[ $COUNT -gt 0 ]] && { ok "Ansible via canal oficial: $COUNT RPMs"; ANSIBLE_OK=true; }
fi

# Tentativa 2: Canal Extras
if [[ "$ANSIBLE_OK" == false ]]; then
    info "Tentativa 2: canal rhel-7-server-extras-rpms..."
    if subscription-manager repos --enable=rhel-7-server-extras-rpms 2>/dev/null; then
        yumdownloader --resolve --destdir="$DIR_ANSIBLE" \
            ansible python-jmespath python-six sshpass 2>&1 | grep -v "^$" || true
        COUNT=$(find "$DIR_ANSIBLE" -name "*.rpm" | wc -l)
        [[ $COUNT -gt 0 ]] && { ok "Ansible via Extras: $COUNT RPMs"; ANSIBLE_OK=true; }
    fi
fi

# Tentativa 3: EPEL (fallback)
if [[ "$ANSIBLE_OK" == false ]]; then
    warn "Canais RH não disponíveis. A usar EPEL como fallback..."
    EPEL_RPM="/tmp/epel-release-latest-7.noarch.rpm"
    curl -sSL "https://dl.fedoraproject.org/pub/epel/epel-release-latest-7.noarch.rpm" \
        -o "$EPEL_RPM" || die "Falhou download do EPEL."
    rpm -Uvh "$EPEL_RPM" 2>/dev/null || true
    # Guardar EPEL no bundle (para instalar na máquina offline)
    cp "$EPEL_RPM" "$DIR_ANSIBLE/epel-release-latest-7.noarch.rpm"

    yumdownloader --resolve --destdir="$DIR_ANSIBLE" \
        ansible python-jmespath python-six sshpass python2-cryptography 2>&1 | grep -v "^$" || true
    COUNT=$(find "$DIR_ANSIBLE" -name "*.rpm" | wc -l)
    if [[ $COUNT -gt 0 ]]; then
        ok "Ansible via EPEL: $COUNT RPMs"; ANSIBLE_OK=true
    else
        warn "Não foi possível obter RPMs do Ansible. Verifique os repositórios disponíveis."
    fi
fi

# ---------- Manifesto --------------------------------------------------------
section "Manifesto do bundle"

MANIFEST="$DIR_METADATA/manifest.txt"
{
    echo "=== BUNDLE OFFLINE RHEL 7 — $(date) ==="
    echo "Sistema fonte: $(cat /etc/redhat-release)"
    echo "Arquitectura: $ARCH"
    echo ""
    echo "--- OpenSCAP ($(find "$DIR_OPENSCAP" -name "*.rpm" | wc -l) RPMs) ---"
    find "$DIR_OPENSCAP" -name "*.rpm" -exec basename {} \; | sort
    echo ""
    echo "--- Puppet ($(find "$DIR_PUPPET" -name "*.rpm" | wc -l) RPMs) ---"
    find "$DIR_PUPPET" -name "*.rpm" -exec basename {} \; | sort
    echo ""
    echo "--- Ansible ($(find "$DIR_ANSIBLE" -name "*.rpm" | wc -l) RPMs) ---"
    find "$DIR_ANSIBLE" -name "*.rpm" -exec basename {} \; | sort
    echo ""
    echo "--- Totais ---"
    echo "OpenSCAP : $(find "$DIR_OPENSCAP" -name "*.rpm" | wc -l) RPMs"
    echo "Puppet   : $(find "$DIR_PUPPET"   -name "*.rpm" | wc -l) RPMs"
    echo "Ansible  : $(find "$DIR_ANSIBLE"  -name "*.rpm" | wc -l) RPMs"
    echo "Total    : $(find "$BUNDLE_DIR"   -name "*.rpm" | wc -l) RPMs"
} | tee "$MANIFEST"

# Copiar script de instalação para dentro do bundle
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -f "$SCRIPT_DIR/02_install_offline.sh" ]]; then
    cp "$SCRIPT_DIR/02_install_offline.sh" "$BUNDLE_DIR/"
    chmod +x "$BUNDLE_DIR/02_install_offline.sh"
    ok "Script 02_install_offline.sh incluído no bundle."
else
    warn "02_install_offline.sh não encontrado. Coloque-o na mesma pasta e re-execute, ou copie-o manualmente para o bundle."
fi

# ---------- Empacotar --------------------------------------------------------
section "A criar arquivo tar.gz"

OUTPUT_FILE="$(pwd)/offline-bundle-rhel7-${BUNDLE_DATE}.tar.gz"
tar -czf "$OUTPUT_FILE" -C /tmp "offline-bundle-rhel7"

BUNDLE_SIZE=$(du -sh "$OUTPUT_FILE" | cut -f1)
ok "Bundle criado com sucesso!"
echo ""
echo -e "  Ficheiro : ${BOLD}$OUTPUT_FILE${NC}"
echo -e "  Tamanho  : ${BOLD}$BUNDLE_SIZE${NC}"
echo ""
echo -e "${BOLD}Próximos passos:${NC}"
echo "  1. Copie o bundle para a máquina offline:"
echo "       scp $OUTPUT_FILE user@maquina-offline:/tmp/"
echo ""
echo "  2. Na máquina offline, extraia e execute o instalador:"
echo "       tar -xzf offline-bundle-rhel7-${BUNDLE_DATE}.tar.gz -C /tmp/"
echo "       sudo bash /tmp/offline-bundle-rhel7/02_install_offline.sh"
