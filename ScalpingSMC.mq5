//+------------------------------------------------------------------+
//|                                                  ScalpingSMC.mq5 |
//|                                        Copyright 2026, Antigravity|
//+------------------------------------------------------------------+
#property copyright "Antigravity"
#property link      ""
#property version   "1.00"
#include <Trade\Trade.mqh>

double   RiskPercent          = 5.0;   // Riesgo por operación (%)
double   MinRR                = 1.5;   // Riesgo/Beneficio (RR) mínimo
int      TrendDays            = 14;     // Días para calcular tendencia macro
int      SwingBars            = 3;     // Barras a cada lado para detectar un Swing High/Low
int      TP_SwingBars         = 30;    // Barras a cada lado para fractal de TP (estructura mayor)


CTrade trade;
ENUM_TIMEFRAMES macroTF = PERIOD_D1;
ENUM_TIMEFRAMES structTF = PERIOD_M15;
ENUM_TIMEFRAMES entryTF = PERIOD_M5;

// Variables globales de estado
datetime lastBarM15 = 0;
double currentSwingHigh = 0.0;
double currentSwingLow = 0.0;
bool waitingForMSS_Buy = false;
bool waitingForMSS_Sell = false;
bool waitingForRetracement_Buy = false;
bool waitingForRetracement_Sell = false;
double activeFVG_Top = 0.0;
double activeFVG_Bottom = 0.0;
datetime activeFVG_Time = 0;
double activeStopLoss = 0.0;
double activeTakeProfit = 0.0;
double lowestPriceSinceSweep = 0.0;
double highestPriceSinceSweep = 0.0;
datetime timeSweepBuy = 0;
datetime timeSweepSell = 0;
datetime lastFVGTime = 0;

// Tipos de tendencia
enum ENUM_TREND { TREND_BUY, TREND_SELL, TREND_NONE };

//+------------------------------------------------------------------+
//| Autocalibración por Activo                                       |
//+------------------------------------------------------------------+
void CalibrateParameters()
{
    string sym = _Symbol;
    StringToUpper(sym);
    
   
    
    // NQ (Nasdaq)
    if(StringFind(sym, "NQ") >= 0 || StringFind(sym, "USTEC") >= 0 || StringFind(sym, "NAS") >= 0 || StringFind(sym, "US100") >= 0)
    {
        RiskPercent = 1.0; // Riesgo normal
        MinRR = 2.0;       // Nasdaq permite mejores recorridos
        TrendDays = 3;
        SwingBars = 3;
        TP_SwingBars = 20; // Nasdaq es rápido, con 20 velas (casi 2 hrs) suele bastar para atrapar el extremo de la sesión de NY
    }
    // ORO (XAUUSD / GOLD)
    else if(StringFind(sym, "XAU") >= 0 || StringFind(sym, "GOLD") >= 0)
    {
        RiskPercent = 1.0;
        MinRR = 1.5;
        TrendDays = 3;
        SwingBars = 4;     // Ligeramente más holgado por mechas del oro
        TP_SwingBars = 30; // Oro, requiere más holgura para extremos absolutos (2.5 hrs)
    }
    // BITCOIN
    else if(StringFind(sym, "BTC") >= 0)
    {
        RiskPercent = 0.5; // Mitad de riesgo por alta volatilidad/barridos
        MinRR = 1.2;       
        TrendDays = 7;     // El ciclo es más rápido
        SwingBars = 5;     // Mayor filtro de ruido para encontrar Swings reales
        TP_SwingBars = 50; // BTC es 24/7 y consolida larguísimo, 50 velas (4+ hrs) para el extremo
    }
    // PLATA
    else if(StringFind(sym, "XAG") >= 0 || StringFind(sym, "SILVER") >= 0)
    {
        RiskPercent = 1.0; // Plata tiene más beta que el oro
        MinRR = 1.5;
        TrendDays = 3;
        SwingBars = 10;    
        TP_SwingBars = 40; 
    }
}

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
  {
   trade.SetExpertMagicNumber(1337);
   CalibrateParameters();
   return(INIT_SUCCEEDED);
  }

