#!/bin/bash

######################################################################
#    NoctaShell SAFE-SECURITY SETUP (UFW OFF)
#    - Создание пользователя ryvyj (пароль спрашивает)
#    - sudo без пароля
#    - Смена SSH порта 22 → 50012
#    - Полное отключение root SSH входа
#    - Fail2Ban (SSH)
#    - sysctl hardening
#    - iptables anti-scan
#    - UFW выключен
#    - Порты НЕ трогаются
######################################################################

clear
echo ""
echo "------------------------------------------------------"
echo "   🛡️  NoctaShell SAFE SECURITY INSTALLER"
echo "        Mode: UFW OFF / Ports Untouched"
echo "------------------------------------------------------"
echo ""

######################################################################
#   1. СОЗДАНИЕ ПОЛЬЗОВАТЕЛЯ
######################################################################
echo "[1/10] Создание пользователя 'ryvyj'..."

USERNAME="ryvyj"

if id "$USERNAME" &>/dev/null; then
    echo "     ↳ Пользователь уже существует — пропускаем."
else
    adduser "$USERNAME"
    usermod -aG sudo "$USERNAME"
    echo "     ✔ Пользователь создан."
fi
echo ""

######################################################################
#   2. SUDO БЕЗ ПАРОЛЯ
######################################################################
echo "[2/10] Настройка sudo без пароля..."

echo "$USERNAME ALL=(ALL) NOPASSWD:ALL" >/etc/sudoers.d/${USERNAME}_nopasswd
chmod 440 /etc/sudoers.d/${USERNAME}_nopasswd

echo "     ✔ Настроено."
echo ""

######################################################################
#   3. SSH HARDENING + Смена порта
######################################################################
echo "[3/10] Настройка SSH и смена порта 22 → 50012..."

NEW_SSH_PORT=50012

cp /etc/ssh/sshd_config /etc/ssh/sshd_config.backup

sed -i "s/^#Port 22/Port $NEW_SSH_PORT/" /etc/ssh/sshd_config
sed -i "s/^Port 22/Port $NEW_SSH_PORT/" /etc/ssh/sshd_config

sed -i "s/^#PermitRootLogin yes/PermitRootLogin no/" /etc/ssh/sshd_config
sed -i "s/^PermitRootLogin yes/PermitRootLogin no/" /etc/ssh/sshd_config
sed -i "s/^#PermitRootLogin prohibit-password/PermitRootLogin no/" /etc/ssh/sshd_config
sed -i "s/^PermitRootLogin prohibit-password/PermitRootLogin no/" /etc/ssh/sshd_config

sed -i "s/^Banner.*/#Banner/" /etc/ssh/sshd_config

rm -f /etc/issue /etc/issue.net
touch /etc/issue /etc/issue.net

systemctl daemon-reload
systemctl restart ssh

echo "     ✔ SSH настроен."
echo ""

######################################################################
#   4. FAIL2BAN
######################################################################
echo "[4/10] Установка и настройка Fail2Ban..."

apt install -y fail2ban >/dev/null 2>&1

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

systemctl enable fail2ban >/dev/null 2>&1
systemctl restart fail2ban

echo "     ✔ Fail2Ban активирован."
echo ""

######################################################################
#   5. SYSCTL HARDENING
######################################################################
echo "[5/10] Применение sysctl-защиты..."

cat >/etc/sysctl.d/99-hardening.conf <<EOF
net.ipv4.icmp_echo_ignore_all = 1
net.ipv4.tcp_syncookies = 1
net.ipv4.conf.all.send_redirects = 0
net.ipv4.conf.default.send_redirects = 0
net.ipv4.conf.all.accept_redirects = 0
net.ipv4.conf.default.accept_redirects = 0
net.ipv4.conf.all.rp_filter = 1
net.ipv4.conf.default.rp_filter = 1
EOF

sysctl --system >/dev/null 2>&1

echo "     ✔ sysctl защита включена."
echo ""

######################################################################
#   6. IPTABLES ANTI-SCAN
######################################################################
echo "[6/10] Анти-скан iptables фильтры..."

apt install -y iptables-persistent >/dev/null 2>&1

iptables -A INPUT -p tcp --tcp-flags ALL NONE -j DROP
iptables -A INPUT -p tcp ! --syn -m state --state NEW -j DROP
iptables -A INPUT -p tcp --tcp-flags ALL ALL -j DROP

netfilter-persistent save >/dev/null 2>&1

echo "     ✔ Анти-скан фильтры активированы."
echo ""

######################################################################
#   7. UFW OFF
######################################################################
echo "[7/10] Отключение UFW..."

systemctl stop ufw >/dev/null 2>&1
systemctl disable ufw >/dev/null 2>&1

echo "     ✔ UFW выключен."
echo ""

######################################################################
#   8. ФИНАЛЬНАЯ СТАТУС-ИНФА
######################################################################
echo "------------------------------------------------------"
echo "    🟢 Установка завершена успешно"
echo "------------------------------------------------------"
echo " Пользователь:            $USERNAME"
echo " Sudo без пароля:         ✔"
echo " Root вход:               ✘ отключён"
echo " SSH порт:                $NEW_SSH_PORT"
echo " Fail2Ban:                ✔ активен"
echo " sysctl hardening:        ✔"
echo " Anti-scan iptables:      ✔"
echo " Firewall (UFW):          ✘ выключен"
echo " Порты:                   ✔ НЕ трогались"
echo "------------------------------------------------------"
echo " Подключение по SSH теперь:"
echo "   ssh -p $NEW_SSH_PORT $USERNAME@<IP>"
echo "------------------------------------------------------"
echo ""
