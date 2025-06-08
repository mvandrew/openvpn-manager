#!/bin/bash

# quick-add-client.sh - Быстрое создание клиента OpenVPN
# Использование: ./quick-add-client.sh <имя_клиента>

# Цвета для вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
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

# Проверка аргументов
if [ -z "$1" ]; then
    echo "Использование: $0 <имя_клиента>"
    exit 1
fi

CLIENT_NAME="$1"

# Сохранение текущей директории
CURRENT_DIR=$(pwd)

# Переход в директорию EasyRSA
cd "$EASYRSA_DIR" || exit 1

# Проверка существования клиента
if [ -f "pki/issued/${CLIENT_NAME}.crt" ]; then
    echo -e "${RED}Ошибка: Клиент '$CLIENT_NAME' уже существует!${NC}"
    cd "$CURRENT_DIR"
    exit 1
fi

# Генерация сертификата клиента
echo -e "${GREEN}Создание сертификата для клиента '$CLIENT_NAME'...${NC}"

./easyrsa gen-req "$CLIENT_NAME" nopass
if [ $? -ne 0 ]; then
    echo -e "${RED}Ошибка при создании запроса сертификата${NC}"
    cd "$CURRENT_DIR"
    exit 1
fi

./easyrsa sign-req client "$CLIENT_NAME"
if [ $? -ne 0 ]; then
    echo -e "${RED}Ошибка при подписании сертификата${NC}"
    cd "$CURRENT_DIR"
    exit 1
fi

# Возврат в исходную директорию
cd "$CURRENT_DIR"

# Создание директории для клиентских конфигураций
mkdir -p "$CLIENT_CONFIG_DIR"

# Генерация .ovpn файла
OUTPUT_FILE="${CLIENT_CONFIG_DIR}/${CLIENT_NAME}.ovpn"

echo -e "${GREEN}Генерация конфигурационного файла...${NC}"

# Создание конфигурации
cat > "$OUTPUT_FILE" <<EOF
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
    echo "redirect-gateway def1 bypass-dhcp" >> "$OUTPUT_FILE"
    
    # Добавление DNS серверов
    [ -n "$CLIENT_DNS1" ] && echo "dhcp-option DNS ${CLIENT_DNS1}" >> "$OUTPUT_FILE"
    [ -n "$CLIENT_DNS2" ] && echo "dhcp-option DNS ${CLIENT_DNS2}" >> "$OUTPUT_FILE"
fi

# Добавление компрессии если включена
if [ "$ENABLE_COMPRESSION" = "yes" ]; then
    echo "comp-lzo" >> "$OUTPUT_FILE"
fi

# Добавление сертификатов
echo "" >> "$OUTPUT_FILE"
echo "<ca>" >> "$OUTPUT_FILE"
cat "$CA_CERT" >> "$OUTPUT_FILE"
echo "</ca>" >> "$OUTPUT_FILE"

echo "<cert>" >> "$OUTPUT_FILE"
echo "-----BEGIN CERTIFICATE-----" >> "$OUTPUT_FILE"
sed -n '/-----BEGIN CERTIFICATE-----/{:a;n;/-----END CERTIFICATE-----/b;p;ba}' "${EASYRSA_DIR}/pki/issued/${CLIENT_NAME}.crt" >> "$OUTPUT_FILE"
echo "-----END CERTIFICATE-----" >> "$OUTPUT_FILE"
echo "</cert>" >> "$OUTPUT_FILE"

echo "<key>" >> "$OUTPUT_FILE"
cat "${EASYRSA_DIR}/pki/private/${CLIENT_NAME}.key" >> "$OUTPUT_FILE"
echo "</key>" >> "$OUTPUT_FILE"

echo "<tls-auth>" >> "$OUTPUT_FILE"
cat "$TLS_KEY" >> "$OUTPUT_FILE"
echo "</tls-auth>" >> "$OUTPUT_FILE"

# Установка прав доступа
chmod 600 "$OUTPUT_FILE"

echo -e "${GREEN}✓ Клиент '$CLIENT_NAME' успешно создан!${NC}"
echo -e "${GREEN}✓ Конфигурация сохранена: $OUTPUT_FILE${NC}"

# Копирование в домашнюю директорию для удобства
if [ -n "$SUDO_USER" ]; then
    USER_HOME=$(getent passwd "$SUDO_USER" | cut -d: -f6)
    cp "$OUTPUT_FILE" "${USER_HOME}/${CLIENT_NAME}.ovpn"
    chown "$SUDO_USER:$SUDO_USER" "${USER_HOME}/${CLIENT_NAME}.ovpn"
    echo -e "${GREEN}✓ Копия сохранена в: ${USER_HOME}/${CLIENT_NAME}.ovpn${NC}"
fi

# Логирование
echo "[$(date '+%Y-%m-%d %H:%M:%S')] CLIENT_CREATED - $CLIENT_NAME" >> "${LOG_DIR}/manager.log"

exit 0