//+------------------------------------------------------------------+
//| Obtener Tendencia Macro (Diario)                                 |
//+------------------------------------------------------------------+
ENUM_TREND GetDailyTrend(int dias)
{
   double closeFirst = iClose(_Symbol, macroTF, dias);
   double closeLast = iClose(_Symbol, macroTF, 1);
   if(closeLast > closeFirst) return TREND_BUY;
   if(closeLast < closeFirst) return TREND_SELL;
   return TREND_NONE;
}

//+------------------------------------------------------------------+
//| Buscar un Extremo Estructural (Soporte/Resistencia) antes del FVG|
//+------------------------------------------------------------------+
double GetStructuralExtreme(bool findHigh, double entryPrice, datetime fvgTime, int fractalBars)
{
   
   if(findHigh)
   {
      int totalBars = iBars(_Symbol, entryTF);
      for(int i = 1; i <= 5000; i++) // Escanear hasta 17 días en M5
      {
         if(i >= totalBars) break; // Protección de límite de historial
         if(iTime(_Symbol, entryTF, i) >= fvgTime) continue; // Solo buscar antes del FVG
         
         bool isHigh = true;
         double checkHigh = iHigh(_Symbol, entryTF, i);
         for(int j = 1; j <= fractalBars; j++)
         {
            // Chequeo de velas a la derecha (hacia el presente) solo si existen
            if(i - j >= 0)
            {
               if(iHigh(_Symbol, entryTF, i - j) >= checkHigh) { isHigh = false; break; }
            }
            // Chequeo de velas a la izquierda (hacia el pasado)
            if(iHigh(_Symbol, entryTF, i + j) >= checkHigh) { isHigh = false; break; }
         }
         // Buscamos el MÁXIMO que esté por encima de la entrada
         if(isHigh && checkHigh > entryPrice)
         {
            return checkHigh;
         }
      }
      return 0.0;
   }
   else
   {
      int totalBars = iBars(_Symbol, entryTF);
      for(int i = 1; i <= 5000; i++) 
      {
         if(i >= totalBars) break;
         if(iTime(_Symbol, entryTF, i) >= fvgTime) continue; // Solo buscar antes del FVG
         
         bool isLow = true;
         double checkLow = iLow(_Symbol, entryTF, i);
         for(int j = 1; j <= fractalBars; j++)
         {
            if(i - j >= 0)
            {
               if(iLow(_Symbol, entryTF, i - j) <= checkLow) { isLow = false; break; }
            }
            if(iLow(_Symbol, entryTF, i + j) <= checkLow) { isLow = false; break; }
         }
         // Buscamos el MÍNIMO que esté por debajo de la entrada
         if(isLow && checkLow < entryPrice)
         {
            return checkLow;
         }
      }
      return 0.0;
   }
}

//+------------------------------------------------------------------+
//| Detectar Swings (Picos/Valles) en M15                            |
//+------------------------------------------------------------------+
void UpdateSwings()
{
   currentSwingHigh = 0.0;
   currentSwingLow = 0.0;
   
   // Buscamos Swing High
   for(int i = SwingBars + 1; i <= 200; i++)
   {
      bool isHigh = true;
      double checkHigh = iHigh(_Symbol, structTF, i);
      for(int j = 1; j <= SwingBars; j++)
      {
         if(iHigh(_Symbol, structTF, i - j) >= checkHigh || iHigh(_Symbol, structTF, i + j) >= checkHigh)
         {
            isHigh = false;
            break;
         }
      }
      if(isHigh)
      {
         currentSwingHigh = checkHigh;
         break;
      }
   }
   
   // Buscamos Swing Low
   for(int i = SwingBars + 1; i <= 200; i++)
   {
      bool isLow = true;
      double checkLow = iLow(_Symbol, structTF, i);
      for(int j = 1; j <= SwingBars; j++)
      {
         if(iLow(_Symbol, structTF, i - j) <= checkLow || iLow(_Symbol, structTF, i + j) <= checkLow)
         {
            isLow = false;
            break;
         }
      }
      if(isLow)
      {
         currentSwingLow = checkLow;
         break;
      }
   }
}

