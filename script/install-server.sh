#!/usr/bin/env bash

set -euo pipefail

declare -A COLORS=(
    ["INFO"]="\033[1;36m"
    ["WARN"]="\033[1;33m"
    ["ERROR"]="\033[1;31m"
    ["SUCCESS"]="\033[1;32m"
    ["TITLE"]="\033[1;34m"
    ["PROMPT"]="\033[1;33m"
    ["RESET"]="\033[0m"
)

GITHUB_REPO="DTunnel0/DTProto-Server-Releases"
INSTALL_DIR="/usr/local/bin"
CONFIG_DIR="/etc/proto-server"
CONFIG_FILE="${CONFIG_DIR}/config.json"
STATS_FILE="${CONFIG_DIR}/stats.json"
SERVICE_FILE="/etc/systemd/system/proto-server.service"
PAM_SERVICE_FILE="/etc/pam.d/proto-server"
LEGACY_SERVICES=("proto-server.service" "dtproto.service" "proxydt.service" "proxy-443.service" "proxy-80.service")

print_message() {
    local type="$1"
    local message="$2"
    local prefix="[INFO]"
    case "$type" in
        "SUCCESS") prefix="[OK]" ;;
        "WARN")    prefix="[AVISO]" ;;
        "ERROR")   prefix="[ERRO]" ;;
        "PROMPT")  prefix="[>]" ;;
    esac
    echo -e "${COLORS[$type]}${prefix} ${message}${COLORS[RESET]}" >&2
}

format_prompt() {
    echo -e "${COLORS[PROMPT]}[>] $1${COLORS[RESET]}"
}

read_input() {
    local prompt_text="$1"
    local default_value="${2:-}"
    local value

    if [[ -n "$default_value" ]]; then
        read -rp "$(format_prompt "$prompt_text") [$default_value]: " value
        echo "${value:-$default_value}"
        return
    fi

    read -rp "$(format_prompt "$prompt_text"): " value
    echo "$value"
}

check_root() {
  if [[ "${EUID}" -ne 0 ]]; then
    print_message "ERROR" "Este instalador deve ser executado como root (use sudo)."
    exit 1
  fi
}

ensure_dependencies() {
  print_message "INFO" "Instalando dependências do sistema e PAM..."
  if command -v apt-get >/dev/null 2>&1; then
    apt-get update -qq
    apt-get install -y -qq curl jq libpam0g libpam-modules >/dev/null
  elif command -v dnf >/dev/null 2>&1; then
    dnf install -y -q curl jq pam >/dev/null
  elif command -v yum >/dev/null 2>&1; then
    yum install -y -q curl jq pam >/dev/null
  else
    print_message "ERROR" "Distribuição não suportada. É necessário instalar jq e Linux-PAM."
    exit 1
  fi

  if ! command -v curl >/dev/null 2>&1 || ! command -v jq >/dev/null 2>&1; then
    print_message "ERROR" "Não foi possível instalar curl e jq."
    exit 1
  fi

  if ! ldconfig -p 2>/dev/null | grep 'libpam\.so\.0' >/dev/null; then
    print_message "ERROR" "A biblioteca libpam.so.0 não está disponível."
    exit 1
  fi

  print_message "SUCCESS" "Dependências PAM instaladas."
}

ensure_glibc() {
  if getconf GNU_LIBC_VERSION >/dev/null 2>&1; then
    return
  fi

  print_message "ERROR" "Esta versão requer uma distribuição glibc. Alpine/musl não é suportado."
  exit 1
}

detect_arch() {
  local arch
  arch="$(uname -m)"
  case "${arch}" in
    x86_64) echo "linux-amd64" ;;
    aarch64|arm64) echo "linux-arm64" ;;
    armv7l|armv6l) echo "linux-arm" ;;
    i386|i686) echo "linux-386" ;;
    *)
      print_message "ERROR" "Arquitetura não suportada: ${arch}"
      exit 1
      ;;
  esac
}

