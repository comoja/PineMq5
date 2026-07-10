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
input string InpAssetProfile = "Auto"; // Perfil: Auto, Oro (XAUUSD), Plata (XAGUSD), Bitcoin (BTCUSD), Nasdaq (NAS100), Manual

input group "--- GESTIÓN DE RIESGO ---"
input double InpRiskPerc = 1.0; // Riesgo por operación (%)
input bool InpUseTP = true; // Usar Take Profit Fijo
input double InpRrRatio = 3.0; // Relación Riesgo/Recompensa (R:R)
input bool InpUseTPChase = false; // Usar Persecución de TP (TP Chasing)
input double InpTpChasePts = 3.0; // Distancia de Persecución TP (Pts)
input double InpTpChaseOffset = 3.0; // Avance del TP (Pts)
input int InpTrailDivisions = 7; // Divisiones del Trailing (partes del recorrido TP→SL)
input bool InpUseFixedLot = false; // ¿Usar Lote Fijo? (True=Fijo, False=Riesgo %)
input double InpFixedLotVal = 0.01; // Valor de Lote Fijo (Lotes MT5)
input double InpMaxRiskPerc = 5.0; // Riesgo Máximo Permitido por Trade (% Balance)
input double InpMaxSpreadPoints = 50.0; // Spread Máximo Permitido (Puntos)
input double InpMinStopsLevel = 0.0; // Mínimo Stop Level (Puntos)
input int InpSignalValidBars = 5; // Velas de validez de la señal (espera de cierre de posición)
input bool InpUseBE = true; // Usar Break-Even (BE)
input ulong MagicNumber = 789101; // Magic Number de la Estrategia

input group "--- PARÁMETROS MANUALES (Si perfil = Manual) ---"
input string InpEmaTF = "Auto"; // Temporalidad de EMAs (Auto, 15, 30, 60, 180, 240, 1440)
input int InpEmaFastLen = 21; // Período EMA Rápida manual
input int InpEmaSlowLen = 55; // Período EMA Lenta manual
input int InpSwingPeriod = 8; // Velas Swing High/Low manual
input double InpSlBufPts = 2.0; // Buffer SL manual (Puntos)
input bool InpUseIMACD = false; // Usar iMACD manual
input int InpImacdLen = 35; // Período iMACD manual
// input bool InpUseEMASpread = true; // Usar Abertura EMAs manual
// input double InpEmaSpreadMult = 0.4; // Abertura Mínima EMAs manual (x ATR)
// input bool InpUseHAStrength = false; // Fuerza Heikin-Ashi manual
// input bool InpUseATRMin = false; // Filtro ATR Mínimo manual
input int InpAtrFilterLen = 14; // Período ATR manual
// input double InpAtrMinUSD = 2.0; // ATR Mínimo USD manual
// input bool InpUseADX = false; // Filtro ADX manual
// input int InpAdxLen = 14; // Período ADX manual
// input double InpAdxMin = 22.0; // ADX Mínimo manual
// input double InpMaxOverextensionMult = 0.0; // Multiplicador de sobreextensión (0 = Desactivado)
input double InpBodyMinMult = 0.75; // Multiplicador de Cuerpo Mínimo manual (x ATR)

input group "--- CONTROL DE SESIÓN ---"
// input bool InpUseSession = false; // Usar Sesión Horaria
// input string InpSessionStr = "0800-1700"; // Horario Operativo (UTC)
// input string InpTimezone = "America/New_York"; // Zona Horaria de la Sesión

// ============================================================================
// VARIABLES GLOBALES
// ============================================================================
double slBufferPts;
double rrRatio;
bool useIMACD;
bool useEMASpread;
double emaSpreadMult;
bool useHAStrength;
bool useATRMin;
double atrMinUSD;
bool useADX;
double adxMin;
bool useADX;
bool useTPChase;
bool useTP;
double tpChasePts;
double tpChaseOffset;
int trailDivisions;
double maxOverextensionMult;
double bodyMinMult;
bool useFixedLot;
double fixedLotValue;
double maxRiskPerc;
double maxSpreadPoints;
double minStopsLevel;
int signalValidBars;
bool useBE;
bool useSession;
string sessionStr;
string timezoneVal;

// Parámetros de Indicadores reasignables
string emaTF;
int fastLen;
int slowLen;
int swingPeriod;
int imacdLen;
int adxLen;

// Banderas de Activo
bool isGold = false;
bool isSilver = false;
bool isBitcoin = false;
bool isNasdaq = false;

// Handles de Indicadores
ENUM_TIMEFRAMES resolvedTimeframe;
// Handles de Indicadores de Posición
double activeSL = 0.0;
double activeTP = 0.0;
double entryP = 0.0;
datetime entryT = 0;
bool posActiveLastTick = false;
datetime lastBarTime = 0;

// Variables de Trailing dinámico
double slPart = 0.0;
double tpPart = 0.0;
bool pasoLaMitad = false;
bool slTrail = false;
double tpChaseSlGap = 0.0;
bool beAplicado = false;

// Registro de las últimas entradas para evitar re-entradas en la misma señal
datetime lastEntryTimeLong = 0;
datetime lastEntryTimeShort = 0;

// Banderas de señal pendiente para confirmación de velas/HA
bool pendingLongSignal = false;
bool pendingShortSignal = false;
datetime signalSetupTime = 0;
string banderaState = "niCompraNiVenta";

double atrValini = 0;

// Estructura de Velas Heikin-Ashi
struct HeikinAshiBar {
    double open;
    double high;
    double low;
    double close;
};

// Modos de zona horaria: 0 = NY, 1 = CDMX, 2 = UTC
int timezoneMode = 0;