//+------------------------------------------------------------------+
//| Detectar FVG en M5                                               |
//+------------------------------------------------------------------+
bool GetFVGLimits(int direction, double &fvgTop, double &fvgBottom, datetime &fvgImpulseTime)
{
   // direction 1 = Buy FVG (gap alcista), -1 = Sell FVG (gap bajista)
   // Revisamos las últimas 5 velas cerradas en M5
   for(int i = 1; i <= 3; i++)
   {
      if(direction == 1)
      {
         // FVG Alcista: Low de la vela [i] > High de la vela [i+2]
         if(iLow(_Symbol, entryTF, i) > iHigh(_Symbol, entryTF, i+2))
         {
            fvgTop = iLow(_Symbol, entryTF, i);
            fvgBottom = iHigh(_Symbol, entryTF, i+2);
            fvgImpulseTime = iTime(_Symbol, entryTF, i+1);
            return true;
         }
      }
      else if(direction == -1)
      {
         // FVG Bajista: High de la vela [i] < Low de la vela [i+2]
         if(iHigh(_Symbol, entryTF, i) < iLow(_Symbol, entryTF, i+2))
         {
            fvgBottom = iHigh(_Symbol, entryTF, i);
            fvgTop = iLow(_Symbol, entryTF, i+2);
            fvgImpulseTime = iTime(_Symbol, entryTF, i+1);
            return true;
         }
      }
   }
   return false;
}

//+------------------------------------------------------------------+
//| Cálculo del Lote                                                 |
//+------------------------------------------------------------------+
double CalculateDynamicLot(double stopLoss, double currentPrice)
{
   double accountBalance = AccountInfoDouble(ACCOUNT_BALANCE);
   double riskAmount = accountBalance * (RiskPercent / 100.0);
   double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   
   if(tickSize == 0 || tickValue == 0) return 0.01;
   
   double priceDifference = MathAbs(currentPrice - stopLoss);
   double ticks = priceDifference / tickSize;
   
   if(ticks == 0) return 0.01;
   
   double lotSize = riskAmount / (ticks * tickValue);
   
   double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double lotStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   
   lotSize = MathRound(lotSize / lotStep) * lotStep;
   
   if(lotSize < minLot) lotSize = minLot;
   if(lotSize > maxLot) lotSize = maxLot;
   
   return lotSize;
}

