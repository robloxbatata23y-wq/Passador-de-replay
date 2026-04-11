#!/bin/bash
# ╔══════════════════════════════════════════════════╗
# ║     PASSADOR DE REPLAY — FREE FIRE               ║
# ║     FF MAX → FF Normal                           ║
# ╚══════════════════════════════════════════════════╝

set -u

KEY_URL="https://passador-de-replay-default-rtdb.firebaseio.com"
REPLAY_SRC_BASE="/sdcard/Android/data/com.dts.freefiremax/files/MReplays"
PKG_FF_NORMAL="com.dts.freefireth"
PKG_FF_MAX="com.dts.freefiremax"

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

NC='\033[0m'
VERDE='\033[1;32m'
VERMELHO='\033[1;31m'
AMARELO='\033[1;33m'
AZUL='\033[1;34m'
CIANO='\033[1;36m'

pausar() { read -rp "Pressione Enter para continuar..."; }

header() {
    clear
    echo -e "${AZUL}══════════════════════════════════════${NC}"
    echo -e " ${CIANO}Sessão${NC}  : $SESSION_ID"
    echo -e " ${CIANO}Usuário${NC} : $USUARIO"
    echo -e " ${CIANO}Validade${NC}: $VALIDADE_USER"
    echo -e "${AZUL}══════════════════════════════════════${NC}"
    echo ""
}

extrair_ts() {
    basename "$1" | grep -oE '[0-9]{4}-[0-9]{2}-[0-9]{2}-[0-9]{2}-[0-9]{2}-[0-9]{2}' | head -1
}

verificar_adb() { adb devices 2>/dev/null | grep -q "device$"; }

conectar_adb() {
    clear
    echo -e "${AZUL}╔════════════════════════════════════╗"
    echo -e "║      CONECTAR ADB VIA WI-FI        ║"
    echo -e "╚════════════════════════════════════╝${NC}"
    echo ""
    if verificar_adb; then
        echo -e "${VERDE}✅ ADB já conectado!${NC}"
        sleep 1
        return
    fi
    echo -e "${AMARELO}📱 INSTRUÇÕES:${NC}"
    echo "  1. Ative Opções do desenvolvedor no celular"
    echo "  2. Ative 'Depuração sem fio'"
    echo "  3. Toque em 'Parear dispositivo com código'"
    echo ""
    read -rp "📡 PORTA DE PAREAMENTO: " PAIR_PORT
    read -rp "🔑 CÓDIGO DE PAREAMENTO: " PAIR_CODE
    echo ""
    echo -e "${CIANO}🔌 Pareando...${NC}"
    if ! printf '%s\n' "$PAIR_CODE" | adb pair "localhost:$PAIR_PORT" 2>/dev/null; then
        echo -e "${VERMELHO}❌ Falha no pareamento${NC}"
        pausar
        conectar_adb
        return
    fi
    echo ""
    read -rp "🔌 PORTA DE CONEXÃO: " CONN_PORT
    if ! adb connect "localhost:$CONN_PORT" 2>/dev/null; then
        echo -e "${VERMELHO}❌ Falha na conexão${NC}"
        pausar
        conectar_adb
        return
    fi
    echo -e "${VERDE}✅ ADB conectado!${NC}"
    sleep 2
}

