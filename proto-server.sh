#!/bin/bash

set -e

RED='\033[1;31m'
GREEN='\033[1;32m'
YELLOW='\033[1;33m'
BLUE='\033[1;34m'
CYAN='\033[1;36m'
MAGENTA='\033[1;35m'
NC='\033[0m'
BOLD='\033[1m'


BINARY_NAME="proto-server"
CONFIG_DIR="/etc/proto-server"
DATA_DIR="/var/lib/proto-server"
TOKEN_FILE="$CONFIG_DIR/token"
CONFIG_FILE="$CONFIG_DIR/config.conf"
SERVICE_NAME="proto-server"

print_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[✓]${NC} $1"
}

print_error() {
    echo -e "${RED}[✗]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[!]${NC} $1"
}

check_root() {
    if [ "$EUID" -ne 0 ]; then
        print_error "This script must be run as root (use sudo)"
        exit 1
    fi
}

check_binary() {
    if ! command -v "$BINARY_NAME" &> /dev/null; then
        print_error "Proto Server binary not found!"
        echo ""
        echo "Install it with:"
        echo "  curl -fsSL https://github.com/DTunnel0/DTProto-Server-Releases/releases/latest/download/install-server.sh | sudo bash"
        echo ""
        exit 1
    fi
}

init_dirs() {
    mkdir -p "$CONFIG_DIR"
    mkdir -p "$DATA_DIR"
}

validate_and_save_token() {
    local token=$1
    
    print_info "Validating token..."
    
    if "$BINARY_NAME" --token "$token" --validate 2>/dev/null; then
        echo "$token" > "$TOKEN_FILE"
        chmod 600 "$TOKEN_FILE"
        print_success "Token validated and saved!"
        return 0
    else
        print_error "Invalid token!"
        return 1
    fi
}

load_token() {
    if [ -f "$TOKEN_FILE" ]; then
        cat "$TOKEN_FILE"
    fi
}

ensure_token() {
    local token=$(load_token)
    
    if [ -z "$token" ]; then
        print_warning "No token configured!"
        
        while true; do
            read -p "Enter your authentication token: " token
            
            if [ -z "$token" ]; then
                print_error "Token cannot be empty!"
                continue
            fi
            
            if validate_and_save_token "$token"; then
                echo ""
                read -p "Press Enter to continue..."
                break
            else
                echo ""
                read -p "Try again? (Y/n): " retry
                if [[ "$retry" =~ ^[Nn]$ ]]; then
                    exit 1
                fi
            fi
        done
    fi
}

load_config() {
    if [ -f "$CONFIG_FILE" ]; then
        source "$CONFIG_FILE"
    else
        PORT=""
        SUBNET="10.10.0.0/16"
        TUN="tun0"
    fi
}

save_config() {
    cat > "$CONFIG_FILE" <<EOF
PORT=$PORT
SUBNET=$SUBNET
TUN=$TUN
EOF
    chmod 600 "$CONFIG_FILE"
}

is_running() {
    systemctl is-active --quiet "$SERVICE_NAME" 2>/dev/null
}

create_service() {
    local token=$1
    local auth_file="$DATA_DIR/credentials.json"
    local stats_file="$DATA_DIR/stats.json"
    local cert_file="$CONFIG_DIR/cert.pem"
    local key_file="$CONFIG_DIR/key.pem"
    
    if [ ! -f "$cert_file" ] || [ ! -f "$key_file" ]; then
        print_info "Generating TLS certificates..."
        openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
            -keyout "$key_file" \
            -out "$cert_file" \
            -subj "/C=BR/ST=State/L=City/O=ProtoServer/CN=proto-server" \
            2>/dev/null
        chmod 600 "$key_file"
        chmod 644 "$cert_file"
    fi
    
    if [ ! -f "$auth_file" ]; then
        echo '{"credentials":[]}' > "$auth_file"
        chmod 600 "$auth_file"
    fi
    
    if [ ! -f "$stats_file" ]; then
        echo '{}' > "$stats_file"
        chmod 644 "$stats_file"
    fi
    
    cat > "/etc/systemd/system/${SERVICE_NAME}.service" <<EOF
[Unit]
Description=Proto Server
After=network.target network-online.target
Wants=network-online.target

[Service]
Type=simple
User=root
Group=root
WorkingDirectory=/var/lib/proto-server
ExecStart=/usr/local/bin/$BINARY_NAME \\
    --token $token \\
    --listen-addr :$PORT \\
    --virtual-subnet-cidr $SUBNET \\
    --tun $TUN \\
    --auth-file $auth_file \\
    --stats-file $stats_file \\
    --tls-cert-file $cert_file \\
    --tls-key-file $key_file \\
    --tun-buffer-size 16384 \\
    --client-cleanup-interval 60 \\
    --client-inactive-timeout 120
Restart=always
RestartSec=10
StandardOutput=journal
StandardError=journal
SyslogIdentifier=proto-server

[Install]
WantedBy=multi-user.target
EOF
    
    systemctl daemon-reload
}

