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

CONFIG_FILE="/etc/proto-server/config.json"
STATS_FILE="/etc/proto-server/stats.json"
SERVICE_NAME="proto-server.service"
INSTALLER_URL="https://raw.githubusercontent.com/DTunnel0/DTProto-Server-Releases/main/script/install-server.sh"
BINARY_PATH="/usr/local/bin/proto-server"
INNER_WIDTH=55
COL_WIDTH=27

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

wait_for_enter() {
    read -rp "$(format_prompt 'Pressione Enter para continuar...')" _
}

check_root() {
  if [[ "${EUID}" -ne 0 ]]; then
    print_message "ERROR" "Este menu deve ser executado como root (use sudo proto)."
    exit 1
  fi
}

visible_len() {
  local str="$1"
  local stripped
  stripped=$(echo -e "${str}" | sed -r 's/\x1B\[[0-9;]*[mK]//g')
  LC_ALL=C.UTF-8 echo "${#stripped}"
}

center_text() {
  local text="$1"
  local width="${2:-$INNER_WIDTH}"
  local vlen
  vlen=$(visible_len "$text")
  local pad=$(( (width - vlen) / 2 ))
  if (( pad < 0 )); then
    pad=0
  fi
  printf "%*s%s" $pad "" "$text"
}

draw_box_line() {
  local content="$1"
  local width="${2:-$INNER_WIDTH}"
  local vlen
  vlen=$(visible_len "${content}")
  local pad=$(( width - vlen ))
  if (( pad < 0 )); then
    pad=0
  fi
  local spaces
  spaces=$(printf '%*s' "${pad}" '')

  echo -e "${COLORS[TITLE]}║${COLORS[RESET]} ${content}${spaces} ${COLORS[TITLE]}║${COLORS[RESET]}"
}

draw_two_column_line() {
  local left_str="$1"
  local right_str="${2:-}"
  local col_width="${3:-$COL_WIDTH}"

  local left_vlen
  left_vlen=$(visible_len "${left_str}")
  local right_vlen
  right_vlen=$(visible_len "${right_str}")

  local left_pad=$(( col_width - left_vlen ))
  if (( left_pad < 0 )); then
    left_pad=0
  fi
  local left_spaces
  left_spaces=$(printf '%*s' "${left_pad}" '')

  local right_pad=$(( col_width - right_vlen ))
  if (( right_pad < 0 )); then
    right_pad=0
  fi
  local right_spaces
  right_spaces=$(printf '%*s' "${right_pad}" '')

  local line_content="${left_str}${left_spaces} ${right_str}${right_spaces}"
  draw_box_line "${line_content}" $INNER_WIDTH
}

draw_header() {
  local title="$1"
  local subtitle="${2:-}"
  local inner_width="${3:-$INNER_WIDTH}"
  local bar_width=$(( inner_width + 2 ))

  local line_bar
  line_bar=$(printf '═%.0s' $(seq 1 $bar_width))

  echo -e "${COLORS[TITLE]}╔${line_bar}╗${COLORS[RESET]}"
  draw_box_line "${COLORS[SUCCESS]}$(center_text "$title" $inner_width)${COLORS[RESET]}" $inner_width
  if [[ -n "$subtitle" ]]; then
    draw_box_line "${COLORS[INFO]}$(center_text "$subtitle" $inner_width)${COLORS[RESET]}" $inner_width
  fi
  echo -e "${COLORS[TITLE]}╠${line_bar}╣${COLORS[RESET]}"
}

draw_separator() {
  local inner_width="${1:-$INNER_WIDTH}"
  local bar_width=$(( inner_width + 2 ))
  local line_bar
  line_bar=$(printf '═%.0s' $(seq 1 $bar_width))
  echo -e "${COLORS[TITLE]}╠${line_bar}╣${COLORS[RESET]}"
}

draw_footer() {
  local inner_width="${1:-$INNER_WIDTH}"
  local bar_width=$(( inner_width + 2 ))
  local line_bar
  line_bar=$(printf '═%.0s' $(seq 1 $bar_width))
  echo -e "${COLORS[TITLE]}╚${line_bar}╝${COLORS[RESET]}"
}

