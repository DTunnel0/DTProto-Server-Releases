#!/bin/bash

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

INSTALL_DIR="/usr/local/bin"

PROXY_GITHUB_REPO=DTunnel0/ProxyDT-Go-Releases
PROXY_BINARY_NAME_DOWNLOAD="proxy"
PROXY_BINARY_NAME_INSTALL="proxy-server"

PROTO_GITHUB_REPO="DTunnel0/DTProto-Server-Releases"
PROTO_BINARY_NAME_DOWNLOAD="proto-server"
PROTO_BINARY_NAME_INSTALL="proto-server"

MANAGER_SCRIPT="proto-server.sh"


print_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

[[ "$EUID" -ne 0 ]] && {
    print_error "This script must be run as root (use sudo)"
    exit 1
}

detect_architecture() {
    local arch=$(uname -m)
    local os="linux"
    
    case $arch in
        x86_64)
            echo "${os}-amd64"
            ;;
        aarch64|arm64)
            echo "${os}-arm64"
            ;;
        armv7l|armv6l)
            echo "${os}-arm"
            ;;
        i386|i686)
            echo "${os}-386"
            ;;
        *)
            print_error "Unsupported architecture: $arch" >&2
            exit 1
            ;;
    esac
}

print_header() {
  clear
  echo -e "${BLUE}╔════════════════════════════════════════════════════╗"
  echo -e "║           INSTALADOR DO DT PROTO SERVER            ║"
  echo -e "╠════════════════════════════════════════════════════╣"
  echo -e "║ Repositório proto: $(printf '%-32s' "$PROTO_GITHUB_REPO")║"
  echo -e "║ Binário do proto: $(printf '%-32s' "$PROTO_BINARY_NAME_INSTALL") ║"
  echo -e "╠════════════════════════════════════════════════════╣"
  echo -e "║ Repositório proxy: $(printf '%-31s' "$PROXY_GITHUB_REPO") ║"
  echo -e "║ Binário do proxy: $(printf '%-32s' "$PROXY_BINARY_NAME_INSTALL") ║"
  echo -e "╠════════════════════════════════════════════════════╣"
  echo -e "║ Instalar em: $(printf '%-36s' "$INSTALL_DIR")  ║"
  echo -e "╚════════════════════════════════════════════════════╝${NC}"
}

get_latest_versions() {
    local repo=$1
    local count=${2:-5}
    curl -s "https://api.github.com/repos/${repo}/releases" | grep -oP '"tag_name": "\K(.*)(?=")' | head -n "$count"
}

download_and_install() {
    local repo=$1
    local binary_name_download=$2
    local binary_name_install=$3
    local version=$4
    local arch=$5

    local full_binary_name_download="${binary_name_download}-${arch}"
    local download_url="https://github.com/${repo}/releases/download/${version}/${full_binary_name_download}"

    echo ""
    print_info "Baixando binário: ${binary_name_install}"

    if ! curl -sL -o"/tmp/${binary_name_install}" "${download_url}"; then
        print_error "Erro ao baixar o binário. Saindo."
        exit 1
    fi

    chmod +x "/tmp/${binary_name_install}"

    print_info "Instalando binário em: ${INSTALL_DIR}/${binary_name_install}..."

    mv "/tmp/${binary_name_install}" "${INSTALL_DIR}/${binary_name_install}"
    chmod +x "${INSTALL_DIR}/${binary_name_install}"

    print_success "Binário instalado com sucesso!"
}

download_manager_script() {
    local download_url="https://raw.githubusercontent.com/${PROTO_GITHUB_REPO}/main/${MANAGER_SCRIPT}"
    
    echo ""
    print_info "Baixando script de gerenciamento..."
    
    if ! curl -sL -o "/tmp/${MANAGER_SCRIPT}" "${download_url}" 2>/dev/null; then
        print_error "Erro ao baixar o script de gerenciamento."
        exit 1
    fi

    if [[ ! -f "/tmp/${MANAGER_SCRIPT}" ]]; then
        print_error "Erro ao baixar o script de gerenciamento."
        exit 1
    fi
    
    mv "/tmp/${MANAGER_SCRIPT}" "${INSTALL_DIR}/proto"
    chmod +x "${INSTALL_DIR}/proto"

    print_success "Script instalado em: ${INSTALL_DIR}/proto"
    print_success "Para executar o menu, execute: ${RED}proto${NC}"
}

select_version() {
    local repo=$1
    local name=$2
    local versions=($(get_latest_versions "$repo"))
    local i=1

    echo -e "${BLUE}╔════════════════════════════════════════════════════╗${NC}" >&2
    echo -e "${BLUE}║${NC}                   ${name}                  ${BLUE}║${NC}" >&2
    echo -e "${BLUE}╠════════════════════════════════════════════════════╣${NC}" >&2
    
    for v in "${versions[@]}"; do
        printf "${BLUE}║${NC} ${YELLOW}[%02d]${NC} %-45s ${BLUE}║${NC}\n" "$i" "$v" >&2
        i=$((i + 1))
    done
    printf "${BLUE}║${NC} ${YELLOW}[00]${NC} ${RED}Última versão (recomendado)                   ${BLUE}║${NC}\n" >&2
    echo -e "${BLUE}╚════════════════════════════════════════════════════╝${NC}" >&2
    echo -ne "${BLUE}👉 Escolha uma versão: ${NC}" >&2
    read -r choice

    if ! [[ "$choice" =~ ^[0-9]+$ ]] || (( choice < 0 || choice > ${#versions[@]} )); then
        print_error "Opção inválida. Saindo." >&2
        exit 1
    fi

    if [[ "$choice" -eq 0 ]]; then
        choice=${#versions[@]}
    fi

    echo "${versions[$((choice - 1))]}"
}

configure_sysctl() {
    print_info "Configurando regras sysctl para otimização de rede..."
    
    local sysctl_conf="/etc/sysctl.d/99-dtunnel.conf"
    echo 'net.ipv4.ip_forward=1' > "$sysctl_conf"
    
    sudo sysctl --system > /dev/null
    print_success "Regras sysctl configuradas e aplicadas."
}

main() {
    clear

    print_header

    ARCH=$(detect_architecture)
    echo -e "${GREEN}💻 Plataforma detectada:${NC} $ARCH"

    PROTO_VERSION=$(select_version "$PROTO_GITHUB_REPO" "DT PROTO SERVER")
    PROXY_VERSION=$(select_version "$PROXY_GITHUB_REPO" "DT PROXY SERVER")

    download_and_install "$PROTO_GITHUB_REPO" "$PROTO_BINARY_NAME_DOWNLOAD" "$PROTO_BINARY_NAME_INSTALL" "$PROTO_VERSION" "$ARCH"
    download_and_install "$PROXY_GITHUB_REPO" "$PROXY_BINARY_NAME_DOWNLOAD" "$PROXY_BINARY_NAME_INSTALL" "$PROXY_VERSION" "$ARCH"
    configure_sysctl
    download_manager_script
}

main "$@"