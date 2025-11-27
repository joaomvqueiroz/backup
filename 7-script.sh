#!/bin/bash
# ===================================================================
# Script 7: Tuning do Apache (Compressão, Timeouts e MPM)
# Objetivo: Aplicar ajustes de performance baseados no hardware (RAM/CPU)
# e configurar o MPM Event.
# ===================================================================

# Cores para feedback visual
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

CONF_FILE="/etc/httpd/conf/httpd.conf"
MODS_DIR="/etc/httpd/conf.modules.d"
MPM_CONF="/etc/httpd/conf.modules.d/00-mpm.conf"

log_info() {
    echo -e "${BLUE}--- $1 ---${NC}"
}

echo -e "${YELLOW}--- 🛠️ Iniciando o Tuning Dinâmico do Apache HTTPD ---${NC}"

# 1. Verificações e Instalação do Apache
if [[ $EUID -ne 0 ]]; then
    echo -e "${RED}⚠️ Este script deve ser executado como root!${NC}"
    exit 1
fi

if ! command -v httpd &> /dev/null; then
    echo "❌ Apache (httpd) não está instalado. Instalando..."
    sudo dnf install -y httpd
    if [ $? -ne 0 ]; then
        echo -e "${RED}❌ ERRO ao instalar o Apache. A sair.${NC}"
        exit 1
    fi
fi

# 2. Coleta informações de hardware e cálculo de MaxRequestWorkers
TOTAL_RAM_MB=$(free -m | awk '/^Mem:/{print $2}')
CPU_CORES=$(nproc)

echo -e "${BLUE}🧮 Detectado: ${TOTAL_RAM_MB}MB RAM, ${CPU_CORES} CPU cores.${NC}"

# Define valores de tuning (ajustado para o ambiente de 2GB RAM / 2vCPUs)
if [[ $TOTAL_RAM_MB -lt 2000 ]]; then
    # Valor de referência do relatório para hardware limitado
    MAX_WORKERS=150 
else
    # Lógica de cálculo se houver mais RAM disponível
    MEM_PER_CHILD=50
    MAX_WORKERS=$((TOTAL_RAM_MB / MEM_PER_CHILD))
    if [[ $MAX_WORKERS -gt 512 ]]; then MAX_WORKERS=512; fi 
fi

START_SERVERS=2      
THREADS_PER_CHILD=25 
SERVER_LIMIT=$MAX_WORKERS

echo -e "${BLUE}🧩 MaxRequestWorkers (total de threads) = ${MAX_WORKERS}${NC}"


# 3. Habilita módulos e desativa MPMs conflitantes
log_info "3. Ativação de Módulos e Seleção do MPM Event"

