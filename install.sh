#!/bin/bash

# install.sh - Установка и настройка скриптов управления OpenVPN
# Этот скрипт устанавливает все необходимые компоненты и настраивает систему

# Цвета для вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Директория установки
INSTALL_DIR="/opt/openvpn-manager"
BIN_DIR="/usr/local/bin"

# Проверка прав root
if [[ $EUID -ne 0 ]]; then
    echo -e "${RED}Этот скрипт должен быть запущен с правами root!${NC}"
    exit 1
fi

echo -e "${BLUE}╔══════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║             OpenVPN Manager Installation Script                  ║${NC}"
echo -e "${BLUE}╚══════════════════════════════════════════════════════════════════╝${NC}"
echo

# Функция проверки зависимостей
check_dependencies() {
    echo -e "${BLUE}Проверка зависимостей...${NC}"
    
    local deps_missing=false
    
    # Список необходимых пакетов
    local required_packages=(
        "openvpn"
        "easy-rsa"
        "tar"
        "gzip"
    )
    
    # Опциональные пакеты
    local optional_packages=(
        "qrencode"  # для QR-кодов
        "mailutils" # для отправки email
    )
    
    # Проверка обязательных пакетов
    for pkg in "${required_packages[@]}"; do
        if ! command -v $pkg &> /dev/null; then
            echo -e "${RED}✗ $pkg не установлен${NC}"
            deps_missing=true
        else
            echo -e "${GREEN}✓ $pkg установлен${NC}"
        fi
    done
    
    # Проверка опциональных пакетов
    echo
    echo -e "${YELLOW}Опциональные пакеты:${NC}"
    for pkg in "${optional_packages[@]}"; do
        if ! command -v $pkg &> /dev/null; then
            echo -e "${YELLOW}○ $pkg не установлен (опционально)${NC}"
        else
            echo -e "${GREEN}✓ $pkg установлен${NC}"
        fi
    done
    
    if [ "$deps_missing" = true ]; then
        echo
        echo -e "${RED}Установите недостающие пакеты перед продолжением${NC}"
        echo -e "Для Ubuntu/Debian: ${YELLOW}apt-get install openvpn easy-rsa${NC}"
        echo -e "Для CentOS/RHEL: ${YELLOW}yum install openvpn easy-rsa${NC}"
        exit 1
    fi
    
    echo
}

# Создание структуры директорий
create_directories() {
    echo -e "${BLUE}Создание директорий...${NC}"
    
    # Основные директории
    mkdir -p "$INSTALL_DIR"
    mkdir -p "/etc/openvpn/client"
    mkdir -p "/etc/openvpn/backup"
    mkdir -p "/var/log/openvpn"
    
    # Настройка прав
    chmod 755 "$INSTALL_DIR"
    chmod 755 "/etc/openvpn/client"
    chmod 700 "/etc/openvpn/backup"
    mkdir -p "/etc/openvpn/ccd"
    chmod 755 "/etc/openvpn/ccd"
    
    echo -e "${GREEN}✓ Директории созданы${NC}"
}

