---
description: lineamientos para creacion de estrategias
---

# Lineamientos y Reglas para la Creación de Estrategias

Este documento define las reglas de diseño, arquitectura y codificación obligatorias para la creación y sincronización de estrategias de trading en Pine Script y MetaTrader 5 (MQL5) dentro de este espacio de trabajo.

---

## 1. Reglas Generales de Programación y Arquitectura

- **Nomenclatura**: Utilizar siempre la convención **camelCase** para el nombramiento de variables locales y funciones (ej. `sessionStartBar`, `currentDayId`).
- **Configuraciones por Símbolo**:
  - Declarar variables globales para los parámetros configurables de la estrategia (ej. Take Profit, Stop Loss, multiplicadores).
  - Encapsular la reasignación de parámetros dentro de un bloque condicional `if` específico para cada instrumento (ej. `if syminfo.tickerid == "XAUUSD"` o `if _Symbol == "EURUSD"`), asegurando que los valores globales se adapten dinámicamente al activo actual.
- **Flujo de Trabajo Limpio**: Antes de proponer cambios o soluciones, analizar efectos secundarios en la ejecución global del sistema. Escribir código limpio, estructurado y autodocumentado (Clean Code).

---

## 2. Lineamientos de Desarrollo en Pine Script (TV)

- **Gestión Horaria de NY**:
  - Para estrategias basadas en sesiones horarias de mercados americanos, no usar la hora por defecto del broker/exchange (`hour`, `minute`).
  - Convertir el tiempo de la barra explícitamente a la zona de Nueva York:
    ```pine
    int nyHour = hour(time, "America/New_York")
    int nyMinute = minute(time, "America/New_York")
    ```
  - Realizar el reseteo diario utilizando también la fecha de Nueva York para evitar problemas por fines de semana o diferencias de servidor.
- **Control de Direccionalidad**:
  - Bloquear entradas en dirección contraria si hay una posición abierta activa.
  - Compras (`longC`): Bloquear si hay una venta abierta (`not in_short`).
  - Ventas (`shortC`): Bloquear si hay una compra abierta (`not in_long`).
- **Visualización Limpia**:
  - Usar la función `box.new` para dibujar el rango horario en color naranja (`color.new(color.orange, 90)`) con su respectivo borde.
  - Asegurar el ancho correcto estableciendo `right = bar_index + 1` en temporalidades de 15 minutos para que cubra exactamente desde el inicio hasta el final del periodo del rango.
  - Usar variables de control como `is_new_session` basada en `ta.change(sessionStartBar) != 0` para instanciar nuevos objetos históricos en vez de actualizar o mover el mismo cuadro indefinidamente.

---

## 3. Lineamientos de Desarrollo en MetaTrader 5 (MQL5)

Toda estrategia en Pine Script debe tener su equivalente MQL5 sincronizado. Se deben respetar de forma obligatoria las siguientes secciones críticas:

- **[MQ5-CRITICAL #1] Detección de Posición Propia**:
  - Implementar la función `GetOwnPositionType()` para escanear y filtrar las posiciones activas en la cuenta.
  - Solo debe retornar el estado de las posiciones del símbolo actual (`_Symbol`) y que coincidan exactamente con el `magic_number` único asignado a la estrategia.
- **[MQ5-CRITICAL #2] Filtro de Posición Contraria**:
  - Bloquear compras si ya hay un Trade tipo `SELL` activo en la cuenta.
  - Bloquear ventas si ya hay un Trade tipo `BUY` activo en la cuenta.
- **[MQ5-CRITICAL #3] Sincronización del Trailing Stop**:
  - La lógica de Trailing Stop debe replicar exactamente la matemática definida en Pine Script (ej. por quintos/tercios).
  - Al abrir un Trade, calcular y almacenar en una variable global el `trail_step` (ej. `dist_puntos / 5.0`).
  - Para calcular el nuevo Stop Loss dinámico en puntos:
    - Compras: `double nuevo_sl = (t_ent - (trail_step * 5.0)) + (trail_step * niveles_superados);`
    - Ventas: `double nuevo_sl = (t_ent + (trail_step * 5.0)) - (trail_step * niveles_superados);`
  - Utilizar siempre el identificador único de la posición (`POSITION_TICKET`) al llamar a `trade.PositionModify()` para asegurar una modificación segura de las órdenes.
- **[MQ5-CRITICAL #4] Magic Number en Consultas**:
  - Todas las operaciones de control, consulta de balance, cierre de pánico y cálculo del beneficio diario deben estar filtradas estrictamente por el `magic_number` para evitar interferencia cruzada entre robots en el mismo terminal.
- **Gestión Horaria**:
  - Mapear las horas de Nueva York a la zona horaria del broker. Por ejemplo, en brokers con servidor estándar GMT+2/+3 (como IC Markets o Pepperstone), el rango de 9:30 a 9:45 NY se traduce a `16:30` - `16:45` en el servidor.