draw_menu_option() {
  local num="$1"
  local label="$2"
  local inner_width="${3:-$INNER_WIDTH}"
  local line_str="${COLORS[INFO]}[${COLORS[SUCCESS]}${num}${COLORS[INFO]}] ${COLORS[SUCCESS]}• ${COLORS[ERROR]}${label}${COLORS[RESET]}"
  draw_box_line "${line_str}" $inner_width
}

format_option_str() {
  local num="$1"
  local label="$2"
  echo -e "${COLORS[INFO]}[${COLORS[SUCCESS]}${num}${COLORS[INFO]}] ${COLORS[SUCCESS]}• ${COLORS[ERROR]}${label}${COLORS[RESET]}"
}

get_installed_version() {
  if [[ ! -x "${BINARY_PATH}" ]]; then
    echo "v3.0.0"
    return
  fi

  local ver
  ver=$("${BINARY_PATH}" -v 2>/dev/null | awk '{print $NF}' | sed 's/^v//i' || true)
  if [[ -n "${ver}" ]]; then
    echo "v${ver}"
    return
  fi

  echo "v3.0.0"
}

get_online_users() {
  if [[ ! -f "${STATS_FILE}" ]]; then
    echo "0"
    return
  fi
  jq 'if type == "object" then length else 0 end' "${STATS_FILE}" 2>/dev/null || echo "0"
}

get_service_status() {
  if systemctl is-active --quiet "${SERVICE_NAME}" 2>/dev/null; then
    echo -e "${COLORS[SUCCESS]}EM EXECUÇÃO (ONLINE)${COLORS[RESET]}"
    return
  fi

  echo -e "${COLORS[ERROR]}DESLIGADO (OFFLINE)${COLORS[RESET]}"
}

get_config_value() {
  local key="$1"
  if [[ ! -f "${CONFIG_FILE}" ]]; then
    echo ""
    return
  fi

  if [[ "${key}" == "proxy.listen" ]]; then
    jq -r '.proxy.listen // .proxy.ports // [] | map(if type == "object" then (if .ssl then "ssl:" else "" end) + (.port | tostring) else tostring end) | join(",")' "${CONFIG_FILE}" 2>/dev/null || echo ""
    return
  fi

  local val
  val=$(jq -r ".${key} // empty" "${CONFIG_FILE}" 2>/dev/null || echo "")
  if [[ -z "${val}" || "${val}" == "null" ]]; then
    echo ""
    return
  fi

  echo "${val}"
}

get_auth_description() {
  if [[ ! -f "${CONFIG_FILE}" ]]; then
    echo "Usuários do Sistema"
    return
  fi

  local url file
  url=$(jq -r '.server.auth.url // empty' "${CONFIG_FILE}" 2>/dev/null || true)
  if [[ -n "${url}" && "${url}" != "null" ]]; then
    echo "API WEB (${url})"
    return
  fi

  file=$(jq -r '.server.auth.file // empty' "${CONFIG_FILE}" 2>/dev/null || true)
  if [[ -n "${file}" && "${file}" != "null" ]]; then
    echo "Arquivo (${file})"
    return
  fi

  echo "Usuários do Sistema"
}

save_token_to_config() {
  local new_token="$1"
  local tmp
  tmp=$(mktemp)
  jq --arg token "${new_token}" '.server.token = $token' "${CONFIG_FILE}" > "${tmp}" && mv "${tmp}" "${CONFIG_FILE}"
}

validate_token_with_binary() {
  local token="$1"
  if [[ -z "${token}" ]]; then
    return 1
  fi

  if [[ "${SKIP_TOKEN_VALIDATION:-false}" == "true" ]]; then
    return 0
  fi

  if [[ ! -x "${BINARY_PATH}" ]]; then
    return 0
  fi

  "${BINARY_PATH}" --validate --token "${token}" >/dev/null 2>&1
}