# Копирование скриптов
install_scripts() {
    echo -e "${BLUE}Установка скриптов...${NC}"
    
    # Список скриптов для установки
    local scripts=(
        "openvpn-manager.sh"
        "quick-add-client.sh"
        "bulk-operations.sh"
        "openvpn-monitor.sh"
    )
    
    # Копирование библиотеки функций
    if [ -d "lib" ]; then
        mkdir -p "$INSTALL_DIR/lib"
        cp -r lib/* "$INSTALL_DIR/lib/"
        chmod 644 "$INSTALL_DIR/lib/"*.sh
        echo -e "${GREEN}✓ Библиотека функций установлена${NC}"
    else
        echo -e "${YELLOW}⚠ Директория lib не найдена${NC}"
    fi
    
    # Копирование скриптов
    for script in "${scripts[@]}"; do
        if [ -f "$script" ]; then
            cp "$script" "$INSTALL_DIR/"
            chmod +x "$INSTALL_DIR/$script"
            
            # Создание символической ссылки в /usr/local/bin
            local link_name="${script%.sh}"
            ln -sf "$INSTALL_DIR/$script" "$BIN_DIR/$link_name"
            
            echo -e "${GREEN}✓ $script установлен${NC}"
        else
            echo -e "${YELLOW}⚠ $script не найден в текущей директории${NC}"
        fi
    done
}

# Создание конфигурационного файла
create_config() {
    echo -e "${BLUE}Создание конфигурационного файла менеджера...${NC}"
    
    local config_file="/etc/openvpn/manager.conf"
    
    if [ -f "$config_file" ]; then
        echo -e "${YELLOW}Конфигурационный файл уже существует${NC}"
        read -p "Перезаписать? (y/n): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            return
        fi
        
        # Резервная копия существующей конфигурации
        cp "$config_file" "${config_file}.backup.$(date +%Y%m%d_%H%M%S)"
    fi
    
    # Копирование конфигурационного файла
    if [ -f "openvpn/manager.conf" ]; then
        cp "openvpn/manager.conf" "$config_file"
        chmod 644 "$config_file"
        echo -e "${GREEN}✓ Конфигурационный файл менеджера создан${NC}"
    else
        echo -e "${RED}✗ Файл openvpn/manager.conf не найден в текущей директории${NC}"
        echo -e "${YELLOW}Создайте файл openvpn/manager.conf перед установкой${NC}"
        return 1
    fi
}

# Настройка EasyRSA
setup_easyrsa() {
    echo -e "${BLUE}Настройка EasyRSA...${NC}"
    
    # Поиск EasyRSA
    local easyrsa_source=""
    
    if [ -d "/usr/share/easy-rsa" ]; then
        easyrsa_source="/usr/share/easy-rsa"
    elif [ -d "/usr/share/doc/easy-rsa" ]; then
        easyrsa_source="/usr/share/doc/easy-rsa"
    else
        echo -e "${RED}EasyRSA не найден в стандартных путях${NC}"
        return 1
    fi
    
    # Копирование EasyRSA
    if [ ! -d "/etc/openvpn/easy-rsa" ]; then
        cp -r "$easyrsa_source" "/etc/openvpn/easy-rsa"
        echo -e "${GREEN}✓ EasyRSA скопирован${NC}"
    else
        echo -e "${YELLOW}EasyRSA уже настроен${NC}"
    fi
    
    # Создание vars файла
    cat > "/etc/openvpn/easy-rsa/vars" << 'EOF'
# Easy-RSA 3 parameter settings

# Проверка корректного использования
if [ -z "$EASYRSA_CALLER" ]; then
        echo "You appear to be sourcing an Easy-RSA 'vars' file." >&2
        echo "This is no longer necessary and is disallowed." >&2
        return 1
fi

# Организационные данные для сертификатов
set_var EASYRSA_REQ_COUNTRY     "NL"
set_var EASYRSA_REQ_PROVINCE    "North Holland"
set_var EASYRSA_REQ_CITY        "Amsterdam"
set_var EASYRSA_REQ_ORG         "MSAV Co"
set_var EASYRSA_REQ_EMAIL       "msav@msav.ru"
set_var EASYRSA_REQ_OU          "Software Development NL Unit"

# Параметры ключей и сертификатов
set_var EASYRSA_KEY_SIZE        2048
set_var EASYRSA_CA_EXPIRE       3650
set_var EASYRSA_CERT_EXPIRE     3650
set_var EASYRSA_DIGEST          "sha256"
EOF
    
    chmod +x /etc/openvpn/easy-rsa/easyrsa
    echo -e "${GREEN}✓ EasyRSA настроен${NC}"
}

# Создание systemd сервиса для мониторинга
create_monitor_service() {
    echo -e "${BLUE}Создание сервиса мониторинга...${NC}"
    
    cat > /etc/systemd/system/openvpn-monitor.service << EOF
[Unit]
Description=OpenVPN Monitor Service
After=network.target openvpn@server.service

[Service]
Type=simple
ExecStart=$INSTALL_DIR/openvpn-monitor.sh 2
Restart=always
RestartSec=30
StandardOutput=null
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF
    
    systemctl daemon-reload
    echo -e "${GREEN}✓ Сервис мониторинга создан${NC}"
    echo -e "${YELLOW}Для запуска используйте: systemctl start openvpn-monitor${NC}"
}

# Создание cron задач
setup_cron() {
    echo -e "${BLUE}Настройка автоматических задач...${NC}"
    
    # Ежедневное резервное копирование
    local cron_backup="0 2 * * * $INSTALL_DIR/openvpn-manager.sh backup >/dev/null 2>&1"
    
    # Еженедельный отчет
    local cron_report="0 9 * * 1 $INSTALL_DIR/bulk-operations.sh report >/dev/null 2>&1"
    
    # Добавление в crontab
    (crontab -l 2>/dev/null | grep -v "openvpn-manager\|bulk-operations"; echo "$cron_backup"; echo "$cron_report") | crontab -
    
    echo -e "${GREEN}✓ Cron задачи настроены${NC}"
}

# Создание алиасов
create_aliases() {
    echo -e "${BLUE}Создание алиасов...${NC}"
    
    local alias_file="/etc/profile.d/openvpn-manager.sh"
    
    cat > "$alias_file" << 'EOF'
# OpenVPN Manager aliases
alias vpn-manager='openvpn-manager'
alias vpn-add='quick-add-client'
alias vpn-bulk='bulk-operations'
alias vpn-monitor='openvpn-monitor'
alias vpn-status='systemctl status openvpn@server'
alias vpn-restart='systemctl restart openvpn@server'
alias vpn-logs='tail -f /var/log/openvpn/openvpn.log'
EOF
    
    chmod +x "$alias_file"
    echo -e "${GREEN}✓ Алиасы созданы${NC}"
    echo -e "${YELLOW}Перезайдите в систему или выполните: source $alias_file${NC}"
}

# Постустановочная проверка
post_install_check() {
    echo
    echo -e "${BLUE}Проверка установки...${NC}"
    
    local errors=0
    
    # Проверка установленных файлов
    for script in openvpn-manager quick-add-client bulk-operations openvpn-monitor; do
        if [ -x "$BIN_DIR/$script" ]; then
            echo -e "${GREEN}✓ $script доступен${NC}"
        else
            echo -e "${RED}✗ $script не найден${NC}"
            ((errors++))
        fi
    done
    
    # Проверка конфигурации
    if [ -f "/etc/openvpn/openvpn.conf" ]; then
        echo -e "${GREEN}✓ Конфигурационный файл создан${NC}"
    else
        echo -e "${RED}✗ Конфигурационный файл не создан${NC}"
        ((errors++))
    fi
    
    if [ $errors -eq 0 ]; then
        echo
        echo -e "${GREEN}╔══════════════════════════════════════════════════════════════════╗${NC}"
        echo -e "${GREEN}║               Установка завершена успешно!                       ║${NC}"
        echo -e "${GREEN}╚══════════════════════════════════════════════════════════════════╝${NC}"
        echo
        echo -e "${BLUE}Доступные команды:${NC}"
        echo -e "  ${YELLOW}openvpn-manager${NC} - Главное меню управления"
        echo -e "  ${YELLOW}quick-add-client <имя>${NC} - Быстрое создание клиента"
        echo -e "  ${YELLOW}bulk-operations${NC} - Массовые операции"
        echo -e "  ${YELLOW}openvpn-monitor${NC} - Мониторинг сервера"
        echo
        echo -e "${BLUE}Первые шаги:${NC}"
        echo -e "1. Запустите ${YELLOW}openvpn-manager${NC} и выберите 'Инициализировать PKI'"
        echo -e "2. Настройте конфигурацию сервера OpenVPN"
        echo -e "3. Создайте первого клиента"
        echo
    else
        echo
        echo -e "${RED}Установка завершена с ошибками${NC}"
        echo -e "Проверьте сообщения выше и исправьте проблемы"
    fi
}

# Главная функция установки
main() {
    echo -e "${BLUE}Начало установки OpenVPN Manager...${NC}"
    echo
    
    # Выполнение шагов установки
    check_dependencies
    create_directories
    install_scripts
    create_config
    setup_easyrsa
    create_monitor_service
    setup_cron
    create_aliases
    
    # Финальная проверка
    post_install_check
}

# Запуск установки
main