# Habilita módulos
sudo sed -i 's/^#\(LoadModule deflate_module modules\/mod_deflate.so\)/\1/' "$MODS_DIR"/*.conf
sudo sed -i 's/^#\(LoadModule headers_module modules\/mod_headers.so\)/\1/' "$MODS_DIR"/*.conf

# Garante que o MPM Event é o único ativado (Desativa prefork/worker)
sudo sed -i 's/^LoadModule mpm_prefork_module/#&/' "$MODS_DIR"/*.conf
sudo sed -i 's/^LoadModule mpm_worker_module/#&/' "$MODS_DIR"/*.conf
sudo sed -i 's/^#LoadModule mpm_event_module/LoadModule mpm_event_module/' "$MODS_DIR"/*.conf
echo -e "${GREEN}✔️ Módulos ativados e MPM Event selecionado.${NC}"


# 4. Aplica ajustes no httpd.conf (KeepAlive, Timeouts, Deflate)
log_info "4. Configuração de KeepAlive, Timeouts e Deflate"

# Remove parâmetros antigos e blocos de deflate antigos
sudo sed -i '/^Timeout/d' "$CONF_FILE"
sudo sed -i '/^KeepAlive/d' "$CONF_FILE"
sudo sed -i '/^MaxKeepAliveRequests/d' "$CONF_FILE"
sudo sed -i '/^KeepAliveTimeout/d' "$CONF_FILE"
sudo sed -i '/^<IfModule mod_deflate.c>/,/^<\/IfModule>/d' "$CONF_FILE" 

cat <<EOF | sudo tee -a "$CONF_FILE" > /dev/null

# ===================================================================
# 🔧 Tuning de performance Apache - $(date)
# ===================================================================

# Configurações Gerais (Capítulo 6.3.2)
Timeout 60           
KeepAlive On         
KeepAliveTimeout 5   
MaxKeepAliveRequests 100

# Compressão GZIP (mod_deflate - Capítulo 6.3.1)
<IfModule mod_deflate.c>
    AddOutputFilterByType DEFLATE text/plain
    AddOutputFilterByType DEFLATE text/html
    AddOutputFilterByType DEFLATE text/xml
    AddOutputFilterByType DEFLATE text/css
    AddOutputFilterByType DEFLATE application/javascript
    DeflateCompressionLevel 6
    Header append Vary User-Agent env=!dont-vary
</IfModule>
EOF


# 5. Configuração do MPM Event no conf.modules.d
log_info "5. Ajuste dos Parâmetros do MPM Event"

sudo sed -i '/<IfModule mpm_event_module>/,/<\/IfModule>/ {
    /StartServers/s/.*/    StartServers '"$START_SERVERS"'/
    /MinSpareThreads/s/.*/    MinSpareThreads 25/
    /MaxSpareThreads/s/.*/    MaxSpareThreads 75/
    /ThreadLimit/s/.*/    ThreadLimit 64/
    /ThreadsPerChild/s/.*/    ThreadsPerChild '"$THREADS_PER_CHILD"'/
    /MaxRequestWorkers/s/.*/    MaxRequestWorkers '"$MAX_WORKERS"'/
}' "$MPM_CONF"
echo -e "${GREEN}✔️ Parâmetros do MPM Event ajustados.${NC}"

# ===================================================================
# 6. Configuração de Domínio e SSL/TLS (Let's Encrypt)
# Lógica movida do script 20 para unificar a configuração do Apache.
# ===================================================================
log_info "6. Configuração de Domínio, DuckDNS e SSL/TLS (Let's Encrypt)"

read -p "Deseja configurar um domínio com DuckDNS e SSL/TLS da Let's Encrypt agora? (s/n): " CONFIGURE_SSL

if [[ "$CONFIGURE_SSL" =~ ^[Ss]$ ]]; then

    CONFIG_FILE="automacao.conf"

    # --- 6.1. Solicitar dados do usuário (Lógica do script 20) ---
    # Verifica se o ficheiro de configuração existe e carrega as variáveis
    if [ -f "$CONFIG_FILE" ]; then
        log_info "A carregar configurações de DuckDNS de $CONFIG_FILE..."
        source "$CONFIG_FILE"
    fi

    # Se as variáveis não foram carregadas, pergunta ao utilizador
    [ -z "$DUCK_DOMAIN" ] && read -p "Digite o seu subdomínio DuckDNS (ex: sabormar): " DUCK_DOMAIN
    [ -z "$DUCK_TOKEN" ] && read -p "Digite o seu token DuckDNS: " DUCK_TOKEN
    read -p "Digite um e-mail para Let’s Encrypt/Apache: " SERVER_EMAIL


    APACHE_DOMAIN="${DUCK_DOMAIN}.duckdns.org"
    DUCK_DIR="/root/duckdns"
    DUCK_SCRIPT="${DUCK_DIR}/duck.sh"
    DUCK_LOG="${DUCK_DIR}/duck.log"

    echo -e "${GREEN}✅ Domínio configurado: ${APACHE_DOMAIN}${NC}"
    echo "--------------------------------------------------------"

    # --- 6.2. Detectar IPs públicos (Lógica do script 20) ---
    log_info "6.2. Detectando IPs públicos"
    IPV4=$(curl -4 -s ifconfig.me)
    IPV6=$(curl -6 -s ifconfig.co || echo "")

    echo "IPv4 detectado: $IPV4"
    if [ -n "$IPV6" ]; then
        echo "IPv6 detectado: $IPV6"
    else
        echo "⚠️ Nenhum IPv6 detectado"
    fi
    echo "--------------------------------------------------------"

    # --- 6.3. Configuração VirtualHosts temporários (Lógica do script 20) ---
    log_info "6.3. Criando VirtualHosts Apache temporários"

    HTTP_CONF="/etc/httpd/conf.d/vhost_http_${DUCK_DOMAIN}.conf"
    SSL_CONF="/etc/httpd/conf.d/vhost_ssl_${DUCK_DOMAIN}.conf"
    TEMP_CERT_DIR="/etc/pki/tls"

    sudo mkdir -p "${TEMP_CERT_DIR}/certs" "${TEMP_CERT_DIR}/private"

    # Certificado temporário self-signed
    sudo openssl req -x509 -nodes -days 1 \
      -newkey rsa:2048 \
      -keyout "${TEMP_CERT_DIR}/private/localhost.key" \
      -out "${TEMP_CERT_DIR}/certs/localhost.crt" \
      -subj "/C=PT/ST=Lisboa/L=Lisboa/O=${DUCK_DOMAIN}/OU=IT/CN=localhost"

    # VirtualHost HTTP
    sudo bash -c "cat > ${HTTP_CONF}" <<EOF_HTTP
