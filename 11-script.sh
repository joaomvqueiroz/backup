#!/bin/bash

# ======================================================
# Script de Monitorização Interativo - CentOS 9/10
# ======================================================

# ------------------------------------------------------
# Pergunta interativa pelo email
# ------------------------------------------------------
read -p "Digite o email para receber alertas: " EMAIL_ALERTA
if [ -z "$EMAIL_ALERTA" ]; then
    echo "Erro: Nenhum email fornecido. Encerrando script."
    exit 1
fi

# ------------------------------------------------------
# Pergunta quais serviços monitorar
# ------------------------------------------------------
echo "Quais serviços deseja monitorar?"
echo "1) Apache"
echo "2) MariaDB"
echo "3) PHP-FPM"
echo "4) Todos os serviços acima"
read -p "Escolha uma opção (1-4): " OPCAO_SERVICOS

SERVICOS=()
LOGS=()

case "$OPCAO_SERVICOS" in
    1)
        SERVICOS=("httpd")
        LOGS=("/var/log/httpd/*.log")
        ;;
    2)
        SERVICOS=("mariadb")
        LOGS=("/var/log/mariadb/mariadb.log")
        ;;
    3)
        SERVICOS=("php-fpm")
        LOGS=("/var/log/php-fpm/error.log")
        ;;
    4)
        SERVICOS=("httpd" "mariadb" "php-fpm")
        LOGS=("/var/log/httpd/*.log" "/var/log/secure" "/var/log/mariadb/mariadb.log" "/var/log/php-fpm/error.log")
        ;;
    *)
        echo "Opção inválida. Encerrando."
        exit 1
        ;;
esac

PATTERN="error"
LOG_ALERTS="/var/log/monitor_alerts.log"

echo "Iniciando monitorização em $(date '+%d %b %Y %T %Z')..."

# ------------------------------------------------------
# Função de envio de alerta por email
# ------------------------------------------------------
enviar_alerta() {
    local MSG="$1"
    local SUBJECT="$2"

    if ! command -v sendmail &> /dev/null; then
        echo "Nenhum MTA ativo. Instalando postfix..."
        yum install -y postfix
        systemctl enable --now postfix
    fi

    echo "$MSG" | sendmail -t "$EMAIL_ALERTA" -s "$SUBJECT"
   echo "$(date '+%Y-%m-%d %H:%M:%S') - $SUBJECT - $MSG" >> "$LOG_ALERTS"
}

# ------------------------------------------------------
# Função de monitorização de logs
# ------------------------------------------------------
monitorar_logs() {
    local ARQUIVOS="$1"
    local SERVICO="$2"

    for LOG in $ARQUIVOS; do
        if [ -f "$LOG" ]; then
            grep -i "$PATTERN" "$LOG" | while read -r LINHA; do
                if ! grep -Fq "$LINHA" "$LOG_ALERTS" 2>/dev/null; then
                    MSG="Alerta de segurança: Padrão '$PATTERN' encontrado em $LOG -> $LINHA"
                    enviar_alerta "$MSG" "Alerta $SERVICO"
                fi
            done
        fi
    done
}

# ------------------------------------------------------
# Monitorização principal
# ------------------------------------------------------
for i in "${!SERVICOS[@]}"; do
    monitorar_logs "${LOGS[$i]}" "${SERVICOS[$i]}"
done

# ------------------------------------------------------
# Verificação de serviços ativos
# ------------------------------------------------------
verificar_servico() {
    local SERVICO="$1"
    if ! systemctl is-active --quiet "$SERVICO"; then
        MSG="Alerta: Serviço $SERVICO não está ativo em $(date)"
        enviar_alerta "$MSG" "Falha Serviço: $SERVICO"
    fi
}

for SVC in "${SERVICOS[@]}"; do
    verificar_servico "$SVC"
done

# ------------------------------------------------------
# Sincronização horária via Chrony
# ------------------------------------------------------
if command -v chronyd &> /dev/null; then
    echo "Sincronizando horário via Chrony..."
    chronyc -a makestep
    systemctl enable --now chronyd
else
    echo "Pacote chrony não encontrado. Instalando chrony..."
    yum install -y chrony
    chronyc -a makestep
    systemctl enable --now chronyd
fi

# ------------------------------------------------------
# Configuração básica de logrotate
# ------------------------------------------------------
if [ ! -f /etc/logrotate.d/lamp ]; then
    echo "Criando configuração de logrotate para Apache e PHP..."
    cat << EOF > /etc/logrotate.d/lamp
/var/log/httpd/*.log {
    daily
    rotate 7
    compress
    missingok
    notifempty
    postrotate
        /bin/systemctl reload httpd > /dev/null 2>/dev/null || true
    endscript
}

/var/log/php-fpm/error.log {
    weekly
    rotate 4
    compress
    missingok
    notifempty
    postrotate
        /bin/systemctl reload php-fpm > /dev/null 2>/dev/null || true
    endscript
}
EOF
fi

echo "Monitorização concluída em $(date '+%d %b %Y %T %Z')"
