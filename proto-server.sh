#!/bin/bash

PROTO_SERVER_BIN="/usr/local/bin/proto-server"
PROTO_MANAGER_SCRIPT="/usr/local/bin/proto"
TOKEN_FILE="/etc/proto-server/token"
CONFIG_FILE="/etc/proto-server/config.conf"
DATA_DIR="/var/lib/proto-server"
CREDENTIALS_FILE="$DATA_DIR/credentials.json"
STATS_FILE="$DATA_DIR/stats.json"
CERTIFICATE_SSL_FILE="$DATA_DIR/cert.pem"
PRIVATE_KEY_SSL_FILE="$DATA_DIR/key.pem"
SERVICE_NAME="proto-server"

PROXY_DIR="/etc/proxy"
PROXY_TOKEN_FILE="$PROXY_DIR/token"
PROXY_CONFIG_DIR="$PROXY_DIR/conf.d"
PROXY_LOG_DIR="/var/log/proxy"
PROXY_SERVICE_PREFIX="proxy"
PROXY_EXECUTABLE="/usr/local/bin/proxy-server"

AUTH_MODE_FILE="file"
AUTH_MODE_URL="url" 
AUTH_MODE_SSH="ssh"
AUTH_MODE_NONE="none"

DEFAULT_BUFFER_SIZE=32768
DEFAULT_HTTP_RESPONSE="DTunnel"
MIN_PORT=1
MAX_PORT=65535

RED='\033[1;31m'
GREEN='\033[1;32m'
YELLOW='\033[1;33m'
BLUE='\033[1;34m'
PURPLE='\033[1;35m'
CYAN='\033[1;36m'
WHITE='\033[1;37m'
GRAY='\033[1;90m'
BG_BLUE='\033[44m'
BG_GREEN='\033[42m'
BG_RED='\033[41m'
BG_GRAY='\033[100m'
RESET='\033[0m'
BOLD='\033[1m'

print_header() {
    clear
    echo -e "${BLUE}╔══════════════════════════════════════════════════════════════╗${RESET}"
    echo -e "${BLUE}║${BG_BLUE}${WHITE}                    DTProto SERVER MANAGER                    ${RESET}${BLUE}║"
    echo -e "${BLUE}║${WHITE}             Next-Generation VPN Management System            ${BLUE}║"
    echo -e "${BLUE}║${GRAY}              Author: Glemison C. DuTra (@DuTra01)            ${BLUE}║"
    echo -e "${BLUE}╚══════════════════════════════════════════════════════════════╝${RESET}"
    echo
}

print_status() {
    local status_text="ONLINE"
    local status_bg=$BG_GREEN
    local status_color=$WHITE
    
    if ! is_server_active; then
        status_text="OFFLINE"
        status_bg=$BG_RED
        status_color=$WHITE
    fi
    
    echo -e "${BLUE}╔══════════════════════════════════════════════════════════════╗${RESET}"
    
    if [ "$status_text" = "ONLINE" ]; then
        local padded_status="ONLINE "
    else
        local padded_status="OFFLINE"
    fi
    
    printf "${BLUE}║${WHITE} STATUS: ${status_bg}${BOLD}${status_color}  ${padded_status}  ${RESET}${BLUE}                                          ║${RESET}\n"
    
    local port=$(get_config_value "PORT")
    local subnet=$(get_config_value "VIRTUAL_SUBNET_CIDR")
    local tun=$(get_config_value "TUN_INTERFACE")
    
    port=${port:-5000}
    subnet=${subnet:-10.10.0.0/16}
    tun=${tun:-tun0}
    
    local line="${WHITE} Porta: ${CYAN}$(printf '%-7s' "$port")${WHITE} | Sub-rede: ${CYAN}$(printf '%-15s' "$subnet")${WHITE} | TUN: ${CYAN}$(printf '%-8s' "$tun")"
    
    printf "${BLUE}║${line}%3s${BLUE}║${RESET}\n" ""
    
    echo -e "${BLUE}╚══════════════════════════════════════════════════════════════╝${RESET}"
    echo
}

