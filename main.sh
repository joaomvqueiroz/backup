#!/bin/bash

# =================================================================
# Script Mestre de Gestão e Execução
# Objetivo: Orquestrar a execução dos scripts de automação de forma
#           interativa e executar validações no final.
# =================================================================

# --- Cores e Funções de Log ---
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

log_header() {
    echo -e "\n${CYAN}===================================================================${NC}"
    echo -e "${CYAN} $1 ${NC}"
    echo -e "${CYAN}===================================================================${NC}"
}

# --- Verificação de Permissões ---
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}❌ ERRO: Este script mestre deve ser executado com privilégios de root (sudo).${NC}"
    echo "Por favor, execute como: sudo ./main.sh"
    exit 1
fi

# --- Definição dos Scripts Disponíveis ---
declare -A SCRIPTS
SCRIPTS[1]="Instalação dos Serviços Principais (LAMP)"
SCRIPTS[2]="Configuração Segura do MariaDB"
SCRIPTS[3]="Configuração de Rede e Firewall"
SCRIPTS[4]="Auditoria de SELinux e Segurança"
SCRIPTS[5]="Configuração do Fail2ban (SSH e Apache)"
SCRIPTS[6]="Configuração do ModSecurity (WAF com OWASP CRS)"
SCRIPTS[7]="Tuning do Apache (Performance e SSL/TLS Opcional)"
SCRIPTS[8]="Tuning do MariaDB (Performance)"
SCRIPTS[9]="Ajustes do PHP (Performance e Ambiente)"
SCRIPTS[10]="Atualizações e Backup do Sistema"
SCRIPTS[11]="Monitorização e Alertas"

# =================================================================
# 1. MENU DE SELEÇÃO DE SCRIPTS
# =================================================================
log_header "GESTOR DE AUTOMAÇÃO DE SERVIDOR"

echo -e "${YELLOW}Por favor, escolha os scripts que deseja executar:${NC}"
for i in $(echo "${!SCRIPTS[@]}" | tr ' ' '\n' | sort -n); do
    printf "  %-2s) %s\n" "$i" "${SCRIPTS[$i]}"
done
echo -e "\n  ${GREEN}99) Executar TODOS os scripts em ordem${NC}"
echo -e "  ${RED}0) Sair${NC}"
echo -e "\n(Pode escolher múltiplos scripts separados por espaço, ex: 1 3 5)"
read -p "Sua escolha: " user_choice

scripts_to_run=()
if [[ "$user_choice" == "0" ]]; then
    echo -e "${YELLOW}A sair do gestor. Nenhuma ação foi executada.${NC}"
    exit 0
elif [[ "$user_choice" == "99" ]]; then
    # Opção "Todos"
    scripts_to_run=($(echo "${!SCRIPTS[@]}" | tr ' ' '\n' | sort -n))
else
    # Opção de seleção múltipla
    read -ra choices <<< "$user_choice"
    for choice in "${choices[@]}"; do
        if [[ -n "${SCRIPTS[$choice]}" ]]; then
            scripts_to_run+=("$choice")
        else
            # Ignorar entradas vazias que podem vir de múltiplos espaços
            if [[ -n "$choice" ]]; then
                echo -e "${RED}Opção inválida '$choice' ignorada.${NC}"
            fi
        fi
    done
fi