ensure_valid_token() {
  local token
  token=$(get_config_value "server.token")

  if validate_token_with_binary "${token}"; then
    return 0
  fi

  clear
  draw_header "VALIDAÇÃO DO TOKEN DE ACESSO" "Autenticação Obrigatória"
  if [[ -z "${token}" ]]; then
    draw_box_line "${COLORS[WARN]}Nenhum Token encontrado na configuração.${COLORS[RESET]}"
  fi
  if [[ -n "${token}" ]]; then
    draw_box_line "${COLORS[ERROR]}O Token cadastrado é inválido ou expirou.${COLORS[RESET]}"
  fi
  draw_footer

  echo ""
  while true; do
    token=$(read_input "Por favor, insira seu token de autenticação")
    token=$(echo "${token}" | xargs)

    if [[ -z "${token}" ]]; then
      print_message "ERROR" "O token não pode ser vazio."
      continue
    fi

    print_message "INFO" "Validando token no servidor..."
    if validate_token_with_binary "${token}"; then
      save_token_to_config "${token}"
      systemctl restart "${SERVICE_NAME}" 2>/dev/null || true
      print_message "SUCCESS" "Token validado e salvo em ${CONFIG_FILE}!"
      sleep 1.5
      return 0
    fi

    print_message "ERROR" "Token inválido. Por favor, forneça um token válido."
    echo ""
  done
}

display_main_menu() {
  local status version online_users proxy_ports
  status=$(get_service_status)
  version=$(get_installed_version)
  online_users=$(get_online_users)
  proxy_ports=$(get_config_value "proxy.listen")

  if [[ -z "${proxy_ports}" ]]; then
    proxy_ports="Nenhuma"
  fi

  draw_header "DTPROTO SERVER MANAGER • ${version}"
  draw_box_line "Status:      ${status}"
  draw_box_line "Conectados:  ${COLORS[SUCCESS]}${online_users}${COLORS[RESET]}"
  draw_box_line "Portas:      ${COLORS[WARN]}${proxy_ports}${COLORS[RESET]}"

  draw_separator

  local opt01 opt02 opt03 opt04 opt05 opt06 opt07 opt00
  opt01=$(format_option_str "01" "GERENCIAR SERVIÇO")
  opt02=$(format_option_str "02" "GERENCIAR PORTAS")
  opt03=$(format_option_str "03" "AUTENTICAÇÃO")
  opt04=$(format_option_str "04" "ALTERAR TOKEN")
  opt05=$(format_option_str "05" "VER LOGS")
  opt06=$(format_option_str "06" "ATUALIZAR")
  opt07=$(format_option_str "07" "DESINSTALAR")
  opt00=$(format_option_str "00" "SAIR")

  draw_two_column_line "${opt01}" "${opt05}"
  draw_two_column_line "${opt02}" "${opt06}"
  draw_two_column_line "${opt03}" "${opt07}"
  draw_two_column_line "${opt04}" "${opt00}"

  draw_footer
}

menu_service_control() {
  while true; do
    clear
    local status
    status=$(get_service_status)

    draw_header "GERENCIAMENTO DO SERVIÇO"
    draw_box_line "Status Atual: ${status}"
    draw_separator
    draw_menu_option "01" "INICIAR SERVIÇO"
    draw_menu_option "02" "PARAR SERVIÇO"
    draw_menu_option "03" "REINICIAR SERVIÇO"
    draw_menu_option "00" "VOLTAR"
    draw_footer
    echo ""

    local choice
    choice=$(read_input "Digite sua opção")

    case "${choice}" in
      1 | 01)
        systemctl start "${SERVICE_NAME}"
        print_message "SUCCESS" "Serviço iniciado com sucesso!"
        sleep 1.5
        ;;
      2 | 02)
        systemctl stop "${SERVICE_NAME}"
        print_message "WARN" "Serviço parado!"
        sleep 1.5
        ;;
      3 | 03)
        systemctl restart "${SERVICE_NAME}"
        print_message "SUCCESS" "Serviço reiniciado com sucesso!"
        sleep 1.5
        ;;
      0 | 00) break ;;
      *)
        print_message "ERROR" "Opção inválida."
        sleep 1
        ;;
    esac
  done
}