print_main_menu() {
    echo -e "${BLUE}╔══════════════════════════════════════════════════════════════╗${RESET}"
    echo -e "${BLUE}║${WHITE}                        MENU PRINCIPAL                        ${BLUE}║${RESET}"
    echo -e "${BLUE}╠══════════════════════════════════════════════════════════════╣${RESET}"
    
    local menu_items=(
        "1 • Iniciar Servidor"
        "2 • Parar Servidor" 
        "3 • Reiniciar Servidor"
        "4 • Status & Configuração"
        "5 • Visualizar Logs"
        "6 • Alterar Porta"
        "7 • Gerenciar Token"
        "8 • Modo de Autenticação"
        "0 • Voltar ao Menu Inicial"
    )
    
    for item in "${menu_items[@]}"; do
        local padding=$((60 - ${#item}))
        if [[ $item == *"Voltar"* ]]; then
            printf "${BLUE}║${RED}  [${item%% *}] ${item#* • }%${padding}s${BLUE}║${RESET}\n" ""
        else
            printf "${BLUE}║${WHITE}  [${CYAN}${item%% *}${WHITE}] ${BLUE}${item#* • }%${padding}s${BLUE}║${RESET}\n" ""
        fi
    done
    
    echo -e "${BLUE}╚══════════════════════════════════════════════════════════════╝${RESET}"
    echo
}

print_initial_menu() {
    echo -e "${BLUE}╔══════════════════════════════════════════════════════════════╗${RESET}"
    echo -e "${BLUE}║${WHITE}                        MENU INICIAL                          ${BLUE}║${RESET}"
    echo -e "${BLUE}╠══════════════════════════════════════════════════════════════╣${RESET}"
    
    local menu_items=(
        "1 • Menu Principal do Protocolo"
        "2 • Menu de Conexão"
        "3 • Remover Script"
        "0 • Sair"
    )
    
    for item in "${menu_items[@]}"; do
        local padding=$((60 - ${#item}))
        if [[ $item == *"Remover"* ]]; then
            printf "${BLUE}║${RED}  [${item%% *}] ${item#* • }%${padding}s${BLUE}║${RESET}\n" ""
        elif [[ $item == *"Sair"* ]]; then
            printf "${BLUE}║${RED}  [${item%% *}] ${item#* • }%${padding}s${BLUE}║${RESET}\n" ""
        else
            printf "${BLUE}║${WHITE}  [${CYAN}${item%% *}${WHITE}] ${BLUE}${item#* • }%${padding}s${BLUE}║${RESET}\n" ""
        fi
    done
    
    echo -e "${BLUE}╚══════════════════════════════════════════════════════════════╝${RESET}"
    echo
}

print_success() {
    echo -e "${GREEN}$1${RESET}"
}

print_error() {
    echo -e "${RED}$1${RESET}"
}

print_info() {
    echo -e "${CYAN}$1${RESET}"
}

print_warning() {
    echo -e "${YELLOW}$1${RESET}"
}

prompt_input() {
    echo -e "${BLUE}$1${RESET}"
    read -rp "> " response
    echo "$response"
}

pause() {
    echo
    print_warning "Pressione Enter para continuar..."
    read -r
}

init_proxy_dirs() {
    sudo mkdir -p "$PROXY_DIR" "$PROXY_CONFIG_DIR" "$PROXY_LOG_DIR"
}

load_proxy_token() {
    if [[ -f "$PROXY_TOKEN_FILE" ]]; then
        cat "$PROXY_TOKEN_FILE"
    else
        echo ""
    fi
}

save_proxy_token() {
    local token="$1"
    sudo mkdir -p "$PROXY_DIR"
    echo "$token" | sudo tee "$PROXY_TOKEN_FILE" > /dev/null
}

save_unified_token() {
    local token="$1"
    
    sudo mkdir -p "$(dirname "$TOKEN_FILE")"
    echo "$token" | sudo tee "$TOKEN_FILE" > /dev/null
    
    sudo mkdir -p "$PROXY_DIR"
    echo "$token" | sudo tee "$PROXY_TOKEN_FILE" > /dev/null
    
    print_success "Token salvo!"
}

prompt_for_token_if_missing() {
    local current_token=$(load_token)
    
    if [[ -z "$current_token" ]]; then
        echo
        print_warning "Token de autenticação não encontrado!"
        echo -e "${BLUE}Por favor, insira seu token:${RESET}"
        read -rp "> " new_token
        
        if [[ -n "$new_token" ]]; then
            save_unified_token "$new_token"
            print_success "Token configurado!"
        else
            print_error "Token não pode ser vazio."
            exit 1
        fi
        echo
    fi
}

list_active_proxies() {
    local active_ports=""
    
    for service in $(systemctl list-units --type=service --no-legend | grep "$PROXY_SERVICE_PREFIX" | awk '{print $1}'); do
        if systemctl is-active --quiet "$service"; then
            local port=$(echo "$service" | sed "s/${PROXY_SERVICE_PREFIX}-//" | sed 's/\.service$//')
            if [[ -n "$active_ports" ]]; then
                active_ports="$active_ports, $port"
            else
                active_ports="$port"
            fi
        fi
    done
    
    echo "$active_ports"
}

get_proxy_config_file() {
    local port="$1"
    echo "$PROXY_CONFIG_DIR/proxy-$port.conf"
}

get_proxy_log_file() {
    local port="$1"
    echo "$PROXY_LOG_DIR/proxy-$port.log"
}

get_proxy_service_name() {
    local port="$1"
    echo "$PROXY_SERVICE_PREFIX-$port"
}

validate_port() {
    local port="$1"
    
    if ! [[ "$port" =~ ^[0-9]+$ ]]; then
        print_error "Porta deve ser um número!"
        return 1
    fi
    
    if [[ "$port" -lt 1 || "$port" -gt 65535 ]]; then
        print_error "Porta deve estar entre 1 e 65535!"
        return 1
    fi
    
    return 0
}

check_port_available() {
    local port="$1"
    
    if ss -tuln | grep -q ":$port "; then
        print_error "Porta $port já está em uso!"
        return 1
    fi
    
    return 0
}

confirm_action() {
    local message="$1"
    local default_answer="${2:-n}"
    echo -e "${YELLOW}$message (s/N)${RESET}"
    read -rp "> " response
    response=${response:-$default_answer}
    case "${response,,}" in
        s|sim|y|yes) return 0 ;;
        *) return 1 ;;
    esac
}

get_proto_port() {
    local proto_port=$(get_config_value "PORT")
    echo "${proto_port:-5000}"
}

build_proxy_command() {
    local port="$1"
    local token="$2"
    local ssl_enabled="$3"
    local ssl_cert_path="$4"
    local ssh_only_flag="$5"
    local http_response="$6"
    
    local command="$PROXY_EXECUTABLE --token=$token --buffer-size=$DEFAULT_BUFFER_SIZE --response=$http_response --domain --log-file=$(get_proxy_log_file "$port")"
    
    local proto_port=$(get_proto_port)
    command="$command --dt-proto-port=$proto_port"
    
    if [[ "$ssl_enabled" == "true" ]]; then
        command="$command --port=$port:ssl"
        if [[ -n "$ssl_cert_path" ]]; then
            command="$command --cert=$ssl_cert_path"
        fi
    else
        command="$command --port=$port"
    fi
    
    if [[ "$ssh_only_flag" == "true" ]]; then
        command="$command --ssh-only"
    fi
    
    echo "$command"
}

start_proxy_service() {
    print_header
    
    local port
    echo -e "${BLUE}Digite a porta para abrir:${RESET}"
    read -rp "> " port
    
    port=$(echo "$port" | tr -d '[:space:]')
    
    if ! validate_port "$port"; then
        pause
        return
    fi
    
    if ! check_port_available "$port"; then
        pause
        return
    fi
    
    local token=$(load_token)
    if [[ -z "$token" ]]; then
        print_error "Token não configurado. Configure o token primeiro."
        pause
        return
    fi
    
    local ssl_enabled="false"
    local ssl_cert_path=""
    
    if confirm_action "Deseja habilitar SSL?" "n"; then
        ssl_enabled="true"
        if ! confirm_action "Usar certificado interno?" "s"; then
            echo -e "${BLUE}Caminho do certificado SSL:${RESET}"
            read -rp "> " ssl_cert_path
        fi
    fi
    
    local http_response
    echo -e "${BLUE}Resposta HTTP padrão (Enter para '$DEFAULT_HTTP_RESPONSE'):${RESET}"
    read -rp "> " http_response
    http_response=${http_response:-$DEFAULT_HTTP_RESPONSE}
    
    local ssh_only_flag="false"
    if confirm_action "Habilitar modo somente SSH?" "n"; then
        ssh_only_flag="true"
    fi
    
    print_info "Iniciando proxy na porta $port..."
    
    local proxy_command=$(build_proxy_command "$port" "$token" "$ssl_enabled" "$ssl_cert_path" "$ssh_only_flag" "$http_response")
    
    local service_name=$(get_proxy_service_name "$port")
    
    sudo tee "/etc/systemd/system/$service_name.service" > /dev/null <<EOF
[Unit]
Description=DTunnel Proxy Server na porta $port
After=network.target

[Service]
ExecStart=$proxy_command
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF

    sudo systemctl daemon-reload
    
    if sudo systemctl start "$service_name"; then
        sudo systemctl enable "$service_name" > /dev/null 2>&1
        print_success "Proxy iniciado com sucesso na porta $port!"
    else
        print_error "Falha ao iniciar proxy na porta $port"
    fi
    
    pause
}

stop_proxy_service() {
    print_header
    
    local active_ports=$(list_active_proxies)
    
    if [[ -z "$active_ports" ]]; then
        print_error "Nenhum proxy ativo no momento."
        pause
        return
    fi
    
    echo -e "${BLUE}Portas ativas: ${GREEN}$active_ports${RESET}"
    echo -e "${BLUE}Digite a porta para fechar:${RESET}"
    read -rp "> " port
    
    port=$(echo "$port" | tr -d '[:space:]')
    
    if ! validate_port "$port"; then
        pause
        return
    fi
    
    local service_name=$(get_proxy_service_name "$port")
    
    if ! systemctl is-active --quiet "$service_name"; then
        print_error "Proxy na porta $port não está ativo."
        pause
        return
    fi
    
    print_info "Parando proxy na porta $port..."
    
    if sudo systemctl stop "$service_name"; then
        sudo systemctl disable "$service_name" > /dev/null 2>&1
        sudo rm -f "/etc/systemd/system/$service_name.service"
        sudo systemctl daemon-reload
        print_success "Proxy parado com sucesso na porta $port!"
    else
        print_error "Falha ao parar proxy na porta $port"
    fi
    
    pause
}

restart_proxy_service() {
    print_header
    
    local active_ports=$(list_active_proxies)
    
    if [[ -z "$active_ports" ]]; then
        print_error "Nenhum proxy ativo no momento."
        pause
        return
    fi
    
    echo -e "${BLUE}Portas ativas: ${GREEN}$active_ports${RESET}"
    echo -e "${BLUE}Digite a porta para reiniciar:${RESET}"
    read -rp "> " port
    
    port=$(echo "$port" | tr -d '[:space:]')
    
    if ! validate_port "$port"; then
        pause
        return
    fi
    
    local service_name=$(get_proxy_service_name "$port")
    
    if ! systemctl is-active --quiet "$service_name"; then
        print_error "Proxy na porta $port não está ativo."
        pause
        return
    fi
    
    print_info "Reiniciando proxy na porta $port..."
    
    if sudo systemctl restart "$service_name"; then
        print_success "Proxy reiniciado com sucesso na porta $port!"
    else
        print_error "Falha ao reiniciar proxy na porta $port"
    fi
    
    pause
}

show_proxy_logs() {
    print_header

    local active_ports=$(list_active_proxies)
    
    if [[ -z "$active_ports" ]]; then
        print_error "Nenhum proxy ativo no momento."
        pause
        return
    fi
    
    echo -e "${BLUE}Portas ativas: ${GREEN}$active_ports${RESET}"
    echo -e "${BLUE}Digite a porta para ver os logs:${RESET}"
    read -rp "> " port
    
    port=$(echo "$port" | tr -d '[:space:]')
    
    if ! validate_port "$port"; then
        pause
        return
    fi
    
    local log_file=$(get_proxy_log_file "$port")
    
    if [[ ! -f "$log_file" ]]; then
        print_error "Arquivo de log não encontrado para porta $port"
        pause
        return
    fi
    
    echo -e "${BLUE}Exibindo logs da porta $port (Ctrl+C para sair):${RESET}"
    echo
    
    trap 'break' INT
    while :; do
        clear
        sudo cat "$log_file"
        echo -e "\n${YELLOW}Pressione Ctrl+C para retornar ao menu.${RESET}"
        sleep 1
    done
    trap - INT
    
    pause
}

connection_menu() {
    init_proxy_dirs
    prompt_for_token_if_missing
    
    while true; do
        print_header
        
        local active_ports
        active_ports=$(list_active_proxies)
        
        echo -e "${BLUE}╔══════════════════════════════════════════════════════════════╗${RESET}"
        echo -e "${BLUE}║${CYAN}                    DTunnel PROXY MENU                        ${BLUE}║${RESET}"
        echo -e "${BLUE}╠══════════════════════════════════════════════════════════════╣${RESET}"
        
        if [[ -n "$active_ports" ]]; then
            echo -e "${BLUE}║${WHITE}  Portas em uso: ${GREEN}$(printf '%-45s' "$active_ports")${BLUE}║${RESET}"
            echo -e "${BLUE}╠══════════════════════════════════════════════════════════════╣${RESET}"
        fi
        
        local menu_items=(
            "1 • Abrir Porta"
            "2 • Fechar Porta"
            "3 • Reiniciar Porta"
            "4 • Ver Log da Porta"
            "0 • Voltar ao Menu Inicial"
        )
        
        for item in "${menu_items[@]}"; do
            local padding=$((60 - ${#item}))
            if [[ $item == *"Voltar"* ]]; then
                printf "${BLUE}║${RED}  [${item%% *}] ${item#* • }%${padding}s${BLUE}║${RESET}\n" ""
            else
                printf "${BLUE}║${WHITE}  [${CYAN}${item%% *}${WHITE}] ${BLUE}${item#* • }%${padding}s${BLUE}║${RESET}\n" ""
            fi
        done
        
        echo -e "${BLUE}╚══════════════════════════════════════════════════════════════╝${RESET}"
        echo
        
        local choice
        read -rp "$(echo -e "${BLUE}Selecione uma opção [1-5]:${RESET} ")" choice
        
        case "$choice" in
            1) start_proxy_service ;;
            2) stop_proxy_service ;;
            3) restart_proxy_service ;;
            4) show_proxy_logs ;;
            0) return 0 ;;
            *) 
                print_error "Opção inválida: $choice"
                pause 
                ;;
        esac
    done
}

get_config_value() {
    local key="$1"
    if [ -f "$CONFIG_FILE" ]; then
        grep "^$key=" "$CONFIG_FILE" | cut -d'=' -f2
    else
        echo ""
    fi
}

set_config_value() {
    local key="$1"
    local value="$2"
    local temp_file=$(mktemp)

    sudo mkdir -p "$(dirname "$CONFIG_FILE")"

    if [ -f "$CONFIG_FILE" ]; then
        grep -v "^$key=" "$CONFIG_FILE" > "$temp_file"
    fi
    echo "$key=$value" >> "$temp_file"
    sudo mv "$temp_file" "$CONFIG_FILE"
}

load_token() {
    if [ -f "$TOKEN_FILE" ]; then
        sudo cat "$TOKEN_FILE"
    fi
}

save_token() {
    local token="$1"
    save_unified_token "$token"
}

validate_token() {
    local token="$1"
    if [ -z "$token" ]; then
        print_error "Token vazio. Não pode ser validado."
        return 1
    fi

    print_info "Validando token..."
    
    if [ ! -f "$PROTO_SERVER_BIN" ]; then
        print_error "Binário do servidor não encontrado."
        return 1
    fi
    
    if sudo "$PROTO_SERVER_BIN" --token "$token" --validate; then
        return 0
    else
        return 1
    fi
}

is_server_active() {
    systemctl is-active "$SERVICE_NAME" &> /dev/null
}

CURRENT_AUTH_MODE=$(get_config_value "AUTH_MODE")
CURRENT_AUTH_MODE=${CURRENT_AUTH_MODE:-$AUTH_MODE_FILE}
CURRENT_AUTH_URL=$(get_config_value "AUTH_URL")

ensure_data_structure() {
    if [ ! -d "$DATA_DIR" ]; then
        sudo mkdir -p "$DATA_DIR"
        print_success "Diretório de dados criado: $DATA_DIR"
    fi

    if [[ ! -f "$CERTIFICATE_SSL_FILE" ]] || [[ ! -f "$PRIVATE_KEY_SSL_FILE" ]]; then
        print_info "Generating TLS certificates..."
        openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
            -keyout "$PRIVATE_KEY_SSL_FILE" \
            -out "$CERTIFICATE_SSL_FILE" \
            -subj "/C=BR/ST=State/L=City/O=ProtoServer/CN=proto-server" \
            2>/dev/null
        chmod 600 "$PRIVATE_KEY_SSL_FILE"
        chmod 644 "$CERTIFICATE_SSL_FILE"
    fi

    if [ ! -f "$CREDENTIALS_FILE" ]; then
        print_info "Criando arquivo de credenciais..."
        sudo cat > "$CREDENTIALS_FILE" <<EOF
{
  "credentials": [
    {
      "user": "Dtunnel",
      "pass": "Dtunnel"
    }
  ]
}
EOF
        sudo chmod 644 "$CREDENTIALS_FILE"
        print_success "Arquivo credentials.json criado com credenciais padrão."
    fi

    if [ ! -f "$STATS_FILE" ]; then
        print_info "Criando arquivo de estatísticas..."
        echo "{}" > "$STATS_FILE"
        sudo chmod 644 "$STATS_FILE"
        print_success "Arquivo stats.json criado."
    fi
}

create_systemd_service() {
    local current_token=$(load_token)
    local port=$(get_config_value "PORT")
    local subnet=$(get_config_value "VIRTUAL_SUBNET_CIDR")
    local tun=$(get_config_value "TUN_INTERFACE")
    local auth_flag=$(get_auth_flag)

    if [ -z "$current_token" ]; then
        print_error "Token não configurado."
        return 1
    fi
    if [ -z "$port" ] || [ -z "$subnet" ] || [ -z "$tun" ]; then
        print_error "Configurações incompletas."
        return 1
    fi

    print_info "Criando serviço systemd..."

    local service_command="$PROTO_SERVER_BIN \\
    --token=$current_token \\
    --listen-addr=:$port \\
    --virtual-subnet-cidr=$subnet \\
    --tun=$tun \\
    --tls-cert-file $CERTIFICATE_SSL_FILE \\
    --tls-key-file $PRIVATE_KEY_SSL_FILE \\
    --stats-file=$STATS_FILE"

    if [[ -n "$auth_flag" ]]; then
        service_command="$service_command \\
    $auth_flag"
    fi

    sudo cat > "/etc/systemd/system/$SERVICE_NAME.service" <<EOF
[Unit]
Description=DTProto Server
After=network.target

[Service]
Type=simple
User=root
Group=root
ExecStart=$service_command
Restart=always

[Install]
WantedBy=multi-user.target
EOF

    sudo systemctl daemon-reload
    print_success "Serviço systemd configurado."
}

start_server() {
    print_header
    
    ensure_data_structure 
    check_or_set_token

    local port=$(get_config_value "PORT")
    local subnet=$(get_config_value "VIRTUAL_SUBNET_CIDR")
    local tun=$(get_config_value "TUN_INTERFACE")

    port=${port:-5000}
    subnet=${subnet:-10.10.0.0/16}
    tun=${tun:-tun0}

    echo -e "${BLUE}╔══════════════════════════════════════════════════════════════╗${RESET}"
    echo -e "${BLUE}║${CYAN}  📋 CONFIGURAÇÕES ATUAIS ${BLUE}                                    ║${RESET}"
    echo -e "${BLUE}╠══════════════════════════════════════════════════════════════╣${RESET}"
    echo -e "${BLUE}║${WHITE}  ┣ Porta: ${BLUE}$(printf '%-51s' "$port")${BLUE}║${RESET}"
    echo -e "${BLUE}║${WHITE}  ┣ Sub-rede: ${BLUE}$(printf '%-48s' "$subnet")${BLUE}║${RESET}"
    echo -e "${BLUE}║${WHITE}  ┗ Interface TUN: ${BLUE}$(printf '%-43s' "$tun")${BLUE}║${RESET}"
    echo -e "${BLUE}╚══════════════════════════════════════════════════════════════╝${RESET}"
    echo

    validate_port() {
        local port_num=$1
        
        if ! [[ "$port_num" =~ ^[0-9]+$ ]]; then
            print_error "Porta deve ser um número!"
            return 1
        fi
       
        if [ "$port_num" -lt 1 ] || [ "$port_num" -gt 65535 ]; then
            print_error "Porta deve estar entre 1 e 65535!"
            return 1
        fi
        
        if [ "$port_num" -lt 1024 ] && [ "$EUID" -ne 0 ]; then
            print_warning "Portas abaixo de 1024 requerem privilégios de root!"
        fi
        
        return 0
    }

    check_port_available() {
        local port_num=$1
        
        if command -v netstat >/dev/null 2>&1; then
            if netstat -tuln | grep -q ":$port_num "; then
                print_error "Porta $port_num já está em uso!"
                return 1
            fi
        fi
        
        if command -v ss >/dev/null 2>&1; then
            if ss -tuln | grep -q ":$port_num "; then
                print_error "Porta $port_num já está em uso!"
                return 1
            fi
        fi
        
        if command -v nc >/dev/null 2>&1; then
            if nc -z 127.0.0.1 "$port_num" 2>/dev/null; then
                print_error "Porta $port_num já está em uso!"
                return 1
            fi
        fi
        
        return 0
    }

    while true; do
        echo -e "${BLUE}Porta (Enter para manter [$port]):${RESET}"
        read -rp "> " new_port_input
        
        if [ -z "$new_port_input" ]; then
            break
        fi
        
        if validate_port "$new_port_input" && check_port_available "$new_port_input"; then
            port="$new_port_input"
            print_success "Porta $port validada com sucesso!"
            break
        else
            print_warning "Por favor, insira uma porta válida e disponível."
            echo
        fi
    done

    echo -e "${BLUE}Sub-rede CIDR (Enter para manter [$subnet]):${RESET}"
    read -rp "> " new_subnet_input
    
    echo -e "${BLUE}Interface TUN (Enter para manter [$tun]):${RESET}"
    read -rp "> " new_tun_input

    if [ -n "$new_subnet_input" ]; then
        subnet="$new_subnet_input"
    fi
    if [ -n "$new_tun_input" ]; then
        tun="$new_tun_input"
    fi

    set_config_value "PORT" "$port"
    set_config_value "VIRTUAL_SUBNET_CIDR" "$subnet"
    set_config_value "TUN_INTERFACE" "$tun"
    
    print_success "Configurações salvas!"

    if create_systemd_service; then
        print_info "Iniciando servidor na porta $port..."
        if sudo systemctl start "$SERVICE_NAME"; then
            sudo systemctl enable "$SERVICE_NAME" &> /dev/null
            print_success "Servidor DTProto iniciado com sucesso!"
            
            sleep 2
            if sudo systemctl is-active --quiet "$SERVICE_NAME"; then
                print_success "Servidor está ativo e rodando na porta $port"
            else
                print_error "Servidor pode não ter iniciado corretamente."
                print_info "Verifique os logs: ${BLUE}sudo journalctl -u $SERVICE_NAME -f${RESET}"
            fi
        else
            print_error "Falha ao iniciar o serviço."
            print_info "Verifique os logs: ${BLUE}sudo journalctl -u $SERVICE_NAME -f${RESET}"
        fi
    fi
    pause
}

stop_server() {
    
    if is_server_active; then
        print_info "Parando serviço $SERVICE_NAME..."
        sudo systemctl stop "$SERVICE_NAME"
        print_success "Servidor parado."
    else
        print_error "Servidor não está ativo."
    fi
    pause
}

restart_server() {
    
    if is_server_active; then
        print_info "Reiniciando serviço $SERVICE_NAME..."
        sudo systemctl restart "$SERVICE_NAME"
        print_success "Servidor reiniciado."
    else
        print_error "Servidor não está ativo."
    fi
    pause
}

show_server_status() {
    print_header
    
    echo -e "${BLUE}╔══════════════════════════════════════════════════════════════╗${RESET}"
    echo -e "${BLUE}║${CYAN}  📊 STATUS DO SISTEMA${BLUE}                                        ║${RESET}"
    echo -e "${BLUE}╠══════════════════════════════════════════════════════════════╣${RESET}"
    
    local port=$(get_config_value 'PORT')
    local subnet=$(get_config_value 'VIRTUAL_SUBNET_CIDR')
    local tun=$(get_config_value 'TUN_INTERFACE')
    local auth_mode=$(get_config_value 'AUTH_MODE')
    auth_mode=${auth_mode:-$AUTH_MODE_FILE}
    local auth_url=$(get_config_value 'AUTH_URL')
    local token_status=$([ -f "$TOKEN_FILE" ] && echo '✅' || echo '❌')
    
    if is_server_active; then
        echo -e "${BLUE}║${WHITE}  ┣ Status: ${GREEN}🟢              ${BLUE}                                  ║${RESET}"
    else
        echo -e "${BLUE}║${WHITE}  ┣ Status: ${RED}🔴         ${BLUE}                                       ║${RESET}"
    fi
    
    echo -e "${BLUE}║${WHITE}  ┣ Porta: ${BLUE}$(printf '%-51s' "${port:-5000}")${BLUE}║${RESET}"
    echo -e "${BLUE}║${WHITE}  ┣ Sub-rede Virtual: ${BLUE}$(printf '%-40s' "${subnet:-10.10.0.0/16}")${BLUE}║${RESET}"
    echo -e "${BLUE}║${WHITE}  ┣ Interface TUN: ${BLUE}$(printf '%-43s' "${tun:-tun0}")${BLUE}║${RESET}"
    echo -e "${BLUE}║${WHITE}  ┣ Token Configurado: ${BLUE}$(printf '%-40s' "$token_status")${BLUE}║${RESET}"
    
    local auth_display=""
    case "$auth_mode" in
        $AUTH_MODE_FILE) auth_display="Arquivo" ;;
        $AUTH_MODE_URL) auth_display="URL ($auth_url)" ;;
        $AUTH_MODE_SSH) auth_display="SSH/PAM" ;; 
        $AUTH_MODE_NONE) auth_display="Nenhuma" ;;
        *) auth_display="Arquivo" ;;
    esac
    echo -e "${BLUE}║${WHITE}  ┗ Autenticação: ${BLUE}$(printf '%-44s' "$auth_display")${BLUE}║${RESET}"
    
    echo -e "${BLUE}╚══════════════════════════════════════════════════════════════╝${RESET}"
    echo

    pause
}

