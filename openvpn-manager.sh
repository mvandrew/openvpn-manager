#!/bin/bash

# openvpn-manager.sh - Главный скрипт управления OpenVPN
# Версия: 2.0
# Описание: Централизованное управление OpenVPN сервером и клиентами

# Цвета для вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Определение пути к конфигурации менеджера
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MANAGER_CONFIG_LOCATIONS=(
    "/etc/openvpn/manager.conf"
    "${SCRIPT_DIR}/manager.conf"
    "./manager.conf"
)

# Поиск файла конфигурации
CONFIG_FILE=""
for location in "${MANAGER_CONFIG_LOCATIONS[@]}"; do
    if [ -f "$location" ]; then
        CONFIG_FILE="$location"
        break
    fi
done

if [ -z "$CONFIG_FILE" ]; then
    echo -e "${RED}Ошибка: Файл конфигурации manager.conf не найден!${NC}"
    echo "Проверьте следующие расположения:"
    for location in "${MANAGER_CONFIG_LOCATIONS[@]}"; do
        echo "  - $location"
    done
    exit 1
fi

# Загрузка библиотеки функций
LIB_DIR="${SCRIPT_DIR}/lib"
if [ -f "${LIB_DIR}/functions.sh" ]; then
    source "${LIB_DIR}/functions.sh"
else
    echo -e "${RED}Ошибка: Библиотека функций не найдена!${NC}"
    exit 1
fi

# Инициализация конфигурации
init_config_vars "$CONFIG_FILE"

# Проверка прав root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        echo -e "${RED}Этот скрипт должен быть запущен с правами root!${NC}"
        exit 1
    fi
}

# Функция логирования
log_action() {
    local action=$1
    local status=$2
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    mkdir -p "$LOG_DIR"
    echo "[$timestamp] $action - $status" >> "$LOG_DIR/manager.log"
}

# Функция создания резервной копии
backup_config() {
    local backup_name="openvpn_backup_$(date +%Y%m%d_%H%M%S)"
    
    echo -e "${BLUE}Создание резервной копии конфигурации...${NC}"
    mkdir -p "$BACKUP_DIR"
    
    tar -czf "$BACKUP_DIR/${backup_name}.tar.gz" \
        "$OPENVPN_DIR" \
        --exclude="$BACKUP_DIR" \
        --exclude="$LOG_DIR" 2>/dev/null
    
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}Резервная копия создана: $BACKUP_DIR/${backup_name}.tar.gz${NC}"
        log_action "BACKUP" "SUCCESS - $backup_name"
        
        # Удаление старых резервных копий (старше 30 дней)
        find "$BACKUP_DIR" -name "openvpn_backup_*.tar.gz" -mtime +30 -delete
    else
        echo -e "${RED}Ошибка при создании резервной копии${NC}"
        log_action "BACKUP" "FAILED"
    fi
}

# Функция проверки состояния службы
check_service_status() {
    if systemctl is-active --quiet openvpn@server; then
        echo -e "${GREEN}OpenVPN сервер работает${NC}"
    else
        echo -e "${RED}OpenVPN сервер не запущен${NC}"
    fi
}

# Функция инициализации PKI
init_pki() {
    echo -e "${BLUE}Инициализация PKI...${NC}"
    
    cd "$EASYRSA_DIR" || exit 1
    
    # Очистка старого PKI
    if [ -d "pki" ]; then
        echo -e "${YELLOW}Внимание: Существующий PKI будет удален!${NC}"
        read -p "Продолжить? (y/n): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            return 1
        fi
        ./easyrsa clean-all
    fi
    
    # Инициализация нового PKI
    ./easyrsa init-pki
    
    # Создание CA
    echo -e "${BLUE}Создание центра сертификации...${NC}"
    ./easyrsa build-ca nopass
    
    # Генерация DH параметров
    echo -e "${BLUE}Генерация DH параметров (это может занять время)...${NC}"
    ./easyrsa gen-dh
    
    # Генерация сертификата сервера
    echo -e "${BLUE}Генерация сертификата сервера...${NC}"
    ./easyrsa gen-req server nopass
    ./easyrsa sign-req server server
    
    # Создание директории ccd если не существует
    mkdir -p "$CCD_DIR"
    
    # Генерация CRL если не существует
    if [ ! -f "$CRL_FILE" ]; then
        cd "$EASYRSA_DIR" || return 1
        ./easyrsa gen-crl
        cp pki/crl.pem "$CRL_FILE"
    fi
    
    # Копирование файлов в рабочую директорию
    cp pki/ca.crt "$CA_CERT"
    cp pki/issued/server.crt "$SERVER_CERT"
    cp pki/private/server.key "$SERVER_KEY"
    cp pki/dh.pem "$DH_PARAMS"
    
    echo -e "${GREEN}PKI успешно инициализирован${NC}"
    log_action "INIT_PKI" "SUCCESS"
}

