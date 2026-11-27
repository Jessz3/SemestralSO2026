#!/bin/bash
 
# En Debian, /usr/sbin (donde queda iotop) no está en el PATH de un usuario normal.
case ":$PATH:" in
    *:/usr/sbin:*) ;;
    *) PATH="$PATH:/usr/sbin" ;;
esac
 
# =====================================================================
# FUNCIÓN: instalar_dependencias
# Instala solo los paquetes que faltan para que funcionen todas las
# funciones de esta librería (Debian, Ubuntu y derivados).
# =====================================================================
instalar_dependencias() {
    echo "=============== INSTALACIÓN DE DEPENDENCIAS ==============="
    echo
 
    if ! command -v apt-get &> /dev/null; then
        echo "Error: este instalador requiere apt-get (Debian/Ubuntu)."
        return 1
    fi
 
    # Formato -> comando:paquete
    local dependencias=(
        "vmstat:procps"         # también aporta ps, free, top y uptime
        "iotop:iotop-c"         # actividad de disco por proceso
        "ss:iproute2"           # puertos en escucha
        "awk:gawk"              # procesamiento de texto
        "less:less"             # ver el reporte
        "clear:ncurses-bin"     # limpiar pantalla
        "hostname:hostname"     # nombre del equipo
        "chrt:util-linux"       # política y prioridad en tiempo real
        "renice:bsdutils"       # cambiar el valor nice
        "nproc:coreutils"       # nproc, sort, head, cut, wc, etc.
    )
 
    local dep comando paquete
    local faltantes=()
 
    for dep in "${dependencias[@]}"; do
        comando="${dep%%:*}"
        paquete="${dep##*:}"
        if command -v "$comando" &> /dev/null; then
            echo "  [OK]    $comando"
        else
            echo "  [FALTA] $comando (paquete: $paquete)"
            faltantes+=("$paquete")
        fi
    done
    echo
 
    if [ "${#faltantes[@]}" -eq 0 ]; then
        echo "Todas las dependencias ya están instaladas."
        return 0
    fi
 
    # Como root no hace falta sudo
    local como_root=()
    if [ "$(id -u)" -ne 0 ]; then
        if ! command -v sudo &> /dev/null; then
            echo "Error: 'sudo' no está disponible. Ejecute el menú como root."
            return 1
        fi
        como_root=(sudo)
    fi
 
    echo "Se instalarán: ${faltantes[*]}"
    echo
 
    if ! "${como_root[@]}" apt-get update; then
        echo "Aviso: falló 'apt-get update'; se intentará instalar de todos modos."
    fi
 
    local errores=0
    for paquete in "${faltantes[@]}"; do
        if "${como_root[@]}" apt-get install -y "$paquete"; then
            continue
        fi
        # Versiones antiguas no tienen iotop-c: usar el iotop clásico
        if [ "$paquete" = "iotop-c" ] && "${como_root[@]}" apt-get install -y iotop; then
            continue
        fi
        echo "Error: no se pudo instalar '$paquete'."
        errores=$((errores + 1))
    done
 
    # Olvidar las rutas de comandos que bash tenga en caché
    hash -r
 
    echo
    if [ "$errores" -gt 0 ]; then
        echo "Instalación incompleta: $errores paquete(s) con error."
        return 1
    fi
    echo "Dependencias instaladas correctamente."
}
 
