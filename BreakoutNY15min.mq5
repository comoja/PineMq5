//+------------------------------------------------------------------+
//|                                             BreakoutNY15min.mq5  |
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
input group "--- GESTIÓN DE RIESGO ---"
input double InpRR              = 0.90;      // Ratio Riesgo Beneficio (TP)
input int    InpMaxTrades       = 3;         // Máx trades por día
input double InpRiskPerc        = 2.0;       // Riesgo por operación (%)
input double InpTpAdvPts        = 10.0;      // Puntos de avance TP (BE/Trailing)
input ulong  MagicNumber        = 123456;    // Magic Number de la Estrategia

input group "--- FILTROS DE ENTRADA ---"
input int    InpEma200Length    = 50;        // Período EMA Tendencia
input bool   InpUseImacd        = false;     // Usar Filtro Impulse MACD
input int    InpImacdLen        = 34;        // Período Impulse MACD

input group "--- HORARIO DEL RANGO ---"
input int    BrokerGmtOffset    = 3;         // GMT Offset del Servidor del Broker (ej. +3)
input bool   IsDST              = true;      // ¿El Broker está en horario de verano? (DST)
input int    TimezoneMode       = 0;         // Zona Horaria (0 = America/New_York, 1 = America/Mexico_City)

// ============================================================================
// VARIABLES GLOBALES
// ============================================================================
// Variables efectivas (reasignables por instrumento en OnInit)
double effectiveRr;
int    effectiveMaxTrades;
double effectiveTpAdv;
int    ema200Length;
int    imacdLength;

// Instrument Flags
bool isNasdaq = false;
bool isGold   = false;
bool isSilver = false;

// Variables de Estado y Tracking
double tEnt            = 0.0;
double tSl             = 0.0;
double tTp             = 0.0;
double tRisk           = 0.0;
int    tradesToday     = 0;
int    lastDayId       = 0;
datetime lastBarTime   = 0;

// Variables de Control de BE y Trailing (Comentado para pruebas de SL estático)
bool   beActivated     = false;
double beTrailDistance = 0.0;
double maxPriceReached = 0.0;

// Horarios de sesión base
int sessionStartHour = 9;
int sessionStartMin  = 30;
int sessionEndHour   = 9;
int sessionEndMin    = 45;

// EMA Handle
int emaHandle = INVALID_HANDLE;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   trade.SetExpertMagicNumber(MagicNumber);
   
   // Autodetección de Instrumento por Nombre
   string symbolLower = Symbol();
   StringToLower(symbolLower);
   
   isNasdaq = (StringFind(symbolLower, "nas100") >= 0 || StringFind(symbolLower, "nasdaq") >= 0 || StringFind(symbolLower, "us100") >= 0 || StringFind(symbolLower, "nq") >= 0);
   isSilver = (StringFind(symbolLower, "xag") >= 0 || StringFind(symbolLower, "silver") >= 0 || StringFind(symbolLower, "plata") >= 0);
   isGold   = (StringFind(symbolLower, "xau") >= 0 || StringFind(symbolLower, "gold") >= 0);
   
   // Cargar Parámetros según Instrumento
   if(isNasdaq)
   {
      effectiveRr        = 1.2;
      effectiveMaxTrades = 1;
      ema200Length       = 50;
      effectiveTpAdv     = 15.0;
   }
   else if(isGold)
   {
      effectiveRr        = 1.5;
      effectiveMaxTrades = 1;
      ema200Length       = 25;
      effectiveTpAdv     = 0.50;
   }
   else if(isSilver)
   {
      effectiveRr        = 2.0;
      effectiveMaxTrades = 1;
      ema200Length       = 55;
      effectiveTpAdv     = 0.50;
   }
   else
   {
      effectiveRr        = InpRR;
      effectiveMaxTrades = InpMaxTrades;
      ema200Length       = InpEma200Length;
      effectiveTpAdv     = InpTpAdvPts;
   }
   
   imacdLength = InpImacdLen;
   
   // Ajustar Horario de Sesión dependiente de Zona Horaria
   if(TimezoneMode == 1) // America/Mexico_City
   {
      sessionStartHour = 8;
      sessionStartMin  = 30;
      sessionEndHour   = 8;
      sessionEndMin    = 45;
   }
   else // America/New_York
   {
      sessionStartHour = 9;
      sessionStartMin  = 30;
      sessionEndHour   = 9;
      sessionEndMin    = 45;
   }
   
   // Inicializar EMA
   emaHandle = iMA(Symbol(), PERIOD_M5, ema200Length, 0, MODE_EMA, PRICE_CLOSE);
   if(emaHandle == INVALID_HANDLE)
   {
      Print("Error inicializando indicador EMA.");
      return(INIT_FAILED);
   }
   
   Print("EA Inicializado con éxito. Instrumento: ", Symbol(), 
         " | RR: ", effectiveRr, 
         " | Máx Trades: ", effectiveMaxTrades, 
         " | EMA Período: ", ema200Length, 
         " | TP Avance: ", effectiveTpAdv);
         
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   IndicatorRelease(emaHandle);
   ObjectDelete(0, "SL_Box");
   ObjectDelete(0, "TP_Box");
   ObjectDelete(0, "SessionBox");
}