# Функция создания клиента
create_client() {
    local client_name=$1
    
    if [ -z "$client_name" ]; then
        echo -e "${RED}Ошибка: Не указано имя клиента${NC}"
        return 1
    fi
    
    echo -e "${BLUE}Создание сертификата для клиента '$client_name'...${NC}"
    
    cd "$EASYRSA_DIR" || exit 1
    
    # Проверка существования клиента
    if [ -f "pki/issued/${client_name}.crt" ]; then
        echo -e "${YELLOW}Клиент '$client_name' уже существует${NC}"
        return 1
    fi
    
    # Генерация запроса и сертификата
    ./easyrsa gen-req "$client_name" nopass
    ./easyrsa sign-req client "$client_name"
    
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}Сертификат для клиента '$client_name' создан${NC}"
        log_action "CREATE_CLIENT" "SUCCESS - $client_name"
        
        # Генерация конфигурационного файла
        generate_client_config "$client_name"
    else
        echo -e "${RED}Ошибка при создании сертификата${NC}"
        log_action "CREATE_CLIENT" "FAILED - $client_name"
        return 1
    fi
}

# Функция генерации клиентской конфигурации
generate_client_config() {
    local client_name=$1
    local output_file="${CLIENT_CONFIG_DIR}/${client_name}.ovpn"
    
    echo -e "${BLUE}Генерация конфигурации для клиента '$client_name'...${NC}"
    
    mkdir -p "$CLIENT_CONFIG_DIR"
    
    # Пути к файлам клиента
    local client_cert="${EASYRSA_DIR}/pki/issued/${client_name}.crt"
    local client_key="${EASYRSA_DIR}/pki/private/${client_name}.key"
    
    # Проверка наличия файлов
    if [ ! -f "$client_cert" ] || [ ! -f "$client_key" ]; then
        echo -e "${RED}Ошибка: Не найдены файлы сертификата или ключа клиента${NC}"
        return 1
    fi
    
    # Генерация .ovpn файла
    cat > "$output_file" <<EOF
client
dev tun
proto ${SERVER_PROTO}
remote ${SERVER_IP} ${SERVER_PORT}
resolv-retry infinite
nobind
persist-key
persist-tun
remote-cert-tls server
auth ${AUTH_ALG}
data-ciphers ${CIPHER_LIST}
tls-client
tls-auth ta.key 1
key-direction 1
verb ${LOG_LEVEL}
EOF

    # Добавление redirect-gateway если включено
    if [ "$REDIRECT_GATEWAY" = "yes" ]; then
        echo "redirect-gateway def1 bypass-dhcp" >> "$output_file"
    fi
    
    # Добавление DNS серверов если redirect-gateway включен
    if [ "$REDIRECT_GATEWAY" = "yes" ] && [ -n "$CLIENT_DNS1" ]; then
        echo "dhcp-option DNS ${CLIENT_DNS1}" >> "$output_file"
        [ -n "$CLIENT_DNS2" ] && echo "dhcp-option DNS ${CLIENT_DNS2}" >> "$output_file"
    fi
    
    # Добавление компрессии если включена
    if [ "$ENABLE_COMPRESSION" = "yes" ]; then
        echo "comp-lzo" >> "$output_file"
    fi
    
    # Добавление сертификатов и ключей
    echo "" >> "$output_file"
    echo "<ca>" >> "$output_file"
    cat "$CA_CERT" >> "$output_file"
    echo "</ca>" >> "$output_file"
    
    echo "<cert>" >> "$output_file"
    echo "-----BEGIN CERTIFICATE-----" >> "$output_file"
    sed -n '/-----BEGIN CERTIFICATE-----/{:a;n;/-----END CERTIFICATE-----/b;p;ba}' "$client_cert" >> "$output_file"
    echo "-----END CERTIFICATE-----" >> "$output_file"
    echo "</cert>" >> "$output_file"
    
    echo "<key>" >> "$output_file"
    cat "$client_key" >> "$output_file"
    echo "</key>" >> "$output_file"
    
    echo "<tls-auth>" >> "$output_file"
    cat "$TLS_KEY" >> "$output_file"
    echo "</tls-auth>" >> "$output_file"
    
    # Установка прав доступа
    chmod 600 "$output_file"
    
    echo -e "${GREEN}Конфигурация сохранена: $output_file${NC}"
    log_action "GENERATE_CONFIG" "SUCCESS - $client_name"
}