start_server() {    
    if is_running; then
        print_warning "Server is already running!"
        echo ""
        load_config
        echo "Current configuration:"
        echo "  Port: $PORT"
        echo "  TUN Interface: $TUN"
        echo "  Virtual Subnet: $SUBNET"
        echo ""
        read -p "Press Enter to continue..."
        return
    fi
    
    local token=$(load_token)
    load_config
    
    echo "Enter the port to start the server:"
    if [ -n "$PORT" ]; then
        read -p "Port [current: $PORT]: " new_port
        if [ -n "$new_port" ]; then
            PORT="$new_port"
        fi
    else
        read -p "Port: " PORT
    fi
    
    if [ -z "$PORT" ] || ! [[ "$PORT" =~ ^[0-9]+$ ]]; then
        print_error "Invalid port number!"
        read -p "Press Enter to continue..."
        return
    fi
    
    read -p "Virtual subnet CIDR [current: $SUBNET]: " new_subnet
    if [ -n "$new_subnet" ]; then
        SUBNET="$new_subnet"
    fi
    
    read -p "TUN interface name [current: $TUN]: " new_tun
    if [ -n "$new_tun" ]; then
        TUN="$new_tun"
    fi
    
    save_config
    
    echo ""
    print_info "Creating service..."
    create_service "$token"
    
    print_info "Starting server on port $PORT..."
    systemctl enable "$SERVICE_NAME" 2>/dev/null
    systemctl start "$SERVICE_NAME"
    
    sleep 2
    
    if is_running; then
        print_success "Server started successfully!"
        echo ""
        echo "Port: $PORT"
        echo "TUN Interface: $TUN"
        echo "Virtual Subnet: $SUBNET"
    else
        print_error "Failed to start server"
        echo "Check logs: journalctl -u $SERVICE_NAME -n 50"
    fi
    
    echo ""
    read -p "Press Enter to continue..."
}

stop_server() {
    if ! is_running; then
        print_warning "Server is not running!"
        read -p "Press Enter to continue..."
        return
    fi
    
    print_info "Stopping server..."
    systemctl stop "$SERVICE_NAME"
    
    sleep 2
    
    if ! is_running; then
        print_success "Server stopped successfully!"
    else
        print_error "Failed to stop server"
    fi
    
    echo ""
    read -p "Press Enter to continue..."
}

restart_server() {    
    if ! is_running; then
        print_warning "Server is not running. Use 'Start Server' instead."
        read -p "Press Enter to continue..."
        return
    fi
    
    print_info "Restarting server..."
    systemctl restart "$SERVICE_NAME"
    
    sleep 2
    
    if is_running; then
        print_success "Server restarted successfully!"
    else
        print_error "Failed to restart server"
    fi
    
    echo ""
    read -p "Press Enter to continue..."
}

show_status() {    
    if is_running; then
        print_success "Server is running"
        echo ""
        
        load_config
        
        echo "Configuration:"
        echo "  Port: $PORT"
        echo "  TUN Interface: $TUN"
        echo "  Virtual Subnet: $SUBNET"
        echo ""
        
        print_info "Systemd Status:"
        systemctl status "$SERVICE_NAME" --no-pager -l
    else
        print_warning "Server is not running"
        echo ""
        
        if [ -f "$CONFIG_FILE" ]; then
            load_config
            echo "Last known configuration:"
            echo "  Port: $PORT"
            echo "  TUN Interface: $TUN"
            echo "  Virtual Subnet: $SUBNET"
        fi
    fi
    
    echo ""
    read -p "Press Enter to continue..."
}

view_logs() {    
    if ! systemctl list-unit-files | grep -q "$SERVICE_NAME.service"; then
        print_warning "Service not configured yet!"
        read -p "Press Enter to continue..."
        return
    fi
    
    echo "Press Ctrl+C to stop following logs"
    echo ""
    sleep 2
    
    journalctl -u "$SERVICE_NAME" -f
}

change_token() {    
    local current_token=$(load_token)
    
    if [ -n "$current_token" ]; then
        echo "Current token: ${current_token:0:10}***"
        echo ""
    fi
    
    read -p "Enter new token: " new_token
    
    if [ -z "$new_token" ]; then
        print_error "Token cannot be empty!"
        read -p "Press Enter to continue..."
        return
    fi
    
    if ! validate_and_save_token "$new_token"; then
        echo ""
        read -p "Press Enter to continue..."
        return
    fi
    
    echo ""
    
    if is_running; then
        print_info "Updating service with new token..."
        create_service "$new_token"
        systemctl restart "$SERVICE_NAME"
        
        sleep 2
        
        if is_running; then
            print_success "Token updated and service restarted!"
        else
            print_error "Service failed to restart with new token"
        fi
    else
        print_success "Token updated! Start the server to use it."
    fi
    
    echo ""
    read -p "Press Enter to continue..."
}