// Declaraciones de funciones
double CalculateATR(int index, int period);
double CalculateADX(int index, int period);
double GetIMACD(int targetIndex, int len);
bool GetHeikinAshi(HeikinAshiBar &haBars[]);
void ManageActivePosition();
void UpdateDashboard();
void ClearDashboard();
void DrawInitBoxes(datetime entryTime, double entryPrice, double slVal, double tpVal);
void UpdateTradeBoxes(double entryPrice, double slVal, double tpVal);
void DrawSetupMark(datetime signalTime, int direction);
double FindSwingLow(int radius);
double FindSwingHigh(int radius);
int GetOwnPositionType();

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
    trade.SetExpertMagicNumber(MagicNumber);
    
    // Determinar Activo por Símbolo
    string symbolLower = Symbol();
    StringToLower(symbolLower);
    
    isGold = (StringFind(symbolLower, "xau") >= 0 || StringFind(symbolLower, "gold") >= 0);
    isSilver = (StringFind(symbolLower, "xag") >= 0 || StringFind(symbolLower, "silver") >= 0 || StringFind(symbolLower, "plata") >= 0);
    isBitcoin = (StringFind(symbolLower, "btc") >= 0 || StringFind(symbolLower, "bitcoin") >= 0);
    isNasdaq = (StringFind(symbolLower, "nas100") >= 0 || StringFind(symbolLower, "nasdaq") >= 0 || StringFind(symbolLower, "us100") >= 0 || StringFind(symbolLower, "ustec") || StringFind(symbolLower, "nq") >= 0 || StringFind(symbolLower, "tech") >= 0);
    
    bool autoProfile = (InpAssetProfile == "Auto");
    useTP = InpUseTP;
    
    // Inicializar valores desde inputs manuales
    fastLen = InpEmaFastLen;
    slowLen = InpEmaSlowLen;
    swingPeriod = InpSwingPeriod;
    imacdLen = InpImacdLen;
    
    slBufferPts = InpSlBufPts;
    rrRatio = InpRrRatio;
    // useEMASpread = InpUseEMASpread;
    // emaSpreadMult = InpEmaSpreadMult;
    // useHAStrength = InpUseHAStrength;
    // useATRMin = InpUseATRMin;
    // atrMinUSD = InpAtrMinUSD;
    // useADX = InpUseADX;
    // adxMin = InpAdxMin;
    useTPChase = InpUseTPChase;
    tpChasePts = InpTpChasePts;
    tpChaseOffset = InpTpChaseOffset;
    trailDivisions = InpTrailDivisions;
    // maxOverextensionMult = InpMaxOverextensionMult;
    bodyMinMult = InpBodyMinMult;
    useBE = InpUseBE;
    useFixedLot = InpUseFixedLot;
    fixedLotValue = InpFixedLotVal;
    maxRiskPerc = InpMaxRiskPerc;
    maxSpreadPoints = InpMaxSpreadPoints;
    minStopsLevel = InpMinStopsLevel;
    // useSession = InpUseSession;
    // sessionStr = InpSessionStr;
    // timezoneVal = InpTimezone;
    signalValidBars = InpSignalValidBars;
    
    if(autoProfile && isGold)
    {
        fastLen       = 9;
        slowLen       = 20;
        swingPeriod   = 7;
        imacdLen      = 20;
        atrFilterLen  = 14;
        adxLen        = 14;
        slBufferPts   = 0.0;
        rrRatio       = 1.8;
        useIMACD      = true;
        useEMASpread  = true;
        emaSpreadMult = 0.09;
        useHAStrength = false;
        useATRMin     = false;
        atrMinUSD     = 0.4;
        useADX        = true;
        adxMin        = 18.0;
        useTPChase    = true;
        tpChasePts    = 12.0;
        tpChaseOffset = 0.75;
        useSession    = false;
        sessionStr    = "0300-1700";
        timezoneVal   = "UTC";
        maxRiskPerc   = 1.0;
        trailDivisions = 4;
        maxSpreadPoints = 300.0;
        maxOverextensionMult = 0.0;
        bodyMinMult   = 0.25;
        useBE = false;
    }
    else if(autoProfile && isSilver)
    {
        fastLen       = 10;
        slowLen       = 21;
        swingPeriod   = 5;
        imacdLen      = 35;
        atrFilterLen  = 14;
        adxLen        = 14;
        useTPChase    = true;
        tpChasePts    = 2.0;
        tpChaseOffset = 0.25;
        useSession    = false;
        trailDivisions = 5;
        maxSpreadPoints = 100.0;
        maxOverextensionMult = 0.0;
        bodyMinMult   = 0.75;
        useBE = false;
    }
    else if(autoProfile && isBitcoin)
    {
        fastLen       = 9;
        slowLen       = 21;
        swingPeriod   = 5;
        imacdLen      = 35;
        atrFilterLen  = 14;
        adxLen        = 14;
        useTPChase    = true;
        tpChasePts    = 150.0;
        tpChaseOffset = 150.0;
        useSession    = false;
        trailDivisions = 7;
        maxSpreadPoints = 10000.0;
        maxOverextensionMult = 0.0;
        bodyMinMult   = 0.75;
        useBE = false;
    }
    else if(autoProfile && isNasdaq)
    {
        fastLen       = 9;
        slowLen       = 21;
        swingPeriod   = 5;
        imacdLen      = 35;
        atrFilterLen  = 14;
        adxLen        = 14;
        useTPChase    = true;
        tpChasePts    = 15.0;
        tpChaseOffset = 15.0;
        useSession    = false;
        trailDivisions = 7;
        maxSpreadPoints = 300.0;
        maxOverextensionMult = 0.0;
        bodyMinMult   = 0.75;
        useBE = false;
    }
    
    // Impedir lote fijo o configuraciones indebidas en modo automático
        minStopsLevel = 0.0;
    
    // Determinar Zona Horaria numérica
    if (timezoneVal == "America/New_York") timezoneMode = 0;
    else if (timezoneVal == "America/Mexico_City") timezoneMode = 1;
    else timezoneMode = 2; // UTC
    
    // Validación de temporalidades requeridas para los activos automáticos
    ENUM_TIMEFRAMES correctPeriod = _Period;
    string strCorrect = "";
    if (autoProfile && isGold) { correctPeriod = PERIOD_M15; strCorrect = "15 minutos (M15)"; }
    else if (autoProfile && isSilver) { correctPeriod = PERIOD_M30; strCorrect = "30 minutos (M30)"; }
    else if (autoProfile && isBitcoin) { correctPeriod = PERIOD_M30; strCorrect = "30 minutos (M30)"; }
    else if (autoProfile && isNasdaq) { correctPeriod = PERIOD_M5; strCorrect = "5 minutos (M5)"; }
    
    if (strCorrect != "" && _Period != correctPeriod)
    {
        Alert("Temporalidad incorrecta para " + Symbol() + ". Cambie el timeframe del grafico a " + strCorrect + " para el correcto funcionamiento.");
        return(INIT_PARAMETERS_INCORRECT);
    }
    
    // Resolución de temporalidad para cálculo de EMAs
    resolvedTimeframe = _Period;
    emaTF = InpEmaTF;
    if(autoProfile)
    {
        if(isGold) emaTF = "Auto";
        else if(isSilver) emaTF = "15";
        else if(isBitcoin) emaTF = "15";
        else if(isNasdaq) emaTF = "Auto";
    }
    
    if(emaTF != "Auto")
    {
        if(emaTF == "15") resolvedTimeframe = PERIOD_M15;
        else if(emaTF == "30") resolvedTimeframe = PERIOD_M30;
        else if(emaTF == "60") resolvedTimeframe = PERIOD_H1;
        else if(emaTF == "180") resolvedTimeframe = PERIOD_H3;
        else if(emaTF == "240") resolvedTimeframe = PERIOD_H4;
        else if(emaTF == "1440") resolvedTimeframe = PERIOD_D1;
    }
    
    // Crear Dashboard
    UpdateDashboard();
    
    Print("EA HaEmaMultV2i inicializado exitosamente.");
    return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
    ObjectDelete(0, "SL_Box");
    ObjectDelete(0, "TP_Box");
    ObjectsDeleteAll(0, "FastEmaLine_");
    ObjectsDeleteAll(0, "SlowEmaLine_");
    ClearDashboard();
}

//+------------------------------------------------------------------+
//| Helper para obtener el offset de Nueva York                      |
//+------------------------------------------------------------------+
int GetNewYorkGmtOffset(datetime time)
{
    MqlDateTime dt;
    TimeToStruct(time, dt);
    
    if(dt.mon < 3 || dt.mon > 11) return(-5);
    if(dt.mon > 3 && dt.mon < 11) return(-4);
    
    if(dt.mon == 3)
    {
        MqlDateTime march1st = dt;
        march1st.day = 1; march1st.hour = 0; march1st.min = 0; march1st.sec = 0;
        datetime m1Time = StructToTime(march1st);
        MqlDateTime m1Parsed;
        TimeToStruct(m1Time, m1Parsed);
        int firstSundayDay = 1 + (7 - m1Parsed.day_of_week) % 7;
        int secondSundayDay = firstSundayDay + 7;
        if(dt.day > secondSundayDay || (dt.day == secondSundayDay && dt.hour >= 2)) return(-4);
        return(-5);
    }
    
    if(dt.mon == 11)
    {
        MqlDateTime nov1st = dt;
        nov1st.day = 1; nov1st.hour = 0; nov1st.min = 0; nov1st.sec = 0;
        datetime n1Time = StructToTime(nov1st);
        MqlDateTime n1Parsed;
        TimeToStruct(n1Time, n1Parsed);
        int firstSundayDay = 1 + (7 - n1Parsed.day_of_week) % 7;
        if(dt.day > firstSundayDay || (dt.day == firstSundayDay && dt.hour >= 2)) return(-5);
        return(-4);
    }
    return(-5);
}

//+------------------------------------------------------------------+
//| Helper para estimar el offset GMT del broker estándar en backtest|
//+------------------------------------------------------------------+
int GetBrokerGmtOffset(datetime time)
{
    MqlDateTime dt;
    TimeToStruct(time, dt);
    if(dt.mon < 3 || dt.mon > 10) return(2);
    if(dt.mon > 3 && dt.mon < 10) return(3);
    if(dt.mon == 3)
    {
        MqlDateTime temp = dt;
        temp.day = 31; temp.hour = 0; temp.min = 0; temp.sec = 0;
        datetime tVal = StructToTime(temp);
        MqlDateTime parsed;
        TimeToStruct(tVal, parsed);
        int lastSunday = 31 - parsed.day_of_week;
        if(dt.day >= lastSunday) return(3);
        return(2);
    }
    if(dt.mon == 10)
    {
        MqlDateTime temp = dt;
        temp.day = 31; temp.hour = 0; temp.min = 0; temp.sec = 0;
        datetime tVal = StructToTime(temp);
        MqlDateTime parsed;
        TimeToStruct(tVal, parsed);
        int lastSunday = 31 - parsed.day_of_week;
        if(dt.day >= lastSunday) return(2);
        return(3);
    }
    return(2);
}

