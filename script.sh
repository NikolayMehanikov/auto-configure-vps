#!/bin/bash

#############################################
# NoctaShell SAFE SECURITY v3
# - Safe Mode (UFW OFF)
# - FIX: iptables-persistent hang
# - Full logging + colors
# - Must be run as root
#############################################

# ---------- COLORS ----------
GREEN="\e[32m"
YELLOW="\e[33m"
BLUE="\e[34m"
RED="\e[31m"
RESET="\e[0m"

# ---------- CHECK ROOT ----------
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}❌ Скрипт должен быть запущен от root!${RESET}"
    echo -e "${YELLOW}➡ Используй: sudo bash script.sh${RESET}"
    exit 1
fi

clear
echo -e "${BLUE}------------------------------------------------------${RESET}"
echo -e "   🛡️  ${GREEN}NoctaShell SAFE SECURITY INSTALLER v3${RESET}"
echo -e "        Mode: ${YELLOW}UFW OFF / Ports Untouched${RESET}"
echo -e "${BLUE}------------------------------------------------------${RESET}"
echo ""

USERNAME="ryvyj"
NEW_SSH_PORT=50012

#############################################
# 1. CREATE USER
#############################################
echo -e "${YELLOW}[1/10] Создание пользователя '${USERNAME}'...${RESET}"
sleep 0.4

if id "$USERNAME" &>/dev/null; then
    echo -e "  ↳ ${BLUE}Пользователь уже существует — пропускаем.${RESET}"
else
    echo -e "  → adduser $USERNAME"
    adduser "$USERNAME"
    echo -e "  → usermod -aG sudo $USERNAME"
    usermod -aG sudo "$USERNAME"
fi
echo ""

#############################################
# 2. SUDO NO-PASSWORD
#############################################
echo -e "${YELLOW}[2/10] Настройка sudo без пароля...${RESET}"
sleep 0.4

sudoers_file="/etc/sudoers.d/${USERNAME}_nopasswd"
echo "$USERNAME ALL=(ALL) NOPASSWD:ALL" > "$sudoers_file"
chmod 440 "$sudoers_file"

echo -e "  ${GREEN}✔ sudo теперь не требует пароль${RESET}"
echo ""

#############################################
# 3. SSH HARDENING + PORT CHANGE
#############################################
echo -e "${YELLOW}[3/10] Настройка SSH → порт $NEW_SSH_PORT...${RESET}"
sleep 0.4

cp /etc/ssh/sshd_config /etc/ssh/sshd_config.backup

echo "  → Меняем порт SSH"
sed -i "s/^#Port 22/Port $NEW_SSH_PORT/" /etc/ssh/sshd_config
sed -i "s/^Port 22/Port $NEW_SSH_PORT/" /etc/ssh/sshd_config

echo "  → Запрещаем root-login"
sed -i "s/^#PermitRootLogin.*/PermitRootLogin no/" /etc/ssh/sshd_config
sed -i "s/^PermitRootLogin.*/PermitRootLogin no/" /etc/ssh/sshd_config

echo "  → Выключаем баннер SSH"
sed -i "s/^Banner.*/#Banner/" /etc/ssh/sshd_config

rm -f /etc/issue /etc/issue.net
touch /etc/issue /etc/issue.net

echo "  → Перезапускаем SSH"
systemctl daemon-reload
systemctl restart ssh

if [ $? -eq 0 ]; then
    echo -e "  ${GREEN}✔ SSH успешно перезапущен${RESET}"
else
    echo -e "  ${RED}❌ Ошибка перезапуска SSH — проверь вручную!${RESET}"
fi

echo ""

#############################################
# 4. FAIL2BAN
#############################################
echo -e "${YELLOW}[4/10] Установка и настройка Fail2Ban...${RESET}"
sleep 0.4

DEBIAN_FRONTEND=noninteractive apt-get install -y fail2ban >/dev/null 2>&1

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

echo -e "  ${GREEN}✔ Fail2Ban активирован${RESET}"
echo ""

#############################################
# 5. SYSCTL HARDENING
#############################################
echo -e "${YELLOW}[5/10] Применение sysctl-защиты...${RESET}"
sleep 0.4

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

echo -e "  ${GREEN}✔ sysctl защита включена${RESET}"
echo ""

#############################################
# 6. IPTABLES ANTI-SCAN
#############################################
echo -e "${YELLOW}[6/10] Установка анти-скан фильтров...${RESET}"
sleep 0.4

DEBIAN_FRONTEND=noninteractive apt-get install -y iptables-persistent >/dev/null 2>&1

echo "  → Добавляем DROP для NULL scan"
iptables -A INPUT -p tcp --tcp-flags ALL NONE -j DROP

echo "  → Добавляем DROP для FIN/XMAS scan"
iptables -A INPUT -p tcp ! --syn -m state --state NEW -j DROP

echo "  → Добавляем DROP для XMAS scan"
iptables -A INPUT -p tcp --tcp-flags ALL ALL -j DROP

netfilter-persistent save >/dev/null 2>&1

echo -e "  ${GREEN}✔ анти-скан защита включена${RESET}"
echo ""

#############################################
# 7. UFW OFF
#############################################
echo -e "${YELLOW}[7/10] Отключаем UFW...${RESET}"

systemctl stop ufw >/dev/null 2>&1
systemctl disable ufw >/dev/null 2>&1

echo -e "  ${GREEN}✔ UFW выключен${RESET}"
echo ""

#############################################
# FINAL
#############################################
echo -e "${BLUE}------------------------------------------------------${RESET}"
echo -e "    🟢 ${GREEN}Установка завершена успешно${RESET}"
echo -e "${BLUE}------------------------------------------------------${RESET}"
echo " Пользователь:            $USERNAME"
echo " SSH порт:                $NEW_SSH_PORT"
echo " Root вход:               выключен"
echo " Sudo без пароля:         включено"
echo " Fail2Ban:                активен"
echo " sysctl:                  включён"
echo " Anti-scan iptables:      включён"
echo " Firewall (UFW):          отключён"
echo " Порты:                   НЕ трогались"
echo -e "${BLUE}------------------------------------------------------${RESET}"
echo " Новая команда подключения:"
echo -e "   ${GREEN}ssh -p $NEW_SSH_PORT $USERNAME@<IP>${RESET}"
echo -e "${BLUE}------------------------------------------------------${RESET}"
echo ""