view_logs() {
    
    print_info "Exibindo logs (Ctrl+C para sair)..."
    echo
    sudo journalctl -u "$SERVICE_NAME" -f
    pause
}

get_auth_flag() {
    local auth_mode=$(get_config_value "AUTH_MODE")
    auth_mode=${auth_mode:-$AUTH_MODE_FILE}
    local auth_url=$(get_config_value "AUTH_URL")
    
    case "$auth_mode" in
        $AUTH_MODE_URL)
            if [[ -n "$auth_url" ]]; then
                echo "--auth-url=$auth_url"
            else
                echo "--auth-file=$CREDENTIALS_FILE"
            fi
            ;;
        $AUTH_MODE_SSH) 
            echo "--auth-url=http://127.0.0.1:5001/auth"
            ;;
        $AUTH_MODE_FILE)
            echo "--auth-file=$CREDENTIALS_FILE"
            ;;
        $AUTH_MODE_NONE)
            echo ""
            ;;
        *)
            echo "--auth-file=$CREDENTIALS_FILE"
            ;;
    esac
}

setup_ssh_auth() {
    print_info "Configurando autenticação SSH/PAM..."
    
    local SCRIPT_PATH="/usr/local/bin/ssh_auth.py"
    local VENV_PATH="/usr/local/bin/ssh_auth_venv"
    local SERVICE_NAME="ssh-auth-api"
    local SERVICE_FILE="/etc/systemd/system/ssh-auth-api.service"
    
    echo ">>> Atualizando pacotes..."
    sudo apt update -y

    echo ">>> Instalando dependências..."
    sudo apt install -y python3 python3-venv python3-pip curl systemd

    echo ">>> Instalando módulo PAM..."
    if ! sudo apt install -y python3-pam; then
        echo ">>> Pacote python3-pam não disponível, tentando via pip..."
        sudo pip3 install python-pam || sudo pip3 install pam
    fi

    echo ">>> Criando script ssh_auth.py..."
    sudo tee "$SCRIPT_PATH" > /dev/null << 'EOF'
import logging
from flask import Flask, request, jsonify
import pam

app = Flask(__name__)
logging.basicConfig(level=logging.INFO)

p = pam.pam()

@app.route('/auth', methods=['POST'])
def auth():
    if not request.json:
        return jsonify({'success': False, 'message': 'invalid request'}), 400

    username = request.json.get('username')
    password = request.json.get('password')

    if not username or not password:
        return jsonify({'success': False, 'message': 'username and password required'}), 400

    logging.info('Authentication request for user: %s', username)

    try:
        if p.authenticate(username, password):
            logging.info('Authentication successful for user: %s', username)
            return jsonify({'success': True, 'message': 'Authentication successful'}), 200
        else:
            logging.info('Authentication failed for user: %s', username)
            return jsonify({'success': False, 'message': 'invalid credentials'}), 401
    except Exception as e:
        logging.error('PAM error: %s', e)
        return jsonify({'success': False, 'message': 'authentication error'}), 500

if __name__ == '__main__':
    app.run(host='127.0.0.1', port=5001, debug=False)
EOF

    sudo chmod +x "$SCRIPT_PATH"

    echo ">>> Criando ambiente virtual..."
    sudo python3 -m venv "$VENV_PATH"
    sudo "$VENV_PATH/bin/pip" install --upgrade pip

    echo ">>> Instalando dependências no ambiente virtual..."
    sudo "$VENV_PATH/bin/pip" install flask six python-pam || sudo "$VENV_PATH/bin/pip" install flask six pam

    echo ">>> Criando serviço systemd..."
    sudo tee "$SERVICE_FILE" > /dev/null <<EOF
[Unit]
Description=SSH Auth Python Service
After=network.target

[Service]
Type=simple
ExecStart=${VENV_PATH}/bin/python ${SCRIPT_PATH}
WorkingDirectory=/usr/local/bin
Restart=on-failure
RestartSec=5
Environment=PYTHONUNBUFFERED=1

[Install]
WantedBy=multi-user.target
EOF

    echo ">>> Recarregando e iniciando serviço..."
    sudo systemctl daemon-reload
    sudo systemctl enable "$SERVICE_NAME"
    sudo systemctl restart "$SERVICE_NAME"

    sleep 2
    
    echo ">>> Verificando status do serviço..."
    if sudo systemctl is-active --quiet "$SERVICE_NAME"; then
        print_success "Serviço SSH Auth API criado e iniciado com sucesso!"
        print_info "API rodando em: http://127.0.0.1:5001/auth"
        
        set_config_value "AUTH_MODE" "$AUTH_MODE_SSH"
        set_config_value "AUTH_URL" "http://127.0.0.1:5001/auth"
        
        print_success "Autenticação SSH/PAM configurada com sucesso!"
    else
        print_error "Falha ao iniciar o serviço SSH Auth API."
        print_info "Verifique os logs: sudo journalctl -u ssh-auth-api -f"
        return 1
    fi
}

