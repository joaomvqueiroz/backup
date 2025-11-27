#!/bin/bash

# =================================================================
# Script 2: Configuração Segura do MariaDB
# Objetivo: Executar a rotina de segurança interativa do MariaDB.
# =================================================================

# Cores para feedback visual
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${YELLOW}--- 🛠️ Iniciando a Configuração Segura do MariaDB ---${NC}"

# 1. Verificar o Serviço MariaDB
echo -e "${YELLOW}>> 1. Verificando se o serviço MariaDB está ativo...${NC}"

if ! sudo systemctl is-active mariadb &> /dev/null; then
    echo -e "${RED}❌ ERRO: O serviço MariaDB não está ativo. Por favor, inicie-o com 'sudo systemctl start mariadb'. A sair.${NC}"
    exit 1
fi
echo -e "${GREEN}✔️ Serviço MariaDB ativo.${NC}"

# 2. Executar Configuração de Segurança Inicial (Interativa)
echo -e "\n${YELLOW}>> 2. INICIANDO O UTILITÁRIO DE SEGURANÇA (mysql_secure_installation)...${NC}"
echo -e "${YELLOW}!!! ATENÇÃO: Este passo é INTERATIVO e requer a sua intervenção para:${NC}"
echo -e "${YELLOW}    - Definir a password 'root' do MariaDB.${NC}"
echo -e "${YELLOW}    - Remover utilizadores anónimos e bases de dados de teste.${NC}"
echo -e "${YELLOW}    - Desativar o login 'root' remoto.${NC}"
echo "--------------------------------------------------------"

# Executar o utilitário de segurança, que também recarrega os privilégios no final.
sudo mysql_secure_installation

if [ $? -eq 0 ]; then
    echo -e "\n${GREEN}🎉 Configuração de segurança inicial concluída!${NC}"
else
    echo -e "\n${RED}⚠️ A execução de 'mysql_secure_installation' terminou com um erro. Reveja a segurança do seu MariaDB.${NC}"
fi

echo -e "\n${YELLOW}--- ✅ Script de Configuração Segura do MariaDB Concluído ---${NC}"