//+------------------------------------------------------------------+
//| Verificar si la sesión está activa                               |
//+------------------------------------------------------------------+
bool IsInSessionUTC(string sessStr, datetime evalTime)
{
    if(!useSession || sessStr == "") return(true);
    if(StringLen(sessStr) < 9) return(true);
    
    int startH = (int)StringToInteger(StringSubstr(sessStr, 0, 2));
    int startM = (int)StringToInteger(StringSubstr(sessStr, 2, 2));
    int endH = (int)StringToInteger(StringSubstr(sessStr, 5, 2));
    int endM = (int)StringToInteger(StringSubstr(sessStr, 7, 2));
    
    int autoBrokerGmtOffset = MQLInfoInteger(MQL_TESTER) ? GetBrokerGmtOffset(evalTime) : (int)MathRound((double)(evalTime - TimeGMT()) / 3600.0);
    int targetGmtOffset = timezoneMode == 0 ? GetNewYorkGmtOffset(evalTime) : (timezoneMode == 2 ? 0 : -6);
    
    int diffHours = targetGmtOffset - autoBrokerGmtOffset;
    datetime targetTime = evalTime + diffHours * 3600;
    
    MqlDateTime tgt;
    TimeToStruct(targetTime, tgt);
    
    int currMin = tgt.hour * 60 + tgt.min;
    int startMin = startH * 60 + startM;
    int endMin = endH * 60 + endM;
    
    return startMin < endMin ? (currMin >= startMin && currMin < endMin) : (currMin >= startMin || currMin < endMin);
}

//+------------------------------------------------------------------+
//| Helper para obtener el valor de un búfer de indicador            |
//+------------------------------------------------------------------+
double GetIndicatorValue(int handle, int bufferNum, int index)
{
    double values[1];
    return CopyBuffer(handle, bufferNum, index, 1, values) > 0 ? values[0] : 0.0;
}

//+------------------------------------------------------------------+
//| PnL de las operaciones cerradas en el día actual                 |
//+------------------------------------------------------------------+
double GetTodayClosedPnl()
{
    MqlDateTime dt;
    TimeToStruct(TimeCurrent(), dt);
    dt.hour = 0; dt.min = 0; dt.sec = 0;
    datetime dayStart = StructToTime(dt);
    
    if(!HistorySelect(dayStart, TimeCurrent())) return(0.0);
    
    double pnl = 0.0;
    int total = HistoryDealsTotal();
    for(int i = 0; i < total; i++)
    {
        ulong ticket = HistoryDealGetTicket(i);
        if(ticket == 0) continue;
        if(HistoryDealGetString(ticket, DEAL_SYMBOL) != Symbol()) continue;
        if((ulong)HistoryDealGetInteger(ticket, DEAL_MAGIC) != MagicNumber) continue;
        
        long entry = HistoryDealGetInteger(ticket, DEAL_ENTRY);
        if(entry != DEAL_ENTRY_OUT && entry != DEAL_ENTRY_INOUT) continue;
        
        pnl += HistoryDealGetDouble(ticket, DEAL_PROFIT);
        pnl += HistoryDealGetDouble(ticket, DEAL_SWAP);
        pnl += HistoryDealGetDouble(ticket, DEAL_COMMISSION);
    }
    return(pnl);
}

//+------------------------------------------------------------------+
//| Find first swing low (pivot low) backwards                      |
//+------------------------------------------------------------------+
double FindSwingLow(int radius)
{
    int size = radius * 4 + 100;
    double lows[];
    ArraySetAsSeries(lows, true);
    int copied = CopyLow(Symbol(), _Period, 0, size, lows);
    if(copied <= radius + 1) return(lows[1]);
    
    double lowestLow = 0.0;
    for(int i = radius + 1; i < copied - radius; i++)
    {
        bool isPivot = true;
        for(int j = -radius; j <= radius; j++)
        {
            if(lows[i] > lows[i + j])
            {
                isPivot = false;
                break;
            }
        }
        if(isPivot)
        {
            lowestLow = lows[i];
            break;
        }
    }
    if(lowestLow == 0.0)
    {
        int lowestIdx = ArrayMinimum(lows, 1, 10);
        lowestLow = lows[lowestIdx];
    }
    return(lowestLow);
}

//+------------------------------------------------------------------+
//| Find first swing high (pivot high) backwards                     |
//+------------------------------------------------------------------+
double FindSwingHigh(int radius)
{
    int size = radius * 4 + 100;
    double highs[];
    ArraySetAsSeries(highs, true);
    int copied = CopyHigh(Symbol(), _Period, 0, size, highs);
    if(copied <= radius + 1) return(highs[1]);
    
    double highestHigh = 0.0;
    for(int i = radius + 1; i < copied - radius; i++)
    {
        bool isPivot = true;
        for(int j = -radius; j <= radius; j++)
        {
            if(highs[i] < highs[i + j])
            {
                isPivot = false;
                break;
            }
        }
        if(isPivot)
        {
            highestHigh = highs[i];
            break;
        }
    }
    if(highestHigh == 0.0)
    {
        int highestIdx = ArrayMaximum(highs, 1, 10);
        highestHigh = highs[highestIdx];
    }
    return(highestHigh);
}

//+------------------------------------------------------------------+
//| Impulse MACD calculation matching LazyBear exact formulas       |
//+------------------------------------------------------------------+
double GetIMACD(int targetIndex, int len)
{
    int size = len * 6;
    double highs[], lows[], closes[];
    ArraySetAsSeries(highs, true);
    ArraySetAsSeries(lows, true);
    ArraySetAsSeries(closes, true);
    
    int copiedH = CopyHigh(Symbol(), _Period, 0, size, highs);
    int copiedL = CopyLow(Symbol(), _Period, 0, size, lows);
    int copiedC = CopyClose(Symbol(), _Period, 0, size, closes);
    
    int copied = MathMin(copiedH, MathMin(copiedL, copiedC));
    if(copied <= len * 2) return(0.0);
    size = copied;
    
    double hlc3[];
    ArrayResize(hlc3, size);
    ArraySetAsSeries(hlc3, true);
    for(int i = 0; i < size; i++)
    {
        hlc3[i] = (highs[i] + lows[i] + closes[i]) / 3.0;
    }
    
    double ema1[];
    ArrayResize(ema1, size);
    ArraySetAsSeries(ema1, true);
    double alpha = 2.0 / (len + 1.0);
    
    ema1[size - 1] = hlc3[size - 1];
    for(int i = size - 2; i >= 0; i--)
    {
        ema1[i] = hlc3[i] * alpha + ema1[i + 1] * (1.0 - alpha);
    }
    
    double ema2[];
    ArrayResize(ema2, size);
    ArraySetAsSeries(ema2, true);
    
    ema2[size - 1] = ema1[size - 1];
    for(int i = size - 2; i >= 0; i--)
    {
        ema2[i] = ema1[i] * alpha + ema2[i + 1] * (1.0 - alpha);
    }
    
    double mi = ema1[targetIndex] + (ema1[targetIndex] - ema2[targetIndex]);
    
    double hi = highs[targetIndex];
    double lo = lows[targetIndex];
    for(int i = 1; i < len; i++)
    {
        if(highs[targetIndex + i] > hi) hi = highs[targetIndex + i];
        if(lows[targetIndex + i] < lo) lo = lows[targetIndex + i];
    }
    
    double sumH = 0, sumL = 0;
    for(int i = 0; i < len; i++) { sumH += highs[targetIndex + i]; sumL += lows[targetIndex + i]; }
    double smmaH = sumH / len;
    double smmaL = sumL / len;
    
    if(mi > smmaH) return(mi - smmaH);
    if(mi < smmaL) return(mi - smmaL);
    return(0.0);
}

