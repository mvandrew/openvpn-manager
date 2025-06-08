#!/bin/bash

# openvpn-monitor.sh - Мониторинг и статистика OpenVPN сервера
# Отображает информацию о подключениях, трафике и производительности

# Цвета для вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
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

# Файл статуса OpenVPN
STATUS_FILE="$STATUS_LOG"

# Функция форматирования размера
format_bytes() {
    local bytes=$1
    
    if [ $bytes -lt 1024 ]; then
        echo "${bytes} B"
    elif [ $bytes -lt 1048576 ]; then
        echo "$(( bytes / 1024 )) KB"
    elif [ $bytes -lt 1073741824 ]; then
        echo "$(( bytes / 1048576 )) MB"
    else
        echo "$(( bytes / 1073741824 )) GB"
    fi
}

# Функция форматирования времени
format_uptime() {
    local seconds=$1
    local days=$(( seconds / 86400 ))
    local hours=$(( (seconds % 86400) / 3600 ))
    local minutes=$(( (seconds % 3600) / 60 ))
    
    if [ $days -gt 0 ]; then
        echo "${days}д ${hours}ч ${minutes}м"
    elif [ $hours -gt 0 ]; then
        echo "${hours}ч ${minutes}м"
    else
        echo "${minutes}м"
    fi
}

# Отображение заголовка
show_header() {
    clear
    echo -e "${BLUE}╔══════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║                    OpenVPN Server Monitor                        ║${NC}"
    echo -e "${BLUE}║                 $(date '+%Y-%m-%d %H:%M:%S')                    ║${NC}"
    echo -e "${BLUE}╚══════════════════════════════════════════════════════════════════╝${NC}"
    echo
}

# Информация о сервере
show_server_info() {
    echo -e "${CYAN}=== Информация о сервере ===${NC}"
    
    # Статус службы
    if systemctl is-active --quiet openvpn@server; then
        echo -e "Статус: ${GREEN}● Работает${NC}"
        
        # Время работы
        local start_time=$(systemctl show openvpn@server --property=ActiveEnterTimestampMonotonic | cut -d= -f2)
        local current_time=$(date +%s%N | cut -b1-16)
        local uptime=$(( (current_time - start_time) / 1000000 ))
        echo -e "Время работы: $(format_uptime $uptime)"
    else
        echo -e "Статус: ${RED}● Остановлен${NC}"
    fi
    
    echo -e "IP адрес: ${SERVER_IP}:${SERVER_PORT}"
    echo -e "Протокол: ${SERVER_PROTO^^}"
    
    # Загрузка CPU
    local cpu_usage=$(top -bn1 | grep "Cpu(s)" | awk '{print $2}' | cut -d'%' -f1)
    echo -e "Загрузка CPU: ${cpu_usage}%"
    
    # Использование памяти
    local mem_total=$(free -m | awk 'NR==2{print $2}')
    local mem_used=$(free -m | awk 'NR==2{print $3}')
    local mem_percent=$(( mem_used * 100 / mem_total ))
    echo -e "Память: ${mem_used}MB / ${mem_total}MB (${mem_percent}%)"
    
    echo
}

# Активные подключения
show_active_connections() {
    echo -e "${CYAN}=== Активные подключения ===${NC}"
    
    if [ ! -f "$STATUS_FILE" ]; then
        echo -e "${YELLOW}Файл статуса не найден${NC}"
        return
    fi
    
    local total_rx=0
    local total_tx=0
    local client_count=0
    
    # Парсинг файла статуса
    while IFS=',' read -r type name real_addr virtual_addr bytes_rx bytes_tx connected_since; do
        if [ "$type" = "CLIENT_LIST" ] && [ "$name" != "HEADER" ]; then
            ((client_count++))
            
            # Форматирование данных
            local rx_formatted=$(format_bytes $bytes_rx)
            local tx_formatted=$(format_bytes $bytes_tx)
            
            # Подсчет общего трафика
            total_rx=$(( total_rx + bytes_rx ))
            total_tx=$(( total_tx + bytes_tx ))
            
            # Время подключения
            local connect_timestamp=$(date -d "$connected_since" +%s 2>/dev/null)
            local current_timestamp=$(date +%s)
            local connection_time=$(( current_timestamp - connect_timestamp ))
            local time_formatted=$(format_uptime $connection_time)
            
            # Вывод информации о клиенте
            echo -e "${GREEN}● $name${NC}"
            echo -e "  IP: $real_addr → $virtual_addr"
            echo -e "  ↓ $rx_formatted | ↑ $tx_formatted"
            echo -e "  Подключен: $time_formatted"
            echo
        fi
    done < "$STATUS_FILE"
    
    # Общая статистика
    echo -e "${YELLOW}Всего клиентов: $client_count${NC}"
    echo -e "${YELLOW}Общий трафик: ↓ $(format_bytes $total_rx) | ↑ $(format_bytes $total_tx)${NC}"
    echo
}

# График трафика (простой ASCII)
show_traffic_graph() {
    echo -e "${CYAN}=== График трафика (последние 10 минут) ===${NC}"
    
    # Здесь можно реализовать простой ASCII график
    # Для примера показываем заглушку
    echo "   RX ▂▄▆█▆▄▂▁▂▄"
    echo "   TX ▁▂▄▂▁▂▄▆▄▂"
    echo "      └─────────┘"
    echo "       10m   Now"
    echo
}

