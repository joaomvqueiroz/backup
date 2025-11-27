#!/usr/bin/env python3
# -*- coding: utf-8 -*-

import sys
import os
import subprocess

# --- VALORES ESPERADOS PARA VALIDAÇÃO ---
# Mapeia as configurações chave que cada script deveria ter aplicado.
EXPECTED_VALUES = {
    'servicos_essenciais': {
        'pacotes': ['httpd', 'mariadb-server', 'php', 'git', 'fail2ban', 'mod_security'],
        'servicos_ativos': ['httpd', 'mariadb', 'fail2ban']
    },
    'firewall': {
        'servicos': ['http', 'https', 'ssh']
    },
    'seguranca': {
        'selinux_mode': 'Enforcing',
        'modsec_engine': 'On'
    },
    'tuning_mariadb': {
        # O ficheiro de configuração do MariaDB no CentOS 9 é tipicamente my.cnf ou um ficheiro em my.cnf.d/
        'innodb_log_file_size': '256M', 
        'max_connections': '100',
        'query_cache_size': '32M'
    },
    'tuning_php': {
        'date.timezone': 'Europe/Lisbon',
        'upload_max_filesize': '20M',
        'post_max_size': '25M',
        'memory_limit': '256M'
    }
}

# --- Funções Auxiliares ---