//+------------------------------------------------------------------+
//| Dashboard / Update Dashboard                                     |
//+------------------------------------------------------------------+
void UpdateDashboard(ENUM_TREND macroTrend)
{
    int buysWin = 0, buysLoss = 0;
    int sellsWin = 0, sellsLoss = 0;
    double buysWinAcc = 0.0, buysLossAcc = 0.0;
    double sellsWinAcc = 0.0, sellsLossAcc = 0.0;
    
    datetime from_date = TimeCurrent() - (TrendDays * 86400);
    HistorySelect(from_date, TimeCurrent());
    
    for(int i = 0; i < HistoryDealsTotal(); i++)
    {
        ulong ticket = HistoryDealGetTicket(i);
        if(HistoryDealGetInteger(ticket, DEAL_MAGIC) == 1337 && HistoryDealGetString(ticket, DEAL_SYMBOL) == _Symbol)
        {
            if(HistoryDealGetInteger(ticket, DEAL_ENTRY) == DEAL_ENTRY_OUT)
            {
                double profit = HistoryDealGetDouble(ticket, DEAL_PROFIT) + HistoryDealGetDouble(ticket, DEAL_SWAP) + HistoryDealGetDouble(ticket, DEAL_COMMISSION);
                long dealType = HistoryDealGetInteger(ticket, DEAL_TYPE);
                
                // Deal OUT de SELL significa que cerramos una COMPRA
                if(dealType == DEAL_TYPE_SELL)
                {
                    if(profit > 0) { buysWin++; buysWinAcc += profit; }
                    else { buysLoss++; buysLossAcc += profit; }
                }
                // Deal OUT de BUY significa que cerramos una VENTA
                else if(dealType == DEAL_TYPE_BUY)
                {
                    if(profit > 0) { sellsWin++; sellsWinAcc += profit; }
                    else { sellsLoss++; sellsLossAcc += profit; }
                }
            }
        }
    }
    
    string trendStr = "RANGO";
    if(macroTrend == TREND_BUY) trendStr = "ALCISTA";
    if(macroTrend == TREND_SELL) trendStr = "BAJISTA";
    
    string dash = "=====================================\n";
    dash += " ESTADO DEL MERCADO (SMC) PARA " + _Symbol +"\n";
    dash += "======================================\n";
    dash += "Tendencia " + IntegerToString(TrendDays) + " Dias: " + trendStr + "\n";
    dash += "\n";
    dash += "--- RESULTADOS DETALLE ---\n";
    dash += "Compras Exitosas: " + IntegerToString(buysWin) + " ($" + DoubleToString(buysWinAcc, 2) + ")\n";
    dash += "Compras Fallidas: " + IntegerToString(buysLoss) + " ($" + DoubleToString(buysLossAcc, 2) + ")\n";
    dash += " Ventas Exitosas: " + IntegerToString(sellsWin) + " ($" + DoubleToString(sellsWinAcc, 2) + ")\n";
    dash += " Ventas Fallidas: " + IntegerToString(sellsLoss) + " ($" + DoubleToString(sellsLossAcc, 2) + ")\n";
    dash += "--- RESULTADOS ACUMULADO ---\n";
    dash += "Compras: " + IntegerToString(buysWin-buysLoss) + " ($" + DoubleToString(buysWinAcc + buysLossAcc, 2)  + ")\n";
    dash += " Ventas: " + IntegerToString(sellsWin - sellsLoss) + " ($" + DoubleToString(sellsWinAcc + sellsLossAcc, 2) + ")\n";
    
    
    
    
    string lines[];
    int lineCount = StringSplit(dash, '\n', lines);
    for(int j = 0; j < lineCount; j++)
    {
        string objName = "DashLine_" + IntegerToString(j);
        if(ObjectFind(0, objName) < 0)
        {
            ObjectCreate(0, objName, OBJ_LABEL, 0, 0, 0);
            ObjectSetInteger(0, objName, OBJPROP_CORNER, CORNER_RIGHT_UPPER);
            ObjectSetInteger(0, objName, OBJPROP_ANCHOR, ANCHOR_RIGHT_UPPER);
            ObjectSetInteger(0, objName, OBJPROP_XDISTANCE, 10);
            ObjectSetString(0, objName, OBJPROP_FONT, "Courier New");
            ObjectSetInteger(0, objName, OBJPROP_FONTSIZE, 10);
            
            color txtColor = ((color)ChartGetInteger(0, CHART_COLOR_BACKGROUND) == clrWhite || (color)ChartGetInteger(0, CHART_COLOR_BACKGROUND) == clrSnow || (color)ChartGetInteger(0, CHART_COLOR_BACKGROUND) == clrLightGray) ? clrBlack : clrWhite;
            ObjectSetInteger(0, objName, OBJPROP_COLOR, txtColor);
        }
        ObjectSetInteger(0, objName, OBJPROP_YDISTANCE, 10 + (j * 15));
        ObjectSetString(0, objName, OBJPROP_TEXT, lines[j]);
    }
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   // ==========================================
   // DIBUJAR FVGs EN M5 (Solo para visualización)
   // ==========================================
   datetime currentM5Time = iTime(_Symbol, entryTF, 0);
   if(currentM5Time != lastFVGTime)
   {
      if(lastFVGTime != 0) // No dibujar en el primer tick del bot
      {
         ENUM_TREND macroTrendDisplay = GetDailyTrend(TrendDays);
         
         // FVG Alcista (Gap de compra) - Solo si tendencia es BUY
         if(macroTrendDisplay == TREND_BUY && iLow(_Symbol, entryTF, 1) > iHigh(_Symbol, entryTF, 3))
         {
            string objName = "FVG_BUY_" + TimeToString(iTime(_Symbol, entryTF, 2));
            ObjectCreate(0, objName, OBJ_ARROW_UP, 0, iTime(_Symbol, entryTF, 2), iLow(_Symbol, entryTF, 2) - 10*_Point);
            ObjectSetInteger(0, objName, OBJPROP_COLOR, clrLime);
            ObjectSetInteger(0, objName, OBJPROP_WIDTH, 3);
         }
         // FVG Bajista (Gap de venta) - Solo si tendencia es SELL
         if(macroTrendDisplay == TREND_SELL && iHigh(_Symbol, entryTF, 1) < iLow(_Symbol, entryTF, 3))
         {
            string objName = "FVG_SELL_" + TimeToString(iTime(_Symbol, entryTF, 2));
            ObjectCreate(0, objName, OBJ_ARROW_DOWN, 0, iTime(_Symbol, entryTF, 2), iHigh(_Symbol, entryTF, 2) + 10*_Point);
            ObjectSetInteger(0, objName, OBJPROP_COLOR, clrRed);
            ObjectSetInteger(0, objName, OBJPROP_WIDTH, 3);
         }
      }
      lastFVGTime = currentM5Time;
   }
   // ==========================================

   if(PositionsTotal() > 0) return; // Ya hay operación activa
   
   datetime currentBarM15 = iTime(_Symbol, structTF, 0);
   if(currentBarM15 != lastBarM15)
   {
      lastBarM15 = currentBarM15;
      UpdateSwings(); // Actualizamos Swings cada cierre de vela M15
   }
   
   ENUM_TREND macroTrend = GetDailyTrend(TrendDays);
   
   UpdateDashboard(macroTrend);
   
   if(macroTrend == TREND_NONE) return;
   
   MqlTick tick;
   SymbolInfoTick(_Symbol, tick);
   
   // --- LOGICA DE COMPRA ---
   if(macroTrend == TREND_BUY)
   {
      // 1. Barrida de Liquidez: Si el precio cae por debajo del último Swing Low
      if(tick.bid < currentSwingLow && currentSwingLow > 0)
      {
         waitingForMSS_Buy = true;
         waitingForMSS_Sell = false;
         lowestPriceSinceSweep = tick.bid;
         timeSweepBuy = TimeCurrent();
      }
      
      // 2. Esperamos el Market Structure Shift (MSS)
      if(waitingForMSS_Buy && TimeCurrent() - timeSweepBuy < 86400) // Reset después de 1 día
      {
         if(tick.bid < lowestPriceSinceSweep) lowestPriceSinceSweep = tick.bid;
         
         // Verificar si la última vela CERRADA de M15 rompió el Swing High con el cuerpo
         double closeM15 = iClose(_Symbol, structTF, 1);
         double openM15 = iOpen(_Symbol, structTF, 1);
         
         if(closeM15 > currentSwingHigh && openM15 < closeM15) // Rompió con cuerpo
         {
            // 3. Confirmación de FVG en M5
            double fTop = 0, fBot = 0;
            datetime impulseTime = 0;
            if(GetFVGLimits(1, fTop, fBot, impulseTime))
            {
               activeFVG_Top = fTop;
               activeFVG_Bottom = fBot;
               activeFVG_Time = impulseTime; // La vela exacta de impulso del FVG
               
               // 1. Calcular SL Dinámico (Mínimo cercano antes del FVG)
               double structSL = GetStructuralExtreme(false, tick.ask, activeFVG_Time, SwingBars);
               if(structSL > 0 && structSL < tick.ask) 
               {
                  activeStopLoss = structSL - (10 * _Point);
               }
               else 
               {
                  // Fallback a la barrida original si no hay mínimos locales
                  activeStopLoss = lowestPriceSinceSweep - (10 * _Point); 
               }
               
               // 2. Calcular TP Dinámico (Máximo absoluto antes del FVG)
               double structTP = GetStructuralExtreme(true, tick.ask, activeFVG_Time, TP_SwingBars);
               
               // Si no encuentra estructura a 300 velas, usa el matemático de emergencia
               if(structTP <= tick.ask) 
               {
                  double risk = tick.ask - activeStopLoss;
                  structTP = tick.ask + (risk * MinRR);
               }
               activeTakeProfit = structTP;
               
               waitingForRetracement_Buy = true;
            }
            waitingForMSS_Buy = false; // Reset
         }
      }
      else if(TimeCurrent() - timeSweepBuy >= 86400)
      {
         waitingForMSS_Buy = false;
         waitingForRetracement_Buy = false;
      }
      
      // 4. Esperar el Retroceso al FVG
      if(waitingForRetracement_Buy)
      {
         if(tick.ask <= activeStopLoss || tick.ask >= activeTakeProfit)
         {
             waitingForRetracement_Buy = false; // Invalida si rompe el SL o llega al TP sin nosotros
         }
         else if(tick.ask <= activeFVG_Top) // Entró al FVG
         {
             double lotToTrade = CalculateDynamicLot(activeStopLoss, tick.ask);
             
             if(trade.Buy(lotToTrade, _Symbol, tick.ask, activeStopLoss, activeTakeProfit, "ScalpingSMC Buy FVG"))
             {
                // Dibujar cajas SL y TP
                string timeStr = TimeToString(TimeCurrent());
                string slBox = "SL_BOX_" + timeStr;
                string tpBox = "TP_BOX_" + timeStr;
                datetime timeF = TimeCurrent() + (PeriodSeconds() * 10);
                
                ObjectCreate(0, slBox, OBJ_RECTANGLE, 0, TimeCurrent(), tick.ask, timeF, activeStopLoss);
                ObjectSetInteger(0, slBox, OBJPROP_COLOR, clrRed);
                ObjectSetInteger(0, slBox, OBJPROP_BACK, true);
                ObjectSetInteger(0, slBox, OBJPROP_FILL, true);
                
                ObjectCreate(0, tpBox, OBJ_RECTANGLE, 0, TimeCurrent(), tick.ask, timeF, activeTakeProfit);
                ObjectSetInteger(0, tpBox, OBJPROP_COLOR, clrGreen);
                ObjectSetInteger(0, tpBox, OBJPROP_BACK, true);
                ObjectSetInteger(0, tpBox, OBJPROP_FILL, true);
             }
             waitingForRetracement_Buy = false; // Operación ejecutada
         }
      }
   }
   
   // --- LOGICA DE VENTA ---
   if(macroTrend == TREND_SELL)
   {
      // 1. Barrida de Liquidez: Si el precio sube por encima del último Swing High
      if(tick.ask > currentSwingHigh && currentSwingHigh > 0)
      {
         waitingForMSS_Sell = true;
         waitingForMSS_Buy = false;
         highestPriceSinceSweep = tick.ask;
         timeSweepSell = TimeCurrent();
      }
      
      // 2. Esperamos el Market Structure Shift (MSS)
      if(waitingForMSS_Sell && TimeCurrent() - timeSweepSell < 86400) // Reset después de 1 día
      {
         if(tick.ask > highestPriceSinceSweep) highestPriceSinceSweep = tick.ask;
         
         // Verificar si la última vela CERRADA de M15 rompió el Swing Low con el cuerpo
         double closeM15 = iClose(_Symbol, structTF, 1);
         double openM15 = iOpen(_Symbol, structTF, 1);
         
         if(closeM15 < currentSwingLow && openM15 > closeM15) // Rompió con cuerpo hacia abajo
         {
            // 3. Confirmación de FVG en M5
            double fTop = 0, fBot = 0;
            datetime impulseTime = 0;
            if(GetFVGLimits(-1, fTop, fBot, impulseTime))
            {
               activeFVG_Top = fTop;
               activeFVG_Bottom = fBot;
               activeFVG_Time = impulseTime; // La vela exacta de impulso del FVG
               
               // 1. Calcular SL Dinámico (Máximo cercano antes del FVG)
               double structSL = GetStructuralExtreme(true, tick.bid, activeFVG_Time, SwingBars);
               if(structSL > 0 && structSL > tick.bid)
               {
                  activeStopLoss = structSL + (10 * _Point);
               }
               else
               {
                  // Fallback a la barrida original si no hay máximos locales
                  activeStopLoss = highestPriceSinceSweep + (10 * _Point); 
               }
               
               // 2. Calcular TP Dinámico (Mínimo absoluto antes del FVG)
               double structTP = GetStructuralExtreme(false, tick.bid, activeFVG_Time, TP_SwingBars);
               
               // Si no encuentra estructura a 300 velas, usa el matemático de emergencia
               if(structTP >= tick.bid || structTP == 0)
               {
                  double risk = activeStopLoss - tick.bid;
                  structTP = tick.bid - (risk * MinRR);
               }
               activeTakeProfit = structTP;
               
               waitingForRetracement_Sell = true;
            }
            waitingForMSS_Sell = false; // Reset
         }
      }
      else if(TimeCurrent() - timeSweepSell >= 86400)
      {
         waitingForMSS_Sell = false;
         waitingForRetracement_Sell = false;
      }
      
      // 4. Esperar el Retroceso al FVG
      if(waitingForRetracement_Sell)
      {
         if(tick.bid >= activeStopLoss || tick.bid <= activeTakeProfit)
         {
             waitingForRetracement_Sell = false; // Invalida
         }
         else if(tick.bid >= activeFVG_Bottom) // Entró al FVG
         {
             double lotToTrade = CalculateDynamicLot(activeStopLoss, tick.bid);
             
             if(trade.Sell(lotToTrade, _Symbol, tick.bid, activeStopLoss, activeTakeProfit, "ScalpingSMC Sell FVG"))
             {
                // Dibujar cajas SL y TP
                string timeStr = TimeToString(TimeCurrent());
                string slBox = "SL_BOX_" + timeStr;
                string tpBox = "TP_BOX_" + timeStr;
                datetime timeF = TimeCurrent() + (PeriodSeconds() * 10);
                
                ObjectCreate(0, slBox, OBJ_RECTANGLE, 0, TimeCurrent(), tick.bid, timeF, activeStopLoss);
                ObjectSetInteger(0, slBox, OBJPROP_COLOR, clrRed);
                ObjectSetInteger(0, slBox, OBJPROP_BACK, true);
                ObjectSetInteger(0, slBox, OBJPROP_FILL, true);
                
                ObjectCreate(0, tpBox, OBJ_RECTANGLE, 0, TimeCurrent(), tick.bid, timeF, activeTakeProfit);
                ObjectSetInteger(0, tpBox, OBJPROP_COLOR, clrGreen);
                ObjectSetInteger(0, tpBox, OBJPROP_BACK, true);
                ObjectSetInteger(0, tpBox, OBJPROP_FILL, true);
             }
             waitingForRetracement_Sell = false;
         }
      }
   }
}
//+------------------------------------------------------------------+
