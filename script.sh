#!/bin/bash

clear
echo ""
echo "------------------------------------------------------"
echo "   🛡️  NoctaShell SAFE SECURITY INSTALLER v2"
echo "        Mode: UFW OFF / Ports Untouched"
echo "------------------------------------------------------"
echo ""

USERNAME="ryvyj"
NEW_SSH_PORT=50012

###############################################################
# 1. СОЗДАНИЕ ПОЛЬЗОВАТЕЛЯ
###############################################################
echo "[1/10] Создание пользователя '$USERNAME'..."
sleep 0.5

if id "$USERNAME" &>/dev/null; then
    echo "     ↳ Пользователь '$USERNAME' уже существует — пропускаем."
else
    echo "     → adduser $USERNAME"
    adduser "$USERNAME"
    echo "     → usermod -aG sudo $USERNAME"
    usermod -aG sudo "$USERNAME"
    echo "     ✔ Пользователь создан."
fi
echo ""

###############################################################
# 2. SUDO БЕЗ ПАРОЛЯ
###############################################################
echo "[2/10] Настройка sudo без пароля..."
sleep 0.5

sudoers_file="/etc/sudoers.d/${USERNAME}_nopasswd"
echo "     → Создаём файл $sudoers_file"
echo "$USERNAME ALL=(ALL) NOPASSWD:ALL" > "$sudoers_file"

echo "     → chmod 440 $sudoers_file"
chmod 440 "$sudoers_file"

echo "     ✔ sudo теперь НЕ требует пароль."
echo ""

###############################################################
# 3. SSH HARDENING + Смена порта
###############################################################
echo "[3/10] Настройка SSH и смена порта → $NEW_SSH_PORT ..."
sleep 0.5

echo "     → Создаём backup: /etc/ssh/sshd_config.backup"
cp /etc/ssh/sshd_config /etc/ssh/sshd_config.backup

# Логи: какие строки меняются
echo "     → Меняем порт SSH"
grep -E "^Port" /etc/ssh/sshd_config || echo "     (Port строка ещё не существует)"

sed -i "s/^#Port 22/Port $NEW_SSH_PORT/" /etc/ssh/sshd_config
sed -i "s/^Port 22/Port $NEW_SSH_PORT/" /etc/ssh/sshd_config

echo "     → Отключаем root login"
sed -i "s/^#PermitRootLogin.*/PermitRootLogin no/" /etc/ssh/sshd_config
sed -i "s/^PermitRootLogin.*/PermitRootLogin no/" /etc/ssh/sshd_config

echo "     → Отключаем SSH баннер"
sed -i "s/^Banner.*/#Banner/" /etc/ssh/sshd_config

echo "     → Чистим /etc/issue и issue.net"
rm -f /etc/issue /etc/issue.net
touch /etc/issue /etc/issue.net

echo "     → Перезапуск SSH"
systemctl daemon-reload
systemctl restart ssh

echo "     ✔ SSH настроен и перенесён на порт $NEW_SSH_PORT."
echo ""

###############################################################
# 4. FAIL2BAN
###############################################################
echo "[4/10] Установка и настройка Fail2Ban..."
sleep 0.5

echo "     → apt install fail2ban"
apt install -y fail2ban >/dev/null 2>&1

echo "     → Создаём /etc/fail2ban/jail.local"
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

echo "     → Перезапуск Fail2Ban"
systemctl enable fail2ban >/dev/null 2>&1
systemctl restart fail2ban

echo "     ✔ Fail2Ban активирован."
echo ""

###############################################################
# 5. SYSCTL HARDENING
###############################################################
echo "[5/10] Применение sysctl-защиты..."
sleep 0.5

echo "     → Создаём /etc/sysctl.d/99-hardening.conf"

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

echo "     → Применяем sysctl --system"
sysctl --system >/dev/null 2>&1

echo "     ✔ sysctl защита активирована."
echo ""

###############################################################
# 6. IPTABLES ANTI-SCAN
###############################################################
echo "[6/10] Iptables анти-скан фильтры..."
sleep 0.5

echo "     → apt install iptables-persistent"
apt install -y iptables-persistent >/dev/null 2>&1

echo "     → Добавляем NULL scan DROP"
iptables -A INPUT -p tcp --tcp-flags ALL NONE -j DROP

echo "     → Добавляем XMAS/FIN scan DROP"
iptables -A INPUT -p tcp ! --syn -m state --state NEW -j DROP

echo "     → Добавляем XMAS scan DROP"
iptables -A INPUT -p tcp --tcp-flags ALL ALL -j DROP

echo "     → Сохраняем правила"
netfilter-persistent save >/dev/null 2>&1

echo "     ✔ Анти-скан включён."
echo ""

###############################################################
# 7. UFW OFF
###############################################################
echo "[7/10] Отключение UFW..."
sleep 0.5

echo "     → systemctl stop ufw"
systemctl stop ufw >/dev/null 2>&1

echo "     → systemctl disable ufw"
systemctl disable ufw >/dev/null 2>&1

echo "     ✔ UFW отключён."
echo ""

###############################################################
# 10. ФИНАЛ
###############################################################
echo "------------------------------------------------------"
echo "    🟢 Установка завершена успешно"
echo "------------------------------------------------------"
echo " Пользователь:            $USERNAME"
echo " Sudo без пароля:         ✔"
echo " Root вход:               ✘ отключён"
echo " SSH порт:                $NEW_SSH_PORT"
echo " Fail2Ban:                ✔ активен"
echo " sysctl hardening:        ✔ включён"
echo " Anti-scan iptables:      ✔ включён"
echo " Firewall (UFW):          ✘ выключен"
echo " Порты:                   ✔ НЕ трогались"
echo "------------------------------------------------------"
echo " Подключение по SSH:"
echo "   ssh -p $NEW_SSH_PORT $USERNAME@<IP>"
echo "------------------------------------------------------"
echo ""
