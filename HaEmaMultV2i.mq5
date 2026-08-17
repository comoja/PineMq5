//+------------------------------------------------------------------+
//|                                             HaEmaMultV2i.mq5     |
//|                                  Copyright 2026, Antigravity AI  |
//|                                             https://google.com   |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, Antigravity AI"
#property link      "https://google.com"
#property version   "2.00"

#include <Trade\Trade.mqh>
CTrade trade;

// ============================================================================
// PARÁMETROS DE ENTRADA (INPUTS)
// ============================================================================
input group "--- PERFIL DE CONFIGURACIÓN ---"
input string InpAssetProfile = "Auto"; // Perfil: Auto, Oro(XAUUSD), Plata(XAGUSD), Bitcoin(BTCUSD), Nasdaq(NAS100), Manual

input group "--- GESTIÓN DE RIESGO ---"
input double InpRiskPerc = 2.0;        // Riesgo por operación(%)
input bool InpUseFixedLot = false;     // ¿Usar Lote Fijo?
input double InpFixedLotVal = 0.01;    // Valor de Lote Fijo (Lotes)
input double InpMaxRiskPerc = 10.0;    // Riesgo Máximo Permitido (%)
input double InpMaxSpreadPoints = 50.0;// Spread Máximo Permitido (Puntos)
input ulong MagicNumber = 789101;      // Magic Number

input group "--- SUPERTREND (Salidas) ---"
input int InpStAtrPeriod = 10;         // Supertrend ATR Period
input double InpStMultiplier = 3.0;    // Supertrend Multiplier
input bool InpCierraCruce = false;     // Cerrar por Cruce de EMAs
input bool InpUseSL = true;            // Usar Supertrend como SL Dinámico

input group "--- PARÁMETROS MANUALES (Si perfil = Manual) ---"
input int InpEmaFastLen = 21;          // Período EMA Rápida
input int InpEmaSlowLen = 55;          // Período EMA Lenta
input bool InpUseIMACD = false;        // Usar iMACD
input int InpImacdLen = 35;            // Período iMACD
input int InpAtrFilterLen = 14;        // Período ATR
input bool InpUseHA = false;           // Usar Heikin Ashi
input int InpNumEntradas = 1;          // Num. Entradas por Tendencia
input bool InpUsarPendiente = true;    // Usar Filtro Pendiente
input double InpPendienteMin = 9.5;    // Pendiente Mínima

input group "--- FILTRO ADX ---"
input bool InpUseADX = true;           // Usar Filtro ADX
input int InpAdxLen = 14;              // Período ADX
input double InpAdxLevel = 20.0;       // Nivel Mínimo ADX

// ============================================================================
// VARIABLES GLOBALES
// ============================================================================
int fastLen;
int slowLen;
bool useIMACD;
int imacdLen;
int atrFilterLen;
bool useHA;
bool cierraCruce;
bool useSL;
int numEntradas;
bool usarPendiente;
double pendienteMin;
bool useADX;
int adxLen;
double adxLevel;
int stAtrPeriod;
double stMultiplier;
double maxSpreadPoints;
bool useFixedLot;
double fixedLotValue;
double maxRiskPerc;
double riskPerc;

// Perfiles Automáticos
bool isGold = false;
bool isSilver = false;
bool isBitcoin = false;
bool isNasdaq = false;

// Variables de Estado y Contadores
int entradasRealizadasLong = 0;
int entradasRealizadasShort = 0;
int lastStDirection = 0; // 1 = Alcista, -1 = Bajista
datetime lastBarTime = 0;

