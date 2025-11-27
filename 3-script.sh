#!/bin/bash
# =================================================================
# Script 3: Configuração de Rede e Firewall (NMCLI, Firewalld & IP Público)
# Objetivo: Configurar IP Estático, abrir portas essenciais no Firewalld
#           e testar a conectividade externa (Ping, Curl e DuckDNS opcional)
# Compatível com: CentOS 7, 8, 9, Stream e 10
# =================================================================

# --- Cores ---
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# --- Funções auxiliares ---
log_info() {
    echo -e "${BLUE}--- $1 ---${NC}"
}

check_command() {
    command -v "$1" >/dev/null 2>&1
}

# =================================================================
echo -e "${YELLOW}--- 🛠️ Iniciando a Configuração de Rede e Segurança ---${NC}"

# --- 1. Configuração de IP Estático ---
log_info "1. Configuração da Placa de Rede (IP Estático Opcional)"

read -p "Deseja configurar um endereço IP local estático para esta máquina? (s/n): " configure_ip

if [[ "$configure_ip" =~ ^[Ss]$ ]]; then
    echo -e "${BLUE}Interfaces de rede disponíveis:${NC}"
    nmcli device status | grep -E "ethernet|wifi"
    echo

    read -p "Digite o nome da interface de rede/conexão (ex: ens33): " NET_IFACE
    CONN_NAME="$NET_IFACE"

    CONN_EXISTS=$(nmcli connection show | grep -w "$CONN_NAME" | wc -l)

    if [ "$CONN_EXISTS" -eq 0 ]; then
        log_info "Conexão '$CONN_NAME' não encontrada. Criando nova..."
        sudo nmcli connection add type ethernet con-name "$CONN_NAME" ifname "$NET_IFACE"
    else
        log_info "Conexão '$CONN_NAME' encontrada. Modificando configuração existente."
    fi

    # --- Dados de rede ---
    read -p "Digite o IP do servidor (CIDR, ex: 192.168.1.10/24): " IP_CIDR
    read -p "Digite o gateway padrão (ex: 192.168.1.254): " GATEWAY
    read -p "Digite o servidor DNS principal (ex: 8.8.8.8): " DNS_SERVER

    # --- Aplicar configuração ---
    log_info "Aplicando configurações estáticas..."
    sudo nmcli connection modify "$CONN_NAME" ipv4.method manual ipv4.addresses "$IP_CIDR" ipv4.gateway "$GATEWAY" ipv4.dns "$DNS_SERVER" connection.autoconnect yes

    log_info "Reativando a conexão ${CONN_NAME}..."
    sudo nmcli connection up "$CONN_NAME"
    echo -e "${GREEN}✔️ IP estático configurado com sucesso.${NC}"
else
    log_info "A configuração de IP estático foi ignorada."
fi
echo "--------------------------------------------------------"

# =================================================================
# --- 2. Configuração do Firewalld ---
log_info "2. Configuração do Firewall (Firewalld)"

if ! systemctl is-active firewalld &>/dev/null; then
    echo ">> Firewalld não está ativo. Iniciando serviço..."
    sudo systemctl enable --now firewalld
    if [ $? -ne 0 ]; then
        echo -e "${RED}❌ ERRO: Falha ao iniciar o firewalld.${NC}"
        exit 1
    fi
fi

echo ">> Limpando e abrindo apenas as portas essenciais (22, 80, 443)..."
sudo firewall-cmd --permanent --remove-service=ssh >/dev/null 2>&1
sudo firewall-cmd --permanent --remove-service=http >/dev/null 2>&1
sudo firewall-cmd --permanent --remove-service=https >/dev/null 2>&1
sudo firewall-cmd --permanent --add-service=ssh
sudo firewall-cmd --permanent --add-service=http
sudo firewall-cmd --permanent --add-service=https
sudo firewall-cmd --reload

