#!/usr/bin/env bash
set -euo pipefail

if [ "$(id -u)" -ne 0 ]; then
    echo "ERRO: execute este script como root (ex.: sudo ./scripts/deploy.sh)." >&2
    exit 1
fi

APP_NAME="ufla-shop"
APP_USER="ufla-shop"
APP_DIR="/opt/ufla-shop"
ENV_FILE="/etc/ufla-shop.env"
ENV_EXAMPLE="/etc/ufla-shop.env.example"
BACKUP_DIR="/var/backups/ufla-shop"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

echo "==> Instalando dependências do sistema..."

apt-get update
apt-get install -y \
    curl \
    python3-venv \
    postgresql \
    redis-server \
    nginx \
    openssl \
    rsync

echo "==> Verificando usuário $APP_USER..."

if ! id "$APP_USER" >/dev/null 2>&1; then
    useradd \
        --system \
        --user-group \
        --home "$APP_DIR" \
        --shell /usr/sbin/nologin \
        "$APP_USER"
fi

echo "==> Preparando diretório da aplicação..."

mkdir -p "$APP_DIR"

rsync -a \
    --delete \
    --exclude ".git" \
    --exclude ".venv" \
    "$REPO_DIR/" \
    "$APP_DIR/"

chown -R "$APP_USER:$APP_USER" "$APP_DIR"

echo "==> Criando ambiente virtual..."

if [ ! -d "$APP_DIR/.venv" ]; then
    python3 -m venv "$APP_DIR/.venv"
fi

"$APP_DIR/.venv/bin/pip" install --upgrade pip
"$APP_DIR/.venv/bin/pip" install -r "$APP_DIR/requirements.txt"

chown -R "$APP_USER:$APP_USER" "$APP_DIR/.venv"

echo "==> Configurando variáveis de ambiente..."

install -m 644 \
    "$REPO_DIR/ufla-shop.env.example" \
    "$ENV_EXAMPLE"

if [ ! -f "$ENV_FILE" ]; then
    if [ ! -f "$ENV_EXAMPLE" ]; then
        echo "ERRO: $ENV_EXAMPLE não existe."
        exit 1
    fi

    cp "$ENV_EXAMPLE" "$ENV_FILE"
    chmod 600 "$ENV_FILE"

    echo "Arquivo $ENV_FILE criado."
    echo "Revise as credenciais antes de continuar."
fi

echo "==> Preparando diretório de backups..."

mkdir -p "$BACKUP_DIR"
chown postgres:postgres "$BACKUP_DIR"
chmod 750 "$BACKUP_DIR"

echo "==> Instalando units do systemd..."

install -m 644 \
    "$REPO_DIR/systemd/ufla-shop.service" \
    /etc/systemd/system/ufla-shop.service

install -m 644 \
    "$REPO_DIR/systemd/ufla-shop-backup.service" \
    /etc/systemd/system/ufla-shop-backup.service

install -m 644 \
    "$REPO_DIR/systemd/ufla-shop-backup.timer" \
    /etc/systemd/system/ufla-shop-backup.timer

chmod +x "$APP_DIR/scripts/backup.sh"

systemctl daemon-reload

systemctl enable --now postgresql
systemctl enable --now redis-server

echo "==> Iniciando aplicação..."

systemctl enable ufla-shop
systemctl restart ufla-shop

echo "==> Configurando Nginx..."

install -m 644 \
    "$REPO_DIR/nginx/loja.conf" \
    /etc/nginx/sites-available/loja.conf

ln -sfn \
    /etc/nginx/sites-available/loja.conf \
    /etc/nginx/sites-enabled/loja.conf

rm -f /etc/nginx/sites-enabled/default

echo "==> Gerando certificado TLS..."

mkdir -p /etc/nginx/ssl

if [ ! -f /etc/nginx/ssl/ufla-shop.crt ] ||
   [ ! -f /etc/nginx/ssl/ufla-shop.key ]; then

    openssl req \
        -x509 \
        -nodes \
        -days 365 \
        -newkey rsa:2048 \
        -keyout /etc/nginx/ssl/ufla-shop.key \
        -out /etc/nginx/ssl/ufla-shop.crt \
        -subj "/CN=localhost"
fi

chmod 600 /etc/nginx/ssl/ufla-shop.key
chmod 644 /etc/nginx/ssl/ufla-shop.crt

echo "==> Validando configuração do Nginx..."

nginx -t

systemctl enable nginx
systemctl restart nginx

echo "==> Habilitando backup diário..."

systemctl enable --now ufla-shop-backup.timer

echo "==> Executando healthcheck..."

for attempt in $(seq 1 10); do
    if curl -fsS \
        --max-time 2 \
        -o /dev/null \
        http://localhost:8000/ready; then

        echo "Healthcheck OK."
        exit 0
    fi

    echo "Healthcheck falhou (tentativa $attempt/10)."

    if [ "$attempt" -lt 10 ]; then
        sleep 1
    fi
done

echo "ERRO: aplicação não respondeu 200 em /ready."

systemctl status ufla-shop --no-pager || true

exit 1