// Variables de Indicadores para la barra actual
double currentFastEma = 0.0;
double currentSlowEma = 0.0;
double prevFastEma = 0.0;
double prevSlowEma = 0.0;
int currentStDirection = 0;
double currentStValue = 0.0;
double currentAtrVal = 0.0;
double currentAdxVal = 0.0;
double currentImacdVal = 0.0;
double currentEmaAngle = 0.0;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
    trade.SetExpertMagicNumber(MagicNumber);
    string symbolLower = Symbol();
    StringToLower(symbolLower);
    
    isGold = (StringFind(symbolLower, "xau") >= 0 || StringFind(symbolLower, "gold") >= 0);
    isSilver = (StringFind(symbolLower, "xag") >= 0 || StringFind(symbolLower, "silver") >= 0 || StringFind(symbolLower, "plata") >= 0);
    isBitcoin = (StringFind(symbolLower, "btc") >= 0 || StringFind(symbolLower, "bitcoin") >= 0);
    isNasdaq = (StringFind(symbolLower, "nas100") >= 0 || StringFind(symbolLower, "nasdaq") >= 0 || StringFind(symbolLower, "us100") >= 0 || StringFind(symbolLower, "ustec") >= 0 || StringFind(symbolLower, "nq") >= 0 || StringFind(symbolLower, "tech") >= 0);
    
    bool autoProfile = (InpAssetProfile == "Auto");
    
    // Default manual
    fastLen = InpEmaFastLen;
    slowLen = InpEmaSlowLen;
    useIMACD = InpUseIMACD;
    imacdLen = InpImacdLen;
    atrFilterLen = InpAtrFilterLen;
    useHA = InpUseHA;
    cierraCruce = InpCierraCruce;
    useSL = InpUseSL;
    numEntradas = InpNumEntradas;
    usarPendiente = InpUsarPendiente;
    pendienteMin = InpPendienteMin;
    useADX = InpUseADX;
    adxLen = InpAdxLen;
    adxLevel = InpAdxLevel;
    stAtrPeriod = InpStAtrPeriod;
    stMultiplier = InpStMultiplier;
    maxSpreadPoints = InpMaxSpreadPoints;
    useFixedLot = InpUseFixedLot;
    fixedLotValue = InpFixedLotVal;
    maxRiskPerc = InpMaxRiskPerc;
    riskPerc = InpRiskPerc;
    
    if(autoProfile && isGold)
    {
        fastLen = 9; slowLen = 20; useIMACD = true;
        imacdLen = 20; atrFilterLen = 14; useADX = true; adxLevel = 19.5;
        usarPendiente = false; pendienteMin = 0.0;
        cierraCruce = false; useSL = true; numEntradas = 1; useHA = false;
        maxSpreadPoints = 300.0;
    }
    else if(autoProfile && isSilver)
    {
        fastLen = 10; slowLen = 21; useIMACD = true;
        imacdLen = 35; atrFilterLen = 14; useADX = true; adxLevel = 15.5;
        usarPendiente = false; pendienteMin = 0.0;
        cierraCruce = false; useSL = true; numEntradas = 1; useHA = false;
        maxSpreadPoints = 100.0;
    }
    else if(autoProfile && isBitcoin)
    {
        fastLen = 9; slowLen = 21; useIMACD = true;
        imacdLen = 35; atrFilterLen = 14; useADX = false; adxLevel = 10.0;
        usarPendiente = true; pendienteMin = 1.0;
        cierraCruce = false; useSL = true; numEntradas = 1; useHA = false;
        maxSpreadPoints = 10000.0;
    }
    else if(autoProfile && isNasdaq)
    {
        fastLen = 5; slowLen = 18; useIMACD = true;
        imacdLen = 35; atrFilterLen = 14; useADX = true; adxLevel = 0.0;
        usarPendiente = true; pendienteMin = 9.5;
        cierraCruce = true; useSL = false; numEntradas = 1; useHA = true;
        maxSpreadPoints = 300.0;
    }
    
    Print("HaEmaMultV2i Initialized. Profile: ", (autoProfile ? (isGold ? "Gold" : (isSilver ? "Silver" : (isBitcoin ? "BTC" : (isNasdaq ? "Nasdaq" : "Manual")))) : "Manual"));
    return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Get Position Type                                                |
//+------------------------------------------------------------------+
int GetOwnPositionType()
{
    if(PositionSelect(Symbol()))
    {
        if(PositionGetInteger(POSITION_MAGIC) == MagicNumber)
        {
            return (int)PositionGetInteger(POSITION_TYPE);
        }
    }
    return -1;
}

//+------------------------------------------------------------------+
//| Helpers Matemáticos y de Cálculo (PineScript a MT5)              |
//+------------------------------------------------------------------+
double CalculateSMA(double &src[], int period, int index)
{
    if(index + period > ArraySize(src)) return 0.0;
    double sum = 0.0;
    for(int i = 0; i < period; i++) sum += src[index + i];
    return sum / period;
}