obtener_estadistica() {
    echo "=================================================================="
    echo " 1. ESTADÍSTICAS DE MEMORIA VIRTUAL, PAGINACIÓN, INTERRUPCIONES Y CPU"
    echo "=================================================================="
    echo "Muestreo: 5 intervalos de 1 segundo (la 1ra fila es promedio histórico)"
    echo ""
 
    # Verifica si vmstat está instalado 
    if ! command -v vmstat &> /dev/null; then
        echo "Error: 'vmstat' no está instalado. Instálalo con: sudo apt install procps"
        return 1
    fi
 
    # Ejecuta vmstat cada 1 segundo, 5 veces
    vmstat 1 5
 
    echo ""
    echo "------------------------------------------------------------------"
    echo " Leyenda de Columnas:"
    echo "  • Procesos / Bloqueo CPU : r = en espera de CPU | b = bloqueados (I/O)"
    echo "  • Memoria Virtual (KB)   : swpd = swap usada | free = libre | buff/cache = búfer/caché"
    echo "  • Paginación (KB/s)      : si = lectura desde swap | so = escritura hacia swap"
    echo "  • Interrupciones (/s)    : in = interrupciones | cs = cambios de contexto"
    echo "  • Tiempo de CPU (%)      : us = usuario | sy = sistema | id = inactivo | wa = espera I/O"
    echo "=================================================================="
    echo ""
}
 
 
extraer_proceso() {
    echo "Top 10 de procesos por consumo de CPU y memoria RAM"
    ps -eo pid,comm,%cpu,%mem --sort=-%cpu,-%mem | head -n 11
}
 
 
identificar_proceso() {
    echo "=================================================================="
    echo "       3. PROCESOS CON MAYOR ACTIVIDAD DE LECTURA/ESCRITURA"
    echo "=================================================================="
    echo "Monitoreo: 5 intervalos de 1 segundo"
    echo ""
 
    # Verifica si iotop está instalado
    if ! command -v iotop &> /dev/null; then
        echo "Error: 'iotop' no está instalado."
        echo "Instálalo con: sudo apt install iotop-c"
        return 1
    fi
 
    # Verifica permisos de administrador
    if ! sudo -v; then
        echo "Error: Se requieren permisos de administrador."
        return 1
    fi
 
    echo "Identificando procesos que realizan operaciones de disco..."
    echo ""
 
    # Monitorea únicamente procesos que realizan I/O
    sudo iotop -o -P -b -n 5 -d 1
 
    echo ""
    echo "------------------------------------------------------------------"
    echo " Leyenda:"
    echo "  DISK READ  : Velocidad de lectura desde el disco."
    echo "  DISK WRITE : Velocidad de escritura hacia el disco."
    echo "  IO%        : Porcentaje de tiempo dedicado a operaciones I/O."
    echo "  COMMAND    : Nombre del proceso."
    echo "  PID        : Identificador del proceso."
    echo "------------------------------------------------------------------"
    echo ""
}
 