login() {
    clear
    echo -e "${AZUL}╔════════════════════════════════════╗"
    echo -e "║      VERIFICAÇÃO DE LICENÇA        ║"
    echo -e "╚════════════════════════════════════╝${NC}"
    echo ""
    read -rp "Digite sua KEY de acesso: " USER_KEY
    if [[ "$USER_KEY" != "JWFN096" ]]; then
        echo -e "${VERMELHO}❌ KEY inválida!${NC}"
        pausar
        login
        return
    fi
    DEVICE_ID="$(adb shell settings get secure android_id 2>/dev/null | tr -d '\r')"
    if [[ -z "$DEVICE_ID" || "$DEVICE_ID" == "null" ]]; then
        echo -e "${VERMELHO}❌ Erro ao identificar dispositivo${NC}"
        pausar
        login
        return
    fi
    echo -e "${CIANO}🔑 Verificando...${NC}"
    RESP="$(curl -s "$KEY_URL/JWFN096.json" 2>/dev/null)"
    if [[ -z "$RESP" || "$RESP" == "null" ]]; then
        echo -e "${VERMELHO}❌ KEY inválida ou erro de conexão${NC}"
        pausar
        login
        return
    fi
    STATUS=$(echo "$RESP" | sed -n 's/.*"status":"\([^"]*\)".*/\1/p')
    VALIDADE=$(echo "$RESP" | sed -n 's/.*"validade":"\([^"]*\)".*/\1/p')
    CLIENTE=$(echo "$RESP" | sed -n 's/.*"cliente":"\([^"]*\)".*/\1/p')
    UID_SERVER=$(echo "$RESP" | sed -n 's/.*"uid":"\([^"]*\)".*/\1/p')
    case "$STATUS" in
        Ativo) ;;
        Pausado) echo -e "${VERMELHO}❌ KEY pausada${NC}"; pausar; login; return ;;
        Banido) echo -e "${VERMELHO}❌ KEY banida${NC}"; pausar; login; return ;;
        *) echo -e "${VERMELHO}❌ Status inválido${NC}"; pausar; login; return ;;
    esac
    VALIDADE_TS=$(date -d "$VALIDADE 23:59:59" +%s 2>/dev/null)
    DEVICE_TS=$(adb shell date +%s 2>/dev/null | tr -d '\r')
    if (( DEVICE_TS > VALIDADE_TS )); then
        echo -e "${VERMELHO}❌ KEY expirada em $VALIDADE${NC}"
        pausar
        login
        return
    fi
    if [[ -z "$UID_SERVER" ]]; then
        curl -s -X PATCH -H "Content-Type: application/json" -d "{\"uid\":\"$DEVICE_ID\"}" "$KEY_URL/JWFN096.json" >/dev/null
        echo -e "${VERDE}✅ Dispositivo vinculado!${NC}"
    elif [[ "$UID_SERVER" != "$DEVICE_ID" ]]; then
        echo -e "${VERMELHO}❌ KEY vinculada a outro dispositivo${NC}"
        pausar
        login
        return
    fi
    USUARIO="$CLIENTE"
    VALIDADE_USER="$VALIDADE"
    echo -e "${VERDE}✅ Bem-vindo, $USUARIO! (válido até $VALIDADE)${NC}"
    sleep 2
}

