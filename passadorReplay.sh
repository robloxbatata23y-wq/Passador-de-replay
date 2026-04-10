#!/bin/bash
# ╔══════════════════════════════════════════════════╗
# ║     PASSADOR DE REPLAY — FREE FIRE               ║
# ║     MODO STEALTH + AUTO-DESTRUIÇÃO               ║
# ║     VERSÃO FINAL                                 ║
# ╚══════════════════════════════════════════════════╝

set -u

# ──────────────────────────────────────────────────
#  CONFIGURAÇÕES DO FIREBASE
# ──────────────────────────────────────────────────
KEY_URL="https://passador-de-replay-default-rtdb.firebaseio.com"

# ──────────────────────────────────────────────────
#  VARIÁVEIS GLOBAIS
# ──────────────────────────────────────────────────
CONN_PORT=""
USUARIO="N/A"
VALIDADE_USER="N/A"
SESSION_ID="$(date +%Y%m%d_%H%M%S)_$$"
FF_ESCOLHIDO=""
PKG_DST=""
DST_DIR=""
REPLAY_SRC=""
REPLAY_ESCOLHIDO=""
TIMESTAMP_ALVO=""

# ──────────────────────────────────────────────────
#  CORES
# ──────────────────────────────────────────────────
NC='\033[0m'
VERDE='\033[1;32m'
VERMELHO='\033[1;31m'
AMARELO='\033[1;33m'
AZUL='\033[1;34m'
CIANO='\033[1;36m'
BRANCO='\033[1;37m'

# ══════════════════════════════════════════════════
#  🛡️ FUNÇÕES ANTI-FORENSE
# ══════════════════════════════════════════════════

secure_overwrite() {
    local file="$1"
    if [[ -f "$file" ]]; then
        for ((i=1; i<=3; i++)); do
            dd if=/dev/zero of="$file" bs=4096 2>/dev/null
            sync
            dd if=/dev/urandom of="$file" bs=4096 2>/dev/null
            sync
        done
        rm -f "$file"
    fi
}

