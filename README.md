# OpenVPN Manager Suite

Набор скриптов для автоматизации управления OpenVPN сервером с централизованной конфигурацией и расширенными возможностями.

## 📋 Возможности

- **Централизованная конфигурация** - параметры автоматически извлекаются из server.conf
- **Портативность** - скрипты можно легко переносить между серверами
- **Управление клиентами** - создание, отзыв, массовые операции
- **Мониторинг в реальном времени** - статистика подключений и трафика
- **Автоматическое резервное копирование** - защита конфигураций
- **Массовые операции** - импорт из CSV, групповое создание/отзыв
- **Экспорт конфигураций** - включая QR-коды для мобильных устройств
- **Детальное логирование** - отслеживание всех операций

## 🚀 Быстрая установка

```bash
# Клонирование репозитория или копирование файлов
git clone https://github.com/your-repo/openvpn-manager.git
cd openvpn-manager

# Убедитесь, что manager.conf находится в текущей директории
# Запуск установщика
sudo ./install.sh
```

## 📁 Структура файлов

```
/etc/openvpn/
├── server.conf           # Конфигурация OpenVPN сервера
├── manager.conf          # Конфигурация скриптов управления
├── easy-rsa/             # PKI инфраструктура
├── client/               # Конфигурации клиентов (.ovpn)
├── ccd/                  # Индивидуальные настройки клиентов
└── backup/               # Резервные копии

/var/log/openvpn/         # Логи
├── openvpn.log          # Основной лог сервера
├── status.log           # Статус подключений
└── manager.log          # Лог операций менеджера

/opt/openvpn-manager/     # Установленные скрипты
├── openvpn-manager.sh    # Главный скрипт управления
├── quick-add-client.sh   # Быстрое добавление клиента
├── bulk-operations.sh    # Массовые операции
└── openvpn-monitor.sh    # Мониторинг
```

## 📝 Конфигурационные файлы

### server.conf
Основной конфигурационный файл OpenVPN сервера. Скрипты автоматически извлекают из него:
- Порт и протокол
- Сеть VPN
- Настройки DNS
- Параметры безопасности
- Максимальное количество клиентов

### manager.conf
Конфигурационный файл для скриптов управления:
- Пути к файлам и директориям
- Параметры EasyRSA
- Настройки логирования
- Функции для извлечения параметров из server.conf

Скрипты автоматически ищут manager.conf в:
1. `/etc/openvpn/manager.conf`
2. Директории со скриптом
3. Текущей директории

## 🛠️ Использование

### Главное меню управления

```bash
sudo openvpn-manager
```

Доступные функции:
1. Инициализация PKI (первый запуск)
2. Создание клиента
3. Отзыв клиента
4. Список клиентов
5. Активные подключения
6. Экспорт конфигурации
7. Проверка конфигурации
8. Резервное копирование
9. Статус сервера

### Быстрое создание клиента

```bash
sudo quick-add-client username
```

Автоматически:
- Создаст сертификат
- Сгенерирует .ovpn файл
- Скопирует в домашнюю директорию

### Массовые операции

```bash
sudo bulk-operations
```

Возможности:
- Создание нескольких клиентов
- Импорт из CSV файла
- Массовый отзыв сертификатов
- Экспорт всех конфигураций
- Генерация отчетов

#### Формат CSV для импорта:
```csv
client_name,email
john_doe,john@example.com
jane_smith,jane@example.com
```

### Мониторинг

```bash
sudo openvpn-monitor
```

Показывает:
- Статус сервера и uptime
- Активные подключения
- Статистику трафика
- Топ клиентов по трафику
- Системные метрики

## 🔧 Дополнительные команды

### Алиасы (доступны после установки)

```bash
vpn-manager    # Главное меню
vpn-add        # Быстрое добавление клиента
vpn-bulk       # Массовые операции
vpn-monitor    # Мониторинг
vpn-status     # Статус службы
vpn-restart    # Перезапуск сервера
vpn-logs       # Просмотр логов
```

### Примеры использования

