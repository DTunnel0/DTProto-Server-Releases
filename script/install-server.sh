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
LEGACY_SERVICES=("proto-server.service" "dtproto.service" "proxydt.service")

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
    else
        read -rp "$(format_prompt "$prompt_text"): " value
        echo "$value"
    fi
}

check_root() {
  if [[ "${EUID}" -ne 0 ]]; then
    print_message "ERROR" "Este instalador deve ser executado como root (use sudo)."
    exit 1
  fi
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

detect_current_version() {
  if [[ -x "${INSTALL_DIR}/proto-server" ]]; then
    local ver
    ver=$("${INSTALL_DIR}/proto-server" -v 2>/dev/null | awk '{print $NF}' || true)
    if [[ -n "${ver}" ]]; then
      echo "v${ver}"
      return
    fi
  fi
  echo "nenhuma"
}

fetch_latest_version() {
  local version
  version=$(curl -sL "https://api.github.com/repos/${GITHUB_REPO}/releases/latest" 2>/dev/null | grep -oP '"tag_name": "\K(.*)(?=")' | head -n 1 || true)
  if [[ -z "${version}" ]]; then
    version=$(curl -sL "https://api.github.com/repos/${GITHUB_REPO}/releases" 2>/dev/null | grep -oP '"tag_name": "\K(.*)(?=")' | head -n 1 || true)
  fi
  if [[ -z "${version}" ]]; then
    print_message "ERROR" "Não foi possível obter a versão mais recente do GitHub."
    exit 1
  fi
  echo "${version}"
}

cleanup_legacy_installations() {
  print_message "INFO" "Limpeza prévia: removendo versões anteriores, serviços e processos antigos..."

  for svc in "${LEGACY_SERVICES[@]}"; do
    if systemctl is-active --quiet "${svc}" 2>/dev/null; then
      print_message "WARN" "Parando serviço: ${svc}"
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
  pkill -9 -f "proxydt" 2>/dev/null || true
  pkill -9 -f "dtproto" 2>/dev/null || true

  rm -f "${INSTALL_DIR}/proto-server" "${INSTALL_DIR}/proto" 2>/dev/null || true

  print_message "SUCCESS" "Limpeza prévia concluída com sucesso."
}

configure_sysctl() {
  print_message "INFO" "Otimizando parâmetros de rede do Kernel (sysctl)..."
  local sysctl_file="/etc/sysctl.d/99-proto-server.conf"
  cat <<'EOF' > "${sysctl_file}"
net.ipv4.ip_forward=1
net.core.rmem_max=16777216
net.core.wmem_max=16777216
EOF
  sysctl --system >/dev/null 2>&1 || true
  print_message "SUCCESS" "Parâmetros de rede otimizados."
}

setup_config() {
  mkdir -p "${CONFIG_DIR}"
  if [[ ! -f "${CONFIG_FILE}" ]]; then
    print_message "INFO" "Criando arquivo de configuração padrão em ${CONFIG_FILE}..."
    cat <<EOF > "${CONFIG_FILE}"
{
  "server": {
    "token": "",
    "protocol": [
      "tcp:8000"
    ],
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
        "port": 8080,
        "ssl": false
      },
      {
        "host": "0.0.0.0",
        "port": 8443,
        "ssl": true
      }
    ]
  }
}
EOF
    print_message "SUCCESS" "Configuração padrão criada em ${CONFIG_FILE}."
  fi
}

install_systemd_service() {
  print_message "INFO" "Instalando serviço systemd em ${SERVICE_FILE}..."
  cat <<EOF > "${SERVICE_FILE}"
[Unit]
Description=DTProto Unified VPN and Proxy Server
After=network.target

[Service]
Type=simple
ExecStart=${INSTALL_DIR}/proto-server --config ${CONFIG_FILE}
Restart=always
RestartSec=3
LimitNOFILE=65535

[Install]
WantedBy=multi-user.target
EOF

  systemctl daemon-reload
  systemctl enable proto-server.service >/dev/null 2>&1 || true
  print_message "SUCCESS" "Serviço proto-server.service configurado e ativado."
}

download_binary() {
  local version=$1
  local arch=$2
  local download_url="https://github.com/${GITHUB_REPO}/releases/download/${version}/proto-server-${arch}"

  print_message "INFO" "Baixando versão ${version} (${arch})..."
  if ! curl -sL -o "/tmp/proto-server" "${download_url}"; then
    print_message "ERROR" "Erro ao baixar o binário da versão ${version}."
    exit 1
  fi

  chmod +x "/tmp/proto-server"
  mv "/tmp/proto-server" "${INSTALL_DIR}/proto-server"
  print_message "SUCCESS" "Binário proto-server instalado em ${INSTALL_DIR}/proto-server."
}

download_menu_script() {
  local raw_url="https://raw.githubusercontent.com/${GITHUB_REPO}/main/script/proto-server.sh"
  print_message "INFO" "Instalando menu interativo 'proto'..."
  if ! curl -sL -o "/tmp/proto" "${raw_url}" 2>/dev/null; then
    print_message "ERROR" "Erro ao baixar o script do menu."
    exit 1
  fi

  chmod +x "/tmp/proto"
  mv "/tmp/proto" "${INSTALL_DIR}/proto"
  print_message "SUCCESS" "Menu de gerenciamento instalado em ${INSTALL_DIR}/proto."
}

main() {
  clear
  echo -e "${COLORS[TITLE]}╔═════════════════════════════════════════════╗${COLORS[RESET]}"
  echo -e "${COLORS[TITLE]}║${COLORS[SUCCESS]}      INSTALADOR DO DTPROTO SERVER & PROXY    ${COLORS[RESET]}${COLORS[TITLE]}║${COLORS[RESET]}"
  echo -e "${COLORS[TITLE]}╚═════════════════════════════════════════════╝${COLORS[RESET]}"
  echo ""

  check_root

  local current_ver
  current_ver=$(detect_current_version)
  if [[ "${current_ver}" != "nenhuma" ]]; then
    print_message "INFO" "Versão atual detectada: ${current_ver}"
  fi

  cleanup_legacy_installations

  local arch
  arch=$(detect_arch)
  print_message "INFO" "Arquitetura detectada: ${arch}"

  local version
  version=$(fetch_latest_version)
  print_message "INFO" "Última versão detectada no GitHub: ${version}"

  download_binary "${version}" "${arch}"
  configure_sysctl
  setup_config
  install_systemd_service
  download_menu_script

  print_message "INFO" "Iniciando serviço proto-server..."
  systemctl restart proto-server.service || true

  echo ""
  print_message "SUCCESS" "DTProto Server ${version} instalado com sucesso!"
  print_message "SUCCESS" "Para abrir o menu de gerenciamento, digite: proto"
  echo ""
}

main "$@"