//+------------------------------------------------------------------+
//| Helper para calcular volumen por riesgo                          |
//+------------------------------------------------------------------+
double CalculateRiskLot(double slDist)
{
   double riskAmount = AccountInfoDouble(ACCOUNT_EQUITY) * (InpRiskPerc / 100.0);
   double tickValue  = SymbolInfoDouble(Symbol(), SYMBOL_TRADE_TICK_VALUE);
   double tickSize   = SymbolInfoDouble(Symbol(), SYMBOL_TRADE_TICK_SIZE);
   double point      = SymbolInfoDouble(Symbol(), SYMBOL_POINT);
   
   double lotSize = 0.0;
   if(slDist > 0 && tickValue > 0)
   {
      lotSize = riskAmount / (slDist * tickValue / tickSize);
   }
   
   double minLot  = SymbolInfoDouble(Symbol(), SYMBOL_VOLUME_MIN);
   double maxLot  = SymbolInfoDouble(Symbol(), SYMBOL_VOLUME_MAX);
   double stepLot = SymbolInfoDouble(Symbol(), SYMBOL_VOLUME_STEP);
   
   lotSize = MathFloor(lotSize / stepLot) * stepLot;
   if(lotSize < minLot) lotSize = minLot;
   if(lotSize > maxLot) lotSize = maxLot;
   
   return(lotSize);
}

//+------------------------------------------------------------------+
//| Helper para calcular EMA del buffer                              |
//+------------------------------------------------------------------+
double GetEMA(int index)
{
   double values[1];
   if(CopyBuffer(emaHandle, 0, index, 1, values) > 0)
   {
      return(values[0]);
   }
   return(0.0);
}