//+------------------------------------------------------------------+
//| Recursive Heikin-Ashi calculation over historical candles       |
//+------------------------------------------------------------------+
bool GetHeikinAshi(HeikinAshiBar &haBars[])
{
    int count = ArraySize(haBars);
    MqlRates rates[];
    if(CopyRates(Symbol(), _Period, 0, count + 100, rates) <= 0) return(false);
    
    int copied = ArraySize(rates);
    if(copied < count) return(false);
    
    double haO[], haC[], haH[], haL[];
    ArrayResize(haO, copied);
    ArrayResize(haC, copied);
    ArrayResize(haH, copied);
    ArrayResize(haL, copied);
    
    haO[0] = (rates[0].open + rates[0].close) / 2.0;
    haC[0] = (rates[0].open + rates[0].high + rates[0].low + rates[0].close) / 4.0;
    haH[0] = MathMax(rates[0].high, MathMax(haO[0], haC[0]));
    haL[0] = MathMin(rates[0].low, MathMin(haO[0], haC[0]));
    
    for(int i = 1; i < copied; i++)
    {
        haC[i] = (rates[i].open + rates[i].high + rates[i].low + rates[i].close) / 4.0;
        haO[i] = (haO[i - 1] + haC[i - 1]) / 2.0;
        haH[i] = MathMax(rates[i].high, MathMax(haO[i], haC[i]));
        haL[i] = MathMin(rates[i].low, MathMin(haO[i], haC[i]));
    }
    
    for(int i = 0; i < count; i++)
    {
        int srcIdx = copied - 1 - i;
        if(srcIdx >= 0 && srcIdx < copied)
        {
            haBars[i].open = haO[srcIdx];
            haBars[i].close = haC[srcIdx];
            haBars[i].high = haH[srcIdx];
            haBars[i].low = haL[srcIdx];
        }
    }
    return(true);
}

//+------------------------------------------------------------------+
//| Detección de Posición Propia (MQ5-CRITICAL #1 & #2)             |
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
//| Dibujar rectángulos iniciales de SL y TP                         |
//+------------------------------------------------------------------+
void DrawInitBoxes(datetime entryTime, double entryPrice, double slVal, double tpVal)
{
    ObjectDelete(0, "SL_Box");
    ObjectDelete(0, "TP_Box");
    entryT = entryTime;
    
    datetime endTime = entryTime + PeriodSeconds(PERIOD_CURRENT) * 20; // Visible por 20 velas
    
    // Caja SL (Rojo transparente)
    ObjectCreate(0, "SL_Box", OBJ_RECTANGLE, 0, entryTime, entryPrice, endTime, slVal);
    ObjectSetInteger(0, "SL_Box", OBJPROP_COLOR, C'255, 220, 220');
    ObjectSetInteger(0, "SL_Box", OBJPROP_FILL, true);
    ObjectSetInteger(0, "SL_Box", OBJPROP_BACK, true);
    ObjectSetInteger(0, "SL_Box", OBJPROP_SELECTABLE, false);
    
    if(tpVal > 0.0)
    {
        // Caja TP (Verde transparente)
        ObjectCreate(0, "TP_Box", OBJ_RECTANGLE, 0, entryTime, entryPrice, endTime, tpVal);
        ObjectSetInteger(0, "TP_Box", OBJPROP_COLOR, C'220, 255, 220');
        ObjectSetInteger(0, "TP_Box", OBJPROP_FILL, true);
        ObjectSetInteger(0, "TP_Box", OBJPROP_BACK, true);
        ObjectSetInteger(0, "TP_Box", OBJPROP_SELECTABLE, false);
    }
    ChartRedraw(0);
}

//+------------------------------------------------------------------+
//| Actualizar cajas en base a los nuevos valores de SL y TP         |
//+------------------------------------------------------------------+
void UpdateTradeBoxes(double entryPrice, double slVal, double tpVal)
{
    datetime boxStart = entryT;
    if(boxStart == 0)
    {
        boxStart = (datetime)ObjectGetInteger(0, "SL_Box", OBJPROP_TIME, 0);
        if(boxStart == 0) boxStart = TimeCurrent();
    }
    
    datetime boxEnd = TimeCurrent() + PeriodSeconds(PERIOD_CURRENT) * 20;
    
    if(ObjectFind(0, "SL_Box") >= 0)
    {
        ObjectMove(0, "SL_Box", 0, boxStart, entryPrice);
        ObjectMove(0, "SL_Box", 1, boxEnd, slVal);
    }
    else
    {
        ObjectCreate(0, "SL_Box", OBJ_RECTANGLE, 0, boxStart, entryPrice, boxEnd, slVal);
        ObjectSetInteger(0, "SL_Box", OBJPROP_COLOR, C'255, 220, 220');
        ObjectSetInteger(0, "SL_Box", OBJPROP_FILL, true);
        ObjectSetInteger(0, "SL_Box", OBJPROP_BACK, true);
        ObjectSetInteger(0, "SL_Box", OBJPROP_SELECTABLE, false);
    }
    
    if(tpVal > 0.0)
    {
        if(ObjectFind(0, "TP_Box") >= 0)
        {
            ObjectMove(0, "TP_Box", 0, boxStart, entryPrice);
            ObjectMove(0, "TP_Box", 1, boxEnd, tpVal);
        }
        else
        {
            ObjectCreate(0, "TP_Box", OBJ_RECTANGLE, 0, boxStart, entryPrice, boxEnd, tpVal);
            ObjectSetInteger(0, "TP_Box", OBJPROP_COLOR, C'220, 255, 220');
            ObjectSetInteger(0, "TP_Box", OBJPROP_FILL, true);
            ObjectSetInteger(0, "TP_Box", OBJPROP_BACK, true);
            ObjectSetInteger(0, "TP_Box", OBJPROP_SELECTABLE, false);
        }
    }
    else
    {
        ObjectDelete(0, "TP_Box");
    }
    ChartRedraw(0);
}

//+------------------------------------------------------------------+
//| Dibujar marcas visuales en el gráfico para cruces y convergencias|
//+------------------------------------------------------------------+
void DrawSetupMark(datetime signalTime, int direction)
{
    string objName = "Mark_" + TimeToString(signalTime);
    if(ObjectFind(0, objName) >= 0) return;
    
    double price = 0.0;
    int shift = iBarShift(Symbol(), _Period, signalTime);
    if(shift >= 0)
    {
        double range = iHigh(Symbol(), _Period, shift) - iLow(Symbol(), _Period, shift);
        if(range <= 0.0) range = 100 * SymbolInfoDouble(Symbol(), SYMBOL_POINT);
        price = direction == 1 ? iLow(Symbol(), _Period, shift) - (range * 0.3) : (direction == -1 ? iHigh(Symbol(), _Period, shift) + (range * 0.3) : (iHigh(Symbol(), _Period, shift) + iLow(Symbol(), _Period, shift)) / 2.0);
    }
    else
    {
        price = SymbolInfoDouble(Symbol(), SYMBOL_BID);
    }
    
    uchar code = direction == 1 ? 241 : (direction == -1 ? 242 : 159);
    color clr = direction == 1 ? clrLime : (direction == -1 ? clrRed : clrYellow);
    
    if(ObjectCreate(0, objName, OBJ_ARROW, 0, signalTime, price))
    {
        ObjectSetInteger(0, objName, OBJPROP_ARROWCODE, code);
        ObjectSetInteger(0, objName, OBJPROP_COLOR, clr);
        ObjectSetInteger(0, objName, OBJPROP_WIDTH, 2);
    }
}

