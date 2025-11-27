#!/bin/bash

# =================================================================
# Script 1: Instalação dos Serviços Principais (LAMP Stack Base)
# Objetivo: Instalar Apache, PHP (8.x) e MariaDB, ativar serviços
# e criar ficheiro de validação info.php.
# =================================================================

# Cores para feedback visual
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

IP_SIMULADO="192.168.1.10" # Baseado no valor IPADDR do relatório

log_info() {
    echo -e "${BLUE}--- $1 ---${NC}"
}

echo -e "${YELLOW}--- 🛠️ Iniciando a Instalação da Stack LAMP Base no CentOS Stream 9 ---${NC}"

# --- 1. Atualização e Repositórios Essenciais ---
log_info "1. Atualização e Repositório EPEL"
echo ">> A instalar o repositório EPEL e atualizar o sistema..."
sudo dnf install epel-release -y 
sudo dnf update -y
echo -e "${GREEN}✔️ Repositórios prontos.${NC}"
echo "--------------------------------------------------------"

# --- 2. Instalação e Ativação do Apache (HTTPD) ---
log_info "2. Instalação e Verificação do Servidor Apache (HTTPD)"
echo ">> A instalar o Apache (httpd) e o módulo SSL (mod_ssl)..."
sudo dnf install httpd mod_ssl -y

echo ">> A ativar e iniciar o serviço httpd..."
sudo systemctl enable httpd
sudo systemctl start httpd

if sudo systemctl is-active httpd &> /dev/null; then
    echo -e "${GREEN}✔️ Apache ativo e em execução.${NC}"
else
    echo -e "${RED}❌ ERRO: Falha ao iniciar o Apache. Verifique o estado: 'sudo systemctl status httpd'.${NC}"
    exit 1
fi
echo "--------------------------------------------------------"

# --- 3. Instalação e Configuração do PHP (8.x) ---
log_info "3. Instalação e Verificação do PHP (Versão 8.x)"

# Configuração do módulo PHP 8.3 (seguindo o relatório)
echo ">> A instalar o repositório Remi e a preparar o PHP 8.3..."
sudo dnf install https://rpms.remirepo.net/enterprise/remi-release-9.rpm -y
sudo dnf module reset php -y
sudo dnf module enable php:8.3 -y 
echo ">> A instalar o PHP e módulos essenciais (php-mysqlnd, php-cli, etc.)..."
sudo dnf install php php-cli php-fpm php-mysqlnd php-gd php-xml php-json php-mbstring -y

echo -e "${GREEN}✔️ PHP $(php -v | head -n 1) instalado.${NC}"
echo "--------------------------------------------------------"

# --- 4. Instalação e Ativação do MariaDB ---
log_info "4. Instalação e Ativação do MariaDB Server"
echo ">> A instalar o MariaDB..."
sudo dnf install mariadb-server -y

echo ">> A ativar e iniciar o serviço mariadb..."
sudo systemctl enable mariadb
sudo systemctl start mariadb

if sudo systemctl is-active mariadb &> /dev/null; then
    echo -e "${GREEN}✔️ MariaDB ativo e em execução.${NC}"
else
    echo -e "${RED}❌ ERRO: Falha ao iniciar o MariaDB. Verifique o estado: 'sudo systemctl status mariadb'.${NC}"
    exit 1
fi
echo "--------------------------------------------------------"

# --- 5. Instalação do Website a partir do Repositório Git ---
log_info "5. Instalação do Website a partir do Repositório Git"

echo ">> A verificar se o 'git' está instalado..."
if ! command -v git &> /dev/null; then
    echo ">> 'git' não encontrado. A instalar..."
    sudo dnf install git -y
    if [ $? -ne 0 ]; then
        echo -e "${RED}❌ ERRO: Falha ao instalar o 'git'. A sair.${NC}"
        exit 1
    fi
fi

echo ">> A remover o diretório /var/www/html existente..."
sudo rm -rf /var/www/html

echo ">> A clonar o repositório https://github.com/joaomvqueiroz/html.git para /var/www/html..."
sudo git clone https://github.com/joaomvqueiroz/html.git /var/www/html

if [ ! -d "/var/www/html" ]; then
    echo -e "${RED}❌ ERRO: Falha ao clonar o repositório do website. A sair.${NC}"
    exit 1
fi

echo ">> A reiniciar o Apache para carregar as configurações do PHP..."
sudo systemctl restart httpd

# --- 6. Validação ---
echo -e "\n${YELLOW}--- ✅ Instalação e Ativação Concluídas ---${NC}"
echo -e "${GREEN}Status dos Serviços:${NC}"
echo "Apache: $(sudo systemctl is-active httpd)"
echo "MariaDB: $(sudo systemctl is-active mariadb)"
echo "PHP Versão: $(php -v | head -n 1)"
echo -e "${GREEN}Pode verificar a acessibilidade do website no browser através do IP do servidor.${NC}"
echo "--------------------------------------------------------"