# Статистика по клиентам
show_client_statistics() {
    echo -e "${CYAN}=== Статистика клиентов ===${NC}"
    
    cd "$EASYRSA_DIR" || return
    
    local total_certs=0
    local active_certs=0
    local revoked_certs=0
    
    # Подсчет сертификатов
    for cert in pki/issued/*.crt; do
        if [ -f "$cert" ]; then
            client=$(basename "$cert" .crt)
            if [ "$client" != "server" ]; then
                ((total_certs++))
                if ! grep -q "R.*CN=$client" pki/index.txt 2>/dev/null; then
                    ((active_certs++))
                else
                    ((revoked_certs++))
                fi
            fi
        fi
    done
    
    echo -e "Всего сертификатов: $total_certs"
    echo -e "Активных: ${GREEN}$active_certs${NC}"
    echo -e "Отозванных: ${RED}$revoked_certs${NC}"
    
    # Топ клиентов по трафику
    if [ -f "$STATUS_FILE" ]; then
        echo
        echo -e "${YELLOW}Топ-5 клиентов по трафику:${NC}"
        
        grep "^CLIENT_LIST" "$STATUS_FILE" | grep -v HEADER | \
            awk -F',' '{total=$5+$6; print $2, total}' | \
            sort -k2 -rn | head -5 | \
            while read name traffic; do
                echo -e "  $name: $(format_bytes $traffic)"
            done
    fi
    
    echo
}

# Системные логи
show_recent_logs() {
    echo -e "${CYAN}=== Последние события ===${NC}"
    
    if [ -f "/var/log/openvpn/openvpn.log" ]; then
        tail -n 10 /var/log/openvpn/openvpn.log | while read line; do
            if [[ $line == *"ERROR"* ]] || [[ $line == *"error"* ]]; then
                echo -e "${RED}$line${NC}"
            elif [[ $line == *"WARNING"* ]] || [[ $line == *"warning"* ]]; then
                echo -e "${YELLOW}$line${NC}"
            else
                echo "$line"
            fi
        done
    else
        echo -e "${YELLOW}Лог-файл не найден${NC}"
    fi
    
    echo
}

# Режим реального времени
monitor_realtime() {
    while true; do
        show_header
        show_server_info
        show_active_connections
        show_client_statistics
        
        echo -e "${BLUE}Обновление каждые 5 секунд. Нажмите Ctrl+C для выхода.${NC}"
        sleep 5
    done
}

# Экспорт статистики
export_statistics() {
    local export_file="${HOME}/openvpn_stats_$(date +%Y%m%d_%H%M%S).csv"
    
    echo "timestamp,client_name,real_address,bytes_received,bytes_sent,connected_since" > "$export_file"
    
    if [ -f "$STATUS_FILE" ]; then
        grep "^CLIENT_LIST" "$STATUS_FILE" | grep -v HEADER | \
            awk -F',' -v ts="$(date '+%Y-%m-%d %H:%M:%S')" \
            '{print ts","$2","$3","$5","$6","$7}' >> "$export_file"
    fi
    
    echo -e "${GREEN}Статистика экспортирована: $export_file${NC}"
}

# Проверка производительности
check_performance() {
    echo -e "${CYAN}=== Проверка производительности ===${NC}"
    
    # Проверка загрузки сети
    local interface=$(ip route | grep default | awk '{print $5}' | head -n1)
    if [ -n "$interface" ]; then
        echo -e "Сетевой интерфейс: $interface"
        
        # Получение статистики интерфейса
        local rx_bytes=$(cat /sys/class/net/$interface/statistics/rx_bytes)
        local tx_bytes=$(cat /sys/class/net/$interface/statistics/tx_bytes)
        
        sleep 1
        
        local rx_bytes_new=$(cat /sys/class/net/$interface/statistics/rx_bytes)
        local tx_bytes_new=$(cat /sys/class/net/$interface/statistics/tx_bytes)
        
        local rx_rate=$(( rx_bytes_new - rx_bytes ))
        local tx_rate=$(( tx_bytes_new - tx_bytes ))
        
        echo -e "Скорость: ↓ $(format_bytes $rx_rate)/s | ↑ $(format_bytes $tx_rate)/s"
    fi
    
    # Проверка количества соединений
    local conn_count=$(netstat -an | grep -c ":${SERVER_PORT}.*ESTABLISHED")
    echo -e "Активных TCP/UDP соединений: $conn_count"
    
    # Рекомендации
    if [ $conn_count -gt 100 ]; then
        echo -e "${YELLOW}⚠ Высокое количество соединений${NC}"
    fi
    
    echo
}

# Главное меню
show_menu() {
    echo
    echo -e "${BLUE}=== OpenVPN Monitor ===${NC}"
    echo "1. Показать сводку"
    echo "2. Мониторинг в реальном времени"
    echo "3. Детальная статистика клиентов"
    echo "4. Последние логи"
    echo "5. Проверка производительности"
    echo "6. Экспорт статистики в CSV"
    echo "7. Выход"
    echo
}

# Показать сводку
show_summary() {
    show_header
    show_server_info
    show_active_connections
    show_client_statistics
    show_recent_logs
}

# Главная функция
main() {
    # Проверка прав на чтение логов
    if [ ! -r "$STATUS_FILE" ] && [ -f "$STATUS_FILE" ]; then
        echo -e "${YELLOW}Предупреждение: Нет прав на чтение файла статуса${NC}"
        echo "Некоторые функции могут быть недоступны"
    fi
    
    while true; do
        show_menu
        read -p "Выберите действие: " choice
        
        case $choice in
            1)
                show_summary
                ;;
            2)
                monitor_realtime
                ;;
            3)
                show_client_statistics
                ;;
            4)
                show_recent_logs
                ;;
            5)
                check_performance
                ;;
            6)
                export_statistics
                ;;
            7)
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