# =====================================================================
# FUNCIÓN 4: listar_puertos
# Lista todos los puertos TCP/UDP en escucha con el PID y el nombre
# del proceso asociado.
# =====================================================================
listar_puertos() {
    echo "=============== PUERTOS TCP/UDP EN ESCUCHA ==============="
    echo
    if [ "$EUID" -ne 0 ]; then
        echo "Aviso: sin sudo solo se ve el PID/nombre de TUS procesos."
        echo "       Para verlos todos: sudo ./$(basename "$0")"
        echo
    fi
    printf "%-6s %-30s %-7s %-8s %s\n" "PROTO" "IP_LOCAL" "PUERTO" "PID" "PROCESO"
    ss -tulnpH | awk '{
        proto = $1; direccion = $5; info = $7
        n = split(direccion, partes, ":")
        puerto = partes[n]
        ip = substr(direccion, 1, length(direccion) - length(puerto) - 1)
        pid = "-"; nombre = "-"
        if (match(info, /pid=[0-9]+/)) pid = substr(info, RSTART + 4, RLENGTH - 4)
        if (match(info, /\("[^"]+"/))  nombre = substr(info, RSTART + 2, RLENGTH - 3)
        printf "%-6s %-30s %-7s %-8s %s\n", proto, ip, puerto, pid, nombre
    }' | sort -k1,1 -k3,3n
    echo
    echo "Total de puertos en escucha: $(ss -tulnH | wc -l)"
    echo
}
 
visualizar_monitoreo() {
    echo "========================================================="
    echo "Monitor en tiempo real. Presiona q para volver al menú."
    echo "========================================================="
    # top muestra el uso de CPU, memoria y los procesos activos.
    # -d 1 actualiza la pantalla cada segundo.
    # -o %CPU ordena los procesos por uso de CPU.
    # Presiona q para cerrar el monitor y volver al menú.
    top -d 1 -o %CPU
}
 
# =====================================================================
# FUNCIÓN 6: generar_reporte
# Genera diagnostico.txt llamando a las funciones 1 a 5, de modo que
# el reporte contiene exactamente lo mismo que muestra el menú.
# =====================================================================
generar_reporte() {
    local reporte
    reporte="$(cd "$(dirname "$0")" && pwd)/diagnostico.txt"

    echo "Generando reporte (unos 10 segundos)..."
    echo "Si se solicita, ingrese su contraseña de sudo (la usa el punto 3)."

    {
        echo "##################################################################"
        echo "    DIAGNÓSTICO INTEGRAL DE RENDIMIENTO Y CUELLOS DE BOTELLA"
        echo "##################################################################"
        echo "Fecha:        $(date '+%Y-%m-%d %H:%M:%S')"
        echo "Equipo:       $(hostname)"
        echo "Usuario:      $(whoami)"
        echo "Kernel:       $(uname -r)"
        echo "Encendido:    $(uptime -p)"
        echo "Carga media:  $(cut -d' ' -f1-3 /proc/loadavg)  (1, 5 y 15 min)"
        echo "Núcleos CPU:  $(nproc)"
        echo ""

        # Punto 1
        obtener_estadistica
        echo ""

        # Punto 2
        echo "=================================================================="
        echo "             2. TOP 10 PROCESOS POR CPU Y MEMORIA RAM"
        echo "=================================================================="
        extraer_proceso
        echo ""

        # Punto 3
        identificar_proceso
        echo ""

        # Punto 4
        listar_puertos
        echo ""

        # Punto 5: visualizar_monitoreo abre top interactivo, que no se puede
        # guardar en un archivo. Se usa el mismo top (-o %CPU) en modo batch.
        echo "=================================================================="
        echo "        5. MONITOR (instantánea de top ordenado por CPU)"
        echo "=================================================================="
        top -b -n 1 -o %CPU -w 512 | head -n 20
        echo ""

        echo "======================== FIN DEL REPORTE ========================="
    } > "$reporte" 2>&1

    echo ""
    echo "Reporte generado: $reporte ($(wc -l < "$reporte") líneas)"
    echo ""
    read -r -p "¿Desea ver el reporte ahora? (s/n): " ver
    if [[ "$ver" =~ ^[sS]$ ]]; then
        less "$reporte"
    fi
}

matar_proceso() {
    read -rp "Escriba el PID a matar: " pid
    # 1. Validar que el PID sea numérico y que el proceso realmente exista
    if [[ ! "$pid" =~ ^[0-9]+$ ]] || [ ! -d "/proc/$pid" ]; then
        echo "Error: Inserte un PID numérico válido y activo."
        return 1
    fi
    # 2. Evitar matar procesos críticos del sistema o la propia terminal
    if [ "$pid" -eq 1 ] || [ "$pid" -eq "$$" ]; then
        echo "Error: Por seguridad, no se permite matar el proceso principal (PID 1) ni la terminal actual."
        return 1
    fi
    # 3. Verificar permisos (si no es root ni dueño del proceso)
    local proc_name proc_uid current_uid
    proc_name=$(ps -p "$pid" -o comm=)
    proc_uid=$(ps -p "$pid" -o uid= | tr -d ' ')
    current_uid=$(id -u)
    if [ "$current_uid" -ne 0 ] && [ "$current_uid" -ne "$proc_uid" ]; then
        echo "Error: No tiene permisos para matar el proceso '$proc_name' (PID: $pid)."
        return 1
    fi
    # 4. Mostrar información del proceso y pedir confirmación
    echo "Proceso encontrado: $proc_name (PID: $pid)"
    read -rp "¿Está seguro de que desea terminar este proceso? (s/N): " confirm
    if [[ ! "$confirm" =~ ^[SsYy]$ ]]; then
        echo "Operación cancelada."
        return 0
    fi
    # 5. Elegir señal (normal o forzada)
    read -rp "¿Quiere forzar kill con -9? (s/N): " force
    if [[ "$force" =~ ^[SsYy]$ ]]; then
        kill -9 "$pid" 2>/dev/null && echo "Proceso $proc_name (PID $pid) terminado forzadamente (SIGKILL)."
    else
        kill "$pid" 2>/dev/null && echo "Señal de terminación (SIGTERM) enviada a $proc_name (PID $pid)."
    fi
}
 
cambiar_prioridad() {
    read -rp "Ingrese el PID del proceso que desea modificar: " pid
    # 1. Validar que el PID exista
    if [[ ! "$pid" =~ ^[0-9]+$ ]] || [ ! -d "/proc/$pid" ]; then
        echo "Error: El PID $pid no existe."
        return 1
    fi
    # Obtener información del proceso
    local proc_name proc_uid current_uid policy current_ni current_rt
    proc_name=$(ps -p "$pid" -o comm=)
    proc_uid=$(ps -p "$pid" -o uid= | tr -d ' ')
    current_uid=$(id -u)
    policy=$(chrt -p "$pid" 2>/dev/null | awk -F': ' '/scheduling policy/{print $2}')
    current_ni=$(ps -p "$pid" -o ni= | tr -d ' ')
    current_rt=$(chrt -p "$pid" 2>/dev/null | awk -F': ' '/scheduling priority/{print $2}')
    echo "----------------------------------------"
    echo "Proceso: $proc_name (PID: $pid)"
    echo "Política: $policy | Nice actual: $current_ni | Prioridad RT: $current_rt"
    echo "----------------------------------------"
    # 2. Verificar propiedad del proceso o permisos de root
    if [ "$current_uid" -ne 0 ] && [ "$current_uid" -ne "$proc_uid" ]; then
        echo "Error: No puede modificar el PID $pid porque no es el propietario (ejecute con sudo)."
        return 1
    fi
    # 3. Determinar límites y aplicar el cambio según la política
    case "$policy" in
        SCHED_OTHER|SCHED_BATCH)
            local min_allowed=0 max_allowed=19
            if [ "$current_uid" -eq 0 ]; then
                min_allowed=-20
                echo "Valores de Nice permitidos: -20 a 19 (Menor valor = mayor prioridad)"
            else
                local max_nice_limit
                max_nice_limit=$(ulimit -e)
                if [[ "$max_nice_limit" =~ ^[0-9]+$ ]] && [ "$max_nice_limit" -gt 0 ]; then
                    min_allowed=$((20 - max_nice_limit))
                else
                    min_allowed=$current_ni
                fi
                if [ "$min_allowed" -ge 19 ]; then
                    echo "Aviso: No se puede reducir más la prioridad; el proceso ya está en el mínimo (19)."
                    return 0
                fi
                echo "Valores de Nice permitidos: $min_allowed a 19"
                echo "(Como usuario sin privilegios de root, solo puede aumentar el valor nice / reducir la prioridad)"
            fi
            read -rp "Ingrese el nuevo valor de Nice ($min_allowed a $max_allowed): " nuevo_ni
            if [[ ! "$nuevo_ni" =~ ^-?[0-9]+$ ]] || [ "$nuevo_ni" -lt "$min_allowed" ] || [ "$nuevo_ni" -gt "$max_allowed" ]; then
                echo "Error: Valor fuera del rango permitido ($min_allowed a $max_allowed)."
                return 1
            fi
            renice -n "$nuevo_ni" -p "$pid" >/dev/null && echo "Prioridad actualizada. Nuevo Nice de $proc_name (PID $pid): $nuevo_ni"
            ;;
        SCHED_IDLE)
            echo "Información: El proceso usa SCHED_IDLE (la prioridad en segundo plano más baja posible)."
            if [ "$current_uid" -eq 0 ]; then
                read -rp "¿Desea cambiarlo a política normal SCHED_OTHER con Nice 0? (s/N): " resp
                if [[ "$resp" =~ ^[SsYy]$ ]]; then
                    chrt -o -p 0 "$pid" && echo "Política cambiada a SCHED_OTHER (Nice 0)."
                fi
            else
                echo "Error: No se puede modificar la prioridad de SCHED_IDLE sin permisos de root."
                return 1
            fi
            ;;
        SCHED_FIFO|SCHED_RR)
            local rt_limit max_rt=0
            rt_limit=$(ulimit -r)
            if [ "$current_uid" -eq 0 ]; then
                max_rt=99
            elif [[ "$rt_limit" =~ ^[0-9]+$ ]] && [ "$rt_limit" -gt 0 ]; then
                max_rt=$rt_limit
            else
                echo "Error: Los procesos en tiempo real requieren permisos de root o privilegios RTPRIO."
                return 1
            fi
            echo "Prioridades en tiempo real permitidas: 1 a $max_rt (Mayor valor = mayor prioridad)"
            read -rp "Ingrese la nueva prioridad RT (1 a $max_rt): " nuevo_rt
            if [[ ! "$nuevo_rt" =~ ^[0-9]+$ ]] || [ "$nuevo_rt" -lt 1 ] || [ "$nuevo_rt" -gt "$max_rt" ]; then
                echo "Error: Valor fuera del rango permitido (1 a $max_rt)."
                return 1
            fi
            local flag="-f"
            [ "$policy" = "SCHED_RR" ] && flag="-r"
            chrt "$flag" -p "$nuevo_rt" "$pid" && echo "Prioridad RT actualizada a $nuevo_rt para $proc_name (PID $pid)."
            ;;
        *)
            echo "Aviso: Política de planificación desconocida o especial ($policy)."
            ;;
    esac
}
