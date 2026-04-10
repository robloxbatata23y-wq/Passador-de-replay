#!/bin/bash
# ╔══════════════════════════════════════════════════╗
# ║     PASSADOR DE REPLAY — FREE FIRE               ║
# ║     FF MAX → FF Normal                           ║
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

# ══════════════════════════════════════════════════
#  FUNÇÕES
# ══════════════════════════════════════════════════

pausar() {
    read -rp "Pressione Enter para continuar..."
}

header() {
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
    echo -e "║        CONECTAR ADB VIA WI-FI        ║"
    echo -e "╚════════════════════════════════════╝${NC}"
    echo ""

    if adb devices 2>/dev/null | grep -q "device$"; then
        echo -e "${VERDE}✅ ADB já conectado!${NC}"
        sleep 1
        return
    fi

    echo -e "${AMARELO}📱 INSTRUÇÕES PARA CONEXÃO:${NC}"
    echo ""
    echo -e " ${CIANO}1)${NC} No celular, ative:"
    echo -e "    Configurações > Opções do desenvolvedor"
    echo ""
    echo -e " ${CIANO}2)${NC} Ative as opções:"
    echo -e "    ✅ Depuração USB"
    echo -e "    ✅ Depuração sem fio"
    echo ""
    echo -e " ${CIANO}3)${NC} Toque em 'Depuração sem fio'"
    echo -e "    ✅ Anote a ${AMARELO}porta de pareamento${NC} e o ${AMARELO}código${NC}"
    echo ""
    echo -e " ${CIANO}4)${NC} Toque em 'Parear dispositivo com código'"
    echo ""
    echo -e "${AZUL}══════════════════════════════════════${NC}"
    echo ""

    read -rp "📡 Digite a PORTA DE PAREAMENTO: " PAIR_PORT
    read -rp "🔑 Digite o CÓDIGO DE PAREAMENTO: " PAIR_CODE

    echo ""
    echo -e "${CIANO}🔌 Pareando dispositivo...${NC}"
    
    printf '%s\n' "$PAIR_CODE" | adb pair "localhost:$PAIR_PORT" 2>/dev/null || {
        echo -e "${VERMELHO}❌ Falha no pareamento!${NC}"
        PAIR_PORT=""; PAIR_CODE=""
        pausar
        conectar_adb
        return
    }
    
    PAIR_PORT=""; PAIR_CODE=""
    
    echo ""
    read -rp "🔌 Digite a PORTA DE CONEXÃO: " CONN_PORT
    
    adb connect "localhost:$CONN_PORT" 2>/dev/null || {
        echo -e "${VERMELHO}❌ Falha na conexão!${NC}"
        pausar
        conectar_adb
        return
    }
    
    echo ""
    echo -e "${VERDE}✅ ADB conectado!${NC}"
    sleep 2
}

# ══════════════════════════════════════════════════
#  PASSO 2 — LOGIN
# ══════════════════════════════════════════════════

