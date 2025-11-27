#!/bin/bash

# ============================================================
# Script 9 — Ajustes PHP
# Objetivo: Aplicar configurações de desempenho e ambiente no /etc/php.ini
# ============================================================

# Cores
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() {
    echo -e "${BLUE}--- $1 ---${NC}"
}
log_ok() {
    echo -e "${GREEN}✔ $1${NC}"
}
log_warn() {
    echo -e "${YELLOW}⚠ $1${NC}"
}
log_error() {
    echo -e "${RED}✖ $1${NC}"
}

# ============================================================
# 1. Verificação de permissões e dependências
# ============================================================

if [ "$EUID" -ne 0 ]; then
    log_error "Execute este script como root."
    exit 1
fi

PHP_INI="/etc/php.ini"

if [ ! -f "$PHP_INI" ]; then
    log_error "Arquivo $PHP_INI não encontrado. Verifique a instalação do PHP."
    exit 1
fi

# ============================================================
# 2. Fazer backup do php.ini
# ============================================================

BACKUP_FILE="${PHP_INI}.bak_$(date +%F_%H-%M-%S)"
cp "$PHP_INI" "$BACKUP_FILE"
log_ok "Backup criado: $BACKUP_FILE"

# ============================================================
# 3. Aplicar as configurações solicitadas
# ============================================================

log_info "Aplicando configurações no $PHP_INI ..."

# Remove linhas antigas e substitui por novas configurações
sed -i '/^date.timezone/d' "$PHP_INI"
sed -i '/^upload_max_filesize/d' "$PHP_INI"
sed -i '/^post_max_size/d' "$PHP_INI"
sed -i '/^memory_limit/d' "$PHP_INI"

cat <<EOF >> "$PHP_INI"

; ===== Ajustes automáticos de configuração =====
date.timezone = Europe/Lisbon
upload_max_filesize = 20M
post_max_size = 25M
memory_limit = 256M
; ===============================================
EOF

log_ok "Configurações aplicadas com sucesso."

# ============================================================
# 4. Reiniciar o serviço PHP (detecção automática)
# ============================================================

log_info "Reiniciando o serviço PHP..."

if systemctl list-units --type=service | grep -q "php-fpm"; then
    systemctl restart php-fpm && log_ok "Serviço php-fpm reiniciado."
elif systemctl list-units --type=service | grep -q "apache2"; then
    systemctl restart apache2 && log_ok "Serviço Apache reiniciado."
elif systemctl list-units --type=service | grep -q "httpd"; then
    systemctl restart httpd && log_ok "Serviço httpd reiniciado."
else
    log_warn "Nenhum serviço PHP-FPM ou Apache detectado. Reinicie manualmente se necessário."
fi

# ============================================================
# 5. Validação das configurações
# ============================================================

log_info "Validando configurações aplicadas..."
grep -E "date.timezone|upload_max_filesize|post_max_size|memory_limit" "$PHP_INI"

echo
log_ok "Ajustes PHP concluídos com sucesso!"
echo -e "${GREEN}=====================================================${NC}"
echo -e "${GREEN}Parâmetros atualizados e serviço verificado.${NC}"
echo -e "${GREEN}=====================================================${NC}"
