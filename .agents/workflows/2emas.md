---
description: Estrategia basada cruce de emaRapida y emaLenta
---

### Calculos iniciales
- Calcular emaRapida = 20
- Calcular emaLenta  = 50
- Calcular pendienteEmaRapida en grados
- Calcular pendienteEmaLenta en grados
- definir pendienteMinima = 12 (para compras es + y para ventas es -)

## Ciclo principal en cada tick
- **Detección del Cruce:** El cruce de EMAs se detecta exclusivamente con **velas cerradas** (velas 1 y 2) para evitar señales falsas intra-vela (repintado).
- **Separación (Filtro de Apertura):** La entrada solo se evalúa si la distancia entre ambas EMAs es mayor o igual a `minDistancePuntos`. Esta separación NO debe bloquear la lectura inicial del cruce ni el dibujo de indicadores.
- **Entrada (Compras):** Se ejecuta al cierre de la vela si la separación es óptima Y:
  - (A) El precio acaba de hacer un pullback por debajo de la EMA 20 y es la **primera vela que cierra por arriba**.
  - (B) O el cruce acaba de suceder y el precio ya cerró por arriba.
- **Entrada (Ventas):** Se ejecuta al cierre de la vela si la separación es óptima Y:
  - (A) El precio acaba de hacer un pullback por arriba de la EMA 20 y es la **primera vela que cierra por debajo**.
  - (B) O el cruce acaba de suceder y el precio ya cerró por debajo.
- **Stop Loss:** Se coloca en el nivel de precio **exacto donde ocurrió el cruce** (precio de la EMA en el momento del cruce confirmado). *Nota: Pendiente a eficientar a un modelo más dinámico.*
- **Salida:** Cuando el precio cierre por debajo (compras) o por encima (ventas) de la emaLenta (50), O cuando haya un cruce de EMAs en sentido contrario.

## Notas sobre la implementación técnica:
1. **Detección de Posición e Interferencias:** Se usa `getOwnPositionType()` respetando estrictamente el `magicNumber` y el `_Symbol` [MQ5-CRITICAL #1, #2 y #4].
2. **Dibujado de Cruces:** Se llama a `drawArrow()` cuando se detecta el cruce en velas cerradas. Se usa una memoria `static datetime` para no redibujar o sobreescribir la flecha.
3. **CamelCase:** Las funciones internas respetan el formato `camelCase` por regla del sistema.
4. **Validación Extra del Precio:** Para las salidas, se implementó el OR `(closeActual < emaLentaActual)` protegiendo de retiros de beneficios profundos.