# Функция отзыва сертификата клиента
revoke_client() {
    local client_name=$1
    
    if [ -z "$client_name" ]; then
        echo -e "${RED}Ошибка: Не указано имя клиента${NC}"
        return 1
    fi
    
    echo -e "${YELLOW}Отзыв сертификата клиента '$client_name'...${NC}"
    
    cd "$EASYRSA_DIR" || exit 1
    
    # Проверка существования сертификата
    if [ ! -f "pki/issued/${client_name}.crt" ]; then
        echo -e "${RED}Клиент '$client_name' не найден${NC}"
        return 1
    fi
    
    # Отзыв сертификата
    ./easyrsa revoke "$client_name"
    
    if [ $? -eq 0 ]; then
        # Генерация CRL
        ./easyrsa gen-crl
        cp pki/crl.pem "$OPENVPN_DIR/crl.pem"
        
        # Удаление конфигурационного файла
        rm -f "${CLIENT_CONFIG_DIR}/${client_name}.ovpn"
        
        echo -e "${GREEN}Сертификат клиента '$client_name' отозван${NC}"
        log_action "REVOKE_CLIENT" "SUCCESS - $client_name"
        
        # Перезапуск сервера для применения CRL
        systemctl restart openvpn@server
    else
        echo -e "${RED}Ошибка при отзыве сертификата${NC}"
        log_action "REVOKE_CLIENT" "FAILED - $client_name"
        return 1
    fi
}

