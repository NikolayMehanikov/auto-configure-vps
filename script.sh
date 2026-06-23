#!/bin/bash


# ---------- COLORS ----------
GREEN="\e[32m"
YELLOW="\e[33m"
BLUE="\e[34m"
RED="\e[31m"
RESET="\e[0m"

NEW_SSH_PORT=50012

# ---------- CHECK ROOT ----------
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}❌ Скрипт должен быть запущен от root!${RESET}"
    echo -e "${YELLOW}➡ Используй: sudo bash script.sh${RESET}"
    exit 1
fi

clear
echo -e "${BLUE}------------------------------------------------------${RESET}"
echo -e "   🛡️  ${GREEN}SAFE SECURITY INSTALLER v5${RESET}"
echo -e "        Mode: ${YELLOW}UFW OFF / Ports Untouched${RESET}"
echo -e "${BLUE}------------------------------------------------------${RESET}"
echo ""

#############################################
# 0. ВЫБОР: НАСТРОЙКА СЕРТА ДЛЯ HYSTERIA2
#############################################
echo -e "${YELLOW}Настроить сертификат для Hysteria2 (вытащить из Caddy + cron автопродление)?${RESET}"
# /dev/tty — чтобы read работал даже при запуске через curl | bash
if [ -e /dev/tty ]; then
    read -r -p "  [y/N]: " DO_CERT </dev/tty
else
    read -r -p "  [y/N]: " DO_CERT
fi
DO_CERT=$(echo "$DO_CERT" | tr '[:upper:]' '[:lower:]')
echo ""

#############################################
# 1. ROOT PASSWORD CHANGE
#############################################
echo -e "${YELLOW}[1/10] Установка нового пароля root...${RESET}"
sleep 0.4

passwd root

echo -e "  ${GREEN}✔ Пароль root успешно изменён${RESET}"
echo ""

#############################################
# 2. SSH HARDENING + PORT CHANGE
#############################################
echo -e "${YELLOW}[2/10] Настройка SSH → порт $NEW_SSH_PORT...${RESET}"
sleep 0.4

cp /etc/ssh/sshd_config /etc/ssh/sshd_config.backup

echo "  → Меняем порт SSH"
sed -i "s/^#Port 22/Port $NEW_SSH_PORT/" /etc/ssh/sshd_config
sed -i "s/^Port 22/Port $NEW_SSH_PORT/" /etc/ssh/sshd_config

echo "  → Отключаем SSH баннер"
sed -i "s/^Banner.*/#Banner/" /etc/ssh/sshd_config

rm -f /etc/issue /etc/issue.net
touch /etc/issue /etc/issue.net

echo "  → Перезапускаем SSH"
systemctl daemon-reload
systemctl restart ssh

echo -e "  ${GREEN}✔ SSH успешно перезапущен${RESET}"
echo ""

#############################################
# 3. FAIL2BAN
#############################################
echo -e "${YELLOW}[3/10] Установка и настройка Fail2Ban...${RESET}"
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
# 4. SYSCTL HARDENING
#############################################
echo -e "${YELLOW}[4/10] Применение sysctl-защиты...${RESET}"
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
# 5. IPTABLES ANTI-SCAN
#############################################
echo -e "${YELLOW}[5/10] Установка анти-скан фильтров...${RESET}"
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
# 6. UFW OFF
#############################################
echo -e "${YELLOW}[6/10] Отключаем UFW...${RESET}"
sleep 0.4

systemctl stop ufw >/dev/null 2>&1
systemctl disable ufw >/dev/null 2>&1

echo -e "  ${GREEN}✔ UFW выключен${RESET}"
echo ""

#############################################
# 7. HYSTERIA2 CERT (опционально)
#############################################
CERT_DONE="пропущено"
CERT_DOMAIN="-"
MOUNT_STATUS=""

if [ "$DO_CERT" = "y" ]; then
    echo -e "${YELLOW}[7/10] Настройка сертификата для Hysteria2...${RESET}"
    sleep 0.4

    NODE="remnanode"
    DEST="/var/lib/remnawave/configs/xray/ssl"

    # --- автодетект серта Caddy (LE или ZeroSSL, исключая внутренний CA) ---
    CRT=$(find /var/lib/docker/volumes -path '*acme*' -name '*.crt' 2>/dev/null | head -n1)

    if [ -z "$CRT" ]; then
        echo -e "  ${RED}✘ Серт Caddy не найден. Caddy запущен и выписал серт на реальный домен?${RESET}"
        CERT_DONE="ОШИБКА: серт не найден"
    else
        CERT_DOMAIN=$(basename "$(dirname "$CRT")")
        echo -e "  → Найден домен: ${GREEN}${CERT_DOMAIN}${RESET}"

        # --- генерим скрипт деплоя (самодетектирующийся, для cron) ---
        cat >/usr/local/bin/deploy-hy2-cert.sh <<'EOS'