fetch_latest_version() {
  local version
  version=$(curl -fsSL "https://api.github.com/repos/${GITHUB_REPO}/releases/latest" 2>/dev/null | jq -r '.tag_name // empty' || true)
  if [[ -n "${version}" ]]; then
    echo "${version}"
    return
  fi

  version=$(curl -fsSL "https://api.github.com/repos/${GITHUB_REPO}/releases" 2>/dev/null | jq -r '.[0].tag_name // empty' || true)
  if [[ -n "${version}" ]]; then
    echo "${version}"
    return
  fi

  print_message "ERROR" "Não foi possível obter a versão mais recente do GitHub."
  exit 1
}

cleanup_legacy_installations() {
  print_message "INFO" "Detectando e removendo versões anteriores, serviços e processos antigos..."

  for svc in "${LEGACY_SERVICES[@]}"; do
    if systemctl is-active --quiet "${svc}" 2>/dev/null; then
      print_message "WARN" "Parando serviço antigo: ${svc}"
      systemctl stop "${svc}" 2>/dev/null || true
    fi
    if systemctl is-enabled --quiet "${svc}" 2>/dev/null; then
      systemctl disable "${svc}" 2>/dev/null || true
    fi
    if [[ -f "/etc/systemd/system/${svc}" ]]; then
      rm -f "/etc/systemd/system/${svc}"
    fi
  done

  systemctl daemon-reload 2>/dev/null || true

  pkill -9 -f "proto-server" 2>/dev/null || true
  pkill -9 -f "proxy-server" 2>/dev/null || true

  print_message "SUCCESS" "Limpeza prévia concluída."
}

configure_sysctl() {
  print_message "INFO" "Otimizando parâmetros de rede do Kernel (sysctl)..."
  local sysctl_file="/etc/sysctl.d/99-dtproto.conf"
  cat <<'EOF' > "${sysctl_file}"
net.ipv4.ip_forward=1
net.core.rmem_max=16777216
net.core.wmem_max=16777216
EOF
  sysctl --system >/dev/null 2>&1 || true
  print_message "SUCCESS" "Parâmetros sysctl otimizados."
}

setup_config() {
  mkdir -p "${CONFIG_DIR}"
  if [[ -f "${CONFIG_FILE}" ]]; then
    local tmp
    tmp=$(mktemp)
    jq '.server.auth = {"system": true}' "${CONFIG_FILE}" > "${tmp}"
    mv "${tmp}" "${CONFIG_FILE}"
    print_message "SUCCESS" "Configuração de autenticação migrada para PAM."
    return 0
  fi

  print_message "INFO" "Criando arquivo de configuração padrão em ${CONFIG_FILE}..."
  cat <<EOF > "${CONFIG_FILE}"
{
  "server": {
    "virtual_subnet_cidr": "10.10.0.0/16",
    "stats_file": "${STATS_FILE}",
    "auth": {
      "system": true
    },
    "tun": {
      "name": "tun0",
      "buffer_size": 16384
    }
  },
  "proxy": {
    "enabled": true,
    "listen": [
      {
        "host": "0.0.0.0",
        "port": 443,
        "ssl": true
      },
      {
        "host": "0.0.0.0",
        "port": 80,
        "ssl": false
      }
    ]
  }
}
EOF
  print_message "SUCCESS" "Configuração criada em ${CONFIG_FILE}."
}

install_pam_service() {
  print_message "INFO" "Configurando serviço PAM em ${PAM_SERVICE_FILE}..."
  mkdir -p "$(dirname "${PAM_SERVICE_FILE}")"
  cat <<'EOF' > "${PAM_SERVICE_FILE}"
auth required pam_unix.so nodelay
account required pam_unix.so
EOF
  chmod 0644 "${PAM_SERVICE_FILE}"
  print_message "SUCCESS" "Serviço PAM proto-server configurado."
}

install_systemd_service() {
  print_message "INFO" "Instalando serviço systemd em ${SERVICE_FILE}..."
  cat <<EOF > "${SERVICE_FILE}"
[Unit]
Description=DTunnel Protocolo Server
After=network.target

[Service]
Type=simple
ExecStart=${INSTALL_DIR}/proto-server --config ${CONFIG_FILE}
Restart=on-failure
RestartSec=3
LimitNOFILE=65535

[Install]
WantedBy=multi-user.target
EOF

  systemctl daemon-reload
  print_message "SUCCESS" "Serviço proto-server.service configurado."
}

