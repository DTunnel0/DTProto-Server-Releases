#!/usr/bin/env bash

set -euo pipefail

declare -A COLORS=(
    ["INFO"]="\033[1;36m"
    ["WARN"]="\033[1;33m"
    ["ERROR"]="\033[1;31m"
    ["SUCCESS"]="\033[1;32m"
    ["EXIT"]="\033[1;32m"
    ["TITLE"]="\033[1;34m"
    ["PROMPT"]="\033[1;33m"
    ["RESET"]="\033[0m"
)

CONFIG_FILE="/etc/proto-server/config.json"
STATS_FILE="/etc/proto-server/stats.json"
SERVICE_NAME="proto-server.service"
INSTALLER_URL="https://raw.githubusercontent.com/DTunnel0/DTProto-Server-Releases/main/install-server.sh"
BINARY_PATH="/usr/local/bin/proto-server"
PAM_SERVICE_FILE="/etc/pam.d/proto-server"
INNER_WIDTH=55
COL_WIDTH=27
INPUT_EOF="__DTPROTO_INPUT_EOF__"

print_message() {
    local type="$1"
    local message="$2"
    local prefix="[INFO]"
    case "$type" in
        "SUCCESS") prefix="[OK]" ;;
        "WARN")    prefix="[AVISO]" ;;
        "ERROR")   prefix="[ERRO]" ;;
        "PROMPT")  prefix="[>]" ;;
        "EXIT")    prefix="[SAIR]" ;;
    esac
    local color="${COLORS[$type]:-${COLORS[INFO]}}"
    printf '%b%s %s%b\n' "${color}" "${prefix}" "${message}" "${COLORS[RESET]}" >&2
}

format_prompt() {
    echo -e "${COLORS[PROMPT]}[>] $1${COLORS[RESET]}"
}