if [ $? -eq 0 ]; then
    echo -e "${GREEN}✔️ Regras do firewall aplicadas com sucesso.${NC}"
    echo "Regras ativas:"
    sudo firewall-cmd --list-services
else
    echo -e "${RED}❌ ERRO: Falha ao aplicar regras do firewall.${NC}"
fi
echo "--------------------------------------------------------"

# =================================================================
# --- 3. Verificação de IP Público e Conectividade ---
log_info "3. Verificação de Conectividade Externa (Ping e Curl)"

# --- IP público ---
echo ">> Obtendo IP público (via ifconfig.me)..."
PUBLIC_IP=$(curl -s ifconfig.me || curl -s ipinfo.io/ip)
if [ -n "$PUBLIC_IP" ]; then
    echo -e "IP Público Detetado: ${YELLOW}${PUBLIC_IP}${NC}"
else
    echo -e "${RED}⚠️ Não foi possível obter o IP público.${NC}"
fi

# --- Teste de conectividade ---
echo ">> Testando ping (google.com)..."
if ping -c 3 google.com &>/dev/null; then
    echo -e "${GREEN}✔️ Conectividade externa OK (Ping).${NC}"
else
    echo -e "${RED}❌ Falha no ping para a Internet.${NC}"
fi
echo "--------------------------------------------------------"

# =================================================================
# --- 4. Configuração opcional de Redirecionamento (DuckDNS) ---
log_info "4. Configuração do DuckDNS (Redirecionamento dinâmico opcional)"
CONFIG_FILE="automacao.conf"

read -p "Deseja configurar o DuckDNS e agendamento via cron? (s/n): " duck_response

if [[ "$duck_response" =~ ^[Ss]$ ]]; then
    if check_command curl && check_command crontab; then
        read -p "Digite o seu subdomínio DuckDNS (ex: sabormar): " DUCK_DOMAIN
        read -p "Digite o seu token DuckDNS: " DUCK_TOKEN

        # Salva as variáveis no ficheiro de configuração para serem usadas por outros scripts
        echo ">> Salvando informações em ${CONFIG_FILE}..."
        sed -i '/^DUCK_DOMAIN=/d' "$CONFIG_FILE" 2>/dev/null
        sed -i '/^DUCK_TOKEN=/d' "$CONFIG_FILE" 2>/dev/null
        echo "DUCK_DOMAIN=\"${DUCK_DOMAIN}\"" >> "$CONFIG_FILE"
        echo "DUCK_TOKEN=\"${DUCK_TOKEN}\"" >> "$CONFIG_FILE"
        echo ">> Criando diretório e script do DuckDNS..."
        sudo mkdir -p /root/duckdns
        sudo chmod 700 /root/duckdns

        echo -e "${GREEN}✔️ Domínio e token do DuckDNS foram guardados em ${CONFIG_FILE} para uso no script 7.${NC}"
        cat <<EOF | sudo tee /root/duckdns/duck.sh >/dev/null
#!/bin/bash
echo url="https://www.duckdns.org/update?domains=${DUCK_DOMAIN}&token=${DUCK_TOKEN}&ip=" | curl -k -o /root/duckdns/duck.log -K -
DATA=\$(date)
echo -e "\n\${DATA} OK" >> /root/duckdns/duck.log
EOF

        sudo chmod 700 /root/duckdns/duck.sh

        (sudo crontab -l 2>/dev/null; echo "*/5 * * * * /root/duckdns/duck.sh >/dev/null 2>&1") | sudo crontab -
        echo -e "${GREEN}✔️ DuckDNS configurado e agendado com sucesso para o domínio '${DUCK_DOMAIN}'.${NC}"
    else
        echo -e "${RED}❌ curl ou crontab não estão instalados.${NC}"
    fi
else
    echo "DuckDNS ignorado."
fi

echo -e "\n${YELLOW}--- ✅ Configuração de Rede e Firewall concluída ---${NC}"
# =================================================================