change_auth_mode() {
    print_header
    
    local current_mode=$(get_config_value "AUTH_MODE")
    current_mode=${current_mode:-$AUTH_MODE_FILE}
    local current_url=$(get_config_value "AUTH_URL")
    
    echo -e "${BLUE}╔══════════════════════════════════════════════════════════════╗${RESET}"
    echo -e "${BLUE}║${CYAN}                 ALTERAR MODO DE AUTENTICAÇÃO                 ${BLUE}║${RESET}"
    echo -e "${BLUE}╠══════════════════════════════════════════════════════════════╣${RESET}"
    
    local mode_line="${WHITE}  Modo atual: ${GREEN}$current_mode"
    local mode_padding=$((60 - ${#mode_line} + 22)) 
    printf "${BLUE}║${mode_line}%${mode_padding}s${BLUE}║${RESET}\n" ""
    
    if [[ "$current_mode" == "$AUTH_MODE_URL" && -n "$current_url" ]]; then
        local url_line="${WHITE}  URL atual: ${CYAN}$current_url"
        local url_padding=$((60 - ${#url_line} + 22)) 
        printf "${BLUE}║${url_line}%${url_padding}s${BLUE}║${RESET}\n" ""
    fi
    
    echo -e "${BLUE}╠══════════════════════════════════════════════════════════════╣${RESET}"
    
    local menu_items=(
        "1 • Arquivo ($CREDENTIALS_FILE)"
        "2 • URL personalizada"
        "3 • SSH (PAM Authentication)" 
        "4 • Sem autenticação"
        "0 • Voltar"
    )
    
    for item in "${menu_items[@]}"; do
        local padding=$((60 - ${#item}))
        if [[ $item == *"Voltar"* ]]; then
            printf "${BLUE}║${RED}  [${item%% *}] ${item#* • }%${padding}s${BLUE}║${RESET}\n" ""
        else
            printf "${BLUE}║${WHITE}  [${CYAN}${item%% *}${WHITE}] ${BLUE}${item#* • }%${padding}s${BLUE}║${RESET}\n" ""
        fi
    done
    
    echo -e "${BLUE}╚══════════════════════════════════════════════════════════════╝${RESET}"
    echo
    
    local option
    read -rp "$(echo -e "${BLUE}Selecione uma opção [0-4]:${RESET} ")" option 
    
    case "$option" in
        1)
            set_config_value "AUTH_MODE" "$AUTH_MODE_FILE"
            set_config_value "AUTH_URL" ""
            print_success "Modo de autenticação alterado para: Arquivo"
            ;;
        2)
            echo -e "${BLUE}Digite a URL de autenticação:${RESET}"
            read -rp "> " auth_url
            if [[ -n "$auth_url" ]]; then
                set_config_value "AUTH_MODE" "$AUTH_MODE_URL"
                set_config_value "AUTH_URL" "$auth_url"
                print_success "Modo de autenticação alterado para: URL ($auth_url)"
            else
                print_error "URL não pode ser vazia!"
            fi
            ;;
        3) 
            setup_ssh_auth
            ;;
        4) 
            set_config_value "AUTH_MODE" "$AUTH_MODE_NONE"
            set_config_value "AUTH_URL" ""
            print_success "Autenticação desativada"
            ;;
        0)
            return
            ;;
        *)
            print_error "Opção inválida!"
            ;;
    esac
    
    if is_server_active; then
        echo
        print_info "Reiniciando serviço para aplicar mudanças..."
        if create_systemd_service; then
            sudo systemctl restart "$SERVICE_NAME"
            print_success "Serviço reiniciado com nova configuração de autenticação!"
        else
            print_error "Falha ao atualizar o serviço."
        fi
    fi
    
    pause
}

change_port() {
    print_header
    
    local current_port=$(get_config_value "PORT")
    local is_running=$(is_server_active && echo "true" || echo "false")

    echo -e "${WHITE}Porta atual: ${BLUE}${current_port:-5000}${RESET}"

    validate_port() {
        local port_num=$1
        
        if ! [[ "$port_num" =~ ^[0-9]+$ ]]; then
            print_error "Porta deve ser um número!"
            return 1
        fi
        
        if [ "$port_num" -lt 1 ] || [ "$port_num" -gt 65535 ]; then
            print_error "Porta deve estar entre 1 e 65535!"
            return 1
        fi
        
        if [ "$port_num" -lt 1024 ] && [ "$EUID" -ne 0 ]; then
            print_warning "Portas abaixo de 1024 requerem privilégios de root!"
        fi
        
        return 0
    }

    check_port_available() {
        local port_num=$1
        
        if command -v netstat >/dev/null 2>&1; then
            if netstat -tuln | grep -q ":$port_num "; then
                print_error "Porta $port_num já está em uso!"
                return 1
            fi
        fi
        
        if command -v ss >/dev/null 2>&1; then
            if ss -tuln | grep -q ":$port_num "; then
                print_error "Porta $port_num já está em uso!"
                return 1
            fi
        fi
        
        if command -v nc >/dev/null 2>&1; then
            if nc -z 127.0.0.1 "$port_num" 2>/dev/null; then
                print_error "Porta $port_num já está em uso!"
                return 1
            fi
        fi

        if [ "$port_num" -eq "$current_port" ]; then
            print_warning "Esta já é a porta atual!"
            return 1
        fi
        
        return 0
    }

    local new_port
    while true; do
        echo -e "${BLUE}Nova porta (1-65535):${RESET}"
        read -rp "> " new_port
        
        new_port=$(echo "$new_port" | tr -d '\000-\037')
        
        if validate_port "$new_port" && check_port_available "$new_port"; then
            print_success "Porta $new_port validada com sucesso!"
            break
        else
            print_warning "Por favor, insira uma porta válida e disponível."
            echo
        fi
    done

    echo
    echo -e "${YELLOW}Alterar a porta de $current_port para $new_port${RESET}"
    echo -e "${YELLOW}Isso afetará todos os clientes conectados.${RESET}"
    
    if confirm_action "Deseja continuar?"; then
        set_config_value "PORT" "$new_port"
        print_success "Porta atualizada para $new_port"

        if [ "$is_running" == "true" ]; then
            print_info "Reiniciando servidor com nova configuração..."
            if create_systemd_service; then
                if sudo systemctl restart "$SERVICE_NAME"; then
                    print_success "Servidor reiniciado na porta $new_port!"
                    
                    sleep 2
                    if sudo systemctl is-active --quiet "$SERVICE_NAME"; then
                        print_success "Servidor está ativo e rodando na nova porta $new_port"
                    else
                        print_error "Servidor pode não ter reiniciado corretamente."
                        print_info "Verifique os logs: ${BLUE}sudo journalctl -u $SERVICE_NAME -f${RESET}"
                    fi
                else
                    print_error "Falha ao reiniciar o serviço."
                    print_info "Verifique os logs: ${BLUE}sudo journalctl -u $SERVICE_NAME -f${RESET}"
                fi
            else
                print_error "Falha ao atualizar o serviço systemd."
            fi
        else
            print_info "Servidor não está em execução. A nova porta será usada no próximo início."
        fi
    else
        print_info "Alteração de porta cancelada."
    fi
    
    pause
}

change_token_menu() {
    print_header
    
    local new_token
    while true; do
        echo -e "${BLUE}Insira o token:${RESET}"
        read -rp "> " new_token
        
        new_token=$(echo "$new_token" | tr -d '\000-\037')
        
        if [ -z "$new_token" ]; then
            print_error "Token não pode ser vazio."
            continue
        fi
       
        if validate_token "$new_token"; then
            save_unified_token "$new_token"
            break
        else
            print_error "Tente novamente."
        fi
    done

    if is_server_active; then
        print_info "Reiniciando servidor com novo token..."
        if create_systemd_service; then
            sudo systemctl restart "$SERVICE_NAME"
            print_success "Servidor reiniciado com novo token!"
        else
            print_error "Falha ao reiniciar o serviço."
        fi
    fi
    pause
}

check_or_set_token() {
    local current_token=$(load_token)
    
    if [ -z "$current_token" ]; then
        print_warning "Token de autenticação não encontrado."
        change_token_menu
    fi
}

check_token_on_startup() {
    if [ ! -f "$TOKEN_FILE" ]; then
        print_warning "Token de autenticação não encontrado!"
        print_info "Para usar o DTProto Server, você precisa configurar um token válido."
        echo
        
        change_token_menu
    fi
}

protocol_main_menu() {
    while true; do
        print_header
        print_status
        print_main_menu
        
        local option
        read -rp "$(echo -e "${BLUE}Selecione uma opção [1-8]:${RESET} ")" option
        
        case "$option" in
            1) start_server ;;
            2) stop_server ;;
            3) restart_server ;;
            4) show_server_status ;;
            5) view_logs ;;
            6) change_port ;;
            7) change_token_menu ;;
            8) change_auth_mode ;; 
            0) return 0 ;;
            *) 
                print_error "Opção inválida: $option"
                pause 
                ;;
        esac
    done
}