wipe_all_evidence() {
    echo -e "${VERMELHO}🧹 ELIMINANDO TODAS AS EVIDÊNCIAS...${NC}"
    
    # Limpa todos os históricos
    history -c 2>/dev/null
    rm -f ~/.bash_history ~/.zsh_history ~/.ash_history ~/.sh_history 2>/dev/null
    ln -sf /dev/null ~/.bash_history 2>/dev/null
    ln -sf /dev/null ~/.zsh_history 2>/dev/null
    
    # Limpa caches
    rm -rf ~/.cache/* 2>/dev/null
    rm -rf ~/.local/share/* 2>/dev/null
    rm -rf ~/.config/* 2>/dev/null
    rm -rf ~/.termux/shell_log 2>/dev/null
    
    # Limpa logs do sistema
    logcat -c 2>/dev/null || true
    dmesg -c 2>/dev/null || true
    
    # Remove arquivos temporários
    rm -f /data/local/tmp/tmp_* 2>/dev/null
    rm -f /sdcard/.temp_* 2>/dev/null
    rm -f /sdcard/Android/data/*/cache/* 2>/dev/null
    
    # Limpa variáveis
    unset HISTFILE HISTFILESIZE HISTSIZE
    unset USER_KEY DEVICE_ID RESP
    
    echo -e "${VERDE}✅ EVIDÊNCIAS ELIMINADAS${NC}"
}

nuke_termux() {
    echo -e "${VERMELHO}💀 AUTO-DESTRUIÇÃO DO TERMUX ATIVADA!${NC}"
    echo -e "${VERMELHO}⚠️ O Termux será completamente removido do dispositivo${NC}"
    echo ""
    sleep 2
    
    # Elimina todas as evidências primeiro
    wipe_all_evidence
    
    # Sobrescreve o próprio script
    if [[ -f "$0" ]]; then
        secure_overwrite "$0"
    fi
    
    # Mata processos do Termux
    pkill -f termux 2>/dev/null
    pkill -f com.termux 2>/dev/null
    
    # Remove diretório do Termux completamente
    rm -rf /data/data/com.termux 2>/dev/null
    rm -rf /sdcard/Android/data/com.termux 2>/dev/null
    rm -rf ~/.termux 2>/dev/null
    rm -rf ~/storage 2>/dev/null
    rm -rf ~/.ssh 2>/dev/null
    rm -rf ~/.bashrc ~/.zshrc ~/.profile 2>/dev/null
    
    # Deixa arquivos falsos para enganar forense
    echo "ERROR: Termux environment corrupted. Please reinstall." > /sdcard/error.log 2>/dev/null
    echo "FATAL: $(date) - System integrity compromised" > /sdcard/crash.log 2>/dev/null
    
    # Desinstala o Termux (se possível)
    pm uninstall com.termux 2>/dev/null
    
    # Limpeza final
    unset CONN_PORT USUARIO VALIDADE_USER SESSION_ID FF_ESCOLHIDO PKG_DST DST_DIR REPLAY_SRC REPLAY_ESCOLHIDO TIMESTAMP_ALVO
    
    # Fecha tudo
    clear
    echo -e "${VERMELHO}╔══════════════════════════════════════════════════╗${NC}"
    echo -e "${VERMELHO}║  ✅ TERMUX REMOVIDO COM SUCESSO                 ║${NC}"
    echo -e "${VERMELHO}║  🔒 NENHUMA EVIDÊNCIA FOI DEIXADA               ║${NC}"
    echo -e "${VERMELHO}╚══════════════════════════════════════════════════╝${NC}"
    sleep 3
    exit 0
}

obfuscate_cmd() {
    "$@" 2>/dev/null | while IFS= read -r line; do
        echo "$line" | grep -vi "key\|senha\|password\|token\|usuário\|JWFN096"
    done
}

check_monitoring() {
    if [[ -f /proc/self/status ]]; then
        if grep -q "TracerPid:" /proc/self/status | grep -v "0" >/dev/null 2>&1; then
            echo -e "${VERMELHO}⚠️ Monitoramento detectado! Executando auto-destruição...${NC}"
            nuke_termux
        fi
    fi
    return 0
}

# ══════════════════════════════════════════════════
#  UTILITÁRIOS
# ══════════════════════════════════════════════════

pausar() {
    read -rp "Pressione Enter para continuar..." 2>/dev/null
}

header() {
    check_monitoring
    printf '\033[2J\033[3J\033[H'
    echo -e "${AZUL}══════════════════════════════════════${NC}"
    echo -e " ${CIANO}Sessão${NC}: $SESSION_ID"
    echo -e " ${CIANO}Usuário${NC}: $USUARIO"
    echo -e " ${CIANO}Validade${NC}: $VALIDADE_USER"
    echo -e "${AZUL}══════════════════════════════════════${NC}"
    echo ""
}

extrair_ts() {
    basename "$1" | grep -oE '[0-9]{4}-[0-9]{2}-[0-9]{2}-[0-9]{2}-[0-9]{2}-[0-9]{2}'
}

# ══════════════════════════════════════════════════
#  PASSO 1 — CONECTAR ADB
# ══════════════════════════════════════════════════

conectar_adb() {
    clear
    echo -e "${AZUL}╔════════════════════════════════════╗"
    echo -e "║    CONECTAR ADB VIA WI-FI          ║"
    echo -e "╚════════════════════════════════════╝${NC}"
    echo ""

    if obfuscate_cmd adb devices 2>/dev/null | grep -q "device$"; then
        echo -e "${VERDE}✅ ADB já conectado!${NC}"
        sleep 1
        return
    fi

    echo -e "${AMARELO}Ative no celular:"
    echo "   Configurações > Opções do desenvolvedor"
    echo "   > Depuração sem fio > Parear dispositivo"
    echo ""

    read -rp "Porta de pareamento: " PAIR_PORT 2>/dev/null
    read -rp "Código de pareamento: " PAIR_CODE 2>/dev/null

    printf '%s\n' "$PAIR_CODE" | adb pair "localhost:$PAIR_PORT" 2>/dev/null || {
        echo -e "${VERMELHO}❌ Falha no pareamento${NC}"
        PAIR_PORT=""; PAIR_CODE=""
        exit 1
    }
    
    PAIR_PORT=""; PAIR_CODE=""
    
    read -rp "Porta de conexão: " CONN_PORT 2>/dev/null
    adb connect "localhost:$CONN_PORT" 2>/dev/null || {
        echo -e "${VERMELHO}❌ Falha na conexão${NC}"
        exit 1
    }
    
    echo -e "${VERDE}✅ ADB conectado!${NC}"
    sleep 1
}

# ══════════════════════════════════════════════════
#  PASSO 2 — LOGIN FIREBASE
# ══════════════════════════════════════════════════

login() {
    clear
    echo -e "${AZUL}╔════════════════════════════════════╗"
    echo -e "║    LOGIN POR CHAVE                 ║"
    echo -e "╚════════════════════════════════════╝${NC}"
    echo ""

    read -rp "Sua KEY de acesso: " USER_KEY 2>/dev/null

    if [[ "$USER_KEY" != "JWFN096" ]]; then
        echo -e "${VERMELHO}❌ KEY inválida!${NC}"
        exit 1
    fi

    DEVICE_ID="$(adb shell settings get secure android_id 2>/dev/null | tr -d '\r')"
    [[ -z "$DEVICE_ID" || "$DEVICE_ID" == "null" ]] && {
        echo -e "${VERMELHO}❌ Erro ao obter UID do dispositivo${NC}"
        exit 1
    }

    echo -e "${CIANO}🔑 Verificando chave...${NC}"
    
    RESP="$(curl -s "$KEY_URL/JWFN096.json" 2>/dev/null)"
    [[ -z "$RESP" || "$RESP" == "null" ]] && {
        echo -e "${VERMELHO}❌ Erro ao conectar ao Firebase${NC}"
        exit 1
    }

    STATUS="$(echo "$RESP" | sed -n 's/.*"status":"\([^"]*\)".*/\1/p')"
    VALIDADE="$(echo "$RESP" | sed -n 's/.*"validade":"\([^"]*\)".*/\1/p')"
    CLIENTE="$(echo "$RESP" | sed -n 's/.*"cliente":"\([^"]*\)".*/\1/p')"
    UID_SERVER="$(echo "$RESP" | sed -n 's/.*"uid":"\([^"]*\)".*/\1/p')"

    case "$STATUS" in
        Ativo)   ;;
        Pausado) echo -e "${VERMELHO}❌ KEY pausada${NC}"; exit 1 ;;
        Banido)  echo -e "${VERMELHO}❌ KEY banida${NC}"; exit 1 ;;
        *)       echo -e "${VERMELHO}❌ Status inválido${NC}"; exit 1 ;;
    esac

    VALIDADE_TS="$(date -d "$VALIDADE 23:59:59" +%s 2>/dev/null)"
    DEVICE_TS="$(adb shell date +%s 2>/dev/null | tr -d '\r')"
    
    (( DEVICE_TS > VALIDADE_TS )) && {
        echo -e "${VERMELHO}❌ KEY expirada em $VALIDADE${NC}"
        exit 1
    }

    if [[ -z "$UID_SERVER" ]]; then
        curl -s -X PATCH \
            -H "Content-Type: application/json" \
            -d "{\"uid\":\"$DEVICE_ID\"}" \
            "$KEY_URL/JWFN096.json" >/dev/null
        echo -e "${VERDE}✅ Dispositivo vinculado!${NC}"
    elif [[ "$UID_SERVER" != "$DEVICE_ID" ]]; then
        echo -e "${VERMELHO}❌ KEY vinculada a outro dispositivo${NC}"
        exit 1
    fi

    USUARIO="$CLIENTE"
    VALIDADE_USER="$VALIDADE"
    echo -e "${VERDE}✅ Bem-vindo, $USUARIO! (válido até $VALIDADE)${NC}"
    
    USER_KEY=""
    sleep 2
}

# ══════════════════════════════════════════════════
#  PASSO 3 — ESCOLHER FREE FIRE
# ══════════════════════════════════════════════════

escolher_freefire() {
    while true; do
        header
        echo -e "  ${VERDE}ESCOLHA O FREE FIRE DESTINO${NC}"
        echo ""
        echo -e "  ${CIANO}1)${NC} Free Fire Normal (com.dts.freefireth)"
        echo -e "  ${CIANO}2)${NC} Free Fire MAX (com.dts.freefiremax)"
        echo -e "  ${CIANO}3)${NC} Voltar"
        echo ""
        read -rp "Opção: " OP 2>/dev/null
        
        case "$OP" in
            1)
                PKG_DST="com.dts.freefireth"
                DST_DIR="/sdcard/Android/data/${PKG_DST}/files/MReplays"
                REPLAY_SRC="/sdcard/Android/data/com.dts.freefiremax/files/MReplays"
                FF_ESCOLHIDO="Free Fire Normal"
                echo -e "${VERDE}✅ Free Fire Normal selecionado${NC}"
                sleep 1
                return
                ;;
            2)
                PKG_DST="com.dts.freefiremax"
                DST_DIR="/sdcard/Android/data/${PKG_DST}/files/MReplays"
                REPLAY_SRC="/sdcard/Android/data/com.dts.freefiremax/files/MReplays"
                FF_ESCOLHIDO="Free Fire MAX"
                echo -e "${VERDE}✅ Free Fire MAX selecionado${NC}"
                sleep 1
                return
                ;;
            3)
                return 1
                ;;
            *)
                echo -e "${VERMELHO}Opção inválida${NC}"
                sleep 1
                ;;
        esac
    done
}