//+------------------------------------------------------------------+
//| Dashboard Informativo Premium en el gráfico                      |
//+------------------------------------------------------------------+
void UpdateDashboard()
{
    string prefix = "DB_";
    string labels[] = {
        "Estrategia:", "HaEmaMultV2i",
        "Perfil:", "",
        "Estado:", "",
        "Sesion:", "",
        "ATR:", "",
        "iMACD:", "",
        "Equidad:", "",
        "Rendimiento:", ""
    };
    
    string profileName = InpAssetProfile;
    if(profileName == "Auto")
    {
        if(isGold) profileName = "ORO (Auto)";
        else if(isSilver) profileName = "PLATA (Auto)";
        else if(isBitcoin) profileName = "BTC (Auto)";
        else if(isNasdaq) profileName = "NASDAQ (Auto)";
        else profileName = "MANUAL";
    }
    
    bool inTrade = GetOwnPositionType() != -1;
    bool inSession = IsInSessionUTC(sessionStr, TimeCurrent());
    double atrVal = CalculateATR(1, atrFilterLen);
    
    double md = GetIMACD(1, imacdLen);
    string imacdStatus = (!useIMACD) ? "DESACTIVADO" : (md == 0.0 ? "RANGO" : (md > 0.0 ? "ALCISTA" : "BAJISTA"));
    color imacdColor = (!useIMACD) ? clrGray : (md == 0.0 ? clrOrange : (md > 0.0 ? clrGreen : clrRed));
    atrValini = atrVal;
    
    labels[3] = profileName;
    labels[5] = inTrade ? "DENTRO" : "BUSCANDO";
    labels[7] = inSession ? "ACTIVA" : "CERRADA";
    labels[9] = DoubleToString(atrVal, 2) + " USD";
    labels[11] = imacdStatus;
    labels[13] = "$" + DoubleToString(AccountInfoDouble(ACCOUNT_EQUITY), 2);
    labels[15] = DoubleToString(GetTodayClosedPnl(), 2) + " USD";
    
    int startX = 220;
    int startY = 40;
    int rowHeight = 16;
    int colWidth = 100;
    
    for(int i = 0; i < 8; i++)
    {
        string nameKey = prefix + "Key_" + (string)i;
        string nameVal = prefix + "Val_" + (string)i;
        
        if(ObjectFind(0, nameKey) < 0)
        {
            ObjectCreate(0, nameKey, OBJ_LABEL, 0, 0, 0);
            ObjectSetInteger(0, nameKey, OBJPROP_CORNER, CORNER_RIGHT_UPPER);
            ObjectSetInteger(0, nameKey, OBJPROP_XDISTANCE, startX);
            ObjectSetInteger(0, nameKey, OBJPROP_YDISTANCE, startY + i * rowHeight);
            ObjectSetString(0, nameKey, OBJPROP_FONT, "Outfit");
            ObjectSetInteger(0, nameKey, OBJPROP_FONTSIZE, 9);
            ObjectSetInteger(0, nameKey, OBJPROP_COLOR, clrWhite);
            ObjectSetInteger(0, nameKey, OBJPROP_SELECTABLE, false);
        }
        ObjectSetString(0, nameKey, OBJPROP_TEXT, labels[i * 2]);
        
        if(ObjectFind(0, nameVal) < 0)
        {
            ObjectCreate(0, nameVal, OBJ_LABEL, 0, 0, 0);
            ObjectSetInteger(0, nameVal, OBJPROP_CORNER, CORNER_RIGHT_UPPER);
            ObjectSetInteger(0, nameVal, OBJPROP_XDISTANCE, startX - colWidth);
            ObjectSetInteger(0, nameVal, OBJPROP_YDISTANCE, startY + i * rowHeight);
            ObjectSetString(0, nameVal, OBJPROP_FONT, "Outfit");
            ObjectSetInteger(0, nameVal, OBJPROP_FONTSIZE, 9);
            ObjectSetInteger(0, nameVal, OBJPROP_COLOR, clrYellow);
            ObjectSetInteger(0, nameVal, OBJPROP_SELECTABLE, false);
        }
        ObjectSetString(0, nameVal, OBJPROP_TEXT, labels[i * 2 + 1]);
        
        if(i == 0) ObjectSetInteger(0, nameVal, OBJPROP_COLOR, clrYellow);
        if(i == 1) ObjectSetInteger(0, nameVal, OBJPROP_COLOR, clrLightBlue);
        if(i == 2) ObjectSetInteger(0, nameVal, OBJPROP_COLOR, inTrade ? clrGreen : clrOrange);
        if(i == 3) ObjectSetInteger(0, nameVal, OBJPROP_COLOR, inSession ? clrGreen : clrGray);
        if(i == 4) ObjectSetInteger(0, nameVal, OBJPROP_COLOR, clrGreen);
        if(i == 5) ObjectSetInteger(0, nameVal, OBJPROP_COLOR, imacdColor);
        if(i == 6) ObjectSetInteger(0, nameVal, OBJPROP_COLOR, clrGreen);
        if(i == 7) ObjectSetInteger(0, nameVal, OBJPROP_COLOR, GetTodayClosedPnl() >= 0 ? clrGreen : clrRed);
    }
    ChartRedraw(0);
}

//+------------------------------------------------------------------+
//| Limpieza de dashboard al cerrar                                  |
//+------------------------------------------------------------------+
void ClearDashboard()
{
    string prefix = "DB_";
    for(int i = 0; i < 8; i++)
    {
        ObjectDelete(0, prefix + "Key_" + (string)i);
        ObjectDelete(0, prefix + "Val_" + (string)i);
    }
}

