//+------------------------------------------------------------------+
//|                                                HA_EMA_Multi.mq5  |
//|                                  Copyright 2026, Antigravity AI  |
//|                                             https://google.com   |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, Antigravity AI"
#property link      "https://google.com"
#property version   "1.00"

#include <Trade\Trade.mqh>
CTrade trade;

// ============================================================================
// PARÁMETROS DE ENTRADA (INPUTS)
// ============================================================================
input group "--- PERFIL DE CONFIGURACIÓN ---"
input string InpAssetProfile    = "Auto";    // Perfil: Auto, Oro (XAUUSD), Plata (XAGUSD), Bitcoin (BTCUSD), Nasdaq (NAS100), Manual

input group "--- GESTIÓN DE RIESGO ---"
input double InpRiskPerc        = 1.0;       // Riesgo por operación (%)
input bool   InpUseTP           = true;      // Usar Take Profit Fijo
input double InpRrRatio         = 3.0;       // Relación Riesgo/Recompensa (R:R)
input bool   InpUseBE           = true;      // Mover a Break-Even
input double InpBeRatio         = 1.0;       // Multiplicador R:R para BE
input bool   InpUseTPChase      = true;      // Usar Persecución de TP (TP Chasing)
input double InpTpChasePts      = 2.0;       // Distancia de Persecución TP (Pts)
input double InpTpChaseOffset   = 2.0;       // Avance del TP (Pts)
input bool   InpUseFixedLot     = false;     // ¿Usar Lote Fijo? (True=Fijo, False=Riesgo %)
input double InpFixedLotVal     = 0.01;      // Valor de Lote Fijo (Lotes MT5)
input double InpMaxRiskPerc     = 5.0;       // Riesgo Máximo Permitido por Trade (%)
input double InpMaxSpreadPoints = 50.0;      // Spread Máximo Permitido (Puntos)
input double InpMinStopsLevel   = 0.0;       // Mínimo Stop Level (Puntos)
input ulong  MagicNumber        = 654321;    // Magic Number de la Estrategia

input group "--- FILTROS MANUALES (Solo si Perfil = Manual) ---"
input string InpEmaTF           = "Auto";    // Temporalidad de EMAs (Auto, 15, 30, 60, 180, 240, 1440)
input int    InpEmaFastLen      = 21;        // Período EMA Rápida manual
input int    InpEmaSlowLen      = 55;        // Período EMA Lenta manual
input int    InpSwingPeriod     = 8;         // Velas Swing High/Low manual
input double InpSlBufPts        = 2.0;       // Buffer SL manual (Puntos)
input bool   InpUseIMACD        = false;     // Usar iMACD manual
input int    InpImacdLen        = 35;        // Período iMACD manual
input bool   InpUseEMASpread    = true;      // Usar Abertura EMAs manual
input double InpEmaSpreadMult   = 0.4;       // Abertura Mínima EMAs manual (× ATR)
input bool   InpUseHAStrength   = false;     // Fuerza Heikin-Ashi manual
input bool   InpUseEMA200       = false;     // Filtro EMA 200 manual
input int    InpEma200Len       = 200;       // Período EMA 200 manual
input bool   InpUseATRMin       = false;     // Filtro ATR Mínimo manual
input int    InpAtrFilterLen    = 14;        // Período ATR manual
input double InpAtrMinUSD       = 2.0;       // ATR Mínimo USD manual
input bool   InpUseADX          = false;     // Filtro ADX manual
input int    InpAdxLen          = 14;        // Período ADX manual
input double InpAdxMin          = 22.0;      // ADX Mínimo manual
input bool   InpUseRSI          = false;     // Filtro RSI manual
input int    InpRsiLen          = 14;        // Período RSI manual
input double InpRsiOB           = 70.0;      // RSI Sobrecompra manual
input double InpRsiOS           = 30.0;      // RSI Sobreventa manual
input bool   InpUseHTF          = false;     // Filtro HTF manual
input int    InpHtfEMALen       = 50;        // Período EMA HTF manual
input bool   InpUseSession      = false;     // Usar Sesión Horaria manual
input string InpSessionStr      = "0800-1700"; // Horario Operativo manual (UTC)
input int    InpTimezoneMode    = 0;         // Zona Horaria manual (0 = America/New_York, 1 = America/Mexico_City)

// ============================================================================
// VARIABLES GLOBALES
// ============================================================================
double slBufferPts;
double rrRatio;
bool   useBE;
double beRatio;
bool   useIMACD;
bool   useEMASpread;
double emaSpreadMult;
bool   useHAStrength;
bool   useEMA200;
bool   useATRMin;
double atrMinUSD;
bool   useADX;
double adxMin;
bool   useRSI;
double rsiOB;
double rsiOS;
bool   useHTF;
bool   useSession;
string sessionStr;
int    timezoneMode;
bool   useTPChase;
bool   useTP;
double tpChasePts;
double tpChaseOffset;
bool   useFixedLot;
double fixedLotValue;
double maxRiskPerc;
double maxSpreadPoints;
double minStopsLevel;