def run_command(command):
    """Executa um comando no shell e retorna a sua saída."""
    try:
        result = subprocess.run(command, shell=True, check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        return result.stdout.strip()
    except subprocess.CalledProcessError as e:
        return None

def print_status(message, success):
    """Imprime uma mensagem de status com um ícone de sucesso ou falha."""
    icon = "✅" if success else "❌"
    print(f"{icon} {message}")
    return success

def read_config_file(filepath):
    """
    Lê um ficheiro de configuração (estilo .ini ou Apache) e retorna um dicionário.
    CORREÇÃO: Melhor tratamento de espaços e separadores.
    """
    values = {}
    # Adaptação para caminhos comuns para my.cnf se /etc/my.cnf não existir
    if 'my.cnf' in filepath and not os.path.exists(filepath):
        filepath = "/etc/my.cnf.d/mariadb-server.cnf"
        
    if not os.path.exists(filepath):
        return None
    
    try:
        with open(filepath, 'r') as f:
            for line in f:
                line = line.strip()
                # Ignora linhas vazias, comentários e cabeçalhos de secção
                if not line or line.startswith('#') or line.startswith(';') or (line.startswith('[') and line.endswith(']')):
                    continue
                
                # Lógica unificada para tratar ambos os formatos
                # Ex: "key = value" ou "key value"
                separator = '=' if '=' in line else None
                
                if separator:
                    parts = line.split(separator, 1)
                else: # Fallback para separador de espaço
                    parts = line.split(None, 1)

                if len(parts) < 2:
                    continue

                key = parts[0].strip()
                value = parts[1].strip()
                values[key] = value
    except Exception as e:
        # Apanha erros de leitura/permissão, embora o script seja executado como root.
        print(f"Erro ao ler o ficheiro {filepath}: {e}")
        return None
    return values

def print_header(title):
    """Imprime um cabeçalho formatado."""
    print("\n" + "="*50)
    print(f"  {title}")
    print("="*50)

# --- Funções de Validação por Script ---

def validate_script_1_e_5():
    """Valida pacotes e serviços instalados pelos scripts 1 e 5."""
    print_header("Scripts 1 & 5: Pacotes e Serviços Essenciais")
    overall_success = True

    # Validação de pacotes
    for pkg in EXPECTED_VALUES['servicos_essenciais']['pacotes']:
        output = run_command(f"rpm -q {pkg}")
        success = output is not None and "not installed" not in output
        overall_success &= print_status(f"Pacote '{pkg}' está instalado.", success)

    # Validação de serviços
    for service in EXPECTED_VALUES['servicos_essenciais']['servicos_ativos']:
        output = run_command(f"systemctl is-active {service}")
        success = output == "active"
        overall_success &= print_status(f"Serviço '{service}' está ativo.", success)
    
    return overall_success

def validate_script_3():
    """Valida a configuração do Firewall."""
    print_header("Script 3: Configuração do Firewall")
    output = run_command("firewall-cmd --list-services")
    if output is None:
        return print_status("Não foi possível verificar os serviços do firewalld.", False)
    
    current_services = output.split()
    overall_success = True
    for service in EXPECTED_VALUES['firewall']['servicos']:
        success = service in current_services
        overall_success &= print_status(f"Serviço '{service}' está permitido no firewall.", success)
        
    return overall_success

def validate_script_4_e_6():
    """Valida configurações de segurança (SELinux e ModSecurity)."""
    print_header("Scripts 4 & 6: Configurações de Segurança")
    overall_success = True

    # Validação SELinux
    selinux_mode = run_command("getenforce")
    success = selinux_mode == EXPECTED_VALUES['seguranca']['selinux_mode']
    overall_success &= print_status(f"SELinux está em modo '{EXPECTED_VALUES['seguranca']['selinux_mode']}'. (Atual: {selinux_mode})", success)

    # Validação ModSecurity
    modsec_conf = read_config_file("/etc/httpd/conf.d/mod_security.conf")
    if modsec_conf is None:
        # O ficheiro pode não existir se a instalação falhou, mas se existe, deve ser validado.
        print_status("Ficheiro de configuração do ModSecurity não encontrado.", False)
        # Vamos assumir TRUE se o ModSecurity estiver configurado para 'Não Encontrado' na saída anterior
        # (A saída anterior já validou que o ModSecurity estava 'On', então este bloco não deve ser executado se estiver tudo OK)
        if modsec_conf is None:
             engine_status = 'Não Encontrado'
        else:
             engine_status = 'Não Encontrado'
             
    engine_status = modsec_conf.get('SecRuleEngine', 'Não Encontrado') if modsec_conf else 'Não Encontrado'
    success = engine_status == EXPECTED_VALUES['seguranca']['modsec_engine']
    overall_success &= print_status(f"ModSecurity Engine está '{EXPECTED_VALUES['seguranca']['modsec_engine']}'. (Atual: {engine_status})", success)

    return overall_success

def validate_script_8():
    """Valida o tuning do MariaDB. Adapta o caminho para my.cnf."""
    print_header("Script 8: Tuning do MariaDB")
    # Tentativa de ler o caminho padrão e o caminho específico do CentOS Stream 9
    config = read_config_file("/etc/my.cnf") 
    
    if config is None:
         return print_status("Ficheiro de configuração do MariaDB não encontrado.", False)

    overall_success = True
    for key, expected_value in EXPECTED_VALUES['tuning_mariadb'].items():
        current_value = config.get(key, 'Não Encontrado')
        # Comparação exata: o strip() dentro de read_config_file garante que não há espaços ou = no valor.
        success = current_value == expected_value
        overall_success &= print_status(f"MariaDB '{key}' = '{expected_value}'. (Atual: {current_value})", success)
        
    return overall_success

def validate_script_9():
    """Valida os ajustes do PHP."""
    print_header("Script 9: Ajustes do PHP")
    config = read_config_file("/etc/php.ini")
    if config is None:
        return print_status("Ficheiro de configuração /etc/php.ini não encontrado.", False)

    overall_success = True
    for key, expected_value in EXPECTED_VALUES['tuning_php'].items():
        current_value = config.get(key, 'Não Encontrado')
        # Comparação exata após strip()
        success = current_value == expected_value
        overall_success &= print_status(f"PHP '{key}' = '{expected_value}'. (Atual: {current_value})", success)
        
    return overall_success


def main():
    """Função principal que executa todas as validações."""
    if os.geteuid() != 0:
        print("❌ ERRO: Este script precisa ser executado como root para verificar as configurações do sistema.")
        sys.exit(1)

    print("🚀 INICIANDO VALIDAÇÃO COMPLETA DA CONFIGURAÇÃO DO SERVIDOR 🚀")
    
    # Executar todas as funções de validação
    results = [
        validate_script_1_e_5(),
        validate_script_3(),
        validate_script_4_e_6(),
        validate_script_8(),
        validate_script_9()
    ]
    
    # Verificar o resultado final
    if all(results):
        print("\n" + "="*50)
        print("🎉 SUCESSO: Todas as configurações principais foram validadas com êxito!")
        print("="*50)
        sys.exit(0)
    else:
        print("\n" + "="*50)
        print("⚠️ FALHA: Algumas configurações não correspondem ao esperado. Reveja o relatório acima.")
        print("="*50)
        sys.exit(1)

if __name__ == "__main__":
    main()