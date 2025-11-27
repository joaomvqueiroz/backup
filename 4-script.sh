#!/bin/bash

# =================================================================
# Script 4: SELinux e Políticas de Segurança (Auditoria e Relatório)
# Objetivo: Confirmar SELinux em enforcing, gerar relatório de alertas
# de auditoria e criar um log centralizado.
# =================================================================

# Cores
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

SELINUX_REPORT_FILE="/var/log/seguranca.log"
AUDIT_LOG="/var/log/audit/audit.log"

log_info() {
    echo -e "${BLUE}--- $1 ---${NC}"
}

echo -e "${YELLOW}--- 🛠️ Iniciando a Auditoria de SELinux e Segurança ---${NC}"

# --- 1. Confirmação do Estado do SELinux ---
log_info "1. Confirmação do Modo SELinux"

CURRENT_SELINUX_MODE=$(getenforce)
echo ">> Estado atual do SELinux: ${YELLOW}$CURRENT_SELINUX_MODE${NC}"

if [ "$CURRENT_SELINUX_MODE" == "Enforcing" ]; then
    echo -e "${GREEN}✔️ SELinux está em modo 'Enforcing'.${NC}"
else
    echo -e "${RED}⚠️ AVISO: SELinux NÃO está em modo 'Enforcing'. Ajuste via 'sudo nano /etc/selinux/config' e reinicie.${NC}"
fi
echo "--------------------------------------------------------"

# --- 2. Geração de Relatórios de Auditoria (sealert) ---
log_info "2. Geração de Relatórios de Alertas de Auditoria (sealert)"

# Verifica se o auditd está ativo para ter certeza de que o ficheiro de log existe
if ! sudo systemctl is-active auditd &> /dev/null; then
    echo -e "${YELLOW}>> Serviço 'auditd' inativo. Tentando iniciar para gerar o relatório.${NC}"
    sudo systemctl enable --now auditd
    sleep 2
fi

if [ -f "$AUDIT_LOG" ]; then
    echo ">> A gerar relatório de alertas de SELinux a partir de $AUDIT_LOG..."
    
    # O comando sealert pode levar algum tempo; limitamos a saída para o terminal.
    # O output completo é direcionado para o log centralizado na próxima seção.
    SELINUX_ALERT_OUTPUT=$(sudo sealert -a "$AUDIT_LOG" | head -n 10)
    
    if [ -n "$SELINUX_ALERT_OUTPUT" ]; then
        echo -e "${YELLOW}Primeiros alertas de SELinux encontrados (saída completa no log):${NC}"
        echo "$SELINUX_ALERT_OUTPUT"
        echo -e "${GREEN}✔️ Relatório de alertas gerado com sucesso.${NC}"
    else
        echo -e "${GREEN}✔️ Nenhum alerta recente de SELinux encontrado em $AUDIT_LOG.${NC}"
    fi
else
    echo -e "${RED}❌ ERRO: Ficheiro de log de auditoria $AUDIT_LOG não encontrado. Instale e inicie o 'auditd'.${NC}"
fi
echo "--------------------------------------------------------"

# --- 3. Criação de Log Centralizado (/var/log/seguranca.log) ---
log_info "3. Criação e Preenchimento de Log Centralizado"

TIMESTAMP=$(date "+%Y-%m-%d %H:%M:%S")

echo ">> A criar/atualizar o log centralizado em $SELINUX_REPORT_FILE..."

# Cria o ficheiro de log se não existir e adiciona um cabeçalho
if [ ! -f "$SELINUX_REPORT_FILE" ]; then
    echo "============================================================" | sudo tee "$SELINUX_REPORT_FILE" > /dev/null
    echo "LOG DE SEGURANÇA E AUDITORIA - $TIMESTAMP" | sudo tee -a "$SELINUX_REPORT_FILE" > /dev/null
    echo "============================================================" | sudo tee -a "$SELINUX_REPORT_FILE" > /dev/null
else
    echo -e "\n\n=== RELATÓRIO DE SEGURANÇA EXECUTADO EM $TIMESTAMP ===" | sudo tee -a "$SELINUX_REPORT_FILE" > /dev/null
fi

# Adiciona o estado do SELinux
echo "Estado do SELinux: $CURRENT_SELINUX_MODE" | sudo tee -a "$SELINUX_REPORT_FILE" > /dev/null

# Adiciona o relatório completo de alertas de SELinux (se o ficheiro de audit existir)
if [ -f "$AUDIT_LOG" ]; then
    echo "--- Relatório sealert Completo ---" | sudo tee -a "$SELINUX_REPORT_FILE" > /dev/null
    sudo sealert -a "$AUDIT_LOG" | sudo tee -a "$SELINUX_REPORT_FILE" > /dev/null
    echo "--- Fim do Relatório sealert ---" | sudo tee -a "$SELINUX_REPORT_FILE" > /dev/null
fi

echo -e "${GREEN}✔️ Log de segurança centralizado atualizado em $SELINUX_REPORT_FILE.${NC}"
echo "--------------------------------------------------------"

echo -e "\n${YELLOW}--- ✅ Script de Auditoria SELinux Concluído ---${NC}"