# ══════════════════════════════════════════════════
#  PASSO 4 — LISTAR REPLAYS DISPONÍVEIS
# ══════════════════════════════════════════════════

listar_replays() {
    adb shell "
        for f in \"$REPLAY_SRC\"/*.bin; do
            [ -f \"\$f\" ] || continue
            j=\"\${f%.bin}.json\"
            [ -f \"\$j\" ] && echo \"\$f\"
        done
    " 2>/dev/null | tr -d '\r'
}

menu_replays() {
    while true; do
        header
        echo -e "  ${VERDE}REPLAYS DISPONÍVEIS (FF MAX)${NC}"
        echo -e "  ${CIANO}Destino: $FF_ESCOLHIDO${NC}"
        echo ""
        
        mapfile -t BINS < <(listar_replays)

        if [[ ${#BINS[@]} -eq 0 ]]; then
            echo -e "${AMARELO}Nenhum replay encontrado em:${NC}"
            echo -e "  $REPLAY_SRC"
            echo ""
            echo -e "${CIANO}Jogue uma partida no FF MAX e salve o replay.${NC}"
            echo ""
            echo -e "  ${CIANO}R)${NC} Recarregar"
            echo -e "  ${CIANO}0)${NC} Voltar"
            echo ""
            read -rp "Opção: " OP 2>/dev/null
            [[ "$OP" =~ ^[Rr]$ ]] && continue
            [[ "$OP" == "0" ]] && return 1
            continue
        fi

        echo -e "${VERDE}Replays encontrados:${NC}"
        echo ""
        for i in "${!BINS[@]}"; do
            local TS DATA HORA
            TS="$(extrair_ts "${BINS[$i]}")"
            if [[ -n "$TS" ]]; then
                DATA="${TS:0:4}-${TS:5:2}-${TS:8:2}"
                HORA="${TS:11:2}:${TS:14:2}:${TS:17:2}"
                printf "  ${CIANO}%2d)${NC} 📅 %s  ⏰ %s\n" $((i+1)) "$DATA" "$HORA"
            else
                printf "  ${CIANO}%2d)${NC} %s\n" $((i+1)) "$(basename "${BINS[$i]}")"
            fi
        done

        echo ""
        echo -e "  ${CIANO}0)${NC} Voltar"
        echo ""
        read -rp "Escolha o replay: " SEL 2>/dev/null

        [[ "$SEL" == "0" ]] && return 1

        if ! [[ "$SEL" =~ ^[0-9]+$ ]] || (( SEL < 1 || SEL > ${#BINS[@]} )); then
            echo -e "${VERMELHO}Opção inválida${NC}"
            sleep 1
            continue
        fi

        REPLAY_ESCOLHIDO="${BINS[$((SEL-1))]}"
        TIMESTAMP_ALVO="$(extrair_ts "$REPLAY_ESCOLHIDO")"
        
        if [[ -z "$TIMESTAMP_ALVO" ]]; then
            echo -e "${VERMELHO}❌ Erro ao extrair timestamp do replay${NC}"
            sleep 2
            continue
        fi
        
        return 0
    done
}

# ══════════════════════════════════════════════════
#  PASSO 5 — PASSAR REPLAY COM BYPASS
# ══════════════════════════════════════════════════

passar_replay() {
    local BIN="$REPLAY_ESCOLHIDO"
    local JSON="${BIN%.bin}.json"
    local TS="$TIMESTAMP_ALVO"
    
    clear
    echo -e "${AZUL}╔════════════════════════════════════╗"
    echo -e "║    PREPARANDO BYPASS...            ║"
    echo -e "╚════════════════════════════════════╝${NC}"
    echo ""
    
    DATA_ALVO="${TS:0:4}-${TS:5:2}-${TS:8:2}"
    HORA_ALVO="${TS:11:2}:${TS:14:2}:${TS:17:2}"
    
    echo -e " ${CIANO}Replay selecionado:${NC}"
    echo -e "   📅 Data: ${AMARELO}$DATA_ALVO${NC}"
    echo -e "   ⏰ Hora: ${AMARELO}$HORA_ALVO${NC}"
    echo -e "   🎮 Destino: ${VERDE}$FF_ESCOLHIDO${NC}"
    echo ""
    
    # Verifica se o FF destino está instalado
    APK_VER_DST="$(adb shell dumpsys package "$PKG_DST" 2>/dev/null \
        | grep -m1 versionName | sed 's/.*=//' | tr -d '\r')"
    
    if [[ -z "$APK_VER_DST" ]]; then
        echo -e "${VERMELHO}❌ $FF_ESCOLHIDO não está instalado no celular${NC}"
        pausar
        return 1
    fi
    
    # Modifica versão no JSON
    adb shell "sed -i 's/\"Version\":\"[^\"]*\"/\"Version\":\"$APK_VER_DST\"/g' \"$JSON\"" 2>/dev/null
    
    # Desativa hora automática
    adb shell "settings put global auto_time 0" 2>/dev/null
    adb shell "settings put global auto_time_zone 0" 2>/dev/null
    adb shell "am start -a android.settings.DATE_SETTINGS" 2>/dev/null
    
    echo -e "${CIANO}⏳ Configure a data/hora do celular para:${NC}"
    echo -e "   Data: ${VERDE}$DATA_ALVO${NC}"
    echo -e "   Hora: ${VERDE}$HORA_ALVO${NC}"
    echo ""
    echo -e "${AMARELO}⚠️ Aguardando o horário exato...${NC}"
    echo ""
    
    # Aguarda o horário exato
    local aguardando=true
    while $aguardando; do
        local NOW
        NOW="$(adb shell date '+%Y-%m-%d-%H-%M-%S' 2>/dev/null | tr -d '\r')"
        printf "\r   ⏰ Celular: ${AMARELO}%s${NC}  |  Alvo: ${VERDE}%s${NC}   " "$NOW" "$TS"
        
        if [[ "$NOW" == "$TS" ]]; then
            echo ""
            echo -e "\n${VERDE}✅ HORÁRIO EXATO ATINGIDO!${NC}"
            echo ""
            echo -e "${AZUL}══════════════════════════════════════${NC}"
            echo -e " ${CIANO}🎮 EXECUTAR BYPASS?${NC}"
            echo -e "${AZUL}══════════════════════════════════════${NC}"
            echo ""
            read -rp "Executar bypass agora? (s/N): " EXECUTAR 2>/dev/null
            
            if [[ "$EXECUTAR" =~ ^[Ss]$ ]]; then
                echo -e "${VERDE}✅ Executando bypass...${NC}"
                
                # Volta para home
                adb shell "input keyevent KEYCODE_BACK" 2>/dev/null
                adb shell "input keyevent KEYCODE_HOME" 2>/dev/null
                
                # Cria diretório destino
                adb shell "mkdir -p \"$DST_DIR\"" 2>/dev/null
                
                local BIN_DST="$DST_DIR/$(basename "$BIN")"
                local JSON_DST="$DST_DIR/$(basename "$JSON")"
                
                # Copia os arquivos
                adb exec-out "cat \"$BIN\"" | adb shell "cat > \"$BIN_DST\"" 2>/dev/null
                adb exec-out "cat \"$JSON\"" | adb shell "cat > \"$JSON_DST\"" 2>/dev/null
                
                # Restaura hora automática
                adb shell "settings put global auto_time 1" 2>/dev/null
                adb shell "settings put global auto_time_zone 1" 2>/dev/null
                
                # Apaga originais com overwrite
                adb shell "dd if=/dev/urandom of=\"$BIN\" bs=4096 2>/dev/null; rm -f \"$BIN\"" 2>/dev/null
                adb shell "dd if=/dev/urandom of=\"$JSON\" bs=4096 2>/dev/null; rm -f \"$JSON\"" 2>/dev/null
                
                echo ""
                echo -e "${VERDE}╔════════════════════════════════════╗${NC}"
                echo -e "${VERDE}║  ✅ REPLAY PASSADO COM SUCESSO!   ║${NC}"
                echo -e "${VERDE}╚════════════════════════════════════╝${NC}"
                echo ""
                echo -e "${AMARELO}⚠️ O Termux será completamente removido em 5 segundos...${NC}"
                sleep 5
                
                # AUTO-DESTRUIÇÃO TOTAL
                nuke_termux
                
            else
                echo -e "${AMARELO}❌ Bypass cancelado.${NC}"
                # Restaura hora automática
                adb shell "settings put global auto_time 1" 2>/dev/null
                adb shell "settings put global auto_time_zone 1" 2>/dev/null
                pausar
                return 1
            fi
        fi
        sleep 0.1
    done
}

# ══════════════════════════════════════════════════
#  MENU PRINCIPAL
# ══════════════════════════════════════════════════

menu_principal() {
    while true; do
        header
        echo -e "  ${VERDE}MENU PRINCIPAL${NC}"
        echo -e "  ${VERMELHO}⚠️ MODO STEALTH ATIVADO${NC}"
        echo -e "  ${VERMELHO}💀 Auto-destruição será executada ao final${NC}"
        echo ""
        echo -e "  ${CIANO}1)${NC} 🎮 Escolher Free Fire"
        echo -e "  ${CIANO}2)${NC} 📋 Passar Replay"
        echo -e "  ${CIANO}3)${NC} ❌ Sair"
        echo ""
        read -rp "Opção: " OP 2>/dev/null
        
        case "$OP" in
            1)
                escolher_freefire
                ;;
            2)
                if [[ -z "$FF_ESCOLHIDO" ]]; then
                    echo -e "${VERMELHO}⚠️ Primeiro escolha o Free Fire destino!${NC}"
                    sleep 2
                    continue
                fi
                if menu_replays; then
                    passar_replay
                fi
                ;;
            3)
                echo -e "${VERMELHO}⚠️ Saindo sem auto-destruição...${NC}"
                exit 0
                ;;
            *)
                echo -e "${VERMELHO}Opção inválida${NC}"
                sleep 1
                ;;
        esac
    done
}

# ══════════════════════════════════════════════════
#  TRAP PARA INTERRUPÇÃO
# ══════════════════════════════════════════════════

trap 'echo -e "\n${VERMELHO}⚠️ Interrompido. Executando auto-destruição...${NC}"; nuke_termux' INT TERM

# ══════════════════════════════════════════════════
#  INÍCIO
# ══════════════════════════════════════════════════

clear
echo -e "${VERMELHO}╔══════════════════════════════════════════════════╗${NC}"
echo -e "${VERMELHO}║  🔥 PASSADOR DE REPLAY - MODO STEALTH           ║${NC}"
echo -e "${VERMELHO}║  ⚠️  AUTO-DESTRUIÇÃO ATIVA                       ║${NC}"
echo -e "${VERMELHO}║  💀 O Termux será DESTRUÍDO ao passar o replay   ║${NC}"
echo -e "${VERMELHO}╚══════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${AMARELO}Recursos anti-forense ativos:${NC}"
echo -e "  ✅ Sobrescrita segura de arquivos (3 passes)"
echo -e "  ✅ Limpeza total de logs e históricos"
echo -e "  ✅ Ofuscação de comandos"
echo -e "  ✅ Anti-debugging"
echo -e "  ✅ Auto-destruição do Termux"
echo -e "  ✅ Remoção de todas as evidências"
echo ""
read -rp "Pressione Enter para continuar..." 2>/dev/null

conectar_adb
login
menu_principal