add_port_flow() {
  echo ""
  print_message "INFO" "Configuração de Porta do Proxy"
  echo ""

  local host port ssl_choice is_ssl custom_msg custom_ssh_port ssh_choice is_ssh_only custom_buf custom_cert
  host=$(read_input "Digite o Host de escuta" "0.0.0.0")
  host=$(echo "${host}" | xargs)

  while true; do
    port=$(read_input "Digite o número da porta (ex: 8080, 8443)")
    port=$(echo "${port}" | xargs)
    if [[ "${port}" =~ ^[0-9]+$ ]] && (( port >= 1 && port <= 65535 )); then
      break
    fi
    print_message "ERROR" "Porta inválida. Digite um número entre 1 e 65535."
  done

  read -rp "$(format_prompt "Habilitar SSL/TLS nesta porta?") (s/n) [n]: " ssl_choice
  is_ssl=false
  if [[ "${ssl_choice,,}" =~ ^(s|sim)$ ]]; then
    is_ssl=true
  fi

  read -rp "$(format_prompt "Mensagem HTTP personalizada?") [Enter para padrão/DTunnel]: " custom_msg
  custom_msg=$(echo "${custom_msg}" | xargs)

  read -rp "$(format_prompt "Porta SSH do encaminhamento?") [Enter para padrão/22]: " custom_ssh_port
  custom_ssh_port=$(echo "${custom_ssh_port}" | xargs)

  read -rp "$(format_prompt "Restringir a Somente SSH?") (s/n) [n]: " ssh_choice
  is_ssh_only=false
  if [[ "${ssh_choice,,}" =~ ^(s|sim)$ ]]; then
    is_ssh_only=true
  fi

  read -rp "$(format_prompt "Buffer de conexão em bytes?") [Enter para padrão/32768]: " custom_buf
  custom_buf=$(echo "${custom_buf}" | xargs)

  read -rp "$(format_prompt "Certificado SSL (.pem/.crt)") [Enter para interno/padrão]: " custom_cert
  custom_cert=$(echo "${custom_cert}" | xargs)

  local obj
  obj=$(jq -n \
    --arg host "${host:-0.0.0.0}" \
    --argjson port "${port}" \
    --argjson ssl "${is_ssl}" \
    --arg msg "${custom_msg}" \
    --arg ssh_port "${custom_ssh_port}" \
    --argjson ssh_only "${is_ssh_only}" \
    --arg buf "${custom_buf}" \
    --arg cert "${custom_cert}" \
    '{
      host: $host,
      port: $port,
      ssl: $ssl
    }
    + (if $msg != "" then {message: $msg} else {} end)
    + (if $ssh_port != "" and ($ssh_port | test("^[0-9]+$")) then {ssh_port: ($ssh_port | tonumber)} else {} end)
    + (if $ssh_only then {ssh_only: true} else {} end)
    + (if $buf != "" and ($buf | test("^[0-9]+$")) then {buffer_size: ($buf | tonumber)} else {} end)
    + (if $cert != "" then {cert_file: $cert} else {} end)'
  )

  local tmp
  tmp=$(mktemp)
  jq --argjson new_obj "${obj}" --argjson port_num "${port}" '
    .proxy = (.proxy // {}) |
    .proxy.listen = (
      [(.proxy.listen // .proxy.ports // [])[] | select(
        if type == "object" then .port != $port_num
        else (tostring | split(":") | last | tonumber) != $port_num end
      )] + [$new_obj]
    ) |
    del(.proxy.listener, .proxy.listeners, .proxy.ports)
  ' "${CONFIG_FILE}" > "${tmp}" && mv "${tmp}" "${CONFIG_FILE}"

  systemctl restart "${SERVICE_NAME}" 2>/dev/null || true
  print_message "SUCCESS" "Porta '${host}:${port}' configurada com sucesso!"
  sleep 1.5
}