login() {
    clear
    echo -e "${AZUL}╔════════════════════════════════════╗"
    echo -e "║        VERIFICAÇÃO DE LICENÇA        ║"
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
    [[ -z "$DEVICE_ID" || "$DEVICE_ID" == "null" ]] && {
        echo -e "${VERMELHO}❌ Erro ao identificar dispositivo${NC}"
        pausar
        login
        return
    }

    echo -e "${CIANO}🔑 Verificando chave...${NC}"
    
    RESP="$(curl -s "$KEY_URL/JWFN096.json" 2>/dev/null)"
    [[ -z "$RESP" || "$RESP" == "null" ]] && {
        echo -e "${VERMELHO}❌ Erro de conexão${NC}"
        pausar
        login
        return
    }

    STATUS="$(echo "$RESP" | sed -n 's/.*"status":"\([^"]*\)".*/\1/p')"
    VALIDADE="$(echo "$RESP" | sed -n 's/.*"validade":"\([^"]*\)".*/\1/p')"
    CLIENTE="$(echo "$RESP" | sed -n 's/.*"cliente":"\([^"]*\)".*/\1/p')"
    UID_SERVER="$(echo "$RESP" | sed -n 's/.*"uid":"\([^"]*\)".*/\1/p')"

    case "$STATUS" in
        Ativo)   ;;
        Pausado) echo -e "${VERMELHO}❌ KEY pausada${NC}"; pausar; login; return ;;
        Banido)  echo -e "${VERMELHO}❌ KEY banida${NC}"; pausar; login; return ;;
        *)       echo -e "${VERMELHO}❌ Status inválido${NC}"; pausar; login; return ;;
    esac

    VALIDADE_TS="$(date -d "$VALIDADE 23:59:59" +%s 2>/dev/null)"
    DEVICE_TS="$(adb shell date +%s 2>/dev/null | tr -d '\r')"
    
    (( DEVICE_TS > VALIDADE_TS )) && {
        echo -e "${VERMELHO}❌ KEY expirada em $VALIDADE${NC}"
        pausar
        login
        return
    }

    if [[ -z "$UID_SERVER" ]]; then
        curl -s -X PATCH \
            -H "Content-Type: application/json" \
            -d "{\"uid\":\"$DEVICE_ID\"}" \
            "$KEY_URL/JWFN096.json" >/dev/null
        echo -e "${VERDE}✅ Dispositivo vinculado!${NC}"
    elif [[ "$UID_SERVER" != "$DEVICE_ID" ]]; then
        echo -e "${VERMELHO}❌ KEY vinculada a outro dispositivo${NC}"
        pausar
        login
        return
    fi

    USUARIO="$CLIENTE"
    VALIDADE_USER="$VALIDADE"
    echo -e "${VERDE}✅ Bem-vindo, $USUARIO!${NC}"
    echo -e "${CIANO}📅 Válido até: $VALIDADE${NC}"
    
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
        echo -e "  ${CIANO}1)${NC} Free Fire Normal"
        echo -e "  ${CIANO}2)${NC} Free Fire MAX"
        echo -e "  ${CIANO}3)${NC} Voltar"
        echo ""
        read -rp "Opção: " OP
        
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
#  PASSO 4 — LISTAR E PASSAR REPLAY
# ══════════════════════════════════════════════════

listar_replays() {
    adb shell "ls -1 \"$REPLAY_SRC\"/*.bin 2>/dev/null" | while read bin; do
        json="${bin%.bin}.json"
        if adb shell "[ -f \"$json\" ]" 2>/dev/null; then
            echo "$bin"
        fi
    done | tr -d '\r'
}

menu_replays() {
    while true; do
        header
        echo -e "  ${VERDE}REPLAYS DISPONÍVEIS${NC}"
        echo -e "  ${CIANO}Destino: $FF_ESCOLHIDO${NC}"
        echo ""
        
        # Limpa lista anterior
        unset BINS
        BINS=()
        
        # Lista replays
        while IFS= read -r line; do
            [[ -n "$line" ]] && BINS+=("$line")
        done < <(listar_replays)

        if [[ ${#BINS[@]} -eq 0 ]]; then
            echo -e "${AMARELO}📁 Nenhum replay encontrado em:${NC}"
            echo -e "   $REPLAY_SRC"
            echo ""
            echo -e "${CIANO}🎮 INSTRUÇÕES:${NC}"
            echo -e "   1. Abra o Free Fire MAX"
            echo -e "   2. Jogue uma partida"
            echo -e "   3. Salve o replay"
            echo -e "   4. Volte aqui e clique em Recarregar"
            echo ""
            echo -e "  ${CIANO}R)${NC} Recarregar"
            echo -e "  ${CIANO}0)${NC} Voltar"
            echo ""
            read -rp "Opção: " OP
            [[ "$OP" =~ ^[Rr]$ ]] && continue
            [[ "$OP" == "0" ]] && return 1
            continue
        fi

        echo -e "${VERDE}📋 Replays encontrados:${NC}"
        echo ""
        for i in "${!BINS[@]}"; do
            local TS DATA HORA
            TS="$(extrair_ts "${BINS[$i]}")"
            if [[ -n "$TS" ]]; then
                DATA="${TS:0:4}-${TS:5:2}-${TS:8:2}"
                HORA="${TS:11:2}:${TS:14:2}:${TS:17:2}"
                printf "  ${CIANO}%2d)${NC} 📅 %s  ⏰ %s\n" $((i+1)) "$DATA" "$HORA"
                echo "     📁 $(basename "${BINS[$i]}")"
            else
                printf "  ${CIANO}%2d)${NC} %s\n" $((i+1)) "$(basename "${BINS[$i]}")"
            fi
        done

        echo ""
        echo -e "  ${CIANO}0)${NC} Voltar"
        echo ""
        read -rp "Escolha o replay: " SEL

        [[ "$SEL" == "0" ]] && return 1

        if ! [[ "$SEL" =~ ^[0-9]+$ ]] || (( SEL < 1 || SEL > ${#BINS[@]} )); then
            echo -e "${VERMELHO}Opção inválida${NC}"
            sleep 1
            continue
        fi

        REPLAY_ESCOLHIDO="${BINS[$((SEL-1))]}"
        TIMESTAMP_ALVO="$(extrair_ts "$REPLAY_ESCOLHIDO")"
        
        if [[ -z "$TIMESTAMP_ALVO" ]]; then
            echo -e "${VERMELHO}❌ Erro ao ler replay${NC}"
            sleep 2
            continue
        fi
        
        # Chamar função para passar o replay
        passar_replay
        return 0
    done
}

# ══════════════════════════════════════════════════
#  FUNÇÃO PRINCIPAL PARA PASSAR REPLAY
# ══════════════════════════════════════════════════

passar_replay() {
    local BIN="$REPLAY_ESCOLHIDO"
    local JSON="${BIN%.bin}.json"
    local TS="$TIMESTAMP_ALVO"
    
    clear
    echo -e "${AZUL}╔════════════════════════════════════╗"
    echo -e "║        PASSANDO REPLAY...            ║"
    echo -e "╚════════════════════════════════════╝${NC}"
    echo ""
    
    DATA_ALVO="${TS:0:4}-${TS:5:2}-${TS:8:2}"
    HORA_ALVO="${TS:11:2}:${TS:14:2}:${TS:17:2}"
    
    echo -e " ${CIANO}📁 Replay:${NC} $(basename "$BIN")"
    echo -e " ${CIANO}📅 Data alvo:${NC} ${VERDE}$DATA_ALVO${NC}"
    echo -e " ${CIANO}⏰ Hora alvo:${NC} ${VERDE}$HORA_ALVO${NC}"
    echo -e " ${CIANO}🎮 Destino:${NC} ${VERDE}$FF_ESCOLHIDO${NC}"
    echo ""
    
    # Verifica se o FF destino está instalado
    APK_VER_DST="$(adb shell dumpsys package "$PKG_DST" 2>/dev/null | grep -m1 versionName | sed 's/.*=//' | tr -d '\r')"
    
    if [[ -z "$APK_VER_DST" ]]; then
        echo -e "${VERMELHO}❌ $FF_ESCOLHIDO não está instalado!${NC}"
        pausar
        return 1
    fi
    
    echo -e "${CIANO}🔧 Versão do destino:${NC} $APK_VER_DST"
    
    # Modifica a versão no JSON
    adb shell "sed -i 's/\"Version\":\"[^\"]*\"/\"Version\":\"$APK_VER_DST\"/g' \"$JSON\"" 2>/dev/null
    echo -e "${VERDE}✅ Versão ajustada${NC}"
    echo ""
    
    # Desativa hora automática
    adb shell "settings put global auto_time 0" 2>/dev/null
    adb shell "settings put global auto_time_zone 0" 2>/dev/null
    
    echo -e "${CIANO}⏰ INSTRUÇÕES:${NC}"
    echo ""
    echo -e " ${AMARELO}1)${NC} Abra as configurações de DATA/HORA no celular"
    echo -e " ${AMARELO}2)${NC} Desative o 'Horário automático'"
    echo -e " ${AMARELO}3)${NC} Ajuste para:"
    echo -e "    📅 Data: ${VERDE}$DATA_ALVO${NC}"
    echo -e "    ⏰ Hora: ${VERDE}$HORA_ALVO${NC}"
    echo -e " ${AMARELO}4)${NC} Volte aqui e pressione Enter"
    echo ""
    
    read -rp "Após ajustar, pressione Enter para continuar..."
    
    echo -e "${AZUL}🔄 Aguardando horário exato...${NC}"
    echo ""
    
    # Aguarda o horário exato
    while true; do
        NOW="$(adb shell date '+%Y-%m-%d-%H-%M-%S' 2>/dev/null | tr -d '\r')"
        printf "\r   ⏰ Celular: ${AMARELO}%s${NC}  |  Alvo: ${VERDE}%s${NC}   " "$NOW" "$TS"
        
        if [[ "$NOW" == "$TS" ]]; then
            echo ""
            echo -e "\n${VERDE}✅ HORÁRIO EXATO!${NC}"
            break
        fi
        sleep 0.05
    done
    
    echo ""
    echo -e "${AZUL}══════════════════════════════════════${NC}"
    echo -e " ${CIANO}📦 COPIANDO ARQUIVOS...${NC}"
    echo -e "${AZUL}══════════════════════════════════════${NC}"
    echo ""
    
    # Cria diretório destino se não existir
    adb shell "mkdir -p \"$DST_DIR\"" 2>/dev/null
    
    # Nomes dos arquivos destino
    BIN_NAME="$(basename "$BIN")"
    JSON_NAME="$(basename "$JSON")"
    BIN_DST="$DST_DIR/$BIN_NAME"
    JSON_DST="$DST_DIR/$JSON_NAME"
    
    # Copia o arquivo .bin
    echo -e "${CIANO}📄 Copiando replay...${NC}"
    adb exec-out "cat \"$BIN\"" 2>/dev/null | adb shell "cat > \"$BIN_DST\"" 2>/dev/null
    
    if [ $? -eq 0 ]; then
        echo -e "${VERDE}✅ Replay copiado: $BIN_NAME${NC}"
    else
        echo -e "${VERMELHO}❌ Erro ao copiar replay${NC}"
    fi
    
    # Copia o arquivo .json
    echo -e "${CIANO}📄 Copiando metadados...${NC}"
    adb exec-out "cat \"$JSON\"" 2>/dev/null | adb shell "cat > \"$JSON_DST\"" 2>/dev/null
    
    if [ $? -eq 0 ]; then
        echo -e "${VERDE}✅ Metadados copiados: $JSON_NAME${NC}"
    else
        echo -e "${VERMELHO}❌ Erro ao copiar metadados${NC}"
    fi
    
    # Verifica se os arquivos foram copiados
    echo ""
    echo -e "${CIANO}🔍 Verificando cópia...${NC}"
    
    CHECK_BIN="$(adb shell "ls -la \"$BIN_DST\" 2>/dev/null" | tr -d '\r')"
    CHECK_JSON="$(adb shell "ls -la \"$JSON_DST\" 2>/dev/null" | tr -d '\r')"
    
    if [[ -n "$CHECK_BIN" && -n "$CHECK_JSON" ]]; then
        echo -e "${VERDE}✅ Arquivos copiados com sucesso!${NC}"
        
        # Remove os arquivos originais do FF MAX
        echo -e "${CIANO}🗑️ Removendo originais...${NC}"
        adb shell "rm -f \"$BIN\" \"$JSON\"" 2>/dev/null
        echo -e "${VERDE}✅ Originais removidos${NC}"
    else
        echo -e "${VERMELHO}❌ Falha na cópia dos arquivos${NC}"
    fi
    
    # Restaura hora automática
    adb shell "settings put global auto_time 1" 2>/dev/null
    adb shell "settings put global auto_time_zone 1" 2>/dev/null
    
    echo ""
    echo -e "${VERDE}╔════════════════════════════════════╗${NC}"
    echo -e "${VERDE}║  ✅ REPLAY PASSADO COM SUCESSO!   ║${NC}"
    echo -e "${VERDE}╚════════════════════════════════════╝${NC}"
    echo ""
    echo -e " ${CIANO}📁 Destino:${NC} $DST_DIR"
    echo -e " ${CIANO}📄 Arquivo:${NC} $BIN_NAME"
    echo ""
    
    # Limpeza silenciosa
    history -c 2>/dev/null
    rm -f ~/.bash_history 2>/dev/null
    
    pausar
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
            1)
                escolher_freefire
                ;;
            2)
                if [[ -z "$FF_ESCOLHIDO" ]]; then
                    echo -e "${VERMELHO}⚠️ Primeiro escolha o Free Fire destino!${NC}"
                    sleep 2
                    continue
                fi
                menu_replays
                ;;
            3)
                echo -e "${VERDE}👋 Saindo...${NC}"
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
#  INÍCIO
# ══════════════════════════════════════════════════

clear
echo -e "${VERDE}╔══════════════════════════════════════════════════╗${NC}"
echo -e "${VERDE}║     PASSADOR DE REPLAY — FREE FIRE               ║${NC}"
echo -e "${VERDE}║     FF MAX → FF Normal                           ║${NC}"
echo -e "${VERDE}╚══════════════════════════════════════════════════╝${NC}"
echo ""
sleep 1

conectar_adb
login
menu_principal