// Parámetros de Indicadores reasignables
string emaTF;
int    emaFastLen;
int    emaSlowLen;
int    swingPeriod;
int    imacdLen;
int    ema200Len;
int    atrFilterLen;
int    adxLen;
int    rsiLen;
int    htfEMALen;

// Instrument Flags
bool isGold    = false;
bool isSilver  = false;
bool isBitcoin = false;
bool isNasdaq  = false;

// Handles de Indicadores
ENUM_TIMEFRAMES resolvedTimeframe;
int emaFastHandle  = INVALID_HANDLE;
int emaSlowHandle  = INVALID_HANDLE;
int ema200Handle   = INVALID_HANDLE;
int atrHandle      = INVALID_HANDLE;
int adxHandle      = INVALID_HANDLE;
int rsiHandle      = INVALID_HANDLE;
int htfEmaHandle   = INVALID_HANDLE;

// Variables de Estado
double activeSL    = 0.0;
double activeTP    = 0.0;
double trailStep   = 0.0;
double entryP      = 0.0;
bool   beTriggered = false;
bool   posActiveLastTick = false;
datetime lastBarTime = 0;

struct HeikinAshiBar {
   double open;
   double high;
   double low;
   double close;
};

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   trade.SetExpertMagicNumber(MagicNumber);
   
   // Determinar Símbolo
   string symbolLower = Symbol();
   StringToLower(symbolLower);
   
   isGold    = (StringFind(symbolLower, "xau") >= 0 || StringFind(symbolLower, "gold") >= 0);
   isSilver  = (StringFind(symbolLower, "xag") >= 0 || StringFind(symbolLower, "silver") >= 0 || StringFind(symbolLower, "plata") >= 0);
   isBitcoin = (StringFind(symbolLower, "btc") >= 0 || StringFind(symbolLower, "bitcoin") >= 0);
   isNasdaq  = (StringFind(symbolLower, "nas100") >= 0 || StringFind(symbolLower, "nasdaq") >= 0 || StringFind(symbolLower, "us100") >= 0 || StringFind(symbolLower, "nq") >= 0);
   
   bool autoProfile = (InpAssetProfile == "Auto");
   useTP = InpUseTP;
   
   // Cargar Parámetros según Perfil de Símbolo
   if(autoProfile && isGold)
   {
      slBufferPts    = 0.3;
      rrRatio        = 3.3;
      useBE          = true;
      beRatio        = 1.5;
      useIMACD       = true;
      useEMASpread   = true;
      emaSpreadMult  = 0.15;
      useHAStrength  = false;
      useEMA200      = true;
      useATRMin      = true;
      atrMinUSD      = 3.5;
      useADX         = true;
      adxMin         = 22.0;
      useRSI         = false;
      rsiOB          = 70.0;
      rsiOS          = 30.0;
      useHTF         = false;
      useTPChase     = true;
      tpChasePts     = 12.0;
      tpChaseOffset  = 12.0;
      useFixedLot    = false;
      fixedLotValue  = 0.01;
      maxRiskPerc    = 5.0;
      maxSpreadPoints= 50.0;
      minStopsLevel  = 0.0;
      useSession     = true;
      sessionStr     = "0700-1700";
      timezoneMode   = 2;
      
      emaTF          = "Auto";
      emaFastLen     = 8;
      emaSlowLen     = 22;
      swingPeriod    = 8;
      imacdLen       = 35;
      ema200Len      = 200;
      atrFilterLen   = 14;
      adxLen         = 14;
      rsiLen         = 14;
      htfEMALen      = 50;
   }
   else if(autoProfile && isSilver)
   {
      slBufferPts    = 0.0;
      rrRatio        = 0.0;
      useBE          = false;
      beRatio        = 1.0;
      useIMACD       = true;
      useEMASpread   = false;
      emaSpreadMult  = 0.0;
      useHAStrength  = true;
      useEMA200      = true;
      useATRMin      = false;
      atrMinUSD      = 1.0;
      useADX         = false;
      adxMin         = 22.0;
      useRSI         = false;
      rsiOB          = 70.0;
      rsiOS          = 30.0;
      useHTF         = false;
      useTPChase     = true;
      tpChasePts     = 0.55;
      tpChaseOffset  = 0.55;
      useFixedLot    = false;
      fixedLotValue  = 0.01;
      maxRiskPerc    = 5.0;
      maxSpreadPoints= 50.0;
      minStopsLevel  = 0.0;
      useSession     = false;
      sessionStr     = "";
      timezoneMode   = 0;
      
      emaTF          = "15";
      emaFastLen     = 9;
      emaSlowLen     = 21;
      swingPeriod    = 5;
      imacdLen       = 35;
      ema200Len      = 200;
      atrFilterLen   = 14;
      adxLen         = 14;
      rsiLen         = 14;
      htfEMALen      = 50;
   }
   else if(autoProfile && isBitcoin)
   {
      slBufferPts    = 0.0;
      rrRatio        = 1.8;
      useBE          = true;
      beRatio        = 1.0;
      useIMACD       = true;
      useEMASpread   = true;
      emaSpreadMult  = 0.3;
      useHAStrength  = true;
      useEMA200      = true;
      useATRMin      = false;
      atrMinUSD      = 2.0;
      useADX         = false;
      adxMin         = 22.0;
      useRSI         = true;
      rsiOB          = 70.0;
      rsiOS          = 0.0;
      useHTF         = false;
      useTPChase     = true;
      tpChasePts     = 150.0;
      tpChaseOffset  = 150.0;
      useFixedLot    = false;
      fixedLotValue  = 0.01;
      maxRiskPerc    = 5.0;
      maxSpreadPoints= 50.0;
      minStopsLevel  = 0.0;
      useSession     = false;
      sessionStr     = "";
      timezoneMode   = 0;
      
      emaTF          = "15";
      emaFastLen     = 9;
      emaSlowLen     = 21;
      swingPeriod    = 5;
      imacdLen       = 35;
      ema200Len      = 200;
      atrFilterLen   = 14;
      adxLen         = 14;
      rsiLen         = 14;
      htfEMALen      = 50;
   }
   else if(autoProfile && isNasdaq)
   {
      slBufferPts    = 0.0;
      rrRatio        = 1.5;
      useBE          = true;
      beRatio        = 1.0;
      useIMACD       = true;
      useEMASpread   = true;
      emaSpreadMult  = 0.35;
      useHAStrength  = true;
      useEMA200      = true;
      useATRMin      = false;
      atrMinUSD      = 2.0;
      useADX         = false;
      adxMin         = 22.0;
      useRSI         = false;
      rsiOB          = 70.0;
      rsiOS          = 30.0;
      useHTF         = false;
      useTPChase     = true;
      tpChasePts     = 15.0;
      tpChaseOffset  = 15.0;
      useFixedLot    = false;
      fixedLotValue  = 0.01;
      maxRiskPerc    = 5.0;
      maxSpreadPoints= 50.0;
      minStopsLevel  = 0.0;
      useSession     = false;
      sessionStr     = "";
      timezoneMode   = 0;
      
      emaTF          = "Auto";
      emaFastLen     = 9;
      emaSlowLen     = 21;
      swingPeriod    = 5;
      imacdLen       = 35;
      ema200Len      = 200;
      atrFilterLen   = 14;
      adxLen         = 14;
      rsiLen         = 14;
      htfEMALen      = 50;
   }
   else // Manual
   {
      slBufferPts    = InpSlBufPts;
      rrRatio        = InpRrRatio;
      useBE          = InpUseBE;
      beRatio        = InpBeRatio;
      useIMACD       = InpUseIMACD;
      useEMASpread   = InpUseEMASpread;
      emaSpreadMult  = InpEmaSpreadMult;
      useHAStrength  = InpUseHAStrength;
      useEMA200      = InpUseEMA200;
      useATRMin      = InpUseATRMin;
      atrMinUSD      = InpAtrMinUSD;
      useADX         = InpUseADX;
      adxMin         = InpAdxMin;
      useRSI         = InpUseRSI;
      rsiOB          = InpRsiOB;
      rsiOS          = InpRsiOS;
      useHTF         = InpUseHTF;
      useTPChase     = InpUseTPChase;
      tpChasePts     = InpTpChasePts;
      tpChaseOffset  = InpTpChaseOffset;
      useFixedLot    = InpUseFixedLot;
      fixedLotValue  = InpFixedLotVal;
      maxRiskPerc    = InpMaxRiskPerc;
      maxSpreadPoints= InpMaxSpreadPoints;
      minStopsLevel  = InpMinStopsLevel;
      useSession     = InpUseSession;
      sessionStr     = InpSessionStr;
      timezoneMode   = InpTimezoneMode;
      
      emaTF          = InpEmaTF;
      emaFastLen     = InpEmaFastLen;
      emaSlowLen     = InpEmaSlowLen;
      swingPeriod    = InpSwingPeriod;
      imacdLen       = InpImacdLen;
      ema200Len      = InpEma200Len;
      atrFilterLen   = InpAtrFilterLen;
      adxLen         = InpAdxLen;
      rsiLen         = InpRsiLen;
      htfEMALen      = InpHtfEMALen;
   }
   
   // Determinar resolución de EMAs
   resolvedTimeframe = _Period;
   if(emaTF == "Auto")
   {
      resolvedTimeframe = _Period;
   }
   else
   {
      if(emaTF == "15") resolvedTimeframe = PERIOD_M15;
      else if(emaTF == "30") resolvedTimeframe = PERIOD_M30;
      else if(emaTF == "60") resolvedTimeframe = PERIOD_H1;
      else if(emaTF == "180") resolvedTimeframe = PERIOD_H3;
      else if(emaTF == "240") resolvedTimeframe = PERIOD_H4;
      else if(emaTF == "1440") resolvedTimeframe = PERIOD_D1;
   }
   
   // Inicializar handles de indicadores
   emaFastHandle = iMA(Symbol(), resolvedTimeframe, emaFastLen, 0, MODE_EMA, PRICE_CLOSE);
   emaSlowHandle = iMA(Symbol(), resolvedTimeframe, emaSlowLen, 0, MODE_EMA, PRICE_CLOSE);
   
   if(useEMA200)
      ema200Handle = iMA(Symbol(), resolvedTimeframe, ema200Len, 0, MODE_EMA, PRICE_CLOSE);
      
   atrHandle = iATR(Symbol(), _Period, atrFilterLen);
   adxHandle = iADX(Symbol(), _Period, adxLen);
   rsiHandle = iRSI(Symbol(), _Period, rsiLen, PRICE_CLOSE);
   
   if(useHTF)
      htfEmaHandle = iMA(Symbol(), PERIOD_H1, htfEMALen, 0, MODE_EMA, PRICE_CLOSE);
      
   if(emaFastHandle == INVALID_HANDLE || emaSlowHandle == INVALID_HANDLE || atrHandle == INVALID_HANDLE || adxHandle == INVALID_HANDLE || rsiHandle == INVALID_HANDLE)
   {
      Print("Error inicializando indicadores.");
      return(INIT_FAILED);
   }
   
   Print("EA HA_EMA_Multi inicializado.");
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   IndicatorRelease(emaFastHandle);
   IndicatorRelease(emaSlowHandle);
   if(ema200Handle != INVALID_HANDLE) IndicatorRelease(ema200Handle);
   IndicatorRelease(atrHandle);
   IndicatorRelease(adxHandle);
   IndicatorRelease(rsiHandle);
   if(htfEmaHandle != INVALID_HANDLE) IndicatorRelease(htfEmaHandle);
   
   ObjectDelete(0, "SL_Box");
   ObjectDelete(0, "TP_Box");
}