read_input() {
    local prompt_text="$1"
    local default_value="${2:-}"
    local default_label="${3:-$default_value}"
    local value

    if [[ -n "$default_value" && ${#default_label} -gt 15 ]]; then
        printf '%s\n' "$(format_prompt "Padrão: [${default_label}]")" >&2
        if ! read -r -p "$(format_prompt "$prompt_text"): " value; then
            echo "${INPUT_EOF}"
            return 0
        fi
        echo "${value:-$default_value}"
        return
    fi

    if [[ -n "$default_value" ]]; then
        if ! read -r -p "$(format_prompt "$prompt_text") [${default_label}]: " value; then
            echo "${INPUT_EOF}"
            return 0
        fi
        echo "${value:-$default_value}"
        return
    fi

    if ! read -r -p "$(format_prompt "$prompt_text"): " value; then
        echo "${INPUT_EOF}"
        return 0
    fi
    echo "$value"
}

wait_for_enter() {
    read -r -p "$(format_prompt 'Pressione Enter para continuar...')" _ || true
}

clear_screen() {
  if [[ -t 1 ]]; then
    printf '\033[2J\033[H'
  fi
}

trim_input() {
  local value="$1"
  value="${value#"${value%%[![:space:]]*}"}"
  value="${value%"${value##*[![:space:]]}"}"
  printf '%s' "${value}"
}

shorten_text() {
  local value="$1"
  local max_length="${2:-42}"
  if (( ${#value} <= max_length )); then
    printf '%s' "${value}"
    return
  fi
  printf '...%s' "${value: -$((max_length - 3))}"
}

normalize_choice() {
  local value
  value=$(trim_input "$1")
  if [[ "${value}" == "${INPUT_EOF}" ]]; then
    printf '0'
    return
  fi
  if [[ -z "${value}" ]]; then
    printf '0'
    return
  fi
  if [[ "${value}" =~ ^[0-9]+$ && ${#value} -le 2 ]]; then
    printf '%d' "$((10#${value}))"
    return
  fi
  printf '%s' "${value}"
}

valid_port() {
  local value="$1"
  [[ "${value}" =~ ^[0-9]+$ ]] || return 1
  (( ${#value} <= 5 )) || return 1
  local decimal=$((10#${value}))
  (( decimal >= 1 && decimal <= 65535 ))
}

valid_positive_integer() {
  local value="$1"
  [[ "${value}" =~ ^[0-9]+$ ]] || return 1
  (( ${#value} <= 10 )) || return 1
  (( 10#${value} > 0 ))
}

update_config() {
  local tmp
  tmp=$(mktemp "${CONFIG_FILE}.tmp.XXXXXX")
  if jq "$@" "${CONFIG_FILE}" > "${tmp}"; then
    chmod 0600 "${tmp}"
    mv "${tmp}" "${CONFIG_FILE}"
    return 0
  fi

  unlink "${tmp}"
  print_message "ERROR" "Não foi possível atualizar ${CONFIG_FILE}."
  return 1
}

restart_service() {
  if systemctl restart "${SERVICE_NAME}"; then
    return 0
  fi
  print_message "ERROR" "A configuração foi salva, mas o serviço não reiniciou."
  return 1
}

run_service_action() {
  local action="$1"
  local success_message="$2"
  if systemctl "${action}" "${SERVICE_NAME}"; then
    print_message "SUCCESS" "${success_message}"
    sleep 1.5
    return 0
  fi
  print_message "ERROR" "Falha ao executar '${action}' no serviço."
  sleep 1.5
}

check_root() {
  if [[ "${EUID}" -ne 0 ]]; then
    print_message "ERROR" "Este menu deve ser executado como root (use sudo proto)."
    exit 1
  fi
}

check_dependencies() {
  local command_name
  for command_name in jq systemctl; do
    if command -v "${command_name}" >/dev/null 2>&1; then
      continue
    fi
    print_message "ERROR" "Dependência ausente: ${command_name}."
    return 1
  done
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
  local stats_file
  stats_file=$(get_stats_file_path)
  if [[ ! -f "${stats_file}" ]]; then
    echo "0"
    return
  fi
  jq -r 'if type == "object" then length else 0 end' "${stats_file}" 2>/dev/null || echo "0"
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

get_stats_file_path() {
  local configured_path
  configured_path=$(get_config_value "server.stats_file")
  echo "${configured_path:-${STATS_FILE}}"
}

get_auth_description() {
  if [[ ! -f "${CONFIG_FILE}" ]]; then
    echo "Não configurada"
    return
  fi

  jq -r '
    .server.auth // {} |
    if .system then "PAM (proto-server)"
    elif (.file // "") != "" then "Arquivo de credenciais"
    elif (.url // "") != "" then "URL externa"
    else "Não configurada" end
  ' "${CONFIG_FILE}" 2>/dev/null || echo "Não configurada"
}

write_pam_service() {
  if ! cat <<'EOF' > "${PAM_SERVICE_FILE}"
auth required pam_unix.so nodelay
account required pam_unix.so
EOF
  then
    print_message "ERROR" "Não foi possível gravar a configuração PAM."
    return 1
  fi
  chmod 0644 "${PAM_SERVICE_FILE}"
}

save_token_to_config() {
  local new_token="$1"
  update_config --arg token "${new_token}" '.server.token = $token'
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
    return 1
  fi

  "${BINARY_PATH}" --validate --token "${token}" >/dev/null 2>&1
}

ensure_valid_token() {
  local token
  token=$(get_config_value "server.token")

  if validate_token_with_binary "${token}"; then
    return 0
  fi

  clear_screen
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
    token=$(read_input "Digite o token")
    if [[ "${token}" == "${INPUT_EOF}" ]]; then
      return 1
    fi
    token=$(trim_input "${token}")

    if [[ -z "${token}" ]]; then
      print_message "ERROR" "O token não pode ser vazio."
      continue
    fi

    print_message "INFO" "Validando token no servidor..."
    if validate_token_with_binary "${token}"; then
      if ! save_token_to_config "${token}"; then
        print_message "ERROR" "Não foi possível salvar o token."
        continue
      fi
      restart_service || true
      print_message "SUCCESS" "Token validado e salvo em ${CONFIG_FILE}!"
      sleep 1.5
      return 0
    fi

    print_message "ERROR" "Token inválido. Por favor, forneça um token válido."
    echo ""
  done
}

display_main_menu() {
  local status version online_users proxy_ports stats_file
  status=$(get_service_status)
  version=$(get_installed_version)
  online_users=$(get_online_users)
  proxy_ports=$(get_config_value "proxy.listen")
  stats_file=$(get_stats_file_path)

  if [[ -z "${proxy_ports}" ]]; then
    proxy_ports="Nenhuma"
  fi

  draw_header "DTPROTO SERVER MANAGER • ${version}"
  draw_box_line "Status:      ${status}"
  draw_box_line "Conectados:  ${COLORS[SUCCESS]}${online_users}${COLORS[RESET]}"
  draw_box_line "Stats:       $(shorten_text "${stats_file}")"
  draw_box_line "Portas:      ${COLORS[WARN]}${proxy_ports}${COLORS[RESET]}"

  draw_separator

  local opt01 opt02 opt03 opt04 opt05 opt06 opt07 opt08 opt00
  opt01=$(format_option_str "01" "GERENCIAR SERVIÇO")
  opt02=$(format_option_str "02" "GERENCIAR PORTAS")
  opt03=$(format_option_str "03" "AUTENTICAÇÃO")
  opt04=$(format_option_str "04" "ALTERAR TOKEN")
  opt05=$(format_option_str "05" "VER LOGS")
  opt06=$(format_option_str "06" "ATUALIZAR")
  opt07=$(format_option_str "07" "DESINSTALAR")
  opt08=$(format_option_str "08" "STATS")
  opt00=$(format_option_str "00" "SAIR")

  draw_two_column_line "${opt01}" "${opt05}"
  draw_two_column_line "${opt02}" "${opt06}"
  draw_two_column_line "${opt03}" "${opt07}"
  draw_two_column_line "${opt04}" "${opt08}"
  draw_two_column_line "${opt00}"

  draw_footer
}

menu_service_control() {
  while true; do
    clear_screen
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
    choice=$(normalize_choice "$(read_input "Escolha uma opção")")

    case "${choice}" in
      1) run_service_action start "Serviço iniciado com sucesso!" ;;
      2) run_service_action stop "Serviço parado com sucesso!" ;;
      3) run_service_action restart "Serviço reiniciado com sucesso!" ;;
      0) break ;;
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

  local host="0.0.0.0" port ssl_choice is_ssl custom_msg custom_ssh_port ssh_choice is_ssh_only custom_buf custom_cert

  while true; do
    port=$(read_input "Número da porta (1-65535)")
    [[ "${port}" == "${INPUT_EOF}" ]] && return 0
    port=$(trim_input "${port}")
    if valid_port "${port}"; then
      port=$((10#${port}))
      break
    fi
    print_message "ERROR" "Porta inválida. Digite um número entre 1 e 65535."
  done

  ssl_choice=$(read_input "Ativar SSL? (s/n)")
  [[ "${ssl_choice}" == "${INPUT_EOF}" ]] && return 0
  is_ssl=false
  if [[ "${ssl_choice,,}" =~ ^(s|sim)$ ]]; then
    is_ssl=true
  fi

  custom_msg=$(read_input "Mensagem HTTP (vazio = padrão)")
  [[ "${custom_msg}" == "${INPUT_EOF}" ]] && return 0
  custom_msg=$(trim_input "${custom_msg}")

  custom_ssh_port=$(read_input "Porta SSH (vazio = 22)")
  [[ "${custom_ssh_port}" == "${INPUT_EOF}" ]] && return 0
  custom_ssh_port=$(trim_input "${custom_ssh_port}")
  if [[ -n "${custom_ssh_port}" ]] && ! valid_port "${custom_ssh_port}"; then
    print_message "ERROR" "Porta SSH inválida. Use um número entre 1 e 65535."
    return 1
  fi

  ssh_choice=$(read_input "Usar somente SSH? (s/n)")
  [[ "${ssh_choice}" == "${INPUT_EOF}" ]] && return 0
  is_ssh_only=false
  if [[ "${ssh_choice,,}" =~ ^(s|sim)$ ]]; then
    is_ssh_only=true
  fi

  custom_buf=$(read_input "Buffer em bytes (vazio = 32768)")
  [[ "${custom_buf}" == "${INPUT_EOF}" ]] && return 0
  custom_buf=$(trim_input "${custom_buf}")
  if [[ -n "${custom_buf}" ]] && ! valid_positive_integer "${custom_buf}"; then
    print_message "ERROR" "Buffer inválido. Use um número maior que zero."
    return 1
  fi

  custom_cert=$(read_input "Certificado SSL (vazio = padrão)")
  [[ "${custom_cert}" == "${INPUT_EOF}" ]] && return 0
  custom_cert=$(trim_input "${custom_cert}")

  local obj
  obj=$(jq -n \
    --arg host "${host}" \
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

  update_config --argjson new_obj "${obj}" --argjson port_num "${port}" '
    .proxy = (.proxy // {}) |
    .proxy.listen = (
      [(.proxy.listen // .proxy.ports // [])[] | select(
        if type == "object" then .port != $port_num
        else (try (tostring | split(":") | last | tonumber) catch -1) != $port_num end
      )] + [$new_obj]
    ) |
    del(.proxy.listener, .proxy.listeners, .proxy.ports)
  '

  restart_service || true
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

  clear_screen
  draw_header "REMOVER PORTA"

  local idx=1
  while read -r p; do
    if [[ -n "${p}" ]]; then
      local num_str
      printf -v num_str "%02d" "${idx}"
      draw_menu_option "${num_str}" "${p}"
      idx=$((idx + 1))
    fi
  done < <(jq -r '.proxy.listen // .proxy.ports // [] | .[] | if type == "object" then (.host // "0.0.0.0") + ":" + (if .ssl then "ssl:" else "" end) + (.port | tostring) else tostring end' "${CONFIG_FILE}" 2>/dev/null)

  draw_menu_option "00" "CANCELAR"
  draw_footer
  echo ""

  local rem_choice
  rem_choice=$(normalize_choice "$(read_input "Escolha o número da porta")")

  if [[ "${rem_choice}" == "0" ]]; then
    return
  fi

  if [[ ! "${rem_choice}" =~ ^[0-9]+$ ]] || (( rem_choice < 1 || rem_choice > count )); then
    print_message "ERROR" "Seleção inválida. Escolha uma porta da lista."
    sleep 1.5
    return 0
  fi

  local index=$((rem_choice - 1))
  update_config --argjson idx "${index}" '
    (.proxy.listen // .proxy.ports // []) as $ports |
    .proxy = (.proxy // {}) |
    .proxy.listen = [$ports | to_entries[] | select(.key != $idx) | .value] |
    del(.proxy.listener, .proxy.listeners, .proxy.ports)
  '

  restart_service || true
  print_message "SUCCESS" "Porta removida com sucesso!"
  sleep 1.5
}

menu_ports() {
  while true; do
    clear_screen
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
    choice=$(normalize_choice "$(read_input "Escolha uma opção")")

    case "${choice}" in
      1) add_port_flow || true ;;
      2) remove_port_flow || true ;;
      0) break ;;
      *) print_message "ERROR" "Opção inválida."; sleep 1 ;;
    esac
  done
}

menu_auth() {
  while true; do
    clear_screen
    local current_auth
    current_auth=$(get_auth_description)

    draw_header "AUTENTICAÇÃO DE USUÁRIOS"
    draw_box_line "Modo Atual: ${COLORS[INFO]}${current_auth}${COLORS[RESET]}"
    draw_separator
    draw_menu_option "01" "PAM / SISTEMA"
    draw_menu_option "02" "ARQUIVO (JSON)"
    draw_menu_option "03" "URL EXTERNA"
    draw_menu_option "00" "VOLTAR"
    draw_footer
    echo ""

    local choice
    choice=$(normalize_choice "$(read_input "Escolha uma opção")")

    case "${choice}" in
      1)
        if ! update_config '.server.auth = {"system": true}'; then
          sleep 1.5
          continue
        fi
        if ! write_pam_service; then
          sleep 1.5
          continue
        fi
        restart_service || true
        print_message "SUCCESS" "Autenticação PAM dos usuários da máquina configurada!"
        sleep 1.5
        ;;
      2)
        local auth_file auth_file_default
        auth_file_default=$(get_config_value "server.auth.file")
        auth_file_default="${auth_file_default:-/etc/proto-server/credentials.json}"
        auth_file=$(read_input "Arquivo JSON (ex.: credentials.json)" "${auth_file_default}" "${auth_file_default}")
        [[ "${auth_file}" == "${INPUT_EOF}" ]] && continue
        auth_file=$(trim_input "${auth_file}")
        if [[ ! -f "${auth_file}" || ! -r "${auth_file}" ]]; then
          print_message "ERROR" "O arquivo não existe ou não pode ser lido."
          sleep 1.5
          continue
        fi
        if ! update_config --arg file "${auth_file}" '.server.auth = {"file": $file}'; then
          sleep 1.5
          continue
        fi
        restart_service || true
        print_message "SUCCESS" "Autenticação por arquivo configurada!"
        sleep 1.5
        ;;
      3)
        local auth_url auth_url_default
        auth_url_default=$(get_config_value "server.auth.url")
        auth_url_default="${auth_url_default:-https://auth.example.com/validate}"
        auth_url=$(read_input "URL HTTP/HTTPS (ex.: https://auth...)" "${auth_url_default}" "${auth_url_default}")
        [[ "${auth_url}" == "${INPUT_EOF}" ]] && continue
        auth_url=$(trim_input "${auth_url}")
        if [[ ! "${auth_url}" =~ ^https?://[^[:space:]]+$ ]]; then
          print_message "ERROR" "Informe uma URL HTTP ou HTTPS válida."
          sleep 1.5
          continue
        fi
        if ! update_config --arg url "${auth_url}" '.server.auth = {"url": $url}'; then
          sleep 1.5
          continue
        fi
        restart_service || true
        print_message "SUCCESS" "Autenticação por URL configurada!"
        sleep 1.5
        ;;
      0) break ;;
      *) print_message "ERROR" "Opção inválida."; sleep 1 ;;
    esac
  done
}

menu_stats() {
  while true; do
    clear_screen
    local current_path
    current_path=$(get_stats_file_path)

    draw_header "ARQUIVO DE STATS"
    draw_box_line "Arquivo: $(shorten_text "${current_path}")"
    draw_box_line "Usuários: ${COLORS[SUCCESS]}$(get_online_users)${COLORS[RESET]}"
    draw_separator
    draw_menu_option "01" "ALTERAR CAMINHO"
    draw_menu_option "00" "VOLTAR"
    draw_footer
    echo ""

    local choice
    choice=$(normalize_choice "$(read_input "Escolha uma opção")")
    case "${choice}" in
      1)
        local new_path parent_path
        new_path=$(read_input "Novo caminho do arquivo" "${current_path}" "$(shorten_text "${current_path}")")
        [[ "${new_path}" == "${INPUT_EOF}" ]] && continue
        new_path=$(trim_input "${new_path}")
        if [[ ! "${new_path}" =~ ^/ || -z "${new_path}" ]]; then
          print_message "ERROR" "Informe um caminho absoluto, por exemplo /var/lib/proto-server/stats.json."
          sleep 1.5
          continue
        fi
        parent_path=$(dirname -- "${new_path}")
        if [[ ! -d "${parent_path}" || ! -w "${parent_path}" ]]; then
          print_message "ERROR" "O diretório pai não existe ou não pode ser gravado."
          sleep 1.5
          continue
        fi
        if ! update_config --arg stats_file "${new_path}" '.server.stats_file = $stats_file'; then
          sleep 1.5
          continue
        fi
        restart_service || true
        print_message "SUCCESS" "Arquivo de stats configurado em ${new_path}."
        sleep 1.5
        ;;
      0) break ;;
      *) print_message "ERROR" "Opção inválida."; sleep 1 ;;
    esac
  done
}

menu_token() {
  clear_screen
  local current_token
  current_token=$(get_config_value 'server.token')

  draw_header "ALTERAR TOKEN DE AUTENTICAÇÃO"
  local token_status="Não definido"
  if [[ -n "${current_token}" ]]; then
    token_status="Configurado (oculto)"
  fi
  draw_box_line "Token Atual: ${COLORS[INFO]}${token_status}${COLORS[RESET]}"
  draw_footer
  echo ""

  local new_token
  new_token=$(read_input "Digite o novo token")
  [[ "${new_token}" == "${INPUT_EOF}" ]] && return 0
  new_token=$(trim_input "${new_token}")
  if [[ -z "${new_token}" ]]; then
    return
  fi

  print_message "INFO" "Validando novo token..."
  if validate_token_with_binary "${new_token}"; then
    save_token_to_config "${new_token}"
    restart_service || true
    print_message "SUCCESS" "Token validado e salvo em ${CONFIG_FILE}!"
    sleep 1.5
    return
  fi

  print_message "ERROR" "Token inválido! A alteração não foi salva."
  sleep 1.5
}

view_logs() {
  clear_screen
  print_message "INFO" "Exibindo logs em tempo real (Pressione Ctrl+C para voltar ao menu)..."
  echo ""
  trap 'trap - INT; return 0' INT
  journalctl -u "${SERVICE_NAME}" -f -n 50 2>/dev/null || true
  trap - INT
}

update_server() {
  clear_screen
  print_message "INFO" "Baixando instalador e atualizando para a versão mais recente..."
  local installer
  installer=$(mktemp)
  if ! curl -fSL "${INSTALLER_URL}" -o "${installer}"; then
    unlink "${installer}"
    print_message "ERROR" "Não foi possível baixar o instalador."
    wait_for_enter
    return
  fi

  if ! bash "${installer}"; then
    unlink "${installer}"
    print_message "ERROR" "A atualização falhou."
    wait_for_enter
    return
  fi

  unlink "${installer}"
  print_message "SUCCESS" "Atualização concluída!"
  wait_for_enter
}

uninstall_server() {
  clear_screen
  draw_header "DESINSTALAR SERVIDOR" "Atenção: Ação Destrutiva"
  draw_box_line "${COLORS[ERROR]}Esta ação removerá completamente o DTProto Server,${COLORS[RESET]}"
  draw_box_line "${COLORS[ERROR]}serviços systemd e arquivos de configuração.${COLORS[RESET]}"
  draw_footer
  echo ""

  confirm=$(read_input "Confirmar desinstalação? (s/n)")
  if [[ ! "${confirm,,}" =~ ^(s|sim)$ ]]; then
    return
  fi

  systemctl stop "${SERVICE_NAME}" 2>/dev/null || true
  systemctl disable "${SERVICE_NAME}" 2>/dev/null || true
  rm -f "/etc/systemd/system/${SERVICE_NAME}"
  rm -f "${PAM_SERVICE_FILE}"
  systemctl daemon-reload 2>/dev/null || true
  rm -f /usr/local/bin/proto-server /usr/local/bin/proto
  rm -rf /etc/proto-server
  print_message "SUCCESS" "DTProto Server desinstalado com sucesso!"
  exit 0
}

main_menu() {
  check_root
  check_dependencies
  if ! ensure_valid_token; then
    print_message "WARN" "Entrada encerrada pelo usuário."
    return 0
  fi

  while true; do
    clear_screen
    display_main_menu
    echo ""
    local choice
    choice=$(normalize_choice "$(read_input "Escolha uma opção")")

    case "${choice}" in
      1) menu_service_control ;;
      2) menu_ports ;;
      3) menu_auth ;;
      4) menu_token ;;
      5) view_logs ;;
      6) update_server ;;
      7) uninstall_server ;;
      8) menu_stats ;;
      0)
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

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main_menu "$@"
fi