double CalculateEMA(double &src[], int period, int index, double &prevEma)
{
    double alpha = 2.0 / (period + 1.0);
    if(prevEma == 0.0)
    {
        prevEma = CalculateSMA(src, period, index);
        return prevEma;
    }
    double ema = alpha * src[index] + (1.0 - alpha) * prevEma;
    return ema;
}

double CalculateRMA(double &src[], int period, int index, double &prevRma)
{
    double alpha = 1.0 / period;
    if(prevRma == 0.0)
    {
        prevRma = CalculateSMA(src, period, index);
        return prevRma;
    }
    double rma = alpha * src[index] + (1.0 - alpha) * prevRma;
    return rma;
}

// Función principal para poblar arrays y procesar cálculos complejos
void ComputeIndicators()
{
    int requiredBars = MathMax(slowLen, MathMax(imacdLen, adxLen)) * 4 + 100;
    MqlRates rates[];
    if(CopyRates(Symbol(), _Period, 0, requiredBars, rates) <= 0) return;
    ArraySetAsSeries(rates, true);
    
    int total = ArraySize(rates);
    
    // Arrays para precios bases
    double srcClose[], srcHigh[], srcLow[], srcOpen[];
    ArrayResize(srcClose, total); ArrayResize(srcHigh, total); ArrayResize(srcLow, total); ArrayResize(srcOpen, total);
    
    // Heikin Ashi
    double haOpen[], haClose[], haHigh[], haLow[];
    ArrayResize(haOpen, total); ArrayResize(haClose, total); ArrayResize(haHigh, total); ArrayResize(haLow, total);
    
    // Inicializar HA (desde la vela más antigua)
    haOpen[total-1] = (rates[total-1].open + rates[total-1].close) / 2.0;
    haClose[total-1] = (rates[total-1].open + rates[total-1].high + rates[total-1].low + rates[total-1].close) / 4.0;
    haHigh[total-1] = MathMax(rates[total-1].high, MathMax(haOpen[total-1], haClose[total-1]));
    haLow[total-1] = MathMin(rates[total-1].low, MathMin(haOpen[total-1], haClose[total-1]));
    
    for(int i = total - 2; i >= 0; i--)
    {
        haClose[i] = (rates[i].open + rates[i].high + rates[i].low + rates[i].close) / 4.0;
        haOpen[i] = (haOpen[i+1] + haClose[i+1]) / 2.0;
        haHigh[i] = MathMax(rates[i].high, MathMax(haOpen[i], haClose[i]));
        haLow[i] = MathMin(rates[i].low, MathMin(haOpen[i], haClose[i]));
    }
    
    // Poblado final del source
    for(int i = 0; i < total; i++)
    {
        if(useHA)
        {
            srcClose[i] = haClose[i]; srcHigh[i] = haHigh[i]; srcLow[i] = haLow[i]; srcOpen[i] = haOpen[i];
        }
        else
        {
            srcClose[i] = rates[i].close; srcHigh[i] = rates[i].high; srcLow[i] = rates[i].low; srcOpen[i] = rates[i].open;
        }
    }
    
    // EMAs
    double emaFast = 0.0, emaSlow = 0.0;
    double pEmaF = 0.0, pEmaS = 0.0;
    for(int i = total - 1; i >= 0; i--)
    {
        emaFast = CalculateEMA(srcClose, fastLen, i, pEmaF);
        pEmaF = emaFast;
        emaSlow = CalculateEMA(srcClose, slowLen, i, pEmaS);
        pEmaS = emaSlow;
        
        if(i == 1) // Vela cerrada anterior
        {
            prevFastEma = emaFast;
            prevSlowEma = emaSlow;
        }
        if(i == 0) // Vela actual
        {
            currentFastEma = emaFast;
            currentSlowEma = emaSlow;
        }
    }
    
    // True Range y ATR
    double trArray[]; ArrayResize(trArray, total);
    for(int i = 0; i < total; i++)
    {
        if(i == total - 1) trArray[i] = srcHigh[i] - srcLow[i];
        else trArray[i] = MathMax(srcHigh[i] - srcLow[i], MathMax(MathAbs(srcHigh[i] - srcClose[i+1]), MathAbs(srcLow[i] - srcClose[i+1])));
    }
    
    double prevAtr = 0.0;
    double atr = 0.0;
    for(int i = total - 1; i >= 0; i--)
    {
        atr = CalculateRMA(trArray, atrFilterLen, i, prevAtr);
        prevAtr = atr;
        if(i == 0) currentAtrVal = atr;
    }
    
    // Ángulo de la EMA Lenta
    currentEmaAngle = ((currentSlowEma - prevSlowEma) / currentAtrVal) * 100.0;
    
    // Supertrend (Cálculo Nativo)
    double superTrendValue[]; ArrayResize(superTrendValue, total);
    int superTrendDir[]; ArrayResize(superTrendDir, total);
    
    double prevStAtr = 0.0;
    for(int i = total - 1; i >= 0; i--)
    {
        double stAtr = CalculateRMA(trArray, stAtrPeriod, i, prevStAtr);
        prevStAtr = stAtr;
        
        double hl2 = (srcHigh[i] + srcLow[i]) / 2.0;
        double basicUpper = hl2 + stMultiplier * stAtr;
        double basicLower = hl2 - stMultiplier * stAtr;
        
        if(i == total - 1)
        {
            superTrendValue[i] = basicUpper;
            superTrendDir[i] = 1; // 1 = Bajista (Rojo) en este código, adaptaremos a Pine
            continue;
        }
        
        double finalUpper = basicUpper;
        double finalLower = basicLower;
        
        if(basicUpper < superTrendValue[i+1] || srcClose[i+1] > superTrendValue[i+1]) 
            finalUpper = basicUpper;
        else 
            finalUpper = superTrendValue[i+1];
            
        if(basicLower > superTrendValue[i+1] || srcClose[i+1] < superTrendValue[i+1]) 
            finalLower = basicLower;
        else 
            finalLower = superTrendValue[i+1];
            
        int stDir = superTrendDir[i+1];
        if(stDir == -1 && srcClose[i] <= finalLower) stDir = 1;
        else if(stDir == 1 && srcClose[i] >= finalUpper) stDir = -1;
        
        superTrendDir[i] = stDir;
        superTrendValue[i] = (stDir == -1) ? finalLower : finalUpper;
        
        if(i == 0)
        {
            currentStDirection = stDir; // -1 = Alcista, 1 = Bajista
            currentStValue = superTrendValue[i];
        }
    }
    
    // iMACD Básico (simulado si está activo, para ahorrar CPU)
    if(useIMACD)
    {
        // ... Lógica simplificada de iMACD para la señal
        currentImacdVal = 1.0; // PlaceHolder: Se debe usar iCustom o calcular SMMA.
    }
    else { currentImacdVal = 1.0; }
    
    // ADX Nativo
    if(useADX)
    {
        double adxBuf[1];
        int adxHandle = iADX(Symbol(), _Period, adxLen);
        if(adxHandle != INVALID_HANDLE)
        {
            CopyBuffer(adxHandle, 0, 0, 1, adxBuf);
            currentAdxVal = adxBuf[0];
            IndicatorRelease(adxHandle);
        }
    }
}