```bash
# Создать клиента и отправить конфигурацию по email
sudo quick-add-client john_doe

# Импортировать клиентов из CSV
sudo bulk-operations
# Выбрать пункт 2, указать путь к CSV файлу

# Мониторинг в реальном времени
sudo openvpn-monitor
# Выбрать пункт 2 для обновления каждые 5 секунд

# Создать резервную копию
sudo openvpn-manager
# Выбрать пункт 8
```

## 📊 Формат .ovpn файла

Генерируемые конфигурации содержат:

```
client
dev tun
proto udp
remote 103.54.16.228 1194
resolv-retry infinite
nobind
persist-key
persist-tun
remote-cert-tls server
auth SHA256
data-ciphers AES-256-GCM:AES-128-GCM:CHACHA20-POLY1305:AES-256-CBC
tls-client
tls-auth ta.key 1
key-direction 1
verb 3
redirect-gateway def1 bypass-dhcp
dhcp-option DNS 8.8.8.8
dhcp-option DNS 8.8.4.4

<ca>
# CA сертификат
</ca>

<cert>
# Клиентский сертификат
</cert>

<key>
# Приватный ключ клиента
</key>

<tls-auth>
# TLS ключ
</tls-auth>
```

## 🔐 Безопасность

- Все ключи хранятся с правами 600
- Автоматическое резервное копирование
- Поддержка CRL (Certificate Revocation List)
- Логирование всех операций
- Современные шифры и алгоритмы

## 🚨 Решение проблем

### Сервер не запускается
```bash
# Проверить конфигурацию
sudo openvpn-manager
# Выбрать пункт 7 (Проверить конфигурацию)

# Проверить логи
sudo vpn-logs
```

#### Ошибка "failed to find GID for group nobody"
**Проблема:** В Ubuntu/Debian группа называется `nogroup`, а не `nobody`.

**Симптомы:**
- Сервер не запускается
- В логах ошибка: `failed to find GID for group nobody`
- Статус службы показывает `exit-code`

**Решение:**
```bash
# Исправить группу в конфигурации
sed -i 's/group nobody/group nogroup/' /etc/openvpn/server.conf

# Перезапустить сервер
systemctl restart openvpn@server
systemctl status openvpn@server
```

#### Отсутствует файл CRL (Certificate Revocation List)
**Проблема:** Ошибка `--crl-verify fails with '/etc/openvpn/crl.pem': No such file or directory`

**Решение:**
```bash
# Создать CRL файл
cd /etc/openvpn/easy-rsa
./easyrsa gen-crl
cp pki/crl.pem /etc/openvpn/crl.pem
chmod 644 /etc/openvpn/crl.pem

# Перезапустить сервер
systemctl restart openvpn@server
```

**Альтернативное решение (временное):**
```bash
# Отключить проверку CRL
sed -i 's/^crl-verify/#crl-verify/' /etc/openvpn/server.conf
```

### Клиент не подключается
1. Проверьте, что порт открыт в файрволе
2. Убедитесь, что IP сервера правильный
3. Проверьте время на сервере и клиенте

### Ошибка при создании сертификата
```bash
# Проверить PKI
cd /etc/openvpn/easy-rsa
./easyrsa show-ca
```

### Диагностика проблем запуска
```bash
# Проверить подробные логи
tail -50 /var/log/openvpn/openvpn.log

# Запустить OpenVPN в режиме отладки
openvpn --config /etc/openvpn/server.conf --verb 4

# Проверить наличие всех файлов
ls -la /etc/openvpn/{ca.crt,server.crt,server.key,dh.pem,ta.key,crl.pem}

# Проверить права доступа
chmod 644 /etc/openvpn/{ca.crt,server.crt,dh.pem,ta.key,crl.pem}
chmod 600 /etc/openvpn/server.key
```

## 📅 Автоматические задачи

После установки настроены cron задачи:
- **Ежедневно в 2:00** - резервное копирование
- **Еженедельно в понедельник 9:00** - генерация отчета

## 📧 Уведомления

Для получения уведомлений по email:
1. Установите `mailutils`
2. Укажите email в `openvpn.conf`
3. Настройте SMTP на сервере

## 🔄 Обновление

```bash
# Создать резервную копию
sudo openvpn-manager
# Выбрать пункт 8

# Обновить скрипты
cd /path/to/new/scripts
sudo ./install.sh
```

## 📄 Лицензия

MIT License - свободное использование и модификация