//+------------------------------------------------------------------+
//| Helper para obtener el offset de Nueva York (EDT -4, EST -5)      |
//+------------------------------------------------------------------+
int GetNewYorkGmtOffset(datetime time)
{
   MqlDateTime dt;
   TimeToStruct(time, dt);
   
   if(dt.mon < 3 || dt.mon > 11) return(-5);
   if(dt.mon > 3 && dt.mon < 11) return(-4);
   
   // Marzo: Segundo domingo
   if(dt.mon == 3)
   {
      MqlDateTime march1st = dt;
      march1st.day = 1;
      march1st.hour = 0;
      march1st.min = 0;
      march1st.sec = 0;
      datetime m1Time = StructToTime(march1st);
      MqlDateTime m1Parsed;
      TimeToStruct(m1Time, m1Parsed);
      
      int firstSundayDay = 1 + (7 - m1Parsed.day_of_week) % 7;
      int secondSundayDay = firstSundayDay + 7;
      
      if(dt.day > secondSundayDay || (dt.day == secondSundayDay && dt.hour >= 2)) return(-4);
      return(-5);
   }
   
   // Noviembre: Primer domingo
   if(dt.mon == 11)
   {
      MqlDateTime nov1st = dt;
      nov1st.day = 1;
      nov1st.hour = 0;
      nov1st.min = 0;
      nov1st.sec = 0;
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
//| Helper para verificar si la hora del target está en sesión       |
//+------------------------------------------------------------------+
bool IsInSessionUTC(string sessStr)
{
   if(!useSession || sessStr == "") return(true);
   // Formato esperado: "HHMM-HHMM" (ej. "0700-1700")
   if(StringLen(sessStr) < 9) return(true);
   
   int startH = (int)StringToInteger(StringSubstr(sessStr, 0, 2));
   int startM = (int)StringToInteger(StringSubstr(sessStr, 2, 2));
   int endH   = (int)StringToInteger(StringSubstr(sessStr, 5, 2));
   int endM   = (int)StringToInteger(StringSubstr(sessStr, 7, 2));
   
   int autoBrokerGmtOffset = (int)MathRound((double)(TimeCurrent() - TimeGMT()) / 3600.0);
   int targetGmtOffset = -6; // CDMX por defecto
   if(timezoneMode == 0)
   {
      targetGmtOffset = GetNewYorkGmtOffset(TimeCurrent());
   }
   else if(timezoneMode == 2) // UTC
   {
      targetGmtOffset = 0;
   }
   
   int diffHours = targetGmtOffset - autoBrokerGmtOffset;
   datetime targetTime = TimeCurrent() + diffHours * 3600;
   
   MqlDateTime tgt;
   TimeToStruct(targetTime, tgt);
   
   int currMin = tgt.hour * 60 + tgt.min;
   int startMin = startH * 60 + startM;
   int endMin = endH * 60 + endM;
   
   if(startMin < endMin)
   {
      return(currMin >= startMin && currMin < endMin);
   }
   else // Cruza la medianoche (ej. "2200-0400")
   {
      return(currMin >= startMin || currMin < endMin);
   }
}

//+------------------------------------------------------------------+
//| Helper para obtener valores de buffers                           |
//+------------------------------------------------------------------+
double GetIndicatorValue(int handle, int bufferNum, int index)
{
   double values[1];
   if(CopyBuffer(handle, bufferNum, index, 1, values) > 0)
   {
      return(values[0]);
   }
   return(0.0);
}

//+------------------------------------------------------------------+
//| Helper para calcular RMA                                         |
//+------------------------------------------------------------------+
double CalculateRMA(const double &price[], int size, int len, int targetIndex)
{
   double alpha = 1.0 / len;
   double rma = price[size - 1];
   for(int i = size - 2; i >= targetIndex; i--)
   {
      rma = price[i] * alpha + rma * (1.0 - alpha);
   }
   return(rma);
}

//+------------------------------------------------------------------+
//| Helper para calcular Impulse MACD (iMACD)                        |
//+------------------------------------------------------------------+
double GetIMACD(int targetIndex, int len)
{
   int size = len * 5;
   double highs[], lows[], closes[];
   ArraySetAsSeries(highs, true);
   ArraySetAsSeries(lows, true);
   ArraySetAsSeries(closes, true);
   
   int copiedH = CopyHigh(Symbol(), _Period, 0, size, highs);
   int copiedL = CopyLow(Symbol(), _Period, 0, size, lows);
   int copiedC = CopyClose(Symbol(), _Period, 0, size, closes);
   
   int copied = MathMin(copiedH, MathMin(copiedL, copiedC));
   if(copied <= len + 5) return(0.0);
   size = copied;
   
   double hlc3[];
   ArrayResize(hlc3, size);
   ArraySetAsSeries(hlc3, true);
   for(int i = 0; i < size; i++)
   {
      hlc3[i] = (highs[i] + lows[i] + closes[i]) / 3.0;
   }
   
   double ema1[];
   ArrayResize(ema1, size - len);
   ArraySetAsSeries(ema1, true);
   double alpha = 2.0 / (len + 1.0);
   
   for(int j = 0; j < size - len; j++)
   {
      double ema = hlc3[size - 1];
      for(int k = size - 2; k >= j; k--)
      {
         ema = hlc3[k] * alpha + ema * (1.0 - alpha);
      }
      ema1[j] = ema;
   }
   
   double ema2_val = ema1[size - len - 1];
   for(int i = size - len - 2; i >= targetIndex; i--)
   {
      ema2_val = ema1[i] * alpha + ema2_val * (1.0 - alpha);
   }
   double ema1_val = ema1[targetIndex];
   double mi = ema1_val + (ema1_val - ema2_val);
   
   double hi = CalculateRMA(highs, size, len, targetIndex);
   double lo = CalculateRMA(lows, size, len, targetIndex);
   
   if(mi > hi) return(mi - hi);
   if(mi < lo) return(mi - lo);
   return(0.0);
}

//+------------------------------------------------------------------+
//| Obtener Velas Heikin-Ashi                                        |
//+------------------------------------------------------------------+
bool GetHeikinAshi(HeikinAshiBar &haBars[])
{
   int count = ArraySize(haBars);
   MqlRates rates[];
   if(CopyRates(Symbol(), _Period, 0, count + 20, rates) <= 0) return(false);
   
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
      haO[i] = (haO[i-1] + haC[i-1]) / 2.0;
      haH[i] = MathMax(rates[i].high, MathMax(haO[i], haC[i]));
      haL[i] = MathMin(rates[i].low, MathMin(haO[i], haC[i]));
   }
   
   for(int i = 0; i < count; i++)
   {
      int srcIdx = copied - 1 - i;
      if(srcIdx >= 0 && srcIdx < copied)
      {
         haBars[i].open  = haO[srcIdx];
         haBars[i].close = haC[srcIdx];
         haBars[i].high  = haH[srcIdx];
         haBars[i].low   = haL[srcIdx];
      }
   }
   return(true);
}

//+------------------------------------------------------------------+
//| Dibujar Cajas Transparentes de SL y TP                           |
//+------------------------------------------------------------------+
void DrawInitBoxes(datetime entryTime, double entryPrice, double slVal, double tpVal)
{
   ObjectDelete(0, "SL_Box");
   ObjectDelete(0, "TP_Box");
   
   datetime endTime = entryTime + PeriodSeconds(PERIOD_CURRENT) * 20; // Duración visible de 20 velas
   
   // Dibujar caja de SL (rojo transparente)
   ObjectCreate(0, "SL_Box", OBJ_RECTANGLE, 0, entryTime, entryPrice, endTime, slVal);
   ObjectSetInteger(0, "SL_Box", OBJPROP_COLOR, C'255,220,220');
   ObjectSetInteger(0, "SL_Box", OBJPROP_FILL, true);
   ObjectSetInteger(0, "SL_Box", OBJPROP_BACK, true);
   ObjectSetInteger(0, "SL_Box", OBJPROP_SELECTABLE, false);
   
   // Dibujar caja de TP (verde transparente)
   ObjectCreate(0, "TP_Box", OBJ_RECTANGLE, 0, entryTime, entryPrice, endTime, tpVal);
   ObjectSetInteger(0, "TP_Box", OBJPROP_COLOR, C'220,255,220');
   ObjectSetInteger(0, "TP_Box", OBJPROP_FILL, true);
   ObjectSetInteger(0, "TP_Box", OBJPROP_BACK, true);
   ObjectSetInteger(0, "TP_Box", OBJPROP_SELECTABLE, false);
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   // Evaluar señales al cierre de cada vela del gráfico actual
   datetime currentBarTime = iTime(Symbol(), _Period, 0);
   if(currentBarTime == lastBarTime)
   {
      // --- PERSECUCIÓN DE TAKE PROFIT (TP CHASING) EN TIEMPO REAL ---
      if(PositionSelect(Symbol()) && PositionGetInteger(POSITION_MAGIC) == MagicNumber && useTPChase)
      {
         double currentTP = PositionGetDouble(POSITION_TP);
         double currentSL = PositionGetDouble(POSITION_SL);
         long type = PositionGetInteger(POSITION_TYPE);
         double point = SymbolInfoDouble(Symbol(), SYMBOL_POINT);
         
         if(currentTP > 0)
         {
            if(type == POSITION_TYPE_BUY)
            {
               double highCurr = SymbolInfoDouble(Symbol(), SYMBOL_BID);
               if((currentTP - highCurr) <= tpChasePts)
               {
                  double newTP = highCurr + tpChaseOffset;
                  trade.PositionModify(Symbol(), currentSL, newTP);
               }
            }
            else if(type == POSITION_TYPE_SELL)
            {
               double lowCurr = SymbolInfoDouble(Symbol(), SYMBOL_ASK);
               if((lowCurr - currentTP) <= tpChasePts)
               {
                  double newTP = lowCurr - tpChaseOffset;
                  trade.PositionModify(Symbol(), currentSL, newTP);
               }
            }
         }
      }
      return;
   }
   lastBarTime = currentBarTime;
   
   // =----------------------------------------------------------------=
   // EVALUACIÓN DE POSICIÓN ACTIVA
   // =----------------------------------------------------------------=
   bool outOfMarket = true;
   bool inLong = false;
   bool inShort = false;
   double currentSL = 0.0;
   double currentTP = 0.0;
   
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(PositionGetSymbol(i) == Symbol() && PositionGetInteger(POSITION_MAGIC) == MagicNumber)
      {
         outOfMarket = false;
         long type = PositionGetInteger(POSITION_TYPE);
         if(type == POSITION_TYPE_BUY) inLong = true;
         if(type == POSITION_TYPE_SELL) inShort = true;
         currentSL = PositionGetDouble(POSITION_SL);
         currentTP = PositionGetDouble(POSITION_TP);
      }
   }
   
   // Resetear variables al salir del mercado
   if(outOfMarket)
   {
      if(posActiveLastTick)
      {
         activeSL    = 0.0;
         activeTP    = 0.0;
         trailStep   = 0.0;
         entryP      = 0.0;
         beTriggered = false;
         ObjectDelete(0, "SL_Box");
         ObjectDelete(0, "TP_Box");
      }
      posActiveLastTick = false;
   }
   else
   {
      // Inicializar tracking al entrar a mercado
      if(!posActiveLastTick)
      {
         entryP      = PositionGetDouble(POSITION_PRICE_OPEN);
         activeSL    = currentSL;
         activeTP    = currentTP;
         trailStep   = MathAbs(entryP - activeSL) / 5.0;
         beTriggered = false;
         posActiveLastTick = true;
      }
   }
   
   // ============================================================================
   // GESTIÓN DINÁMICA DE TRADES (BREAK-EVEN Y TRAILING)
   // ============================================================================
   if(!outOfMarket && trailStep > 0.0)
   {
      double ask = SymbolInfoDouble(Symbol(), SYMBOL_ASK);
      double bid = SymbolInfoDouble(Symbol(), SYMBOL_BID);
      
      // --- BREAK-EVEN ---
      if(useBE && !beTriggered)
      {
         double distInicial = MathAbs(entryP - activeSL);
         if(inLong)
         {
            double recorrido = bid - entryP;
            if(recorrido >= (distInicial * beRatio))
            {
               activeSL = entryP;
               beTriggered = true;
               trade.PositionModify(Symbol(), activeSL, activeTP);
            }
         }
         else if(inShort)
         {
            double recorrido = entryP - ask;
            if(recorrido >= (distInicial * beRatio))
            {
               activeSL = entryP;
               beTriggered = true;
               trade.PositionModify(Symbol(), activeSL, activeTP);
            }
         }
      }
      
      // --- TRAILING STOP POR TERCIOS/QUINTOS ---
      if(inLong)
      {
         double recorrido = bid - entryP;
         int niveles = (int)MathFloor(recorrido / trailStep);
         if(niveles > 0)
         {
            double initialSL = entryP - (trailStep * 5.0);
            double nuevoSL = initialSL + (trailStep * niveles);
            if(nuevoSL > activeSL)
            {
               activeSL = nuevoSL;
               trade.PositionModify(Symbol(), activeSL, activeTP);
            }
         }
      }
      else if(inShort)
      {
         double recorrido = entryP - ask;
         int niveles = (int)MathFloor(recorrido / trailStep);
         if(niveles > 0)
         {
            double initialSL = entryP + (trailStep * 5.0);
            double nuevoSL = initialSL - (trailStep * niveles);
            if(nuevoSL < activeSL || activeSL == 0.0)
            {
               activeSL = nuevoSL;
               trade.PositionModify(Symbol(), activeSL, activeTP);
            }
         }
      }
   }
   
   // Si ya estamos dentro del mercado, no evaluamos nuevas entradas
   if(!outOfMarket) return;
   
   // ============================================================================
   // LÓGICA DE FILTROS Y ENTRADAS (Velas Cerradas)
   // ============================================================================
   HeikinAshiBar haBars[10];
   ZeroMemory(haBars);
   if(!GetHeikinAshi(haBars)) return;
   
   bool haGreen = haBars[1].close > haBars[1].open;
   bool haRed   = haBars[1].close < haBars[1].open;
   
   // Obtener EMAs en el resolvedTimeframe (Index 1 es la vela cerrada)
   double emaFast = GetIndicatorValue(emaFastHandle, 0, 1);
   double emaSlow = GetIndicatorValue(emaSlowHandle, 0, 1);
   
   // Filtro de spread de EMAs
   double distEMAs = MathAbs(emaFast - emaSlow);
   double atrVal = GetIndicatorValue(atrHandle, 0, 1);
   bool aberturaOK = !useEMASpread || (distEMAs >= (atrVal * emaSpreadMult));
   
   // Filtro Impulse MACD
   double md = GetIMACD(1, imacdLen);
   bool imacdLongOK  = !useIMACD || (md >= 0.0);
   bool imacdShortOK = !useIMACD || (md <= 0.0);
   
   // Filtro EMA 200
   double ema200Val = useEMA200 ? GetIndicatorValue(ema200Handle, 0, 1) : 0.0;
   double close1    = iClose(Symbol(), _Period, 1);
   bool ema200LongOK  = !useEMA200 || (close1 > ema200Val);
   bool ema200ShortOK = !useEMA200 || (close1 < ema200Val);
   
   // Filtro Heikin-Ashi Strength
   bool haStrengthLong  = !useHAStrength || (haBars[1].low == haBars[1].open);
   bool haStrengthShort = !useHAStrength || (haBars[1].high == haBars[1].open);
   
   // Giro Heikin-Ashi reciente (Máximo 6 velas)
   bool haColorChangeLong = false;
   for(int i = 1; i <= 6; i++)
   {
      if(haBars[i+1].close < haBars[i+1].open && haBars[i].close > haBars[i].open)
      {
         haColorChangeLong = true;
         break;
      }
   }
   
   bool haColorChangeShort = false;
   for(int i = 1; i <= 6; i++)
   {
      if(haBars[i+1].close > haBars[i+1].open && haBars[i].close < haBars[i].open)
      {
         haColorChangeShort = true;
         break;
      }
   }
   
   // Filtros ADX y RSI
   double adxVal = GetIndicatorValue(adxHandle, 0, 1);
   bool adxOK = !useADX || (adxVal >= adxMin);
   
   double rsiVal = GetIndicatorValue(rsiHandle, 0, 1);
   bool rsiLongOK  = !useRSI || (rsiVal < rsiOB);
   bool rsiShortOK = !useRSI || (rsiVal > rsiOS);
   
   // Filtro HTF EMA
   double htfEmaVal = useHTF ? GetIndicatorValue(htfEmaHandle, 0, 1) : 0.0;
   bool htfLongOK  = !useHTF || (close1 > htfEmaVal);
   bool htfShortOK = !useHTF || (close1 < htfEmaVal);
   
   // Filtro ATR mínimo
   bool atrOK = !useATRMin || (atrVal >= atrMinUSD);
   
   // Alineación Final
   bool inSession = IsInSessionUTC(sessionStr);
    
   bool isLongAligned = inSession && (emaFast > emaSlow) && haGreen &&
                        imacdLongOK && ema200LongOK && haStrengthLong &&
                        haColorChangeLong && aberturaOK && atrOK &&
                        adxOK && rsiLongOK && htfLongOK;
                        
   bool isShortAligned = inSession && (emaFast < emaSlow) && haRed &&
                         imacdShortOK && ema200ShortOK && haStrengthShort &&
                         haColorChangeShort && aberturaOK && atrOK &&
                         adxOK && rsiShortOK && htfShortOK;
                         
   // ============================================================================
   // ENTRADA AL MERCADO
   // ============================================================================
   if(isLongAligned)
   {
      // Buscar Stop Loss basado en Swing Low de velas normales
      double lows[];
      int copiedLows = CopyLow(Symbol(), _Period, 1, swingPeriod, lows);
      if(copiedLows <= 0) return;
      double lowestLow = lows[0];
      for(int i = 1; i < copiedLows; i++)
      {
         if(lows[i] < lowestLow) lowestLow = lows[i];
      }
      
      double slVal = lowestLow - (slBufferPts * SymbolInfoDouble(Symbol(), SYMBOL_POINT));
      double risk = close1 - slVal;
      double slPrice = close1 - risk;
      double tpPrice = useTP ? (close1 + risk * rrRatio) : 0.0;
      
      // Calcular volumen por riesgo
      double riskAmt = AccountInfoDouble(ACCOUNT_EQUITY) * (InpRiskPerc / 100.0);
      double tickValue = SymbolInfoDouble(Symbol(), SYMBOL_TRADE_TICK_VALUE);
      double tickSize = SymbolInfoDouble(Symbol(), SYMBOL_TRADE_TICK_SIZE);
      double lots = riskAmt / (risk * tickValue / tickSize);
      
      // Normalizar lote
      double minLot = SymbolInfoDouble(Symbol(), SYMBOL_VOLUME_MIN);
      double maxLot = SymbolInfoDouble(Symbol(), SYMBOL_VOLUME_MAX);
      double stepLot = SymbolInfoDouble(Symbol(), SYMBOL_VOLUME_STEP);
      lots = MathFloor(lots / stepLot) * stepLot;
      if(lots < minLot) lots = minLot;
      if(lots > maxLot) lots = maxLot;
      
      double ask = SymbolInfoDouble(Symbol(), SYMBOL_ASK);
      if(trade.Buy(lots, Symbol(), ask, slPrice, tpPrice, "HA_EMA Long"))
      {
         DrawInitBoxes(currentBarTime, ask, slPrice, tpPrice);
      }
   }
   else if(isShortAligned)
   {
      // Buscar Stop Loss basado en Swing High de velas normales
      double highs[];
      int copiedHighs = CopyHigh(Symbol(), _Period, 1, swingPeriod, highs);
      if(copiedHighs <= 0) return;
      double highestHigh = highs[0];
      for(int i = 1; i < copiedHighs; i++)
      {
         if(highs[i] > highestHigh) highestHigh = highs[i];
      }
      
      double slVal = highestHigh + (slBufferPts * SymbolInfoDouble(Symbol(), SYMBOL_POINT));
      double risk = slVal - close1;
      double slPrice = close1 + risk;
      double tpPrice = useTP ? (close1 - risk * rrRatio) : 0.0;
      
      // Calcular volumen por riesgo
      double riskAmt = AccountInfoDouble(ACCOUNT_EQUITY) * (InpRiskPerc / 100.0);
      double tickValue = SymbolInfoDouble(Symbol(), SYMBOL_TRADE_TICK_VALUE);
      double tickSize = SymbolInfoDouble(Symbol(), SYMBOL_TRADE_TICK_SIZE);
      double lots = riskAmt / (risk * tickValue / tickSize);
      
      // Normalizar lote
      double minLot = SymbolInfoDouble(Symbol(), SYMBOL_VOLUME_MIN);
      double maxLot = SymbolInfoDouble(Symbol(), SYMBOL_VOLUME_MAX);
      double stepLot = SymbolInfoDouble(Symbol(), SYMBOL_VOLUME_STEP);
      lots = MathFloor(lots / stepLot) * stepLot;
      if(lots < minLot) lots = minLot;
      if(lots > maxLot) lots = maxLot;
      
      double bid = SymbolInfoDouble(Symbol(), SYMBOL_BID);
      if(trade.Sell(lots, Symbol(), bid, slPrice, tpPrice, "HA_EMA Short"))
      {
         DrawInitBoxes(currentBarTime, bid, slPrice, tpPrice);
      }
   }
}
//+------------------------------------------------------------------+