<VirtualHost *:80>
    ServerName ${APACHE_DOMAIN}
    DocumentRoot /var/www/html
    Redirect permanent / https://${APACHE_DOMAIN}/
</VirtualHost>
EOF_HTTP

    # VirtualHost HTTPS temporário
    sudo bash -c "cat > ${SSL_CONF}" <<EOF_SSL
<VirtualHost *:443>
    ServerName ${APACHE_DOMAIN}
    ServerAdmin ${SERVER_EMAIL}
    DocumentRoot "/var/www/html"

    ErrorLog logs/${DUCK_DOMAIN}_ssl_error.log
    CustomLog logs/${DUCK_DOMAIN}_ssl_access.log combined

    <Directory "/var/www/html">
        Options Indexes FollowSymLinks
        AllowOverride All
        Require all granted
    </Directory>

    SSLEngine on
    SSLCertificateFile ${TEMP_CERT_DIR}/certs/localhost.crt
    SSLCertificateKeyFile ${TEMP_CERT_DIR}/private/localhost.key

    SSLProtocol all -SSLv2 -SSLv3
    SSLCipherSuite HIGH:!aNULL:!MD5
    Header always set Strict-Transport-Security "max-age=63072000; includeSubDomains; preload"
</VirtualHost>
EOF_SSL

    echo -e "${GREEN}✔️ VirtualHosts temporários criados${NC}"
    echo "--------------------------------------------------------"

    # --- 6.4. Instalar Certbot e configurar Firewall (Lógica do script 20) ---
    log_info "6.4. Instalando Certbot e ajustando Firewall"
    sudo dnf install certbot python3-certbot-apache -y # httpd e mod_ssl já devem estar instalados
    sudo firewall-cmd --permanent --add-service=http --add-service=https
    sudo firewall-cmd --reload
    echo -e "${GREEN}✔️ Certbot instalado e firewall configurado.${NC}"
    echo "--------------------------------------------------------"

    # --- 6.5. Configuração do DuckDNS (Lógica do script 20) ---
    log_info "6.5. Configurando o cliente DuckDNS"
    sudo mkdir -p "$DUCK_DIR" && sudo chmod 700 "$DUCK_DIR"

    sudo bash -c "cat > ${DUCK_SCRIPT}" <<EOF
#!/bin/bash
URL="https://www.duckdns.org/update?domains=${DUCK_DOMAIN}&token=${DUCK_TOKEN}&ip=${IPV4}"
EOF

    if [ -n "$IPV6" ]; then
        sudo bash -c "echo 'URL=\"\${URL}&ipv6=${IPV6}\"' >> ${DUCK_SCRIPT}"
    fi

    sudo bash -c "cat >> ${DUCK_SCRIPT}" <<'EOF2'