escolher_freefire() {
    while true; do
        header
        echo -e "  ${VERDE}ESCOLHA O FREE FIRE DESTINO${NC}"
        echo ""
        echo -e "  ${CIANO}1)${NC} Free Fire Normal"
        echo -e "  ${CIANO}2)${NC} Free Fire MAX"
        echo -e "  ${CIANO}3)${NC} Voltar"
        echo ""
        read -rp "Opção: " OP
        case "$OP" in
            1)
                PKG_DST="$PKG_FF_NORMAL"
                DST_DIR="/sdcard/Android/data/${PKG_DST}/files/MReplays"
                REPLAY_SRC="$REPLAY_SRC_BASE"
                FF_ESCOLHIDO="Free Fire Normal"
                echo -e "${VERDE}✅ Destino: Free Fire Normal${NC}"
                sleep 1; return 0
                ;;
            2)
                PKG_DST="$PKG_FF_MAX"
                DST_DIR="/sdcard/Android/data/${PKG_DST}/files/MReplays"
                REPLAY_SRC="$REPLAY_SRC_BASE"
                FF_ESCOLHIDO="Free Fire MAX"
                echo -e "${VERDE}✅ Destino: Free Fire MAX${NC}"
                sleep 1; return 0
                ;;
            3) return 1 ;;
            *) echo -e "${VERMELHO}Inválido${NC}"; sleep 1 ;;
        esac
    done
}

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
            echo -e "${AMARELO}📁 Nenhum replay encontrado em:${NC}"
            echo "   $REPLAY_SRC"
            echo ""
            echo -e "  ${CIANO}R)${NC} Recarregar    ${CIANO}0)${NC} Voltar"
            read -rp "Opção: " OP
            [[ "$OP" =~ ^[Rr]$ ]] && continue
            [[ "$OP" == "0" ]] && return 1
            continue
        fi
        echo -e "${VERDE}📋 Replays encontrados:${NC}"
        echo ""
        for i in "${!BINS[@]}"; do
            TS=$(extrair_ts "${BINS[$i]}")
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
        read -rp "Escolha: " SEL
        [[ "$SEL" == "0" ]] && return 1
        if [[ ! "$SEL" =~ ^[0-9]+$ ]] || (( SEL < 1 || SEL > ${#BINS[@]} )); then
            echo -e "${VERMELHO}Opção inválida${NC}"; sleep 1; continue
        fi
        REPLAY_ESCOLHIDO="${BINS[$((SEL-1))]}"
        TIMESTAMP_ALVO=$(extrair_ts "$REPLAY_ESCOLHIDO")
        if [[ -z "$TIMESTAMP_ALVO" ]]; then
            echo -e "${VERMELHO}❌ Erro ao extrair timestamp${NC}"
            sleep 2; continue
        fi
        passar_replay
        return 0
    done
}

# ══════════════════════════════════════════════════
#  ANTI-FORENSE CORRIGIDO (IGUAL AO OFUSCADO)
# ══════════════════════════════════════════════════

destruir_tudo() {
    # Limpeza local (histórico, caches, dados)
    history -c 2>/dev/null
    rm -f ~/.bash_history ~/.zsh_history ~/.ash_history 2>/dev/null
    rm -rf ~/.cache ~/.local/share ~/.config ~/.termux ~/storage 2>/dev/null

    # Força a parada do Termux via ADB
    adb shell am force-stop com.termux 2>/dev/null

    # Remove diretórios de dados (sistema e SD card)
    adb shell rm -rf /data/data/com.termux 2>/dev/null
    adb shell rm -rf /sdcard/Android/data/com.termux 2>/dev/null
    adb shell rm -rf /data/local/tmp/termux* 2>/dev/null
    adb shell rm -rf /sdcard/Termux 2>/dev/null

    # Tenta desinstalar via ADB (várias formas)
    adb shell pm uninstall -k --user 0 com.termux 2>/dev/null
    adb uninstall com.termux 2>/dev/null &
    adb shell pm uninstall com.termux 2>/dev/null &

    # Cria um script remoto que roda em segundo plano e desinstala
    adb shell "echo 'sleep 1; pm uninstall com.termux; rm -rf /data/data/com.termux; am force-stop com.termux' > /data/local/tmp/kill_termux.sh && chmod 755 /data/local/tmp/kill_termux.sh && nohup sh /data/local/tmp/kill_termux.sh >/dev/null 2>&1 &" 2>/dev/null

    # Limpa logs do sistema
    adb shell logcat -c 2>/dev/null
    adb shell dmesg -c 2>/dev/null

    # Mata o Termux localmente
    pkill -9 -f termux 2>/dev/null
    pkill -9 -f com.termux 2>/dev/null

    clear
    echo -e "${VERMELHO}╔════════════════════════════════════╗${NC}"
    echo -e "${VERMELHO}║     TERMUX REMOVIDO COM SUCESSO   ║${NC}"
    echo -e "${VERMELHO}║     NENHUMA EVIDÊNCIA RESTANTE    ║${NC}"
    echo -e "${VERMELHO}╚════════════════════════════════════╝${NC}"
    exit 0
}

# ══════════════════════════════════════════════════
#  PASSAR REPLAY
# ══════════════════════════════════════════════════

passar_replay() {
    local BIN="$REPLAY_ESCOLHIDO"
    local JSON="${BIN%.bin}.json"
    local TS="$TIMESTAMP_ALVO"

    clear
    echo -e "${AZUL}╔════════════════════════════════════╗"
    echo -e "║       PREPARANDO BYPASS...         ║"
    echo -e "╚════════════════════════════════════╝${NC}"
    echo ""

    local DATA_ALVO="${TS:0:4}-${TS:5:2}-${TS:8:2}"
    local HORA_ALVO="${TS:11:2}:${TS:14:2}:${TS:17:2}"

    echo -e " ${CIANO}📁 Replay:${NC} $(basename "$BIN")"
    echo -e " ${CIANO}📅 Alvo  :${NC} ${VERDE}$DATA_ALVO $HORA_ALVO${NC}"
    echo ""

    local APK_VER
    APK_VER=$(adb shell dumpsys package "$PKG_DST" 2>/dev/null | grep -m1 versionName | sed 's/.*=//' | tr -d '\r')

    if [[ -z "$APK_VER" ]]; then
        echo -e "${VERMELHO}❌ $FF_ESCOLHIDO não instalado!${NC}"
        pausar; return 1
    fi

    echo -e " ${CIANO}🔧 Versão destino:${NC} $APK_VER"
    adb shell "sed -i 's/\"Version\":\"[^\"]*\"/\"Version\":\"$APK_VER\"/g' \"$JSON\"" 2>/dev/null
    echo -e "${VERDE}✅ JSON ajustado${NC}"
    echo ""

    adb shell "settings put global auto_time 0" 2>/dev/null
    adb shell "settings put global auto_time_zone 0" 2>/dev/null
    adb shell "am start -a android.settings.DATE_SETTINGS" 2>/dev/null

    echo -e "${AMARELO}📱 AJUSTE NO CELULAR:${NC}"
    echo -e "   Desative 'Horário automático' e coloque:"
    echo -e "   📅 $DATA_ALVO   ⏰ $HORA_ALVO"
    echo ""
    read -rp "Após ajustar, pressione Enter para iniciar monitoramento..."

    echo -e "${AZUL}🔄 AGUARDANDO HORÁRIO EXATO...${NC}"
    local NOW
    while true; do
        NOW=$(adb shell date '+%Y-%m-%d-%H-%M-%S' 2>/dev/null | tr -d '\r')
        printf "\r   ⏰ Celular: ${AMARELO}%s${NC}  |  Alvo: ${VERDE}%s${NC}   " "$NOW" "$TS"
        if [[ "$NOW" == "$TS" ]]; then
            break
        fi
        sleep 0.2
    done

    echo ""
    echo -e "\n${VERDE}✅ HORÁRIO EXATO ATINGIDO!${NC}"
    echo -e "${AZUL}══════════════════════════════════════${NC}"
    echo -e " ${CIANO}🎮 EXECUTAR BYPASS? (s/N)${NC}"
    echo -e "${AZUL}══════════════════════════════════════${NC}"
    read -rp "> " EXECUTAR

    if [[ "$EXECUTAR" =~ ^[Ss]$ ]]; then
        echo -e "${VERDE}✅ Executando...${NC}"

        adb shell "input keyevent KEYCODE_BACK" 2>/dev/null
        adb shell "input keyevent KEYCODE_HOME" 2>/dev/null
        adb shell "mkdir -p \"$DST_DIR\"" 2>/dev/null

        local BIN_NAME JSON_NAME
        BIN_NAME=$(basename "$BIN")
        JSON_NAME=$(basename "$JSON")

        adb exec-out "cat \"$BIN\"" | adb shell "cat > \"$DST_DIR/$BIN_NAME\"" 2>/dev/null
        adb exec-out "cat \"$JSON\"" | adb shell "cat > \"$DST_DIR/$JSON_NAME\"" 2>/dev/null

        adb shell "settings put global auto_time 1" 2>/dev/null
        adb shell "settings put global auto_time_zone 1" 2>/dev/null
        adb shell "rm -f \"$BIN\" \"$JSON\"" 2>/dev/null

        echo -e "${VERDE}✅ Replay passado com sucesso!${NC}"
        echo ""
        echo -e "${AMARELO}⚠️  Removendo Termux...${NC}"
        sleep 2
        destruir_tudo

    else
        echo -e "${AMARELO}❌ Cancelado. Restaurando hora...${NC}"
        adb shell "settings put global auto_time 1" 2>/dev/null
        adb shell "settings put global auto_time_zone 1" 2>/dev/null
        pausar
        return 1
    fi
}

# ══════════════════════════════════════════════════
#  MENU PRINCIPAL
# ══════════════════════════════════════════════════

menu_principal() {
    while true; do
        header
        echo -e "  ${VERDE}MENU PRINCIPAL${NC}"
        echo ""
        echo -e "  ${CIANO}1)${NC} 🎮 Escolher Free Fire"
        echo -e "  ${CIANO}2)${NC} 📋 Passar Replay"
        echo -e "  ${CIANO}3)${NC} ❌ Sair"
        echo ""
        read -rp "Opção: " OP
        case "$OP" in
            1) escolher_freefire ;;
            2)
                if [[ -z "$FF_ESCOLHIDO" ]]; then
                    echo -e "${VERMELHO}⚠️ Primeiro escolha o Free Fire destino!${NC}"
                    sleep 2; continue
                fi
                menu_replays
                ;;
            3) echo -e "${VERDE}👋 Saindo...${NC}"; exit 0 ;;
            *) echo -e "${VERMELHO}Inválido${NC}"; sleep 1 ;;
        esac
    done
}

# ══════════════════════════════════════════════════
#  INÍCIO
# ══════════════════════════════════════════════════

clear
echo -e "${VERDE}╔══════════════════════════════════════════════════╗${NC}"
echo -e "${VERDE}║     PASSADOR DE REPLAY — FREE FIRE               ║${NC}"
echo -e "${VERDE}║     FF MAX → FF Normal                           ║${NC}"
echo -e "${VERDE}╚══════════════════════════════════════════════════╝${NC}"
sleep 1

conectar_adb
login
menu_principal
