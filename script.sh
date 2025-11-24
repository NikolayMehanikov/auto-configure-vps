#!/bin/bash

######################################################################
#    NoctaShell SAFE-SECURITY SETUP (UFW OFF)
#    - Создание пользователя ryvyj (пароль спрашивает интерактивно)
#    - sudo без пароля
#    - Смена SSH порта 22 → 50012
#    - Полное отключение root SSH входа
#    - Fail2Ban (SSH)
#    - sysctl hardening
#    - Anti-scan iptables
#    - UFW выключен
#    - Порты НЕ трогаются
######################################################################

NEW_SSH_PORT=50012
USERNAME="ryvyj"

echo "=== [1/10] Обновление системы ==="
apt update -y && apt upgrade -y

######################################################################
#   СОЗДАНИЕ ПОЛЬЗОВАТЕЛЯ
######################################################################
echo "=== [2/10] Создание пользователя '$USERNAME' ==="

if id "$USERNAME" &>/dev/null; then
    echo "Пользователь '$USERNAME' уже существует. Пропускаем создание."
else
    adduser "$USERNAME"
    usermod -aG sudo "$USERNAME"
fi

######################################################################
#   SUDO БЕЗ ПАРОЛЯ
######################################################################
echo "=== [3/10] Настройка sudo без пароля ==="

echo "$USERNAME ALL=(ALL) NOPASSWD:ALL" >/etc/sudoers.d/${USERNAME}_nopasswd
chmod 440 /etc/sudoers.d/${USERNAME}_nopasswd

######################################################################
#   SSH HARDENING + СМЕНА ПОРТА
######################################################################
echo "=== [4/10] Настройка SSH + смена порта 22 → $NEW_SSH_PORT ==="

cp /etc/ssh/sshd_config /etc/ssh/sshd_config.backup

# Смена порта
sed -i "s/^#Port 22/Port $NEW_SSH_PORT/" /etc/ssh/sshd_config
sed -i "s/^Port 22/Port $NEW_SSH_PORT/" /etc/ssh/sshd_config

# Отключение root входа
sed -i "s/^#PermitRootLogin yes/PermitRootLogin no/" /etc/ssh/sshd_config
sed -i "s/^PermitRootLogin yes/PermitRootLogin no/" /etc/ssh/sshd_config
sed -i "s/^#PermitRootLogin prohibit-password/PermitRootLogin no/" /etc/ssh/sshd_config
sed -i "s/^PermitRootLogin prohibit-password/PermitRootLogin no/" /etc/ssh/sshd_config

# Отключение баннеров
sed -i "s/^Banner.*/#Banner/" /etc/ssh/sshd_config
rm -f /etc/issue /etc/issue.net
touch /etc/issue /etc/issue.net

systemctl daemon-reload
systemctl restart ssh

######################################################################
#   FAIL2BAN
######################################################################
echo "=== [5/10] Установка Fail2Ban ==="

apt install -y fail2ban

cat >/etc/fail2ban/jail.local <<EOF
[DEFAULT]
bantime = 30m
findtime = 10m
maxretry = 5
backend = systemd

[sshd]
enabled = true
port = $NEW_SSH_PORT
logpath = /var/log/auth.log
EOF

systemctl enable fail2ban
systemctl restart fail2ban

######################################################################
#   SYSCTL HARDENING
######################################################################
echo "=== [6/10] Применение sysctl-hardening ==="

cat >/etc/sysctl.d/99-hardening.conf <<EOF
# Сервер перестаёт отвечать на ping
net.ipv4.icmp_echo_ignore_all = 1

# SYN cookies (anti-flood)
net.ipv4.tcp_syncookies = 1

# Отключить redirects
net.ipv4.conf.all.send_redirects = 0
net.ipv4.conf.default.send_redirects = 0
net.ipv4.conf.all.accept_redirects = 0
net.ipv4.conf.default.accept_redirects = 0

# Anti-spoofing
net.ipv4.conf.all.rp_filter = 1
net.ipv4.conf.default.rp_filter = 1
EOF

sysctl --system

######################################################################
#   IPTABLES ANTI-SCAN
######################################################################
echo "=== [7/10] Anti-scan фильтры iptables ==="

apt install -y iptables-persistent

# NULL scan
iptables -A INPUT -p tcp --tcp-flags ALL NONE -j DROP
# Xmas / FIN scan
iptables -A INPUT -p tcp ! --syn -m state --state NEW -j DROP
# Xmas scan
iptables -A INPUT -p tcp --tcp-flags ALL ALL -j DROP

netfilter-persistent save

######################################################################
#   ОТКЛЮЧЕНИЕ UFW
######################################################################
echo "=== [8/10] Полное отключение UFW ==="
systemctl stop ufw
systemctl disable ufw

######################################################################
#   ФИНАЛ
######################################################################
echo "=== [9/10] Настройка завершена ==="
echo "------------------------------------------------------"
echo "✔ Root вход:                отключён"
echo "✔ SSH порт:                 $NEW_SSH_PORT"
echo "✔ Пользователь:             $USERNAME"
echo "✔ Пароль sudo:              не требуется"
echo "✔ UFW firewall:             выключен"
echo "✔ Fail2Ban:                 включён"
echo "✔ Anti-scan iptables:       включён"
echo "✔ sysctl защита:            включена"
echo "✔ Открытые порты:           НЕ трогались"
echo "------------------------------------------------------"
echo "Важно: переподключайся так:"
echo "ssh -p $NEW_SSH_PORT $USERNAME@<IP>"