#!/usr/bin/env bash
set -e
NODE="remnanode"
DEST="/var/lib/remnawave/configs/xray/ssl"

CRT=$(find /var/lib/docker/volumes -path '*acme*' -name '*.crt' 2>/dev/null | head -n1)
[ -z "$CRT" ] && { echo "$(date) cert source not found"; exit 1; }

DOMAIN=$(basename "$(dirname "$CRT")")
SRC=$(dirname "$CRT")
mkdir -p "$DEST"

# рестарт ноды только если серт реально изменился (первый запуск = копирует)
if ! cmp -s "$SRC/${DOMAIN}.crt" "$DEST/cert.pem"; then
    cp "$SRC/${DOMAIN}.crt" "$DEST/cert.pem"
    cp "$SRC/${DOMAIN}.key" "$DEST/cert.key"
    chmod 644 "$DEST/cert.pem"
    chmod 640 "$DEST/cert.key"
    docker restart "$NODE" >/dev/null 2>&1
    echo "$(date) cert updated ($DOMAIN), node restarted"
else
    echo "$(date) cert unchanged, skip"
fi
EOS
        chmod +x /usr/local/bin/deploy-hy2-cert.sh

        # --- первый деплой серта сейчас ---
        echo "  → Деплоим серт в ноду"
        /usr/local/bin/deploy-hy2-cert.sh >>/var/log/hy2-cert.log 2>&1

        # --- cron на автопродление (идемпотентно, без дублей) ---
        echo "  → Ставим cron (ежедневно 04:00)"
        ( crontab -l 2>/dev/null | grep -v 'deploy-hy2-cert.sh'; \
          echo "0 4 * * * /usr/local/bin/deploy-hy2-cert.sh >> /var/log/hy2-cert.log 2>&1" ) | crontab -

        # --- проверка проброса серта в контейнер ноды ---
        if docker inspect "$NODE" --format '{{range .Mounts}}{{.Destination}}{{"\n"}}{{end}}' 2>/dev/null \
            | grep -q "$DEST"; then
            MOUNT_STATUS="OK"
            echo -e "  ${GREEN}✔ Маунт серта в контейнер найден${RESET}"
        else
            MOUNT_STATUS="ОТСУТСТВУЕТ"
            echo -e "  ${RED}✘ ВНИМАНИЕ: $DEST не примонтирован в контейнер $NODE${RESET}"
            echo -e "  ${YELLOW}    hy2 не увидит серт. Добавь в /opt/remnanode/docker-compose.yml:${RESET}"
            echo -e "  ${YELLOW}      volumes:${RESET}"
            echo -e "  ${YELLOW}        - '${DEST}:${DEST}:ro'${RESET}"
            echo -e "  ${YELLOW}    затем: cd /opt/remnanode && docker compose up -d${RESET}"
        fi

        CERT_DONE="готово ($CERT_DOMAIN)"
        echo -e "  ${GREEN}✔ Сертификат для Hysteria2 настроен${RESET}"
    fi
    echo ""
else
    echo -e "${YELLOW}[7/10] Сертификат Hysteria2 — пропущен (выбрано N)${RESET}"
    echo ""
fi

#############################################
# FINAL
#############################################
echo -e "${BLUE}------------------------------------------------------${RESET}"
echo -e "    🟢 ${GREEN}Установка завершена успешно${RESET}"
echo -e "${BLUE}------------------------------------------------------${RESET}"
echo " Root пароль:              обновлён"
echo " SSH порт:                $NEW_SSH_PORT"
echo " Root вход:               разрешён (как ты просил)"
echo " Fail2Ban:                активен"
echo " sysctl:                  включён"
echo " Anti-scan iptables:      включён"
echo " Firewall (UFW):          отключён"
echo " Порты:                   НЕ трогались"
echo " Hysteria2 cert:          $CERT_DONE"
if [ "$DO_CERT" = "y" ] && [ -n "$MOUNT_STATUS" ]; then
echo " Маунт серта в контейнер: $MOUNT_STATUS"
fi
echo -e "${BLUE}------------------------------------------------------${RESET}"
echo " Новая команда подключения:"
echo -e "   ${GREEN}ssh -p $NEW_SSH_PORT root@<IP>${RESET}"
echo -e "${BLUE}------------------------------------------------------${RESET}"
echo ""