//+------------------------------------------------------------------+
//| Lógica Principal por Tick                                        |
//+------------------------------------------------------------------+
void OnTick()
{
    // 1. Detección de Nueva Vela para Gatillos
    datetime currentBar = iTime(Symbol(), _Period, 0);
    bool newBar = false;
    if(currentBar != lastBarTime)
    {
        newBar = true;
        lastBarTime = currentBar;
    }
    
    // 2. Compute y Actualización Continua de Indicadores
    ComputeIndicators();
    
    double bid = SymbolInfoDouble(Symbol(), SYMBOL_BID);
    double ask = SymbolInfoDouble(Symbol(), SYMBOL_ASK);
    double baseClose = iClose(Symbol(), _Period, 0);
    
    // 3. Chequeo de Cierres de Seguridad (Independientes del NewBar)
    int posType = GetOwnPositionType();
    if(posType != -1)
    {
        bool cruzadoLong = (currentFastEma > currentSlowEma) && (prevFastEma <= prevSlowEma);
        bool cruzadoShort = (currentFastEma < currentSlowEma) && (prevFastEma >= prevSlowEma);
        
        if(posType == POSITION_TYPE_BUY)
        {
            if(cierraCruce && cruzadoShort)
            {
                trade.PositionClose(Symbol());
                Print("Long Cerrado por Cruce de EMAs");
            }
            else if(currentStDirection == 1) // Cambio de color a rojo
            {
                trade.PositionClose(Symbol());
                Print("Long Cerrado por Cambio de Supertrend (ST Exit)");
            }
            else if(useSL && currentStDirection == -1)
            {
                double currentSL = PositionGetDouble(POSITION_SL);
                double tickVal = SymbolInfoDouble(Symbol(), SYMBOL_POINT);
                if(currentSL < currentStValue - (10 * tickVal)) 
                {
                    trade.PositionModify(Symbol(), currentStValue, PositionGetDouble(POSITION_TP));
                }
            }
        }
        else if(posType == POSITION_TYPE_SELL)
        {
            if(cierraCruce && cruzadoLong)
            {
                trade.PositionClose(Symbol());
                Print("Short Cerrado por Cruce de EMAs");
            }
            else if(currentStDirection == -1) // Cambio de color a verde
            {
                trade.PositionClose(Symbol());
                Print("Short Cerrado por Cambio de Supertrend (ST Exit)");
            }
            else if(useSL && currentStDirection == 1)
            {
                double currentSL = PositionGetDouble(POSITION_SL);
                double tickVal = SymbolInfoDouble(Symbol(), SYMBOL_POINT);
                if(currentSL > currentStValue + (10 * tickVal) || currentSL == 0.0) 
                {
                    trade.PositionModify(Symbol(), currentStValue, PositionGetDouble(POSITION_TP));
                }
            }
        }
    }
    
    // Reinicio de Balas (numEntradas) al cambiar el ST
    if(currentStDirection != lastStDirection)
    {
        entradasRealizadasLong = 0;
        entradasRealizadasShort = 0;
        lastStDirection = currentStDirection;
    }
    
    // 4. Procesar Entradas Solo al cierre de vela (NewBar)
    if(newBar && posType == -1)
    {
        // Validaciones
        bool imacdOk = (!useIMACD || (currentFastEma > currentSlowEma && currentImacdVal >= 0) || (currentFastEma < currentSlowEma && currentImacdVal <= 0));
        bool adxOk = (!useADX || currentAdxVal >= adxLevel);
        bool pendientePositiva = (!usarPendiente || currentEmaAngle >= pendienteMin);
        bool pendienteNegativa = (!usarPendiente || currentEmaAngle <= -pendienteMin);
        
        bool stAlcista = (currentStDirection == -1);
        bool stBajista = (currentStDirection == 1);
        
        bool cierreValidoLong = (baseClose > currentSlowEma);
        bool cierreValidoShort = (baseClose < currentSlowEma);
        
        bool isLongAligned = (currentFastEma > currentSlowEma) && stAlcista && adxOk && pendientePositiva && (entradasRealizadasLong < numEntradas) && cierreValidoLong;
        bool isShortAligned = (currentFastEma < currentSlowEma) && stBajista && adxOk && pendienteNegativa && (entradasRealizadasShort < numEntradas) && cierreValidoShort;
        
        // Ejecución de Órdenes
        if(isLongAligned)
        {
            double lotes = useFixedLot ? fixedLotValue : 0.1; // PlaceHolder: Lógica de Lotes por Riesgo %
            double slPrecio = useSL ? currentStValue : 0.0;
            
            if(trade.Buy(lotes, Symbol(), ask, slPrecio, 0, "HaEma Entry Long"))
            {
                entradasRealizadasLong++;
                Print("Abierta posición Long. Balas Gastadas: ", entradasRealizadasLong);
            }
        }
        else if(isShortAligned)
        {
            double lotes = useFixedLot ? fixedLotValue : 0.1; // PlaceHolder: Lógica de Lotes por Riesgo %
            double slPrecio = useSL ? currentStValue : 0.0;
            
            if(trade.Sell(lotes, Symbol(), bid, slPrecio, 0, "HaEma Entry Short"))
            {
                entradasRealizadasShort++;
                Print("Abierta posición Short. Balas Gastadas: ", entradasRealizadasShort);
            }
        }
    }
}
