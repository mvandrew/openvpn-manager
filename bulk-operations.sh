#!/bin/bash

# bulk-operations.sh - Массовые операции с клиентами OpenVPN
# Поддерживает создание нескольких клиентов, импорт из CSV, массовый отзыв

# Цвета для вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

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
    exit 1
fi

# Загрузка конфигурации
source "$CONFIG_FILE"

# Проверка прав root
if [[ $EUID -ne 0 ]]; then
    echo -e "${RED}Этот скрипт должен быть запущен с правами root!${NC}"
    exit 1
fi

# Функция создания клиента
create_single_client() {
    local client_name=$1
    local email=$2

    cd "$EASYRSA_DIR" || return 1

    # Проверка существования
    if [ -f "pki/issued/${client_name}.crt" ]; then
        echo -e "${YELLOW}Клиент '$client_name' уже существует, пропускаем...${NC}"
        return 1
    fi

    # Генерация сертификата
    ./easyrsa gen-req "$client_name" nopass &>/dev/null
    ./easyrsa sign-req client "$client_name" &>/dev/null

    if [ $? -eq 0 ]; then
        # Генерация конфигурации
        generate_config "$client_name"

        # Отправка по email если указан
        if [ -n "$email" ] && command -v mail &> /dev/null; then
            send_config_email "$client_name" "$email"
        fi

        echo -e "${GREEN}✓ Клиент '$client_name' создан${NC}"
        return 0
    else
        echo -e "${RED}✗ Ошибка при создании клиента '$client_name'${NC}"
        return 1
    fi
}

# Функция генерации конфигурации
generate_config() {
    local client_name=$1
    local output_file="${CLIENT_CONFIG_DIR}/${client_name}.ovpn"

    mkdir -p "$CLIENT_CONFIG_DIR"

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

    # Добавление дополнительных параметров
    [ "$REDIRECT_GATEWAY" = "yes" ] && echo "redirect-gateway def1 bypass-dhcp" >> "$output_file"
    [ "$REDIRECT_GATEWAY" = "yes" ] && [ -n "$CLIENT_DNS1" ] && echo "dhcp-option DNS ${CLIENT_DNS1}" >> "$output_file"
    [ "$REDIRECT_GATEWAY" = "yes" ] && [ -n "$CLIENT_DNS2" ] && echo "dhcp-option DNS ${CLIENT_DNS2}" >> "$output_file"
    [ "$ENABLE_COMPRESSION" = "yes" ] && echo "comp-lzo" >> "$output_file"

    # Добавление сертификатов
    echo "" >> "$output_file"
    echo "<ca>" >> "$output_file"
    cat "$CA_CERT" >> "$output_file"
    echo "</ca>" >> "$output_file"

    echo "<cert>" >> "$output_file"
    echo "-----BEGIN CERTIFICATE-----" >> "$output_file"
    sed -n '/-----BEGIN CERTIFICATE-----/{:a;n;/-----END CERTIFICATE-----/b;p;ba}' "${EASYRSA_DIR}/pki/issued/${client_name}.crt" >> "$output_file"
    echo "-----END CERTIFICATE-----" >> "$output_file"
    echo "</cert>" >> "$output_file"

    echo "<key>" >> "$output_file"
    cat "${EASYRSA_DIR}/pki/private/${client_name}.key" >> "$output_file"
    echo "</key>" >> "$output_file"

    echo "<tls-auth>" >> "$output_file"
    cat "$TLS_KEY" >> "$output_file"
    echo "</tls-auth>" >> "$output_file"

    chmod 600 "$output_file"
}

# Функция отправки конфигурации по email
send_config_email() {
    local client_name=$1
    local email=$2
    local config_file="${CLIENT_CONFIG_DIR}/${client_name}.ovpn"

    if [ -f "$config_file" ]; then
        echo "Ваша конфигурация OpenVPN в приложении. Инструкции по подключению: ..." | \
            mail -s "OpenVPN конфигурация - $client_name" -a "$config_file" "$email"
        echo -e "${GREEN}  Конфигурация отправлена на $email${NC}"
    fi
}