# Функция вывода списка клиентов
list_clients() {
    echo -e "${BLUE}Список клиентов:${NC}"
    echo "----------------------------------------"
    
    cd "$EASYRSA_DIR" || exit 1
    
    # Активные клиенты
    echo -e "${GREEN}Активные клиенты:${NC}"
    for cert in pki/issued/*.crt; do
        if [ -f "$cert" ]; then
            client=$(basename "$cert" .crt)
            if [ "$client" != "server" ]; then
                # Проверка, не отозван ли сертификат
                if ! grep -q "R.*CN=$client" pki/index.txt 2>/dev/null; then
                    echo "  - $client"
                fi
            fi
        fi
    done
    
    # Отозванные клиенты
    if [ -f "pki/index.txt" ]; then
        echo -e "\n${RED}Отозванные клиенты:${NC}"
        grep "^R" pki/index.txt | while read -r line; do
            client=$(echo "$line" | grep -oP 'CN=\K[^/]+')
            if [ -n "$client" ] && [ "$client" != "server" ]; then
                echo "  - $client"
            fi
        done
    fi
    
    echo "----------------------------------------"
}

# Функция показа статистики подключений
show_connections() {
    echo -e "${BLUE}Активные подключения:${NC}"
    echo "----------------------------------------"
    
    if [ -f "/var/log/openvpn/status.log" ]; then
        echo -e "${GREEN}Подключенные клиенты:${NC}"
        grep "^CLIENT_LIST" /var/log/openvpn/status.log | while IFS=',' read -r _ name real_addr _ _ rx tx _ since _; do
            if [ "$name" != "HEADER" ]; then
                echo "  Клиент: $name"
                echo "  IP: $real_addr"
                echo "  Получено: $((rx/1024/1024)) MB"
                echo "  Отправлено: $((tx/1024/1024)) MB"
                echo "  Подключен с: $since"
                echo "  ---"
            fi
        done
    else
        echo -e "${YELLOW}Файл статуса не найден. Возможно, сервер не запущен.${NC}"
    fi
    
    echo "----------------------------------------"
}

# Функция экспорта конфигурации клиента
export_client_config() {
    local client_name=$1
    local export_path=$2
    
    if [ -z "$client_name" ]; then
        echo -e "${RED}Ошибка: Не указано имя клиента${NC}"
        return 1
    fi
    
    local config_file="${CLIENT_CONFIG_DIR}/${client_name}.ovpn"
    
    if [ ! -f "$config_file" ]; then
        echo -e "${RED}Конфигурация клиента '$client_name' не найдена${NC}"
        return 1
    fi
    
    if [ -z "$export_path" ]; then
        export_path="${HOME}/${client_name}.ovpn"
    fi
    
    cp "$config_file" "$export_path"
    chmod 644 "$export_path"
    
    echo -e "${GREEN}Конфигурация экспортирована: $export_path${NC}"
    
    # Генерация QR-кода если установлен qrencode
    if command -v qrencode &> /dev/null; then
        echo -e "${BLUE}Генерация QR-кода...${NC}"
        qrencode -t ansiutf8 < "$config_file"
        echo -e "${YELLOW}QR-код для мобильных устройств отображен выше${NC}"
    fi
}

# Функция проверки конфигурации
check_configuration() {
    echo -e "${BLUE}Проверка конфигурации OpenVPN...${NC}"
    echo "----------------------------------------"
    
    local errors=0
    
    # Проверка файлов
    local files_to_check=(
        "$CA_CERT:CA сертификат"
        "$TLS_KEY:TLS ключ"
        "$SERVER_CERT:Сертификат сервера"
        "$SERVER_KEY:Ключ сервера"
        "$DH_PARAMS:DH параметры"
    )
    
    for file_info in "${files_to_check[@]}"; do
        IFS=':' read -r file desc <<< "$file_info"
        if [ -f "$file" ]; then
            echo -e "${GREEN}✓ $desc найден${NC}"
        else
            echo -e "${RED}✗ $desc не найден${NC}"
            ((errors++))
        fi
    done
    
    # Проверка прав доступа
    if [ -f "$SERVER_KEY" ]; then
        perms=$(stat -c %a "$SERVER_KEY")
        if [ "$perms" = "600" ] || [ "$perms" = "400" ]; then
            echo -e "${GREEN}✓ Права доступа к ключу сервера корректны${NC}"
        else
            echo -e "${YELLOW}⚠ Права доступа к ключу сервера: $perms (рекомендуется 600)${NC}"
        fi
    fi
    
    # Проверка конфигурации сервера
    if [ -f "${OPENVPN_DIR}/server.conf" ]; then
        echo -e "${GREEN}✓ Конфигурация сервера найдена${NC}"
        
        # Проверка синтаксиса
        if openvpn --config "${OPENVPN_DIR}/server.conf" --mode server --dev null --ifconfig-noexec --test-crypto 2>/dev/null; then
            echo -e "${GREEN}✓ Синтаксис конфигурации корректен${NC}"
        else
            echo -e "${RED}✗ Ошибка в синтаксисе конфигурации сервера${NC}"
            ((errors++))
        fi
    else
        echo -e "${RED}✗ Конфигурация сервера не найдена${NC}"
        ((errors++))
    fi
    
    # Проверка портов
    if ss -tuln | grep -q ":${SERVER_PORT}"; then
        echo -e "${GREEN}✓ Порт ${SERVER_PORT} открыт${NC}"
    else
        echo -e "${YELLOW}⚠ Порт ${SERVER_PORT} не прослушивается${NC}"
    fi
    
    echo "----------------------------------------"
    
    if [ $errors -eq 0 ]; then
        echo -e "${GREEN}Конфигурация корректна${NC}"
    else
        echo -e "${RED}Обнаружено ошибок: $errors${NC}"
    fi
}

# Главное меню
show_menu() {
    echo
    echo -e "${BLUE}=== OpenVPN Manager v2.0 ===${NC}"
    echo "1. Инициализировать PKI"
    echo "2. Создать клиента"
    echo "3. Отозвать клиента"
    echo "4. Список клиентов"
    echo "5. Показать активные подключения"
    echo "6. Экспортировать конфигурацию клиента"
    echo "7. Проверить конфигурацию"
    echo "8. Создать резервную копию"
    echo "9. Проверить статус сервера"
    echo "10. Выход"
    echo
}

# Главная функция
main() {
    check_root
    
    while true; do
        show_menu
        read -p "Выберите действие: " choice
        
        case $choice in
            1)
                init_pki
                ;;
            2)
                read -p "Введите имя клиента: " client_name
                create_client "$client_name"
                ;;
            3)
                read -p "Введите имя клиента для отзыва: " client_name
                revoke_client "$client_name"
                ;;
            4)
                list_clients
                ;;
            5)
                show_connections
                ;;
            6)
                read -p "Введите имя клиента: " client_name
                read -p "Путь для экспорта (Enter для домашней директории): " export_path
                export_client_config "$client_name" "$export_path"
                ;;
            7)
                check_configuration
                ;;
            8)
                backup_config
                ;;
            9)
                check_service_status
                ;;
            10)
                echo -e "${GREEN}До свидания!${NC}"
                exit 0
                ;;
            *)
                echo -e "${RED}Неверный выбор. Попробуйте снова.${NC}"
                ;;
        esac
        
        echo
        read -p "Нажмите Enter для продолжения..."
    done
}

# Запуск главной функции
main