//+------------------------------------------------------------------+
//| Gestión activa de posiciones (Trailing y TP Chasing en cada Tick)|
//+------------------------------------------------------------------+
void ManageActivePosition()
{
    int posType = GetOwnPositionType();
    if(posType == -1)
    {
        if(posActiveLastTick)
        {
            activeSL = 0.0; activeTP = 0.0; entryP = 0.0; entryT = 0;
            slPart = 0.0; tpPart = 0.0;
            pasoLaMitad = false; slTrail = false; tpChaseSlGap = 0.0; beAplicado = false;
            ObjectDelete(0, "SL_Box");
            ObjectDelete(0, "TP_Box");
            UpdateDashboard();
        }
        posActiveLastTick = false;
        return;
    }
    
    bool inLong = (posType == POSITION_TYPE_BUY);
    bool inShort = (posType == POSITION_TYPE_SELL);
    double currentSL = PositionGetDouble(POSITION_SL);
    double currentTP = PositionGetDouble(POSITION_TP);
    
    if(!posActiveLastTick)
    {
        entryP = PositionGetDouble(POSITION_PRICE_OPEN);
        activeSL = currentSL;
        activeTP = currentTP;
        entryT = (datetime)PositionGetInteger(POSITION_TIME);
        
        slPart = MathAbs(entryP - activeSL) / trailDivisions;
        tpPart = (activeTP > 0.0) ? MathAbs(activeTP - entryP) / (double)trailDivisions : 0.0;
        
        pasoLaMitad = false; slTrail = false; tpChaseSlGap = 0.0; beAplicado = false;
        posActiveLastTick = true;
        
        DrawInitBoxes(entryT, entryP, activeSL, activeTP);
        UpdateDashboard();
    }
    
    if(slPart <= 0.0 && activeSL > 0.0) slPart = MathAbs(entryP - activeSL) / trailDivisions;
    if(tpPart <= 0.0 && activeTP > 0.0) tpPart = MathAbs(activeTP - entryP) / (double)trailDivisions;
    
    double bid = SymbolInfoDouble(Symbol(), SYMBOL_BID);
    double ask = SymbolInfoDouble(Symbol(), SYMBOL_ASK);
    double point = SymbolInfoDouble(Symbol(), SYMBOL_POINT);
    int digits = (int)SymbolInfoInteger(Symbol(), SYMBOL_DIGITS);
    double stopsDistance = MathMax((double)SymbolInfoInteger(Symbol(), SYMBOL_TRADE_STOPS_LEVEL), minStopsLevel) * point;
    
    double currentHigh = iHigh(Symbol(), _Period, 0);
    double currentLow = iLow(Symbol(), _Period, 0);
    double atrVal = CalculateATR(1, atrFilterLen);
    
    double chaseOffset = isGold ? (tpChaseOffset * atrVal) : tpChaseOffset;
    bool modified = false;
    
    if(inLong)
    {
        if(useBE && !beAplicado && activeTP > 0.0 && bid >= entryP + MathAbs(activeTP - entryP) / 2.0 && activeSL < entryP)
        {
            activeSL = entryP;
            beAplicado = true;
            modified = true;
        }
        
        double recorridoMax = currentHigh - entryP;
        
        if(!slTrail)
        {
            bool cercaDelTP = useTPChase && (activeTP > 0.0) && (activeTP - currentHigh <= tpChasePts);
            if(recorridoMax >= (tpPart * (trailDivisions - 1.0)) || cercaDelTP)
            {
                double tpDistTotal = tpPart * trailDivisions;
                if((activeSL < entryP + (tpDistTotal / 2.0)) && !pasoLaMitad && !cercaDelTP)
                {
                    activeSL = NormalizeDouble(entryP + (tpDistTotal / 2.0), digits);
                    pasoLaMitad = true;
                    modified = true;
                }
                else
                {
                    slTrail = true;
                    tpChaseSlGap = MathMax(currentHigh - activeSL, point);
                }
            }
            else
            {
                for(int i = (int)(trailDivisions - 2); i >= 1; i--)
                {
                    if(recorridoMax >= (tpPart * i))
                    {
                        double nuevoSL = NormalizeDouble(entryP - (slPart * (trailDivisions - i)), digits);
                        if(nuevoSL > activeSL)
                        {
                            activeSL = nuevoSL;
                            modified = true;
                        }
                        break;
                    }
                }
            }
        }
        
        if(slTrail && tpChaseSlGap > 0.0)
        {
            double trailingSL = NormalizeDouble(currentHigh - tpChaseSlGap, digits);
            double maxValidSL = bid - stopsDistance;
            if(trailingSL > maxValidSL) trailingSL = maxValidSL;
            trailingSL = NormalizeDouble(trailingSL, digits);
            
            if(trailingSL > activeSL)
            {
                activeSL = trailingSL;
                modified = true;
            }
            
            if(useTPChase && (activeTP > 0.0) && (activeTP - currentHigh <= tpChasePts))
            {
                double potTP = NormalizeDouble(currentHigh + chaseOffset, digits);
                if(potTP > activeTP)
                {
                    activeTP = potTP;
                    modified = true;
                }
            }
        }
    }
    else if(inShort)
    {
        if(useBE && !beAplicado && activeTP > 0.0 && ask <= entryP - MathAbs(entryP - activeTP) / 2.0 && (activeSL > entryP || activeSL == 0.0))
        {
            activeSL = entryP;
            beAplicado = true;
            modified = true;
        }
        
        double recorridoMax = entryP - currentLow;
        
        if(!slTrail)
        {
            bool cercaDelTP = useTPChase && (activeTP > 0.0) && (currentLow - activeTP <= tpChasePts);
            if(recorridoMax >= (tpPart * (trailDivisions - 1.0)) || cercaDelTP)
            {
                double tpDistTotal = tpPart * trailDivisions;
                if((activeSL > entryP - (tpDistTotal / 2.0) || activeSL == 0.0) && !pasoLaMitad && !cercaDelTP)
                {
                    activeSL = NormalizeDouble(entryP - (tpDistTotal / 2.0), digits);
                    pasoLaMitad = true;
                    modified = true;
                }
                else
                {
                    slTrail = true;
                    tpChaseSlGap = MathMax(activeSL - currentLow, point);
                }
            }
            else
            {
                for(int i = (int)(trailDivisions - 2); i >= 1; i--)
                {
                    if(recorridoMax >= (tpPart * i))
                    {
                        double nuevoSL = NormalizeDouble(entryP + (slPart * (trailDivisions - i)), digits);
                        if(nuevoSL < activeSL || activeSL == 0.0)
                        {
                            activeSL = nuevoSL;
                            modified = true;
                        }
                        break;
                    }
                }
            }
        }
        
        if(slTrail && tpChaseSlGap > 0.0)
        {
            double trailingSL = NormalizeDouble(currentLow + tpChaseSlGap, digits);
            double minValidSL = ask + stopsDistance;
            if(trailingSL < minValidSL) trailingSL = minValidSL;
            trailingSL = NormalizeDouble(trailingSL, digits);
            
            if(trailingSL < activeSL || activeSL == 0.0)
            {
                activeSL = trailingSL;
                modified = true;
            }
            
            if(useTPChase && (activeTP > 0.0) && (currentLow - activeTP <= tpChasePts))
            {
                double potTP = NormalizeDouble(currentLow - chaseOffset, digits);
                if(potTP < activeTP || activeTP == 0.0)
                {
                    activeTP = potTP;
                    modified = true;
                }
            }
        }
    }
    
    if(modified || currentSL != activeSL || currentTP != activeTP)
    {
        if(inLong)
        {
            double maxValidSL = bid - stopsDistance;
            if(activeSL > maxValidSL) activeSL = NormalizeDouble(maxValidSL, digits);
            if(activeTP > 0.0)
            {
                double minValidTP = bid + stopsDistance;
                if(activeTP < minValidTP) activeTP = NormalizeDouble(minValidTP, digits);
            }
        }
        else if(inShort)
        {
            double minValidSL = ask + stopsDistance;
            if(activeSL < minValidSL) activeSL = NormalizeDouble(minValidSL, digits);
            if(activeTP > 0.0)
            {
                double maxValidTP = ask - stopsDistance;
                if(activeTP > maxValidTP) activeTP = NormalizeDouble(maxValidTP, digits);
            }
        }
        
        double diffSL = MathAbs(activeSL - currentSL);
        double diffTP = MathAbs(activeTP - currentTP);
        
        if(diffSL >= 5.0 * point || diffTP >= 5.0 * point)
        {
            if (trade.PositionModify(Symbol(), activeSL, activeTP))
            {
                UpdateTradeBoxes(entryP, activeSL, activeTP);
            }
        }
    }
}

//+------------------------------------------------------------------+
//| Calcular EMAs de forma matemática sin usar handles de MT5        |
//+------------------------------------------------------------------+
void CalculateEMAs(int count, double &fast[], double &slow[])
{
    int size = count + 200;
    double closes[];
    ArraySetAsSeries(closes, true);
    int copied = CopyClose(Symbol(), resolvedTimeframe, 0, size, closes);
    if(copied <= 0) return;
    size = copied;
    
    ArrayResize(fast, size);
    ArrayResize(slow, size);
    
    ArraySetAsSeries(fast, true);
    ArraySetAsSeries(slow, true);
    
    double alphaF = 2.0 / (fastLen + 1.0);
    double alphaS = 2.0 / (slowLen + 1.0);
    
    fast[size - 1] = closes[size - 1];
    slow[size - 1] = closes[size - 1];
    
    for(int i = size - 2; i >= 0; i--)
    {
        fast[i]  = closes[i] * alphaF + fast[i + 1] * (1.0 - alphaF);
        slow[i]  = closes[i] * alphaS + slow[i + 1] * (1.0 - alphaS);
    }
}