echo url="${URL}" | curl -k -o /root/duckdns/duck.log -K -
DATE=$(date)
echo "$DATE - Atualização executada" >> /root/duckdns/duck.log
EOF2

    sudo chmod 700 "$DUCK_SCRIPT"
    (sudo crontab -l 2>/dev/null; echo "*/5 * * * * ${DUCK_SCRIPT} >/dev/null 2>&1") | sudo crontab -

    echo ">> A executar a primeira atualização do DuckDNS..."
    sudo bash "$DUCK_SCRIPT"

    if grep -q "OK" "$DUCK_LOG" 2>/dev/null; then
        echo -e "${GREEN}✔️ DuckDNS atualizado com sucesso.${NC}"
    else
        echo -e "${YELLOW}⚠️ Verifique o log do DuckDNS em ${DUCK_LOG}${NC}"
    fi
    echo "--------------------------------------------------------"

    # --- 6.6. Testar configuração e reiniciar Apache antes do Certbot (Lógica do script 20) ---
    log_info "6.6. Testando e Reiniciando o Apache"
    sudo apachectl configtest
    if [ $? -ne 0 ]; then
        echo -e "${RED}❌ ERRO FATAL: Falha na sintaxe da configuração do Apache. Por favor, corrija antes de continuar.${NC}"
        exit 1
    fi
    sudo systemctl restart httpd
    echo -e "${GREEN}✔️ Apache reiniciado com a configuração temporária.${NC}"
    echo "--------------------------------------------------------"

    # --- 6.7. Emitir certificado Let’s Encrypt com fallback (Lógica do script 20) ---
    log_info "6.7. Emitir certificado Let’s Encrypt"
    
    # Tentativa 1: Apache plugin
    if sudo certbot --apache -d "$APACHE_DOMAIN" --non-interactive --agree-tos -m "$SERVER_EMAIL" --redirect --hsts; then
        echo -e "${GREEN}✔️ Certificado SSL emitido e configurado com sucesso para https://${APACHE_DOMAIN}${NC}"
    else
        echo -e "${YELLOW}⚠️ Apache plugin falhou. Tentando com o modo Standalone...${NC}"
        sudo systemctl stop httpd
        if sudo certbot certonly --standalone -d "$APACHE_DOMAIN" --non-interactive --agree-tos -m "$SERVER_EMAIL"; then
            echo -e "${GREEN}✔️ Certificado emitido com Standalone. Reconfigurando Apache...${NC}"
            # Substitui os certs temporários pelos corretos no vhost SSL
            sudo sed -i "s|SSLCertificateFile .*|SSLCertificateFile /etc/letsencrypt/live/${APACHE_DOMAIN}/fullchain.pem|" "$SSL_CONF"
            sudo sed -i "s|SSLCertificateKeyFile .*|SSLCertificateKeyFile /etc/letsencrypt/live/${APACHE_DOMAIN}/privkey.pem|" "$SSL_CONF"
        else
            echo -e "${RED}❌ Falha ao emitir o certificado Let’s Encrypt. Verifique os logs do Certbot em /var/log/letsencrypt/.${NC}"
        fi
        sudo systemctl start httpd
    fi

else
    echo -e "${YELLOW}Configuração de SSL/TLS ignorada. Apenas o tuning de performance foi aplicado.${NC}"
fi

# 7. Validação Final e Reinício do Apache
log_info "7. Validação Final e Reinício do Apache"
echo "🔁 A testar a configuração final e a reiniciar o Apache..."
sudo systemctl enable httpd >/dev/null 2>&1

sudo apachectl configtest
if [ $? -ne 0 ]; then
    echo -e "${RED}❌ ERRO FATAL: Falha na sintaxe da configuração do Apache. Por favor, corrija antes de reiniciar.${NC}"
    exit 1
fi
sudo systemctl restart httpd

if sudo systemctl is-active --quiet httpd; then
    echo -e "${GREEN}✅ Apache otimizado e em execução!${NC}"
else
    echo -e "${RED}❌ Erro ao iniciar o Apache. Verifique o log.${NC}"
fi

echo -e "${GREEN}🎯 Tuning concluído!${NC}"