# Массовое создание клиентов из списка
bulk_create_from_list() {
    echo -e "${BLUE}Массовое создание клиентов${NC}"
    echo "Введите имена клиентов (по одному на строку, пустая строка для завершения):"

    local clients=()
    while true; do
        read -r client_name
        [ -z "$client_name" ] && break
        clients+=("$client_name")
    done

    if [ ${#clients[@]} -eq 0 ]; then
        echo -e "${YELLOW}Список клиентов пуст${NC}"
        return
    fi

    echo -e "${BLUE}Будет создано клиентов: ${#clients[@]}${NC}"
    read -p "Продолжить? (y/n): " -n 1 -r
    echo

    if [[ $REPLY =~ ^[Yy]$ ]]; then
        local success=0
        local failed=0

        for client in "${clients[@]}"; do
            if create_single_client "$client"; then
                ((success++))
            else
                ((failed++))
            fi
        done

        echo -e "${GREEN}Создано успешно: $success${NC}"
        [ $failed -gt 0 ] && echo -e "${RED}Не удалось создать: $failed${NC}"
    fi
}

# Импорт клиентов из CSV файла
import_from_csv() {
    local csv_file=$1

    if [ ! -f "$csv_file" ]; then
        echo -e "${RED}Файл '$csv_file' не найден${NC}"
        return 1
    fi

    echo -e "${BLUE}Импорт клиентов из CSV файла${NC}"
    echo "Формат CSV: имя_клиента,email (email опционально)"

    local success=0
    local failed=0
    local line_num=0

    while IFS=',' read -r client_name email; do
        ((line_num++))

        # Пропуск заголовка и пустых строк
        if [ $line_num -eq 1 ] && [[ "$client_name" =~ ^(name|client|username) ]]; then
            continue
        fi

        [ -z "$client_name" ] && continue

        # Удаление пробелов
        client_name=$(echo "$client_name" | xargs)
        email=$(echo "$email" | xargs)

        echo -e "${BLUE}Обработка: $client_name${NC}"

        if create_single_client "$client_name" "$email"; then
            ((success++))
        else
            ((failed++))
        fi
    done < "$csv_file"

    echo -e "${GREEN}Импортировано успешно: $success${NC}"
    [ $failed -gt 0 ] && echo -e "${RED}Не удалось импортировать: $failed${NC}"
}

# Массовый отзыв сертификатов
bulk_revoke() {
    echo -e "${YELLOW}Массовый отзыв сертификатов${NC}"
    echo "Введите имена клиентов для отзыва (по одному на строку, пустая строка для завершения):"

    local clients=()
    while true; do
        read -r client_name
        [ -z "$client_name" ] && break
        clients+=("$client_name")
    done

    if [ ${#clients[@]} -eq 0 ]; then
        echo -e "${YELLOW}Список клиентов пуст${NC}"
        return
    fi

    echo -e "${RED}ВНИМАНИЕ: Будет отозвано сертификатов: ${#clients[@]}${NC}"
    echo "Это действие необратимо!"
    read -p "Вы уверены? (yes/no): " -r

    if [ "$REPLY" = "yes" ]; then
        cd "$EASYRSA_DIR" || return 1

        local success=0
        local failed=0

        for client in "${clients[@]}"; do
            if [ -f "pki/issued/${client}.crt" ]; then
                ./easyrsa revoke "$client" &>/dev/null
                if [ $? -eq 0 ]; then
                    rm -f "${CLIENT_CONFIG_DIR}/${client}.ovpn"
                    echo -e "${GREEN}✓ Сертификат '$client' отозван${NC}"
                    ((success++))
                else
                    echo -e "${RED}✗ Ошибка при отзыве '$client'${NC}"
                    ((failed++))
                fi
            else
                echo -e "${YELLOW}Клиент '$client' не найден${NC}"
                ((failed++))
            fi
        done

        # Генерация CRL
        if [ $success -gt 0 ]; then
            ./easyrsa gen-crl
            cp pki/crl.pem "$OPENVPN_DIR/crl.pem"
            systemctl restart openvpn@server
        fi

        echo -e "${GREEN}Отозвано успешно: $success${NC}"
        [ $failed -gt 0 ] && echo -e "${RED}Не удалось отозвать: $failed${NC}"
    fi
}

# Экспорт всех конфигураций в архив
export_all_configs() {
    local export_dir="${HOME}/openvpn_clients_$(date +%Y%m%d_%H%M%S)"

    echo -e "${BLUE}Экспорт всех клиентских конфигураций${NC}"

    mkdir -p "$export_dir"

    local count=0
    for config in "${CLIENT_CONFIG_DIR}"/*.ovpn; do
        if [ -f "$config" ]; then
            cp "$config" "$export_dir/"
            ((count++))
        fi
    done

    if [ $count -gt 0 ]; then
        # Создание архива
        tar -czf "${export_dir}.tar.gz" -C "$(dirname "$export_dir")" "$(basename "$export_dir")"
        rm -rf "$export_dir"

        echo -e "${GREEN}Экспортировано конфигураций: $count${NC}"
        echo -e "${GREEN}Архив сохранен: ${export_dir}.tar.gz${NC}"
    else
        echo -e "${YELLOW}Нет конфигураций для экспорта${NC}"
        rmdir "$export_dir"
    fi
}

# Генерация отчета
generate_report() {
    local report_file="${HOME}/openvpn_report_$(date +%Y%m%d_%H%M%S).txt"

    echo -e "${BLUE}Генерация отчета...${NC}"

    {
        echo "OpenVPN Status Report"
        echo "Generated: $(date)"
        echo "Server: ${SERVER_IP}:${SERVER_PORT}"
        echo "========================================"
        echo

        echo "Active Clients:"
        cd "$EASYRSA_DIR"
        local active_count=0
        for cert in pki/issued/*.crt; do
            if [ -f "$cert" ]; then
                client=$(basename "$cert" .crt)
                if [ "$client" != "server" ] && ! grep -q "R.*CN=$client" pki/index.txt 2>/dev/null; then
                    echo "  - $client"
                    ((active_count++))
                fi
            fi
        done
        echo "Total active: $active_count"
        echo

        echo "Revoked Clients:"
        local revoked_count=0
        if [ -f "pki/index.txt" ]; then
            grep "^R" pki/index.txt | while read -r line; do
                client=$(echo "$line" | grep -oP 'CN=\K[^/]+')
                if [ -n "$client" ] && [ "$client" != "server" ]; then
                    echo "  - $client"
                    ((revoked_count++))
                fi
            done
        fi
        echo "Total revoked: $revoked_count"
        echo

        echo "Server Status:"
        if systemctl is-active --quiet openvpn@server; then
            echo "  Status: Running"
            echo "  Uptime: $(systemctl show openvpn@server --property=ActiveEnterTimestamp | cut -d= -f2-)"
        else
            echo "  Status: Stopped"
        fi
        echo

        echo "Configuration:"
        echo "  Protocol: $SERVER_PROTO"
        echo "  Auth: $AUTH_ALG"
        echo "  Ciphers: $CIPHER_LIST"
        echo "  Redirect Gateway: $REDIRECT_GATEWAY"
        echo "  Compression: $ENABLE_COMPRESSION"

    } > "$report_file"

    echo -e "${GREEN}Отчет сохранен: $report_file${NC}"
}

# Показать меню
show_menu() {
    echo
    echo -e "${BLUE}=== Массовые операции OpenVPN ===${NC}"
    echo "1. Создать несколько клиентов (ввод списка)"
    echo "2. Импорт клиентов из CSV файла"
    echo "3. Массовый отзыв сертификатов"
    echo "4. Экспорт всех конфигураций в архив"
    echo "5. Генерировать отчет"
    echo "6. Выход"
    echo
}

# Главная функция
main() {
    while true; do
        show_menu
        read -p "Выберите действие: " choice

        case $choice in
            1)
                bulk_create_from_list
                ;;
            2)
                read -p "Путь к CSV файлу: " csv_file
                import_from_csv "$csv_file"
                ;;
            3)
                bulk_revoke
                ;;
            4)
                export_all_configs
                ;;
            5)
                generate_report
                ;;
            6)
                echo -e "${GREEN}До свидания!${NC}"
                exit 0
                ;;
            *)
                echo -e "${RED}Неверный выбор${NC}"
                ;;
        esac

        echo
        read -p "Нажмите Enter для продолжения..."
    done
}

# Запуск
main