//+------------------------------------------------------------------+
//| Helper para calcular RMA en un arreglo                           |
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
   
   if(CopyHigh(Symbol(), PERIOD_M5, 0, size, highs) <= 0) return(0.0);
   if(CopyLow(Symbol(), PERIOD_M5, 0, size, lows) <= 0) return(0.0);
   if(CopyClose(Symbol(), PERIOD_M5, 0, size, closes) <= 0) return(0.0);
   
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
//| Dibujar Cajas Transparentes de SL y TP                           |
//+------------------------------------------------------------------+
void DrawInitBoxes(datetime entryTime, double entryPrice, double slVal, double tpVal)
{
   ObjectDelete(0, "SL_Box");
   ObjectDelete(0, "TP_Box");
   
   datetime endTime = entryTime + PeriodSeconds(PERIOD_CURRENT) * 12; // Duración visible de 12 velas
   
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
   // Evaluar ejecuciones al cierre de cada vela de 5 minutos
   datetime currentBarTime = iTime(Symbol(), PERIOD_M5, 0);
   if(currentBarTime == lastBarTime) return;
   lastBarTime = currentBarTime;
   
   // Obtener datos del último día cerrado para reset de operaciones
   MqlDateTime dt;
   TimeToStruct(currentBarTime, dt);
   int currentDayId = dt.year * 10000 + dt.mon * 100 + dt.day;
   if(currentDayId != lastDayId)
   {
      tradesToday = 0;
      lastDayId = currentDayId;
      ObjectDelete(0, "SL_Box");
      ObjectDelete(0, "TP_Box");
      ObjectDelete(0, "SessionBox");
   }
   
   // ============================================================================
   // CALCULO DEL RANGO DE SESIÓN
   // ============================================================================
   int startGmtOffset = (TimezoneMode == 0) ? (IsDST ? -4 : -5) : -6;
   int diffHours = BrokerGmtOffset - startGmtOffset;
   
   int sessionStartMinTotal = sessionStartHour * 60 + sessionStartMin + diffHours * 60;
   int sessionEndMinTotal = sessionEndHour * 60 + sessionEndMin + diffHours * 60;
   
   // Obtener últimas 60 velas de 5 minutos
   datetime times[60];
   double highs[60], lows[60];
   int copied = CopyTime(Symbol(), PERIOD_M5, 0, 60, times);
   CopyHigh(Symbol(), PERIOD_M5, 0, 60, highs);
   CopyLow(Symbol(), PERIOD_M5, 0, 60, lows);
   
   double rHighRaw = 0.0;
   double rLowRaw = 0.0;
   bool sessionBoxDrawn = false;
   datetime sessionLeftTime = 0;
   datetime sessionRightTime = 0;
   
   for(int i = 0; i < copied; i++)
   {
      MqlDateTime barDt;
      TimeToStruct(times[i], barDt);
      int barMinTotal = barDt.hour * 60 + barDt.min;
      
      if(barDt.day == dt.day && barDt.mon == dt.mon && barDt.year == dt.year)
      {
         if(barMinTotal >= sessionStartMinTotal && barMinTotal < sessionEndMinTotal)
         {
            if(rHighRaw == 0.0 || highs[i] > rHighRaw) rHighRaw = highs[i];
            if(rLowRaw == 0.0 || lows[i] < rLowRaw) rLowRaw = lows[i];
            
            if(sessionLeftTime == 0) sessionLeftTime = times[i];
            sessionRightTime = times[i] + 300; // Agregar los 5 minutos de la vela
         }
      }
   }
   
   // Dibujar caja de la sesión (amarilla)
   if(rHighRaw > 0.0 && rLowRaw > 0.0)
   {
      ObjectDelete(0, "SessionBox");
      ObjectCreate(0, "SessionBox", OBJ_RECTANGLE, 0, sessionLeftTime, rHighRaw, sessionRightTime, rLowRaw);
      ObjectSetInteger(0, "SessionBox", OBJPROP_COLOR, clrOrange);
      ObjectSetInteger(0, "SessionBox", OBJPROP_STYLE, STYLE_DOT);
      ObjectSetInteger(0, "SessionBox", OBJPROP_SELECTABLE, false);
   }
   
   // ============================================================================
   // CONDICIONES DE ENTRADA Y DETECCIÓN DE POSICIÓN
   // ============================================================================
   MqlDateTime curBarDt;
   TimeToStruct(currentBarTime, curBarDt);
   int curBarMinTotal = curBarDt.hour * 60 + curBarDt.min;
   bool afterSession = (curBarMinTotal >= sessionEndMinTotal) && (rHighRaw > 0.0) && (rLowRaw > 0.0);
   
   // Detección de Posiciones
   bool outOfMarket = true;
   bool inLong = false;
   bool inShort = false;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(PositionGetSymbol(i) == Symbol() && PositionGetInteger(POSITION_MAGIC) == MagicNumber)
      {
         outOfMarket = false;
         long type = PositionGetInteger(POSITION_TYPE);
         if(type == POSITION_TYPE_BUY) inLong = true;
         if(type == POSITION_TYPE_SELL) inShort = true;
      }
   }
   
   // Obtener cierres y aperturas (M5)
   double c5_prev = iClose(Symbol(), PERIOD_M5, 2); // Vela 1 (Ruptura)
   double o5      = iOpen(Symbol(), PERIOD_M5, 1);  // Vela 2 (Confirmación)
   double c5      = iClose(Symbol(), PERIOD_M5, 1);  // Vela 2 (Confirmación)
   double h5      = iHigh(Symbol(), PERIOD_M5, 1);
   double l5      = iLow(Symbol(), PERIOD_M5, 1);
   double h5_prev = iHigh(Symbol(), PERIOD_M5, 2);
   double l5_prev = iLow(Symbol(), PERIOD_M5, 2);
   double closeCurr = iClose(Symbol(), PERIOD_CURRENT, 0);
   
   // EMA de 5 minutos
   double emaVal      = GetEMA(1);
   double emaValPrev  = GetEMA(2);
   
   // Filtro Impulse MACD
   double md5 = GetIMACD(1, imacdLength);
   bool imacdLongOk5  = !InpUseImacd || (md5 > 0.0);
   bool imacdShortOk5 = !InpUseImacd || (md5 < 0.0);
   
   // Condiciones de ruptura y confirmación
   bool bodyUp = (c5_prev > rHighRaw) && (c5 >= o5) && (closeCurr > rHighRaw);
   bool bodyDn = (c5_prev < rLowRaw)  && (c5 <= o5) && (closeCurr < rLowRaw);
   
   // Filtros finales
   bool longC  = afterSession && bodyUp && (l5_prev > emaValPrev) && (l5 > emaVal) && imacdLongOk5 && outOfMarket && (tradesToday < effectiveMaxTrades);
   bool shortC = afterSession && bodyDn && (h5_prev < emaValPrev) && (h5 < emaVal) && imacdShortOk5 && outOfMarket && (tradesToday < effectiveMaxTrades);
   
   // ============================================================================
   // ENTRADAS
   // ============================================================================
   if(longC)
   {
      double ask = SymbolInfoDouble(Symbol(), SYMBOL_ASK);
      tEnt = ask;
      tSl  = rLowRaw;
      tRisk = MathAbs(tEnt - tSl);
      tTp  = tEnt + tRisk * effectiveRr;
      
      double lots = CalculateRiskLot(tRisk);
      if(trade.Buy(lots, Symbol(), ask, tSl, tTp, "BreakoutNY L"))
      {
         tradesToday++;
         DrawInitBoxes(currentBarTime, tEnt, tSl, tTp);
         beActivated = false;
         maxPriceReached = tEnt;
      }
   }
   
   if(shortC)
   {
      double bid = SymbolInfoDouble(Symbol(), SYMBOL_BID);
      tEnt = bid;
      tSl  = rHighRaw;
      tRisk = MathAbs(tEnt - tSl);
      tTp  = tEnt - tRisk * effectiveRr;
      
      double lots = CalculateRiskLot(tRisk);
      if(trade.Sell(lots, Symbol(), bid, tSl, tTp, "BreakoutNY S"))
      {
         tradesToday++;
         DrawInitBoxes(currentBarTime, tEnt, tSl, tTp);
         beActivated = false;
         maxPriceReached = tEnt;
      }
   }
   
   // ============================================================================
   // LÓGICA DINÁMICA DE TRAILING / BE (COMENTADA PARA PROBAR SL ESTÁTICO)
   // ============================================================================
   /*
   if(!outOfMarket && tRisk > 0)
   {
      bool isLongTrade = inLong;
      double closedHigh = iHigh(Symbol(), PERIOD_M5, 1);
      double closedLow  = iLow(Symbol(), PERIOD_M5, 1);
      
      maxPriceReached = isLongTrade ? MathMax(maxPriceReached > 0 ? maxPriceReached : tEnt, closedHigh) 
                                    : MathMin(maxPriceReached > 0 ? maxPriceReached : tEnt, closedLow);
                                    
      double priceMove = isLongTrade ? (maxPriceReached - tEnt) : (tEnt - maxPriceReached);
      double tpDist = tRisk * effectiveRr;
      
      if(!beActivated)
      {
         if(priceMove >= tpDist * 3.0 / 5.0)
         {
            beActivated = true;
            tSl = isLongTrade ? (tEnt + tpDist / 5.0) : (tEnt - tpDist / 5.0);
            beTrailDistance = MathAbs(maxPriceReached - tSl);
            tTp = isLongTrade ? maxPriceReached + effectiveTpAdv : maxPriceReached - effectiveTpAdv;
            trade.PositionModify(Symbol(), tSl, tTp);
         }
      }
      else
      {
         double newSl = isLongTrade ? MathMax(tSl, maxPriceReached - beTrailDistance) 
                                    : MathMin(tSl, maxPriceReached + beTrailDistance);
         double newTp = isLongTrade ? maxPriceReached + effectiveTpAdv 
                                    : maxPriceReached - effectiveTpAdv;
                                    
         if(MathAbs(newSl - currentSL) > SymbolInfoDouble(Symbol(), SYMBOL_POINT) || 
            MathAbs(newTp - currentTP) > SymbolInfoDouble(Symbol(), SYMBOL_POINT))
         {
            tSl = newSl;
            tTp = newTp;
            trade.PositionModify(Symbol(), tSl, tTp);
         }
      }
   }
   */
}
//+------------------------------------------------------------------+