change_port() {
    echo ""
    
    load_config
    
    if [ -z "$PORT" ]; then
        print_warning "Server not configured yet. Use 'Start Server' first."
        read -p "Press Enter to continue..."
        return
    fi
    
    echo "Current port: $PORT"
    echo ""
    
    if is_running; then
        print_warning "Server is running! It will be restarted with the new port."
        echo ""
    fi
    
    read -p "Enter new port: " new_port
    
    if [ -z "$new_port" ] || ! [[ "$new_port" =~ ^[0-9]+$ ]]; then
        print_error "Invalid port number!"
        read -p "Press Enter to continue..."
        return
    fi
    
    PORT="$new_port"
    save_config
    
    print_success "Port updated to $PORT"
    
    if is_running; then
        echo ""
        print_info "Recreating service..."
        local token=$(load_token)
        create_service "$token"
        
        print_info "Restarting server..."
        systemctl restart "$SERVICE_NAME"
        
        sleep 2
        
        if is_running; then
            print_success "Server restarted on new port!"
        else
            print_error "Failed to restart server"
        fi
    fi
    
    echo ""
    read -p "Press Enter to continue..."
}

show_menu() {
    clear

    if is_running; then
        load_config
        echo -e "${BOLD}${BLUE}╔════════════════════════════════╗${NC}"
        echo -e "${BOLD}${BLUE}║${NC}      ${GREEN}Proto Server Manager${NC}      ${BOLD}${BLUE}║${NC}"
        echo -e "${BOLD}${BLUE}║════════════════════════════════║${NC}"
        echo -e "${BOLD}${BLUE}║${NC} IP: ${GREEN}${SUBNET}${NC}               ${BOLD}${BLUE}║${NC}"
        echo -e "${BOLD}${BLUE}║${NC} Tun: ${GREEN}${TUN}${NC}                      ${BOLD}${BLUE}║${NC}"
        echo -e "${BOLD}${BLUE}║${NC} Port: ${GREEN}${PORT}${NC}                         ${BOLD}${BLUE}║${NC}"
        echo -e "${BOLD}${BLUE}║════════════════════════════════║${NC}"
    else
        echo -e "${BOLD}${BLUE}╔════════════════════════════════╗${NC}"
        echo -e "${BOLD}${BLUE}║${NC}      ${GREEN}Proto Server Manager${NC}      ${BOLD}${BLUE}║${NC}"
        echo -e "${BOLD}${BLUE}║════════════════════════════════║${NC}"
        echo -e "${BOLD}${BLUE}║${NC} ${RED}Status: Server is not running${NC}  ${BOLD}${BLUE}║${NC}"
        echo -e "${BOLD}${BLUE}║════════════════════════════════║${NC}"
    fi
    
    echo -e "${BOLD}${BLUE}║${NC} ${CYAN}[${GREEN}01${CYAN}]${NC} ${GREEN}•${RED} Start Server            ${BOLD}${BLUE}║${NC}"
    echo -e "${BOLD}${BLUE}║${NC} ${CYAN}[${GREEN}02${CYAN}]${NC} ${GREEN}•${RED} Stop Server             ${BOLD}${BLUE}║${NC}"
    echo -e "${BOLD}${BLUE}║${NC} ${CYAN}[${GREEN}03${CYAN}]${NC} ${GREEN}•${RED} Restart Server          ${BOLD}${BLUE}║${NC}"
    echo -e "${BOLD}${BLUE}║${NC} ${CYAN}[${GREEN}04${CYAN}]${NC} ${GREEN}•${RED} Server Status           ${BOLD}${BLUE}║${NC}"
    echo -e "${BOLD}${BLUE}║${NC} ${CYAN}[${GREEN}05${CYAN}]${NC} ${GREEN}•${RED} View Logs               ${BOLD}${BLUE}║${NC}"
    echo -e "${BOLD}${BLUE}║${NC} ${CYAN}[${GREEN}06${CYAN}]${NC} ${GREEN}•${RED} Change Port             ${BOLD}${BLUE}║${NC}"
    echo -e "${BOLD}${BLUE}║${NC} ${CYAN}[${GREEN}07${CYAN}]${NC} ${GREEN}•${RED} Change Token            ${BOLD}${BLUE}║${NC}"
    echo -e "${BOLD}${BLUE}║${NC} ${CYAN}[${GREEN}00${CYAN}]${NC} ${RED}•${RED} Exit                    ${BOLD}${BLUE}║${NC}"
    echo -e "${BOLD}${BLUE}╚════════════════════════════════╝${NC}"
    echo ""
    echo -ne "${BOLD}👉 Select option:${NC} "
}

main() {
    check_root
    check_binary
    init_dirs
    ensure_token
    
    while true; do
        show_menu
        read option

        case $option in
            1|01)
                start_server
                ;;
            2|02)
                stop_server
                ;;
            3|03)
                restart_server
                ;;
            4|04)
                show_status
                ;;
            5|05)
                view_logs
                ;;
            6|06)
                change_port
                ;;
            7|07)
                change_token
                ;;
            0|00)
                echo "Exiting..."
                exit 0
                ;;
            *)
                echo ""
                print_error "Invalid option!"
                sleep 2
                ;;
        esac
    done
}

main "$@"
