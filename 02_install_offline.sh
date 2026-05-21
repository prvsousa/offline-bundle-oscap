#!/usr/bin/env bash
# =============================================================================
# 02_install_offline.sh
# Executar na máquina offline (RHEL 7) DEPOIS de copiar e extrair o bundle.
#
# Uso:
#   tar -xzf offline-bundle-rhel7-*.tar.gz -C /tmp/
#   sudo bash /tmp/offline-bundle-rhel7/02_install_offline.sh
#
# O script deve ser executado a partir do diretório do bundle, ou o bundle
# deve estar em /tmp/offline-bundle-rhel7/ (localização padrão).
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

# ---------- localizar bundle -------------------------------------------------
# O script tenta detetar onde está o bundle automaticamente.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ -d "$SCRIPT_DIR/openscap" ]]; then
    BUNDLE_DIR="$SCRIPT_DIR"
elif [[ -d "/tmp/offline-bundle-rhel7/openscap" ]]; then
    BUNDLE_DIR="/tmp/offline-bundle-rhel7"
else
    die "Não foi possível localizar o bundle. Certifique-se que extraiu o tar.gz para /tmp/."
fi

DIR_OPENSCAP="$BUNDLE_DIR/openscap"
DIR_PUPPET="$BUNDLE_DIR/puppet"
DIR_ANSIBLE="$BUNDLE_DIR/ansible"
DIR_METADATA="$BUNDLE_DIR/metadata"

LOG_FILE="/var/log/install_offline_bundle.log"

# ---------- pré-condições ----------------------------------------------------
section "Verificações iniciais"

[[ $EUID -eq 0 ]] || die "Execute este script como root (sudo)."

# RHEL 7
if ! grep -q 'release 7' /etc/redhat-release 2>/dev/null; then
    die "Este script foi concebido para RHEL 7. Sistema: $(cat /etc/redhat-release 2>/dev/null)"
fi
ok "Sistema detectado: $(cat /etc/redhat-release)"

ARCH=$(uname -m)
info "Arquitectura: $ARCH"
info "Bundle em: $BUNDLE_DIR"
info "Log: $LOG_FILE"

# Garantir que NÃO há acesso à internet (aviso apenas, não bloqueia)
if curl -s --max-time 3 https://yum.puppet.com > /dev/null 2>&1; then
    warn "Esta máquina TEM acesso à internet. O script funciona igualmente, mas foi desenhado para ambientes offline."
else
    ok "Modo offline confirmado (sem acesso à internet)."
fi

# Verificar estrutura do bundle
[[ -d "$DIR_OPENSCAP" ]] || die "Diretório openscap não encontrado em $BUNDLE_DIR"
[[ -d "$DIR_PUPPET"   ]] || die "Diretório puppet não encontrado em $BUNDLE_DIR"
[[ -d "$DIR_ANSIBLE"  ]] || die "Diretório ansible não encontrado em $BUNDLE_DIR"

# Mostrar manifesto se existir
if [[ -f "$DIR_METADATA/manifest.txt" ]]; then
    info "Manifesto do bundle:"
    cat "$DIR_METADATA/manifest.txt"
fi

# Verificar espaço em disco (mínimo 1GB)
FREE_KB=$(df / --output=avail | tail -1)
if [[ $FREE_KB -lt 1048576 ]]; then
    warn "Menos de 1GB livre em /. A instalação pode falhar."
fi

# Criar repo local temporário com createrepo (se disponível) ou usar localinstall
USE_CREATEREPO=false
if command -v createrepo &>/dev/null; then
    USE_CREATEREPO=true
    info "createrepo disponível — a usar repositório local (mais robusto)."
else
    info "createrepo não disponível — a usar yum localinstall."
fi