//+------------------------------------------------------------------+
//| Dibujar líneas continuas de las EMAs                             |
//+------------------------------------------------------------------+
void DrawEMALines()
{
    ObjectsDeleteAll(0, "FastEmaLine_");
    ObjectsDeleteAll(0, "SlowEmaLine_");
    
    double rawFast[], rawSlow[];
    CalculateEMAs(250, rawFast, rawSlow);
    
    int rawSize = ArraySize(rawFast);
    if(rawSize <= 0) return;
    
    double fast[], slow[];
    ArrayResize(fast, 150);
    ArrayResize(slow, 150);
    
    ArraySetAsSeries(fast, true);
    ArraySetAsSeries(slow, true);
    
    for(int i = 0; i < 150; i++)
    {
        datetime t = iTime(Symbol(), _Period, i);
        int shift = iBarShift(Symbol(), resolvedTimeframe, t);
        if(shift < 0 || shift >= rawSize) shift = i;
        
        fast[i]  = rawFast[shift];
        slow[i]  = rawSlow[shift];
    }
    
    for(int i = 0; i < 149; i++)
    {
        datetime t1 = iTime(Symbol(), _Period, i);
        datetime t2 = iTime(Symbol(), _Period, i + 1);
        if(t1 <= 0 || t2 <= 0) continue;
        
        string nameF = "FastEmaLine_" + IntegerToString(i);
        string nameS = "SlowEmaLine_" + IntegerToString(i);
        
        if(ObjectCreate(0, nameF, OBJ_TREND, 0, t2, fast[i+1], t1, fast[i]))
        {
            ObjectSetInteger(0, nameF, OBJPROP_COLOR, clrGreen);
            ObjectSetInteger(0, nameF, OBJPROP_WIDTH, 2);
            ObjectSetInteger(0, nameF, OBJPROP_RAY_RIGHT, false);
            ObjectSetInteger(0, nameF, OBJPROP_SELECTABLE, false);
            ObjectSetInteger(0, nameF, OBJPROP_BACK, true);
        }
        else
        {
            ObjectMove(0, nameF, 0, t2, fast[i+1]);
            ObjectMove(0, nameF, 1, t1, fast[i]);
        }
        
        if(ObjectCreate(0, nameS, OBJ_TREND, 0, t2, slow[i+1], t1, slow[i]))
        {
            ObjectSetInteger(0, nameS, OBJPROP_COLOR, clrOrange);
            ObjectSetInteger(0, nameS, OBJPROP_WIDTH, 2);
            ObjectSetInteger(0, nameS, OBJPROP_RAY_RIGHT, false);
            ObjectSetInteger(0, nameS, OBJPROP_SELECTABLE, false);
            ObjectSetInteger(0, nameS, OBJPROP_BACK, true);
        }
        else
        {
            ObjectMove(0, nameS, 0, t2, slow[i+1]);
            ObjectMove(0, nameS, 1, t1, slow[i]);
        }
    }
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
    if(MQLInfoInteger(MQL_TESTER))
    {
        int totalWindows = (int)ChartGetInteger(0, CHART_WINDOWS_TOTAL);
        if(totalWindows > 1)
        {
            for(int w = totalWindows - 1; w > 0; w--)
            {
                int totalIndicators = ChartIndicatorsTotal(0, w);
                for(int i = totalIndicators - 1; i >= 0; i--)
                {
                    string name = ChartIndicatorName(0, w, i);
                    if(name != "") ChartIndicatorDelete(0, w, name);
                }
            }
        }
    }

    // 1. Gestión activa de la posición en cada Tick
    ManageActivePosition();
    
    // 2. Filtro de nueva vela para la evaluación de señales de entrada
    datetime currentBarTime = iTime(Symbol(), _Period, 0);
    if(currentBarTime == lastBarTime) return;
    lastBarTime = currentBarTime;
    
    DrawEMALines();
    UpdateDashboard();
    
    // ============================================================================
    // EVALUACIÓN DE SEÑALES DE ENTRADA (Sobre velas cerradas)
    // ============================================================================
    double emaFastVal[], emaSlowVal[];
    double atrVal[], adxVal[];
    
    ArrayResize(emaFastVal, 210);
    ArrayResize(emaSlowVal, 210);
    ArrayResize(atrVal, 210);
    ArrayResize(adxVal, 20);
    
    ArraySetAsSeries(emaFastVal, true);
    ArraySetAsSeries(emaSlowVal, true);
    ArraySetAsSeries(atrVal, true);
    ArraySetAsSeries(adxVal, true);
    
    for(int i = 0; i < 210; i++) atrVal[i] = CalculateATR(i, atrFilterLen);
    for(int i = 0; i < 20; i++)
    {
        adxVal[i] = CalculateADX(i, adxLen);
    }
    
    double rawFast[], rawSlow[];
    CalculateEMAs(250, rawFast, rawSlow);
    int rawSize = ArraySize(rawFast);
    if(rawSize <= 0) return;
    
    for(int i = 0; i < 210; i++)
    {
        datetime t = iTime(Symbol(), _Period, i);
        int shift = iBarShift(Symbol(), resolvedTimeframe, t);
        if(shift < 0 || shift >= rawSize) shift = i;
        
        emaFastVal[i] = rawFast[shift];
        emaSlowVal[i] = rawSlow[shift];
    }
    
    HeikinAshiBar haBars[20];
    ZeroMemory(haBars);
    if(!GetHeikinAshi(haBars)) return;
    
    bool haGreen = haBars[1].close > haBars[1].open;
    bool haRed = haBars[1].close < haBars[1].open;
    
    double candleOpen = iOpen(Symbol(), _Period, 1);
    double candleClose = iClose(Symbol(), _Period, 1);
    bool candleGreen = candleClose > candleOpen;
    bool candleRed = candleClose < candleOpen;
    double body = MathAbs(candleClose - candleOpen);
    
    bool strongBull = candleGreen && (body >= atrVal[1] * bodyMinMult);
    bool strongBear = candleRed && (body >= atrVal[1] * bodyMinMult);
    
    bool inSession = IsInSessionUTC(sessionStr, iTime(Symbol(), _Period, 1));
    double distEMAs = MathAbs(emaFastVal[1] - emaSlowVal[1]);
    bool aberturaOK = !useEMASpread || (distEMAs >= (atrVal[1] * emaSpreadMult));
    
    double md = GetIMACD(1, imacdLen);
    bool imacdLongOK = !useIMACD || (md >= 0.0);
    bool imacdShortOK = !useIMACD || (md <= 0.0);
    
    bool haStrengthLong = !useHAStrength || (haBars[1].low == haBars[1].open);
    bool haStrengthShort = !useHAStrength || (haBars[1].high == haBars[1].open);
    
    bool adxOK = !useADX || (adxVal[1] >= adxMin);
    bool atrOK = !useATRMin || (atrVal[1] >= atrMinUSD);
    
    bool sobreextendido = false;
    if(maxOverextensionMult > 0.0)
    {
        double slowEmaVal = emaSlowVal[1];
        double closePrice = iClose(Symbol(), _Period, 1);
        double atrValue = atrVal[1];
        if(closePrice - slowEmaVal > maxOverextensionMult * atrValue || slowEmaVal - closePrice > maxOverextensionMult * atrValue)
        {
            sobreextendido = true;
        }
    }
    

    
    pendingLongSignal = false;
    pendingShortSignal = false;
    signalSetupTime = 0;
    
    bool mercadoLateral = useIMACD && (md == 0.0) && !strongBull && !strongBear;
    
    bool cruceLongActivo = false;
    bool cruceShortActivo = false;
    datetime timeUltimoCruce = 0;
    for(int i = 1; i < 200; i++)
    {
        if(emaFastVal[i] > emaSlowVal[i] && emaFastVal[i+1] <= emaSlowVal[i+1])
        {
            cruceLongActivo = true;
            timeUltimoCruce = iTime(Symbol(), _Period, i);
            break;
        }
        else if(emaFastVal[i] < emaSlowVal[i] && emaFastVal[i+1] >= emaSlowVal[i+1])
        {
            cruceShortActivo = true;
            timeUltimoCruce = iTime(Symbol(), _Period, i);
            break;
        }
    }
    
    if(mercadoLateral)
    {
        banderaState = "niCompraNiVenta";
    }
    else
    {
        if(cruceLongActivo)
        {
            banderaState = "posibleCompra";
            signalSetupTime = timeUltimoCruce;
            DrawSetupMark(signalSetupTime, 1);
        }
        else if(cruceShortActivo)
        {
            banderaState = "posibleVenta";
            signalSetupTime = timeUltimoCruce;
            DrawSetupMark(signalSetupTime, -1);
        }
    }
    
    pendingLongSignal = (banderaState == "posibleCompra");
    pendingShortSignal = (banderaState == "posibleVenta");
    
    bool triggerLong = pendingLongSignal && strongBull && imacdLongOK; // && candleGreen && haGreen && haStrengthLong && inSession && aberturaOK && atrOK && adxOK && !sobreextendido;
    bool triggerShort = pendingShortSignal && strongBear && imacdShortOK; // && candleRed && haRed && haStrengthShort && inSession && aberturaOK && atrOK && adxOK && !sobreextendido;
    
    double spreadVal = (double)SymbolInfoInteger(Symbol(), SYMBOL_SPREAD);
    bool spreadOk = (spreadVal <= maxSpreadPoints);
    
    if(GetOwnPositionType() != -1) return;
    
    double point = SymbolInfoDouble(Symbol(), SYMBOL_POINT);
    int digits = (int)SymbolInfoInteger(Symbol(), SYMBOL_DIGITS);
    atrValini = atrVal[1];
    
    if(triggerLong)
    {
        int pivotRadius = (int)MathMax(2.0, MathFloor(swingPeriod / 2.0));
        double lowestLow = FindSwingLow(pivotRadius);
        if(lowestLow <= 0.0) return;
        
        double slBuffer = slBufferPts * point;
        double slPrice = NormalizeDouble(lowestLow - slBuffer, digits);
        double ask = SymbolInfoDouble(Symbol(), SYMBOL_ASK);
        
        if(slPrice >= ask) slPrice = NormalizeDouble(ask - point, digits);
        
        double currentRisk = ask - slPrice;
        double minSLDist = minStopsLevel * point;
        if(currentRisk < minSLDist)
        {
            currentRisk = minSLDist;
            slPrice = NormalizeDouble(ask - currentRisk, digits);
        }
        
        double tpPrice = useTP ? NormalizeDouble(ask + atrValini * rrRatio, digits) : 0.0;
        double lots = 0.0;
        double tickValue = SymbolInfoDouble(Symbol(), SYMBOL_TRADE_TICK_VALUE);
        double tickSize = SymbolInfoDouble(Symbol(), SYMBOL_TRADE_TICK_SIZE);
        if(tickValue <= 0.0) tickValue = 1.0;
        if(tickSize <= 0.0) tickSize = point;
        
        if(useFixedLot) lots = fixedLotValue;
        else
        {
            double riskAmt = AccountInfoDouble(ACCOUNT_EQUITY) * (InpRiskPerc / 100.0);
            lots = riskAmt / ((currentRisk / tickSize) * tickValue);
        }
        
        double minLot = SymbolInfoDouble(Symbol(), SYMBOL_VOLUME_MIN);
        double maxLot = SymbolInfoDouble(Symbol(), SYMBOL_VOLUME_MAX);
        double stepLot = SymbolInfoDouble(Symbol(), SYMBOL_VOLUME_STEP);
        lots = MathFloor(lots / stepLot) * stepLot;
        if(lots < minLot) lots = minLot;
        if(lots > maxLot) lots = maxLot;
        
        double riskInMoney = lots * (currentRisk / tickSize) * tickValue;
        double maxRiskMoney = AccountInfoDouble(ACCOUNT_EQUITY) * (maxRiskPerc / 100.0);
        bool riskMaxOk = (riskInMoney <= maxRiskMoney);
        
        if(riskMaxOk && spreadOk && lots > 0.0)
        {
            if(trade.Buy(lots, Symbol(), ask, slPrice, tpPrice, "HaEmaMultV2i Long"))
            {
                lastEntryTimeLong = currentBarTime;
                pendingLongSignal = false;
                signalSetupTime = 0;
                DrawInitBoxes(currentBarTime, ask, slPrice, tpPrice);
                UpdateDashboard();
            }
        }
    }
    else if(triggerShort)
    {
        int pivotRadius = (int)MathMax(2.0, MathFloor(swingPeriod / 2.0));
        double highestHigh = FindSwingHigh(pivotRadius);
        if(highestHigh <= 0.0) return;
        
        double slBuffer = slBufferPts * point;
        double slPrice = NormalizeDouble(highestHigh + slBuffer, digits);
        double bid = SymbolInfoDouble(Symbol(), SYMBOL_BID);
        
        if(slPrice <= bid) slPrice = NormalizeDouble(bid + point, digits);
        
        double currentRisk = slPrice - bid;
        double minSLDist = minStopsLevel * point;
        if(currentRisk < minSLDist)
        {
            currentRisk = minSLDist;
            slPrice = NormalizeDouble(bid + currentRisk, digits);
        }
        
        double tpPrice = useTP ? NormalizeDouble(bid - atrValini * rrRatio, digits) : 0.0;
        double lots = 0.0;
        double tickValue = SymbolInfoDouble(Symbol(), SYMBOL_TRADE_TICK_VALUE);
        double tickSize = SymbolInfoDouble(Symbol(), SYMBOL_TRADE_TICK_SIZE);
        if(tickValue <= 0.0) tickValue = 1.0;
        if(tickSize <= 0.0) tickSize = point;
        
        if(useFixedLot) lots = fixedLotValue;
        else
        {
            double riskAmt = AccountInfoDouble(ACCOUNT_EQUITY) * (InpRiskPerc / 100.0);
            lots = riskAmt / ((currentRisk / tickSize) * tickValue);
        }
        
        double minLot = SymbolInfoDouble(Symbol(), SYMBOL_VOLUME_MIN);
        double maxLot = SymbolInfoDouble(Symbol(), SYMBOL_VOLUME_MAX);
        double stepLot = SymbolInfoDouble(Symbol(), SYMBOL_VOLUME_STEP);
        lots = MathFloor(lots / stepLot) * stepLot;
        if(lots < minLot) lots = minLot;
        if(lots > maxLot) lots = maxLot;
        
        double riskInMoney = lots * (currentRisk / tickSize) * tickValue;
        double maxRiskMoney = AccountInfoDouble(ACCOUNT_EQUITY) * (maxRiskPerc / 100.0);
        bool riskMaxOk = (riskInMoney <= maxRiskMoney);
        
        if(riskMaxOk && spreadOk && lots > 0.0)
        {
            if(trade.Sell(lots, Symbol(), bid, slPrice, tpPrice, "HaEmaMultV2i Short"))
            {
                lastEntryTimeShort = currentBarTime;
                pendingShortSignal = false;
                signalSetupTime = 0;
                DrawInitBoxes(currentBarTime, bid, slPrice, tpPrice);
                UpdateDashboard();
            }
        }
    }
}

