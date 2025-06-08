#!/bin/bash

# Создание базовой конфигурации сервера OpenVPN
cat > /etc/openvpn/server.conf << 'EOF'
# Порт и протокол
port 1194
proto udp

# Устройство
dev tun

# Сертификаты и ключи
ca ca.crt
cert server.crt
key server.key
dh dh.pem
tls-auth ta.key 0

# Сеть VPN
server 10.8.0.0 255.255.255.0

# Маршрутизация
push "redirect-gateway def1 bypass-dhcp"
push "dhcp-option DNS 8.8.8.8"
push "dhcp-option DNS 8.8.4.4"

# Безопасность
auth SHA256
data-ciphers AES-256-GCM:AES-128-GCM:CHACHA20-POLY1305:AES-256-CBC
tls-version-min 1.2

# Настройки клиентов
client-to-client
keepalive 10 120
max-clients 100

# Логирование
status /var/log/openvpn/status.log
log-append /var/log/openvpn/openvpn.log
verb 3

# Права пользователя
user nobody
group nogroup

# Постоянство ключей и tun
persist-key
persist-tun

# CRL для отозванных сертификатов
crl-verify crl.pem
EOF

echo "Конфигурация сервера создана в /etc/openvpn/server.conf" 