remove_completely() {
    print_header
    
    echo -e "${RED}╔══════════════════════════════════════════════════════════════╗${RESET}"
    echo -e "${RED}║${WHITE}                   ⚠️  REMOÇÃO COMPLETA ⚠️                    ${RED}║${RESET}"
    echo -e "${RED}║${WHITE}        Esta ação irá remover TODOS os dados e serviços       ${RED}║${RESET}"
    echo -e "${RED}╚══════════════════════════════════════════════════════════════╝${RESET}"
    echo
    echo -e "${YELLOW}Itens que serão removidos:${RESET}"
    echo -e "${WHITE}  • Serviço DTProto Server${RESET}"
    echo -e "${WHITE}  • Todos os serviços Proxy ativos${RESET}"
    echo -e "${WHITE}  • Serviço SSH Auth API${RESET}"
    echo -e "${WHITE}  • Ambiente virtual SSH Auth${RESET}"
    echo -e "${WHITE}  • Binários do sistema${RESET}"
    echo -e "${WHITE}  • Arquivos de configuração${RESET}"
    echo -e "${WHITE}  • Arquivos de dados e logs${RESET}"
    echo -e "${WHITE}  • Script de gerenciamento${RESET}"
    echo
    
    if ! confirm_action "${RED}TEM CERTEZA que deseja remover completamente?${RESET}" "n"; then
        print_info "Remoção cancelada."
        pause
        return
    fi
    
    print_info "Iniciando remoção completa..."
    
    if is_server_active; then
        print_info "Parando serviço $SERVICE_NAME..."
        sudo systemctl stop "$SERVICE_NAME"
        sudo systemctl disable "$SERVICE_NAME" 2>/dev/null
    fi
    
    print_info "Parando serviço SSH Auth API..."
    if systemctl is-active --quiet ssh-auth-api; then
        sudo systemctl stop ssh-auth-api
        sudo systemctl disable ssh-auth-api 2>/dev/null
        sudo rm -f "/etc/systemd/system/ssh-auth-api.service"
    fi
    
    print_info "Removendo arquivos SSH Auth API..."
    sudo rm -f "/usr/local/bin/ssh_auth.py"
    sudo rm -rf "/usr/local/bin/ssh_auth_venv" 
    
    print_info "Parando todos os serviços proxy..."
    for service in $(systemctl list-units --type=service --no-legend | grep "$PROXY_SERVICE_PREFIX" | awk '{print $1}'); do
        if systemctl is-active --quiet "$service"; then
            sudo systemctl stop "$service"
        fi
        sudo systemctl disable "$service" 2>/dev/null
        sudo rm -f "/etc/systemd/system/$service.service"
    done
    
    sudo systemctl daemon-reload
    sudo systemctl reset-failed
    
    print_info "Removendo arquivos de serviço..."
    sudo rm -f "/etc/systemd/system/$SERVICE_NAME.service"
    
    print_info "Removendo binários..."
    sudo rm -f "$PROTO_SERVER_BIN"
    sudo rm -f "$PROXY_EXECUTABLE"
    sudo rm -f "$PROTO_MANAGER_SCRIPT"
    
    print_info "Removendo configurações e dados..."
    sudo rm -rf "$(dirname "$TOKEN_FILE")"
    sudo rm -rf "$(dirname "$CONFIG_FILE")"
    sudo rm -rf "$DATA_DIR"
    sudo rm -rf "$PROXY_DIR"
    sudo rm -rf "$PROXY_LOG_DIR"
    
    if [[ -f "/usr/local/bin/proto" ]]; then
        sudo rm -f "/usr/local/bin/proto"
    fi
    
    print_success "Remoção completa concluída!"
    echo
    echo -e "${GREEN}Todos os serviços e arquivos foram removidos com sucesso.${RESET}"
    echo -e "${YELLOW}O sistema está limpo.${RESET}"
    echo
    
    pause
    exit 0
}

initial_menu() {
    while true; do
        print_header
        print_status
        print_initial_menu
        
        local option
        read -rp "$(echo -e "${BLUE}Selecione uma opção [1-3]:${RESET} ")" option
        
        case "$option" in
            1) protocol_main_menu ;;
            2) connection_menu ;;
            3) remove_completely ;;
            0) 
                print_info "Saindo..."
                exit 0 
                ;;
            *) 
                print_error "Opção inválida: $option"
                pause 
                ;;
        esac
    done
}

if [ "$EUID" -ne 0 ]; then
    print_error "Este script requer privilégios de root."
    echo -e "${YELLOW}Execute com: ${WHITE}sudo $0${RESET}"
    exit 1
fi

check_token_on_startup

initial_menu
