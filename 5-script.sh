#!/bin/bash

# =================================================================
# Script 5: Configuração do Fail2ban (SSH e Apache)
# Objetivo: Instalar Fail2ban, definir política de bloqueio (maxretry=3, bantime=3600)
# e ativar os jails para proteção contra força bruta.
# =================================================================

# Cores
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

JAIL_CONF="/etc/fail2ban/jail.conf"
JAIL_LOCAL="/etc/fail2ban/jail.local"

log_info() {
    echo -e "${BLUE}--- $1 ---${NC}"
}

echo -e "${YELLOW}--- 🛠️ Iniciando a Instalação e Configuração do Fail2ban ---${NC}"

# 1. Instalar o Fail2ban
log_info "1. Instalação do Fail2ban"
echo ">> A instalar o pacote Fail2ban..."
sudo dnf install fail2ban -y

if [ $? -ne 0 ]; then
    echo -e "${RED}❌ ERRO: A instalação do Fail2ban falhou. A sair.${NC}"
    exit 1
fi
echo -e "${GREEN}✔️ Fail2ban instalado com sucesso.${NC}"
echo "--------------------------------------------------------"

# 2. Criar Ficheiro de Configuração Local
log_info "2. Criação do Ficheiro de Configuração Local (jail.local)"
if [ ! -f "$JAIL_LOCAL" ]; then
    echo ">> A criar o ficheiro $JAIL_LOCAL a partir do template..."
    sudo cp "$JAIL_CONF" "$JAIL_LOCAL"
    if [ $? -ne 0 ]; then
        echo -e "${RED}❌ ERRO: Falha ao copiar jail.conf. Verifique as permissões. A sair.${NC}"
        exit 1
    fi
    echo -e "${GREEN}✔️ Ficheiro $JAIL_LOCAL criado para personalização.${NC}"
else
    echo ">> Ficheiro $JAIL_LOCAL já existe. Apenas a aplicar alterações."
fi
echo "--------------------------------------------------------"

# 3. Ajustar Políticas de Bloqueio (maxretry e bantime)
log_info "3. Ajuste de Políticas Globais e Locais"

# Definições globais do relatório: maxretry = 3 e bantime = 3600 (1 hora)
echo ">> A definir maxretry=3 e bantime=3600 (1 hora) globalmente e para jails essenciais..."

# Usar 'sed' para substituir ou adicionar as configurações globais (DEFAULT section)
sudo sed -i 's/^bantime.*$/bantime = 3600/' "$JAIL_LOCAL"
sudo sed -i 's/^maxretry.*$/maxretry = 3/' "$JAIL_LOCAL"

# Ativar o jail SSHD (ssh/sftp)
echo ">> A ativar o jail [sshd]..."
# Garante que 'enabled = true' está presente no bloco [sshd]
sudo sed -i '/^\[sshd\]/,/^maxretry/ { /^enabled/!b; s/.*/enabled = true/; t; :a; /enabled/!{ /^\s*$/i enabled = true
 } }' "$JAIL_LOCAL"

# Ativar o jail Apache-Auth (Autenticação Web, ex: .htpasswd)
echo ">> A ativar o jail [apache-auth] (para proteção de painéis administrativos)..."
# Garante que 'enabled = true' está presente no bloco [apache-auth]
sudo sed -i '/^\[apache-auth\]/,/^maxretry/ { /^enabled/!b; s/.*/enabled = true/; t; :a; /enabled/!{ /^\s*$/i enabled = true
 } }' "$JAIL_LOCAL"

# Configuração de Email (Requer MTA, como Postfix, instalado)
echo ">> NOTA: A configuração de envio de email depende da instalação e configuração de um MTA."
echo ">> Para receber alertas, defina 'destemail' e 'mta' no $JAIL_LOCAL."
# Exemplo: sudo sed -i 's/^destemail.*$/destemail = seu.email@dominio.com/' "$JAIL_LOCAL"

echo -e "${GREEN}✔️ Políticas de segurança (maxretry=3, bantime=3600) e jails ativados.${NC}"
echo "--------------------------------------------------------"

# 4. Ativar e Iniciar o Serviço
log_info "4. Ativação e Início do Serviço"
echo ">> A iniciar e ativar o serviço Fail2ban..."
sudo systemctl enable --now fail2ban

if sudo systemctl is-active fail2ban &> /dev/null; then
    echo -e "${GREEN}🎉 Serviço Fail2ban ativo e a monitorizar os logs!${NC}"
    echo ">> Verifique o estado: sudo fail2ban-client status"
else
    echo -e "${RED}❌ ERRO: Falha ao iniciar o Fail2ban. Verifique os logs do systemd.${NC}"
fi

echo -e "\n${YELLOW}--- ✅ Script de Configuração do Fail2ban Concluído ---${NC}"