if [ ${#scripts_to_run[@]} -eq 0 ]; then
    echo -e "${RED}Nenhum script válido selecionado. A sair.${NC}"
    exit 1
fi

# =================================================================
# 2. EXECUÇÃO DOS SCRIPTS SELECIONADOS
# =================================================================
log_header "INICIANDO EXECUÇÃO DOS SCRIPTS"
echo -e "Scripts a serem executados: ${YELLOW}${scripts_to_run[*]}${NC}"

for script_num in "${scripts_to_run[@]}"; do
    script_file="${script_num}-script.sh"
    if [ -f "$script_file" ]; then
        log_header "Executando: ${script_file} - ${SCRIPTS[$script_num]}"
        bash "$script_file"
        if [ $? -ne 0 ]; then
            echo -e "${RED}❌ ERRO: O script ${script_file} terminou com um erro. Abortando a execução.${NC}"
            exit 1
        fi
        echo -e "${GREEN}✔️ Script ${script_file} concluído com sucesso.${NC}"
        # A linha abaixo foi removida para permitir a execução contínua sem pausas.
        # read -p "Pressione [Enter] para continuar para o próximo script..."
    else
        echo -e "${RED}AVISO: O ficheiro ${script_file} não foi encontrado e será ignorado.${NC}"
    fi
done

echo -e "${GREEN}🎉 Todos os scripts selecionados foram executados com sucesso!${NC}"

# =================================================================
# 3. MENU DE SELEÇÃO DE VALIDAÇÕES
# =================================================================
log_header "VALIDAÇÃO DAS CONFIGURAÇÕES"
read -p "Deseja executar o script de validação (validate_config.py)? (s/n): " run_validation

if [[ ! "$run_validation" =~ ^[Ss]$ ]]; then
    echo "Validação ignorada. Processo concluído."
    exit 0
fi

# --- Definição das Validações Disponíveis ---
declare -A VALIDATIONS
VALIDATIONS[1]="Pacotes e Serviços Essenciais (Scripts 1, 5)"
VALIDATIONS[3]="Configuração do Firewall (Script 3)"
VALIDATIONS[4]="Configurações de Segurança - SELinux e ModSecurity (Scripts 4, 6)"
VALIDATIONS[8]="Tuning do MariaDB (Script 8)"
VALIDATIONS[9]="Ajustes do PHP (Script 9)"

# Mapeia qual script ativa qual validação
declare -A VALIDATION_MAP
VALIDATION_MAP[1]=1; VALIDATION_MAP[5]=1
VALIDATION_MAP[3]=3
VALIDATION_MAP[4]=4; VALIDATION_MAP[6]=4
VALIDATION_MAP[8]=8
VALIDATION_MAP[9]=9

# Determina quais validações são relevantes
relevant_validations=()
for script_num in "${scripts_to_run[@]}"; do
    validation_key=${VALIDATION_MAP[$script_num]}
    if [[ -n "$validation_key" && ! " ${relevant_validations[*]} " =~ " ${validation_key} " ]]; then
        relevant_validations+=("$validation_key")
    fi
done

if [ ${#relevant_validations[@]} -eq 0 ]; then
    echo -e "${YELLOW}Nenhuma validação relevante para os scripts executados.${NC}"
    exit 0
fi

echo -e "\n${YELLOW}Escolha as validações que deseja executar:${NC}"
sorted_relevant=($(echo "${relevant_validations[@]}" | tr ' ' '\n' | sort -n))

for i in "${sorted_relevant[@]}"; do
    printf "  %-2s) %s\n" "$i" "${VALIDATIONS[$i]}"
done
echo -e "  ${GREEN}A) Executar TODAS as validações relevantes${NC}"
read -p "Sua escolha: " validation_choice

# --- Execução das Validações ---
if [[ "$validation_choice" =~ ^[Aa]$ ]]; then
    # Opção "Todas"
    log_header "Executando TODAS as validações relevantes"
    python3 validate_config.py
else
    # Opção de seleção múltipla (executa cada validação individualmente)
    # NOTA: O script validate_config.py atual não suporta execução parcial.
    # Esta é uma implementação de exemplo. Para funcionar, o python teria que aceitar argumentos.
    # Por agora, qualquer seleção executará o script completo.
    log_header "Executando validações selecionadas"
    echo -e "${YELLOW}AVISO: A versão atual do 'validate_config.py' executará todas as validações, independentemente da seleção.${NC}"
    python3 validate_config.py
fi

if [ $? -eq 0 ]; then
    echo -e "${GREEN}🎉 Validação concluída com sucesso!${NC}"
else
    echo -e "${RED}⚠️ A validação encontrou problemas. Verifique o relatório acima.${NC}"
fi

log_header "PROCESSO DE AUTOMAÇÃO CONCLUÍDO"
