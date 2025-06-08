#!/bin/bash
# functions.sh - Вспомогательные функции для скриптов управления OpenVPN

# Загрузка конфигурации
load_config() {
    local config_file="${1:-/etc/openvpn/manager.conf}"
    if [ -f "$config_file" ]; then
        source "$config_file"
    else
        echo "Ошибка: Файл конфигурации $config_file не найден" >&2
        return 1
    fi
}

# Функция для извлечения параметров из server.conf
get_server_param() {
    local param=$1
    local default=$2
    local value
    
    if [ -f "$SERVER_CONF" ]; then
        case $param in
            "port")
                value=$(grep -E "^port\s+" "$SERVER_CONF" | awk '{print $2}')
                ;;
            "proto")
                value=$(grep -E "^proto\s+" "$SERVER_CONF" | awk '{print $2}')
                ;;
            "server_network")
                value=$(grep -E "^server\s+" "$SERVER_CONF" | awk '{print $2}')
                ;;
            "server_netmask")
                value=$(grep -E "^server\s+" "$SERVER_CONF" | awk '{print $3}')
                ;;
            "max_clients")
                value=$(grep -E "^max-clients\s+" "$SERVER_CONF" | awk '{print $2}')
                ;;
            "dns1")
                value=$(grep -E "push.*dhcp-option DNS" "$SERVER_CONF" | head -1 | grep -oE "[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+")
                ;;
            "dns2")
                value=$(grep -E "push.*dhcp-option DNS" "$SERVER_CONF" | tail -1 | grep -oE "[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+")
                ;;
            "redirect_gateway")
                grep -qE "^push.*redirect-gateway" "$SERVER_CONF" && value="yes" || value="no"
                ;;
            "auth_alg")
                value=$(grep -E "^auth\s+" "$SERVER_CONF" | awk '{print $2}')
                ;;
            "cipher_list")
                value=$(grep -E "^data-ciphers\s+" "$SERVER_CONF" | cut -d' ' -f2-)
                ;;
        esac
    fi
    
    echo "${value:-$default}"
}

# Функция для получения внешнего IP адреса
get_server_ip() {
    # Если задан статический IP, используем его
    if [ -n "$SERVER_IP_STATIC" ]; then
        echo "$SERVER_IP_STATIC"
        return
    fi
    
    # Проверяем кеш
    if [ -f "$SERVER_IP_CACHE_FILE" ]; then
        local file_age=$(($(date +%s) - $(stat -c %Y "$SERVER_IP_CACHE_FILE" 2>/dev/null || echo 0)))
        if [ $file_age -lt $SERVER_IP_CACHE_AGE ]; then
            cat "$SERVER_IP_CACHE_FILE"
            return
        fi
    fi
    
    # Получаем IP различными способами
    local ip=""
    local methods=(
        "curl -s --max-time 5 ifconfig.me"
        "curl -s --max-time 5 icanhazip.com"
        "curl -s --max-time 5 ipinfo.io/ip"
        "dig +short myip.opendns.com @resolver1.opendns.com"
    )
    
    for method in "${methods[@]}"; do
        ip=$(eval $method 2>/dev/null)
        if [[ $ip =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
            # Создаем директорию для кеша, если не существует
            mkdir -p "$(dirname "$SERVER_IP_CACHE_FILE")"
            echo "$ip" > "$SERVER_IP_CACHE_FILE"
            echo "$ip"
            return
        fi
    done
    
    # Если не удалось получить, возвращаем заглушку
    echo "YOUR_SERVER_IP"
}

# Инициализация переменных из конфигурации
init_config_vars() {
    # Загружаем конфигурацию
    load_config "$@" || return 1
    
    # Извлекаем параметры из server.conf или используем значения по умолчанию
    SERVER_PORT=$(get_server_param "port" "$SERVER_PORT_DEFAULT")
    SERVER_PROTO=$(get_server_param "proto" "$SERVER_PROTO_DEFAULT")
    SERVER_NETWORK=$(get_server_param "server_network" "$SERVER_NETWORK_DEFAULT")
    SERVER_NETMASK=$(get_server_param "server_netmask" "$SERVER_NETMASK_DEFAULT")
    MAX_CLIENTS=$(get_server_param "max_clients" "$MAX_CLIENTS_DEFAULT")
    CLIENT_DNS1=$(get_server_param "dns1" "$CLIENT_DNS1_DEFAULT")
    CLIENT_DNS2=$(get_server_param "dns2" "$CLIENT_DNS2_DEFAULT")
    REDIRECT_GATEWAY=$(get_server_param "redirect_gateway" "$REDIRECT_GATEWAY_DEFAULT")
    AUTH_ALG=$(get_server_param "auth_alg" "$AUTH_ALG_DEFAULT")
    CIPHER_LIST=$(get_server_param "cipher_list" "$CIPHER_LIST_DEFAULT")
    
    # Получаем IP сервера
    SERVER_IP=$(get_server_ip)
    
    # Экспортируем переменные
    export SERVER_IP SERVER_PORT SERVER_PROTO
    export SERVER_NETWORK SERVER_NETMASK MAX_CLIENTS
    export CLIENT_DNS1 CLIENT_DNS2 REDIRECT_GATEWAY
    export AUTH_ALG CIPHER_LIST
}