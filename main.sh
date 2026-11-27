#!/bin/bash
 
mostrar_menu() {
    clear
    printf "Diagnóstico Integral de Rendimiento y Cuellos de Botella\n"
    printf "1) Obtener estadísticas\n"
    printf "2) Extraer top 10 procesos\n"
    printf "3) Identificar procesos activos\n"
    printf "4) Listar puertos\n"
    printf "5) Visualizar monitoreo\n"
    printf "6) Generar reporte\n"
    printf "7) Matar proceso\n"
    printf "8) Cambiar prioridad\n"
    printf "0) Salir\n"
}
 
while true; do
    mostrar_menu
    read -r -p "Seleccione una opción: " opcion
 
    case "$opcion" in
        1) obtener_estadistica ;;
        2) extraer_proceso ;;
        3) identificar_proceso ;;
        4) listar_puertos ;;
        5) visualizar_monitoreo ;;
        6) generar_reporte ;;
        7) matar_proceso ;;
        8) cambiar_prioridad ;;
        0) echo "Hasta luego."; exit 0 ;;
        *) echo "Opción no válida."; read -r -p "Enter para continuar..." ;;
    esac
done