download_binary() {
  local version=$1
  local arch=$2
  local target_dir=$3
  local artifact="proto-server-${arch}"
  local binary="${target_dir}/${artifact}"
  local download_url="https://github.com/${GITHUB_REPO}/releases/download/${version}/${artifact}"

  print_message "INFO" "Baixando versão ${version} (${arch})..."
  if ! curl -fsSL -o "${binary}" "${download_url}"; then
    print_message "ERROR" "Erro ao baixar o binário da versão ${version}."
    exit 1
  fi

  if ! curl -fsSL -o "${binary}.sha256" "${download_url}.sha256"; then
    print_message "ERROR" "Erro ao baixar o checksum da versão ${version}."
    exit 1
  fi

  if ! (cd "${target_dir}" && sha256sum -c "${artifact}.sha256" >/dev/null); then
    print_message "ERROR" "O checksum do binário baixado é inválido."
    exit 1
  fi

  chmod 0755 "${binary}"
  if ! ldd "${binary}" 2>/dev/null | grep 'libpam\.so\.0' >/dev/null; then
    print_message "ERROR" "O binário baixado não possui suporte PAM válido para esta VPS."
    exit 1
  fi

  if ! "${binary}" --version >/dev/null 2>&1; then
    print_message "ERROR" "O binário PAM não é compatível com a biblioteca C desta VPS."
    exit 1
  fi

  echo "${binary}"
}

download_menu_script() {
  local raw_url="https://raw.githubusercontent.com/${GITHUB_REPO}/main/proto-server.sh"
  print_message "INFO" "Instalando menu interativo 'proto'..."
  if ! curl -fsSL -o "/tmp/proto" "${raw_url}" 2>/dev/null; then
    print_message "WARN" "Não foi possível atualizar o script de menu."
    return
  fi

  chmod +x "/tmp/proto"
  mv "/tmp/proto" "${INSTALL_DIR}/proto"
  print_message "SUCCESS" "Menu de gerenciamento instalado em ${INSTALL_DIR}/proto."
}

install_binary() {
  local candidate=$1
  cleanup_legacy_installations
  install -m 0755 "${candidate}" "${INSTALL_DIR}/proto-server"
  install_systemd_service
  if systemctl start proto-server.service; then
    systemctl enable proto-server.service >/dev/null 2>&1 || true
    print_message "SUCCESS" "Serviço proto-server.service iniciado."
  else
    print_message "WARN" "O serviço não iniciou. Execute 'proto' para configurar o token e tente novamente."
  fi
}

main() {
  clear
  local title="INSTALADOR DO DTUNNEL PROTOCOLO SERVER"
  local padding=4
  local inner_width=$(( ${#title} + padding * 2 ))
  local border
  printf -v border '%*s' "${inner_width}" ''
  border=${border// /═}
  echo -e "${COLORS[TITLE]}╔${border}╗${COLORS[RESET]}"
  echo -e "${COLORS[TITLE]}║${COLORS[SUCCESS]}$(printf '%*s' "${padding}" '')${title}$(printf '%*s' "${padding}" '')${COLORS[RESET]}${COLORS[TITLE]}║${COLORS[RESET]}"
  echo -e "${COLORS[TITLE]}╚${border}╝${COLORS[RESET]}"
  echo ""

  check_root
  ensure_dependencies
  ensure_glibc

  local arch
  arch=$(detect_arch)
  print_message "INFO" "Arquitetura detectada: ${arch}"

  local version
  version=$(fetch_latest_version)
  local display_version="${version#v}"
  print_message "INFO" "Última versão detectada no GitHub: ${display_version}"

  local download_dir
  download_dir=$(mktemp -d)
  trap "rm -rf '${download_dir}'" EXIT

  local candidate
  candidate=$(download_binary "${version}" "${arch}" "${download_dir}")

  configure_sysctl
  setup_config
  install_pam_service

  print_message "INFO" "Instalando o serviço proto-server..."
  install_binary "${candidate}"

  print_message "SUCCESS" "Binário proto-server instalado em ${INSTALL_DIR}/proto-server."
  download_menu_script

  echo ""
  print_message "SUCCESS" "DTunnel Protocolo Server v${display_version} instalado com sucesso!"
  print_message "INFO" "Para abrir o menu, execute: ${COLORS[ERROR]}proto${COLORS[RESET]}"
  echo ""
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main "$@"
fi