remove_port_flow() {
  local count
  count=$(jq -r '.proxy.listen // .proxy.ports // [] | length' "${CONFIG_FILE}" 2>/dev/null || echo "0")

  if [[ "${count}" -eq 0 ]]; then
    print_message "WARN" "Não há portas cadastradas."
    sleep 1.5
    return
  fi

  clear
  draw_header "REMOVER PORTA"

  local idx=1
  while read -r p; do
    if [[ -n "${p}" ]]; then
      local num_str
      printf -v num_str "%02d" "${idx}"
      draw_menu_option "${num_str}" "${p}"
      ((idx++))
    fi
  done < <(jq -r '.proxy.listen // .proxy.ports // [] | .[] | if type == "object" then (.host // "0.0.0.0") + ":" + (if .ssl then "ssl:" else "" end) + (.port | tostring) else tostring end' "${CONFIG_FILE}" 2>/dev/null)

  draw_menu_option "00" "CANCELAR"
  draw_footer
  echo ""

  local rem_choice
  rem_choice=$(read_input "Digite o número da porta a remover")

  if [[ "${rem_choice}" == "0" ]] || [[ "${rem_choice}" == "00" ]] || [[ -z "${rem_choice}" ]]; then
    return
  fi

  local index=$(( 10#${rem_choice} - 1 ))
  local tmp
  tmp=$(mktemp)
  jq --argjson idx "${index}" '
    .proxy = (.proxy // {}) |
    .proxy.listen = [(.proxy.listen // .proxy.ports // []) | keys[] as $i | select($i != $idx) | (.proxy.listen // .proxy.ports)[$i]] |
    del(.proxy.listener, .proxy.listeners, .proxy.ports)
  ' "${CONFIG_FILE}" > "${tmp}" && mv "${tmp}" "${CONFIG_FILE}"

  systemctl restart "${SERVICE_NAME}" 2>/dev/null || true
  print_message "SUCCESS" "Porta removida com sucesso!"
  sleep 1.5
}

menu_ports() {
  while true; do
    clear
    local proxy_ports
    proxy_ports=$(get_config_value "proxy.listen")

    if [[ -z "${proxy_ports}" ]]; then
      proxy_ports="Nenhuma"
    fi

    draw_header "GERENCIAMENTO DE PORTAS"
    draw_box_line "Portas: ${COLORS[WARN]}${proxy_ports}${COLORS[RESET]}"
    draw_separator
    draw_menu_option "01" "ABRIR PORTA"
    draw_menu_option "02" "FECHAR PORTA"
    draw_menu_option "00" "VOLTAR"
    draw_footer
    echo ""

    local choice
    choice=$(read_input "Digite sua opção")

    case "${choice}" in
      1 | 01) add_port_flow ;;
      2 | 02) remove_port_flow ;;
      0 | 00) break ;;
      *) print_message "ERROR" "Opção inválida."; sleep 1 ;;
    esac
  done
}

menu_auth() {
  while true; do
    clear
    local current_auth
    current_auth=$(get_auth_description)

    draw_header "AUTENTICAÇÃO DE USUÁRIOS"
    draw_box_line "Modo Atual: ${COLORS[INFO]}${current_auth}${COLORS[RESET]}"
    draw_separator
    draw_menu_option "01" "USUÁRIOS DO SISTEMA"
    draw_menu_option "02" "API WEB"
    draw_menu_option "03" "ARQUIVO DE USUÁRIOS"
    draw_menu_option "00" "VOLTAR"
    draw_footer
    echo ""

    local choice
    choice=$(read_input "Digite sua opção")

    case "${choice}" in
      1 | 01)
        local tmp
        tmp=$(mktemp)
        jq '.server.auth = {"system": true, "url": "", "file": ""}' "${CONFIG_FILE}" > "${tmp}" && mv "${tmp}" "${CONFIG_FILE}"
        systemctl restart "${SERVICE_NAME}" 2>/dev/null || true
        print_message "SUCCESS" "Autenticação via Usuários do Sistema configurada!"
        sleep 1.5
        ;;
      2 | 02)
        local api_url
        api_url=$(read_input "Digite a URL da API Web (ex: https://exemple.com/auth)")
        api_url=$(echo "${api_url}" | xargs)
        if [[ -n "${api_url}" ]]; then
          local tmp
          tmp=$(mktemp)
          jq --arg url "${api_url}" '.server.auth = {"url": $url, "system": false, "file": ""}' "${CONFIG_FILE}" > "${tmp}" && mv "${tmp}" "${CONFIG_FILE}"
          systemctl restart "${SERVICE_NAME}" 2>/dev/null || true
          print_message "SUCCESS" "Autenticação via API Web configurada!"
          sleep 1.5
        fi
        ;;
      3 | 03)
        local default_cred_file="/etc/proto-server/credentials.json"
        local user_file
        user_file=$(read_input "Caminho do arquivo de usuários" "${default_cred_file}")
        user_file=$(echo "${user_file}" | xargs)
        if [[ -z "${user_file}" ]]; then
          user_file="${default_cred_file}"
        fi

        if [[ ! -f "${user_file}" ]]; then
          mkdir -p "$(dirname "${user_file}")"
          cat <<EOF > "${user_file}"
{
  "credentials": [
    {
      "user": "Dtunnel",
      "pass": "Dtunnel"
    }
  ]
}
EOF
          print_message "INFO" "Criado arquivo padrão de credenciais em ${user_file}"
        fi

        local tmp
        tmp=$(mktemp)
        jq --arg file "${user_file}" '.server.auth = {"file": $file, "system": false, "url": ""}' "${CONFIG_FILE}" > "${tmp}" && mv "${tmp}" "${CONFIG_FILE}"
        systemctl restart "${SERVICE_NAME}" 2>/dev/null || true
        print_message "SUCCESS" "Autenticação via Arquivo de Usuários configurada!"
        sleep 1.5
        ;;
      0 | 00) break ;;
      *) print_message "ERROR" "Opção inválida."; sleep 1 ;;
    esac
  done
}