# Função de instalação com fallback
install_rpms() {
    local label="$1"
    local dir="$2"
    local required_bin="$3"   # binário para verificar se já está instalado
    local verify_cmd="$4"     # comando para verificar versão após instalação

    section "$label"

    local count
    count=$(find "$dir" -name "*.rpm" ! -name "*.src.rpm" | wc -l)

    if [[ $count -eq 0 ]]; then
        warn "Nenhum RPM encontrado em $dir. A ignorar $label."
        return 0
    fi

    info "$count RPMs encontrados em $dir"

    # Verificar se já está instalado
    if command -v "$required_bin" &>/dev/null; then
        warn "$required_bin já está instalado. A tentar actualizar..."
    fi

    # Desactivar todos os repos online temporariamente para forçar instalação local
    local YUM_OPTS="--disablerepo=* --nogpgcheck"

    if [[ "$USE_CREATEREPO" == true ]]; then
        # Criar repo local
        local REPO_DIR="$dir"
        createrepo --quiet "$REPO_DIR" 2>/dev/null || createrepo "$REPO_DIR"

        local REPO_ID="offline_${label// /_}"
        cat > "/etc/yum.repos.d/${REPO_ID}.repo" << EOF
[${REPO_ID}]
name=Offline Bundle - ${label}
baseurl=file://${REPO_DIR}
enabled=1
gpgcheck=0
EOF
        info "A instalar via repo local..."
        # shellcheck disable=SC2086
        if yum install $YUM_OPTS --enablerepo="$REPO_ID" -y \
            $(find "$dir" -name "*.rpm" ! -name "*.src.rpm" -exec rpm -qp --queryformat '%{NAME}' {} \; 2>/dev/null | sort -u | tr '\n' ' ') \
            >> "$LOG_FILE" 2>&1; then
            ok "$label instalado via repo local."
        else
            warn "Repo local falhou. A tentar localinstall..."
            # shellcheck disable=SC2086
            yum localinstall $YUM_OPTS -y "$dir"/*.rpm >> "$LOG_FILE" 2>&1 || \
                rpm -Uvh --nodeps "$dir"/*.rpm >> "$LOG_FILE" 2>&1 || \
                warn "$label: instalação com erros. Ver $LOG_FILE"
        fi
        # Limpar repo temporário
        rm -f "/etc/yum.repos.d/${REPO_ID}.repo"
    else
        info "A instalar via yum localinstall..."
        # shellcheck disable=SC2086
        if yum localinstall $YUM_OPTS -y "$dir"/*.rpm >> "$LOG_FILE" 2>&1; then
            ok "$label instalado via localinstall."
        else
            warn "yum localinstall falhou. A tentar rpm -Uvh direto..."
            rpm -Uvh --nodeps "$dir"/*.rpm >> "$LOG_FILE" 2>&1 || \
                warn "$label: alguns pacotes com erros. Ver $LOG_FILE"
        fi
    fi

    # Verificar instalação
    echo ""
    info "Verificação:"
    if eval "$verify_cmd" 2>/dev/null; then
        ok "$label: verificação OK."
    else
        warn "$label: binário não encontrado no PATH após instalação. Pode requerer ajuste do PATH."
    fi
}

# ---------- Inicializar log --------------------------------------------------
{
    echo "=== Instalação offline RHEL 7 — $(date) ==="
    echo "Sistema: $(cat /etc/redhat-release)"
    echo "Bundle: $BUNDLE_DIR"
    echo ""
} > "$LOG_FILE"

# ---------- 1. OpenSCAP ------------------------------------------------------
install_rpms \
    "OpenSCAP" \
    "$DIR_OPENSCAP" \
    "oscap" \
    "oscap --version"

# Verificação adicional: SCAP content
if [[ -d /usr/share/xml/scap/ssg/content ]]; then
    ok "SCAP Security Guide content disponível em /usr/share/xml/scap/ssg/content/"
    ls /usr/share/xml/scap/ssg/content/*.xml 2>/dev/null | head -3 | while read -r f; do
        info "  $(basename "$f")"
    done
else
    warn "scap-security-guide content não encontrado. Instale o pacote scap-security-guide."
fi

# ---------- 2. Puppet Agent --------------------------------------------------

# Registar o repo do Puppetlabs (sem internet, apenas para o RPM ficar registado)
PUPPET_REPO_RPM=$(find "$DIR_PUPPET" -name "puppet*release*.rpm" | head -1)
if [[ -n "$PUPPET_REPO_RPM" ]]; then
    info "A registar repositório Puppetlabs (sem acesso à internet)..."
    rpm -Uvh "$PUPPET_REPO_RPM" 2>/dev/null || true
    # Desactivar o repo online (não tem internet)
    if [[ -f /etc/yum.repos.d/puppet7.repo ]]; then
        sed -i 's/^enabled=1/enabled=0/' /etc/yum.repos.d/puppet7.repo
        info "Repo Puppetlabs online desactivado (máquina offline)."
    fi
fi

install_rpms \
    "Puppet Agent" \
    "$DIR_PUPPET" \
    "puppet" \
    "/opt/puppetlabs/bin/puppet --version"

# Adicionar puppet ao PATH permanentemente
PUPPET_BIN="/opt/puppetlabs/bin"
if [[ -d "$PUPPET_BIN" ]]; then
    if ! grep -q "puppetlabs/bin" /etc/profile.d/*.sh 2>/dev/null; then
        echo "export PATH=\$PATH:$PUPPET_BIN" > /etc/profile.d/puppet.sh
        ok "Puppet adicionado ao PATH global (/etc/profile.d/puppet.sh)"
    fi
    export PATH="$PATH:$PUPPET_BIN"
fi

# ---------- 3. Ansible -------------------------------------------------------

# Se existe RPM do EPEL no bundle, instalar primeiro (sem internet, apenas regista o pacote)
EPEL_RPM=$(find "$DIR_ANSIBLE" -name "epel-release*.rpm" | head -1)
if [[ -n "$EPEL_RPM" ]]; then
    info "A instalar epel-release (ficheiro local, sem internet)..."
    rpm -Uvh "$EPEL_RPM" 2>/dev/null || true
    # Desactivar repos EPEL online (sem internet)
    for f in /etc/yum.repos.d/epel*.repo; do
        [[ -f "$f" ]] && sed -i 's/^enabled=1/enabled=0/' "$f"
    done
    info "Repos EPEL online desactivados (máquina offline)."
fi

install_rpms \
    "Ansible" \
    "$DIR_ANSIBLE" \
    "ansible" \
    "ansible --version"

# ---------- Verificação final ------------------------------------------------
section "Verificação final completa"

PASS=0; FAIL=0

check() {
    local label="$1"; local cmd="$2"
    if eval "$cmd" &>/dev/null; then
        echo -e "  ${GREEN}✔${NC}  $label"
        ((PASS++))
    else
        echo -e "  ${RED}✘${NC}  $label"
        ((FAIL++))
    fi
}

check "oscap disponível"           "command -v oscap"
check "oscap versão OK"            "oscap --version"
check "scap-security-guide"        "test -d /usr/share/xml/scap/ssg/content"
check "puppet disponível"          "command -v puppet || /opt/puppetlabs/bin/puppet --version"
check "puppet-agent serviço"       "systemctl list-unit-files puppet.service"
check "ansible disponível"         "command -v ansible"
check "ansible-playbook"           "command -v ansible-playbook"
check "python para ansible"        "python --version || python2 --version"

echo ""
echo -e "  Resultado: ${GREEN}$PASS passou(aram)${NC}  /  ${RED}$FAIL falhou(aram)${NC}"

if [[ $FAIL -gt 0 ]]; then
    warn "Alguns componentes podem não ter sido instalados correctamente."
    warn "Consulte o log em: $LOG_FILE"
fi

# ---------- Resumo -----------------------------------------------------------
section "Instalação concluída"

echo ""
echo -e "${BOLD}Comandos úteis pós-instalação:${NC}"
echo ""
echo "  # OpenSCAP — verificar conformidade com perfil PCI-DSS:"
echo "  oscap xccdf eval --profile xccdf_org.ssgproject.content_profile_pci-dss \\"
echo "    --report /tmp/relatorio_oscap.html \\"
echo "    /usr/share/xml/scap/ssg/content/ssg-rhel7-ds.xml"
echo ""
echo "  # Puppet — testar agente:"
echo "  /opt/puppetlabs/bin/puppet --version"
echo "  /opt/puppetlabs/bin/puppet apply --noop /etc/puppetlabs/puppet/manifests/site.pp"
echo ""
echo "  # Ansible — testar:"
echo "  ansible --version"
echo "  ansible localhost -m ping"
echo ""
echo -e "  Log completo: ${BOLD}$LOG_FILE${NC}"
