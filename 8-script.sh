#!/bin/bash

# ============================================================
# Script 8 — Tuning do MariaDB
# Objetivo: Ajustar parâmetros de desempenho no /etc/my.cnf
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
# 1. Verificação de dependências e permissões
# ============================================================

if [ "$EUID" -ne 0 ]; then
    log_error "Execute este script como root."
    exit 1
fi

if ! command -v mysql &>/dev/null; then
    log_error "O MariaDB não está instalado. Instale-o antes de continuar."
    exit 1
fi

# ============================================================
# 2. Calcular parâmetros de tuning
# ============================================================

TOTAL_RAM=$(free -b | awk '/Mem:/ {print $2}')
BUFFER_POOL_SIZE=$(awk -v total="$TOTAL_RAM" 'BEGIN {printf "%d", total * 0.60}')
BUFFER_POOL_SIZE_MB=$((BUFFER_POOL_SIZE / 1024 / 1024))

log_info "Memória total detectada: $(awk "BEGIN {print $TOTAL_RAM/1024/1024}") MB"
log_info "Definindo innodb_buffer_pool_size = ${BUFFER_POOL_SIZE_MB}M"

# ============================================================
# 3. Fazer backup do /etc/my.cnf
# ============================================================

if [ -f /etc/my.cnf ]; then
    BACKUP_FILE="/etc/my.cnf.bak_$(date +%F_%H-%M-%S)"
    cp /etc/my.cnf "$BACKUP_FILE"
    log_ok "Backup criado: $BACKUP_FILE"
else
    log_warn "/etc/my.cnf não encontrado. Será criado do zero."
fi

# ============================================================
# 4. Inserir/Atualizar parâmetros de tuning
# ============================================================

log_info "Aplicando parâmetros de tuning no /etc/my.cnf ..."

# Remove linhas antigas com os mesmos parâmetros
sed -i '/innodb_buffer_pool_size/d' /etc/my.cnf 2>/dev/null
sed -i '/innodb_log_file_size/d' /etc/my.cnf 2>/dev/null
sed -i '/max_connections/d' /etc/my.cnf 2>/dev/null
sed -i '/query_cache_size/d' /etc/my.cnf 2>/dev/null

# Garante que a seção [mysqld] exista
grep -q "^\[mysqld\]" /etc/my.cnf || echo -e "\n[mysqld]" >> /etc/my.cnf

# Adiciona as novas configurações
cat <<EOF >> /etc/my.cnf

# ===== Ajustes automáticos de desempenho =====
innodb_buffer_pool_size = ${BUFFER_POOL_SIZE_MB}M
innodb_log_file_size = 256M
max_connections = 100
query_cache_size = 32M
# =============================================
EOF

log_ok "Parâmetros aplicados com sucesso ao /etc/my.cnf."

# ============================================================
# 5. Reiniciar o serviço MariaDB
# ============================================================

log_info "Reiniciando o serviço MariaDB..."
systemctl restart mariadb || systemctl restart mysql

if systemctl is-active --quiet mariadb || systemctl is-active --quiet mysql; then
    log_ok "MariaDB reiniciado com sucesso."
else
    log_error "Falha ao reiniciar o MariaDB. Verifique o log do sistema."
    exit 1
fi

# ============================================================
# 6. Validação do desempenho
# ============================================================

log_info "Validando parâmetros aplicados no servidor MariaDB..."

mysql -e "SHOW VARIABLES LIKE 'innodb_buffer_pool_size';"
mysql -e "SHOW VARIABLES LIKE 'innodb_log_file_size';"
mysql -e "SHOW VARIABLES LIKE 'max_connections';"
mysql -e "SHOW VARIABLES LIKE 'query_cache_size';"

echo
log_ok "Tuning do MariaDB concluído com sucesso!"
echo -e "${GREEN}=====================================================${NC}"
echo -e "${GREEN}Parâmetros atualizados e serviço validado com sucesso.${NC}"
echo -e "${GREEN}=====================================================${NC}"