menu_token() {
  clear
  local current_token
  current_token=$(get_config_value 'server.token')

  draw_header "ALTERAR TOKEN DE AUTENTICAÇÃO"
  draw_box_line "Token Atual: ${COLORS[INFO]}${current_token:-Não definido}${COLORS[RESET]}"
  draw_footer
  echo ""

  local new_token
  new_token=$(read_input "Digite o novo Token de Autenticação")
  new_token=$(echo "${new_token}" | xargs)
  if [[ -z "${new_token}" ]]; then
    return
  fi

  print_message "INFO" "Validando novo token..."
  if validate_token_with_binary "${new_token}"; then
    save_token_to_config "${new_token}"
    systemctl restart "${SERVICE_NAME}" || true
    print_message "SUCCESS" "Token validado, salvo em ${CONFIG_FILE} e serviço reiniciado!"
    sleep 1.5
    return
  fi

  print_message "ERROR" "Token inválido! A alteração não foi salva."
  sleep 1.5
}

view_logs() {
  clear
  print_message "INFO" "Exibindo logs em tempo real (Pressione Ctrl+C para voltar ao menu)..."
  echo ""
  trap 'trap - INT; return 0' INT
  journalctl -u "${SERVICE_NAME}" -f -n 50 2>/dev/null || true
  trap - INT
}

update_server() {
  clear
  print_message "INFO" "Baixando instalador e atualizando para a versão mais recente..."
  bash <(curl -sL "${INSTALLER_URL}")
  print_message "SUCCESS" "Atualização concluída!"
  wait_for_enter
}

uninstall_server() {
  clear
  draw_header "DESINSTALAR SERVIDOR" "Atenção: Ação Destrutiva"
  draw_box_line "${COLORS[ERROR]}Esta ação removerá completamente o DTProto Server,${COLORS[RESET]}"
  draw_box_line "${COLORS[ERROR]}serviços systemd e arquivos de configuração.${COLORS[RESET]}"
  draw_footer
  echo ""

  read -rp "$(format_prompt 'Tem certeza que deseja desinstalar?') (s/n) [n]: " confirm
  if [[ ! "${confirm,,}" =~ ^(s|sim)$ ]]; then
    return
  fi

  systemctl stop "${SERVICE_NAME}" 2>/dev/null || true
  systemctl disable "${SERVICE_NAME}" 2>/dev/null || true
  rm -f "/etc/systemd/system/${SERVICE_NAME}"
  systemctl daemon-reload
  rm -f /usr/local/bin/proto-server /usr/local/bin/proto
  rm -rf /etc/proto-server
  print_message "SUCCESS" "DTProto Server desinstalado com sucesso!"
  exit 0
}

main_menu() {
  check_root
  ensure_valid_token

  while true; do
    clear
    display_main_menu
    echo ""
    local choice
    choice=$(read_input "Digite sua opção")

    case "${choice}" in
      1 | 01) menu_service_control ;;
      2 | 02) menu_ports ;;
      3 | 03) menu_auth ;;
      4 | 04) menu_token ;;
      5 | 05) view_logs ;;
      6 | 06) update_server ;;
      7 | 07) uninstall_server ;;
      0 | 00)
        print_message "EXIT" "Saindo. Até logo!"
        exit 0
        ;;
      *)
        print_message "ERROR" "Opção inválida."
        sleep 1
        ;;
    esac
  done
}

main_menu "$@"