//+------------------------------------------------------------------+
//| Average True Range (ATR) calculation                             |
//+------------------------------------------------------------------+
double CalculateATR(int index, int period)
{
    int size = period * 4;
    double highs[], lows[], closes[];
    ArraySetAsSeries(highs, true); ArraySetAsSeries(lows, true); ArraySetAsSeries(closes, true);
    int copiedH = CopyHigh(Symbol(), _Period, 0, size, highs);
    int copiedL = CopyLow(Symbol(), _Period, 0, size, lows);
    int copiedC = CopyClose(Symbol(), _Period, 0, size, closes);
    int copied = MathMin(copiedH, MathMin(copiedL, copiedC));
    if(copied <= period + 1) return(0.0);
    
    double tr[];
    ArrayResize(tr, copied - 1);
    for(int i = 0; i < copied - 1; i++)
    {
        double hl = highs[i] - lows[i];
        double hc = MathAbs(highs[i] - closes[i+1]);
        double lc = MathAbs(lows[i] - closes[i+1]);
        tr[i] = MathMax(hl, MathMax(hc, lc));
    }
    
    double atr = 0.0;
    int startIdx = copied - 2;
    double sum = 0.0;
    for(int i = 0; i < period; i++) sum += tr[startIdx - i];
    atr = sum / period;
    
    for(int i = startIdx - period; i >= index; i--)
    {
        atr = (atr * (period - 1) + tr[i]) / period;
    }
    return(atr);
}

//+------------------------------------------------------------------+
//| Average Directional Index (ADX) calculation                      |
//+------------------------------------------------------------------+
double CalculateADX(int index, int period)
{
    int size = period * 4;
    double highs[], lows[], closes[];
    ArraySetAsSeries(highs, true); ArraySetAsSeries(lows, true); ArraySetAsSeries(closes, true);
    int copiedH = CopyHigh(Symbol(), _Period, 0, size, highs);
    int copiedL = CopyLow(Symbol(), _Period, 0, size, lows);
    int copiedC = CopyClose(Symbol(), _Period, 0, size, closes);
    int copied = MathMin(copiedH, MathMin(copiedL, copiedC));
    if(copied <= period + 2) return(20.0);
    
    double tr[], dmPlus[], dmMinus[];
    ArrayResize(tr, copied - 1);
    ArrayResize(dmPlus, copied - 1);
    ArrayResize(dmMinus, copied - 1);
    for(int i = 0; i < copied - 1; i++)
    {
        double hl = highs[i] - lows[i];
        double hc = MathAbs(highs[i] - closes[i+1]);
        double lc = MathAbs(lows[i] - closes[i+1]);
        tr[i] = MathMax(hl, MathMax(hc, lc));
        
        double up = highs[i] - highs[i+1];
        double down = lows[i+1] - lows[i];
        dmPlus[i] = (up > 0 && up > down) ? up : 0.0;
        dmMinus[i] = (down > 0 && down > up) ? down : 0.0;
    }
    
    double atr = 0.0, smoothedPlus = 0.0, smoothedMinus = 0.0;
    int startIdx = copied - 2;
    for(int i = 0; i < period; i++)
    {
        atr += tr[startIdx - i];
        smoothedPlus += dmPlus[startIdx - i];
        smoothedMinus += dmMinus[startIdx - i];
    }
    atr /= period;
    smoothedPlus /= period;
    smoothedMinus /= period;
    
    for(int i = startIdx - period; i >= index; i--)
    {
        atr = (atr * (period - 1) + tr[i]) / period;
        smoothedPlus = (smoothedPlus * (period - 1) + dmPlus[i]) / period;
        smoothedMinus = (smoothedMinus * (period - 1) + dmMinus[i]) / period;
    }
    
    if(atr == 0.0) return(0.0);
    double diPlus = 100.0 * (smoothedPlus / atr);
    double diMinus = 100.0 * (smoothedMinus / atr);
    
    double diSum = diPlus + diMinus;
    double dx = diSum == 0.0 ? 0.0 : 100.0 * MathAbs(diPlus - diMinus) / diSum;
    return(dx);
}
