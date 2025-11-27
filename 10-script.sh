#!/bin/bash
# ============================================================
# Script 10 — Atualizações e Backup
# ============================================================
# Funções:
#  1. Executa atualizações automáticas do sistema (dnf update -y)
#  2. Cria backups diários de:
#     - /var/www/html
#     - Bases de dados MariaDB
#  3. Comprime e envia para /backups ou servidor remoto via SCP
# ============================================================

# ---- Cores ----
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info()  { echo -e "${BLUE}--- $1 ---${NC}"; }
log_ok()    { echo -e "${GREEN}✔ $1${NC}"; }
log_warn()  { echo -e "${YELLOW}⚠ $1${NC}"; }
log_error() { echo -e "${RED}✖ $1${NC}"; }

# ============================================================
# 1. Validação inicial
# ============================================================

if [ "$EUID" -ne 0 ]; then
    log_error "Execute este script como root."
    exit 1
fi

BACKUP_DIR="/backups"
DATA=$(date +%F)
BACKUP_TEMP="/tmp/backup_${DATA}"
mkdir -p "$BACKUP_DIR" "$BACKUP_TEMP"

# ============================================================
# 2. Atualizações do sistema
# ============================================================

log_info "Atualizando pacotes do sistema..."
dnf clean all -q
dnf update -y
if [ $? -eq 0 ]; then
    log_ok "Sistema atualizado com sucesso."
else
    log_warn "Algumas atualizações falharam. Verifique manualmente."
fi

# ============================================================
# 3. Backup de /var/www/html
# ============================================================

log_info "Criando backup dos ficheiros web (/var/www/html)..."

if [ -d "/var/www/html" ]; then
    tar -czf "${BACKUP_TEMP}/html_${DATA}.tar.gz" /var/www/html 2>/dev/null
    log_ok "Backup de /var/www/html concluído."
else
    log_warn "/var/www/html não encontrado, a ignorar..."
fi

# ============================================================
# 4. Backup das bases de dados MariaDB
# ============================================================

log_info "Gerando backup das bases de dados MariaDB..."

if systemctl is-active mariadb &>/dev/null; then
    mkdir -p "${BACKUP_TEMP}/db"
    DB_USER="root"

    read -s -p "Digite a password do utilizador MariaDB ($DB_USER): " DB_PASS
    echo

    DATABASES=$(mysql -u"$DB_USER" -p"$DB_PASS" -e "SHOW DATABASES;" | grep -Ev "(Database|information_schema|performance_schema)")
    for DB in $DATABASES; do
        mysqldump -u"$DB_USER" -p"$DB_PASS" "$DB" > "${BACKUP_TEMP}/db/${DB}_${DATA}.sql"
    done

    tar -czf "${BACKUP_TEMP}/mariadb_${DATA}.tar.gz" -C "${BACKUP_TEMP}/db" .
    rm -rf "${BACKUP_TEMP}/db"
    log_ok "Backup das bases de dados concluído."
else
    log_warn "Serviço MariaDB não está ativo. Nenhum backup de BD criado."
fi

# ============================================================
# 5. Compressão final
# ============================================================

FINAL_FILE="${BACKUP_DIR}/backup_completo_${DATA}.tar.gz"

log_info "Comprimindo todos os backups em ${FINAL_FILE} ..."
tar -czf "$FINAL_FILE" -C "$BACKUP_TEMP" .
rm -rf "$BACKUP_TEMP"
log_ok "Backup completo gerado com sucesso."

# ============================================================
# 6. Envio opcional via SCP
# ============================================================

read -p "Deseja enviar o backup para um servidor remoto via SCP? (s/n): " RESPOSTA
if [[ "$RESPOSTA" =~ ^[Ss]$ ]]; then
    read -p "Endereço do servidor remoto (ex: user@host): " REMOTE_USERHOST
    read -p "Diretório remoto (ex: /home/user/backups): " REMOTE_DIR
    scp "$FINAL_FILE" "${REMOTE_USERHOST}:${REMOTE_DIR}"
    if [ $? -eq 0 ]; then
        log_ok "Backup enviado com sucesso para ${REMOTE_USERHOST}:${REMOTE_DIR}"
    else
        log_error "Falha ao enviar o backup via SCP."
    fi
else
    log_info "Backup armazenado localmente em ${BACKUP_DIR}"
fi

# ============================================================
# 7. Conclusão
# ============================================================

echo
log_ok "Processo concluído!"
echo -e "${GREEN}=====================================================${NC}"
echo -e "${GREEN}Atualizações e backups executados com sucesso!${NC}"
echo -e "${GREEN}=====================================================${NC}"
