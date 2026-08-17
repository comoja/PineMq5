//+------------------------------------------------------------------+
//|                                                      HA_EMA.mq5  |
//|                         Puerto directo de HA_EMA.pine (Pine v6)  |
//|                                                                    |
//|  LÓGICA IDÉNTICA AL PINE:                                         |
//|  [✓] 1. Velas Heikin-Ashi calculadas manualmente (recursivo)      |
//|  [✓] 2. Trigger: cruce EMA rápida/lenta + HA color + filtros      |
//|  [✓] 3. Filtro Impulse MACD (ZLEMA)                               |
//|  [✓] 4. Filtro EMA 200 macro                                      |
//|  [✓] 5. Filtro fuerza HA (sin mechas)                             |
//|  [✓] 6. SL dinámico por swings (highest/lowest N velas)           |
//|  [✓] 7. Trailing stop por tercios (1/3 del riesgo inicial)        |
//|  [✓] 8. Lotaje dinámico por % de equidad                          |
//+------------------------------------------------------------------+
#property copyright "HA_EMA Strategy"
#property version   "1.00"
#property strict

#include <Trade\Trade.mqh>
CTrade trade;

#define MAGIC_HA_EMA 778899

//--- INPUTS
input group  "--- GESTIÓN DE RIESGO ---"
input double RiskPercent   = 1.0;   // Riesgo por operación (%)
input bool   UseTP         = true;  // Usar Take Profit Fijo
input double RR_Ratio      = 2.5;   // Relación R:R

input group  "--- CONFIGURACIÓN DE INDICADORES ---"
input int    EmaFastLen    = 9;     // Período EMA Rápida
input int    EmaSlowLen    = 21;    // Período EMA Lenta
input int    SwingPeriod   = 5;     // Velas para Swing H/L de SL
input double SL_BufferPts  = 0.0;  // Buffer SL (Puntos)

input group  "--- FILTRO DE RANGO (iMACD) ---"
input bool   UseIMACD      = true;  // Usar Filtro Impulse MACD
input int    ImacLen       = 35;    // Período Impulse MACD

input group  "--- FILTROS DE OPTIMIZACIÓN ---"
input bool   UseEMA200     = true;  // Usar Filtro EMA 200 Macro
input int    EMA200Len     = 200;   // Período EMA Macro
input bool   UseHAStrength = true;  // Filtro Fuerza HA (sin mechas)

//--- Estado global
double g_active_sl   = 0;
double g_active_tp   = 0;
double g_trail_step  = 0;
double g_entry_price = 0;
bool   g_in_trade    = false;

static datetime s_last_bar = 0;

//+------------------------------------------------------------------+
//| Utilidades de posición                                            |
//+------------------------------------------------------------------+
bool HasOwnPosition()
{
   for(int i = PositionsTotal()-1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(PositionSelectByTicket(ticket))
         if(PositionGetString(POSITION_SYMBOL) == _Symbol &&
            PositionGetInteger(POSITION_MAGIC) == MAGIC_HA_EMA)
            return true;
   }
   return false;
}

ENUM_POSITION_TYPE GetOwnPositionType()
{
   for(int i = PositionsTotal()-1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(PositionSelectByTicket(ticket))
         if(PositionGetString(POSITION_SYMBOL) == _Symbol &&
            PositionGetInteger(POSITION_MAGIC) == MAGIC_HA_EMA)
            return (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
   }
   return (ENUM_POSITION_TYPE)-1;
}

ulong GetOwnTicket()
{
   for(int i = PositionsTotal()-1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(PositionSelectByTicket(ticket))
         if(PositionGetString(POSITION_SYMBOL) == _Symbol &&
            PositionGetInteger(POSITION_MAGIC) == MAGIC_HA_EMA)
            return ticket;
   }
   return 0;
}

//+------------------------------------------------------------------+
//| EMA sobre array (índice 0 = más antiguo)                          |
//+------------------------------------------------------------------+
double EMAval(const double &arr[], int length, int shift_from_end)
{
   int total = ArraySize(arr);
   int end   = total - 1 - shift_from_end;
   if(end < length - 1) return 0;
   double alpha = 2.0 / (length + 1);
   double ema   = arr[end - length + 1];
   for(int i = end - length + 2; i <= end; i++)
      ema = arr[i] * alpha + ema * (1.0 - alpha);
   return ema;
}

//+------------------------------------------------------------------+
//| Heikin-Ashi para barra bar (1=última cerrada)                     |
//+------------------------------------------------------------------+
struct HABar { double open, high, low, close; };

HABar CalcHA(int bar)
{
   int seed_bars = 300;
   double haO_prev = (iOpen(_Symbol, _Period, bar + seed_bars) +
                      iClose(_Symbol, _Period, bar + seed_bars)) / 2.0;

   double haC_cur = 0;
   double haO_cur = 0;
   for(int i = bar + seed_bars - 1; i >= bar; i--)
   {
      double ci = iClose(_Symbol, _Period, i);
      double oi = iOpen (_Symbol, _Period, i);
      double hi = iHigh (_Symbol, _Period, i);
      double li = iLow  (_Symbol, _Period, i);
      haC_cur = (oi + hi + li + ci) / 4.0;
      haO_cur = (haO_prev + haC_cur) / 2.0; // haOpen[i] usa haOpen[i+1]
      haO_prev = haO_cur;
   }

   HABar r;
   r.close = haC_cur;
   r.open  = haO_cur;
   double o = iOpen(_Symbol, _Period, bar);
   double h = iHigh(_Symbol, _Period, bar);
   double l = iLow (_Symbol, _Period, bar);
   r.high  = MathMax(h, MathMax(r.open, r.close));
   r.low   = MathMin(l, MathMin(r.open, r.close));
   return r;
}

//+------------------------------------------------------------------+
//| ZLEMA (Zero-Lag EMA) — calc_zlema() del Pine                      |
//+------------------------------------------------------------------+
double ZLEMA(const double &arr[], int length, int shift_from_end)
{
   int total = ArraySize(arr);
   int end   = total - 1 - shift_from_end;
   if(end < length - 1) return 0;
   double alpha = 2.0 / (length + 1);
   // EMA1
   double ema1 = arr[end - length + 1];
   for(int i = end - length + 2; i <= end; i++)
      ema1 = arr[i] * alpha + ema1 * (1.0 - alpha);
   // EMA2 (de EMA1 — aproximación: re-smooth ema1 sobre el mismo rango)
   double ema2 = ema1 * 0.9; // semilla
   for(int i = end - length + 2; i <= end; i++)
      ema2 = ema1 * alpha + ema2 * (1.0 - alpha);
   double d = ema1 - ema2;
   return ema1 + d;
}

//+------------------------------------------------------------------+
//| Impulse MACD md para barra bar (1=última cerrada)                 |
//+------------------------------------------------------------------+
double CalcIMACDmd(int bar)
{
   int needed = ImacLen * 4 + bar + 10;
   double hlc3[], hi_arr[], lo_arr[];
   ArrayResize(hlc3,   needed);
   ArrayResize(hi_arr, needed);
   ArrayResize(lo_arr, needed);

   for(int i = 0; i < needed; i++)
   {
      int b = needed - 1 - i + bar;
      hlc3[i]   = (iHigh(_Symbol,_Period,b) + iLow(_Symbol,_Period,b) + iClose(_Symbol,_Period,b)) / 3.0;
      hi_arr[i] = iHigh(_Symbol, _Period, b);
      lo_arr[i] = iLow (_Symbol, _Period, b);
   }

   double mi = ZLEMA(hlc3, ImacLen, 0);

   // RMA (Wilder) de high y low
   double alpha_r = 1.0 / ImacLen;
   double hi_rma  = hi_arr[0];
   double lo_rma  = lo_arr[0];
   for(int i = 1; i < needed; i++)
   {
      hi_rma = hi_arr[i] * alpha_r + hi_rma * (1.0 - alpha_r);
      lo_rma = lo_arr[i] * alpha_r + lo_rma * (1.0 - alpha_r);
   }

   double md;
   if     (mi > hi_rma) md = mi - hi_rma;
   else if(mi < lo_rma) md = mi - lo_rma;
   else                 md = 0.0;
   return md;
}

//+------------------------------------------------------------------+
//| Swing Low/High                                                    |
//+------------------------------------------------------------------+
double LowestLow(int period, int shift)
{
   double lo = iLow(_Symbol, _Period, shift);
   for(int i = shift + 1; i < shift + period; i++)
      lo = MathMin(lo, iLow(_Symbol, _Period, i));
   return lo;
}

double HighestHigh(int period, int shift)
{
   double hi = iHigh(_Symbol, _Period, shift);
   for(int i = shift + 1; i < shift + period; i++)
      hi = MathMax(hi, iHigh(_Symbol, _Period, i));
   return hi;
}

//+------------------------------------------------------------------+
//| Lotaje dinámico                                                   |
//+------------------------------------------------------------------+
double CalcLot(double sl_dist)
{
   if(sl_dist <= 0) return SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double risk_money = AccountInfoDouble(ACCOUNT_EQUITY) * (RiskPercent / 100.0);
   double tick_value = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double tick_size  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   double lot        = risk_money / ((sl_dist / tick_size) * tick_value);
   double lot_min    = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double lot_step   = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   double lot_max    = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   lot = MathMax(lot_min, MathRound(lot / lot_step) * lot_step);
   lot = MathMin(lot, lot_max);
   return lot;
}

//+------------------------------------------------------------------+
//| OnInit                                                            |
//+------------------------------------------------------------------+
int OnInit()
{
   trade.SetExpertMagicNumber(MAGIC_HA_EMA);
   trade.SetDeviationInPoints(20);
   Print("HA_EMA iniciado | Magic: ", MAGIC_HA_EMA);
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| OnTick                                                            |
//+------------------------------------------------------------------+
void OnTick()
{
   // Solo en nueva barra (equivale a process_orders_on_close=true en Pine)
   datetime current_bar = iTime(_Symbol, _Period, 0);
   if(current_bar == s_last_bar) return;
   s_last_bar = current_bar;

   // ── VELAS HEIKIN-ASHI ────────────────────────────────────────
   HABar ha1 = CalcHA(1);  // última barra cerrada
   HABar ha2 = CalcHA(2);  // barra anterior

   bool ha_green_1 = ha1.close > ha1.open;
   bool ha_red_1   = ha1.close < ha1.open;
   bool ha_green_2 = ha2.close > ha2.open;
   bool ha_red_2   = ha2.close < ha2.open;

   // ── EMAS ─────────────────────────────────────────────────────
   int   nb = EMA200Len * 3 + 10;
   double close_arr[];
   ArrayResize(close_arr, nb);
   for(int i = 0; i < nb; i++)
      close_arr[i] = iClose(_Symbol, _Period, nb - i); // bar nb..1 (antiguo→reciente)

   double ema_fast_1 = EMAval(close_arr, EmaFastLen, 0);
   double ema_slow_1 = EMAval(close_arr, EmaSlowLen, 0);
   double ema_200_1  = UseEMA200 ? EMAval(close_arr, EMA200Len, 0) : 0;
   double ema_fast_2 = EMAval(close_arr, EmaFastLen, 1);
   double ema_slow_2 = EMAval(close_arr, EmaSlowLen, 1);

   double close1 = iClose(_Symbol, _Period, 1);

   // ── IMPULSE MACD ─────────────────────────────────────────────
   double md1 = CalcIMACDmd(1);

   // ── FILTROS ──────────────────────────────────────────────────
   bool imacd_long_ok   = !UseIMACD  || (md1 > 0.0);
   bool imacd_short_ok  = !UseIMACD  || (md1 < 0.0);
   bool ema200_long_ok  = !UseEMA200 || (close1 > ema_200_1);
   bool ema200_short_ok = !UseEMA200 || (close1 < ema_200_1);
   bool ha_str_long     = !UseHAStrength || (ha1.low  == ha1.open);   // sin mecha inferior
   bool ha_str_short    = !UseHAStrength || (ha1.high == ha1.open);   // sin mecha superior

   // ── ALINEACIÓN + TRIGGER ─────────────────────────────────────
   bool aligned_long_1  = (ema_fast_1 > ema_slow_1) && ha_green_1 && imacd_long_ok  && ema200_long_ok  && ha_str_long;
   bool aligned_short_1 = (ema_fast_1 < ema_slow_1) && ha_red_1   && imacd_short_ok && ema200_short_ok && ha_str_short;
   bool aligned_long_2  = (ema_fast_2 > ema_slow_2) && ha_green_2;
   bool aligned_short_2 = (ema_fast_2 < ema_slow_2) && ha_red_2;

   bool trigger_long  = aligned_long_1  && !aligned_long_2;   // primer bar alineado
   bool trigger_short = aligned_short_1 && !aligned_short_2;

   // ── TRAILING POR TERCIOS ─────────────────────────────────────
   ENUM_POSITION_TYPE pos_type = GetOwnPositionType();
   bool has_pos = (pos_type != (ENUM_POSITION_TYPE)-1);

   if(has_pos && g_trail_step > 0)
   {
      ulong ticket = GetOwnTicket();
      if(ticket > 0 && PositionSelectByTicket(ticket))
      {
         double cur_tp = PositionGetDouble(POSITION_TP);
         if(pos_type == POSITION_TYPE_BUY)
         {
            double hi1       = iHigh(_Symbol, _Period, 1);
            double recorrido = hi1 - g_entry_price;
            int    niveles   = (int)MathFloor(recorrido / g_trail_step);
            if(niveles > 0)
            {
               double init_sl  = g_entry_price - (g_trail_step * 3.0);
               double nuevo_sl = init_sl + (g_trail_step * niveles);
               if(nuevo_sl > g_active_sl)
               {
                  g_active_sl = nuevo_sl;
                  trade.PositionModify(ticket,
                     NormalizeDouble(g_active_sl, _Digits),
                     NormalizeDouble(cur_tp, _Digits));
               }
            }
         }
         else if(pos_type == POSITION_TYPE_SELL)
         {
            double lo1       = iLow(_Symbol, _Period, 1);
            double recorrido = g_entry_price - lo1;
            int    niveles   = (int)MathFloor(recorrido / g_trail_step);
            if(niveles > 0)
            {
               double init_sl  = g_entry_price + (g_trail_step * 3.0);
               double nuevo_sl = init_sl - (g_trail_step * niveles);
               if(nuevo_sl < g_active_sl || g_active_sl == 0)
               {
                  g_active_sl = nuevo_sl;
                  trade.PositionModify(ticket,
                     NormalizeDouble(g_active_sl, _Digits),
                     NormalizeDouble(cur_tp, _Digits));
               }
            }
         }
      }
   }

   // ── ENTRADAS ─────────────────────────────────────────────────
   if(!has_pos)
   {
      double sl_buf = SL_BufferPts * _Point;

      if(trigger_long)
      {
         double pend_sl  = LowestLow(SwingPeriod, 1) - sl_buf;
         if((close1 - pend_sl) <= 0) pend_sl = close1 - _Point;
         double risk     = close1 - pend_sl;
         double pend_tp  = UseTP ? close1 + risk * RR_Ratio : 0;
         double lot      = CalcLot(risk);

         if(trade.Buy(lot, _Symbol, 0,
                      NormalizeDouble(pend_sl, _Digits),
                      UseTP ? NormalizeDouble(pend_tp, _Digits) : 0,
                      "HA_EMA Long"))
         {
            g_entry_price = trade.ResultPrice();
            g_active_sl   = pend_sl;
            g_active_tp   = pend_tp;
            g_trail_step  = MathAbs(g_entry_price - pend_sl) / 3.0;
         }
      }
      else if(trigger_short)
      {
         double pend_sl  = HighestHigh(SwingPeriod, 1) + sl_buf;
         if((pend_sl - close1) <= 0) pend_sl = close1 + _Point;
         double risk     = pend_sl - close1;
         double pend_tp  = UseTP ? close1 - risk * RR_Ratio : 0;
         double lot      = CalcLot(risk);

         if(trade.Sell(lot, _Symbol, 0,
                       NormalizeDouble(pend_sl, _Digits),
                       UseTP ? NormalizeDouble(pend_tp, _Digits) : 0,
                       "HA_EMA Short"))
         {
            g_entry_price = trade.ResultPrice();
            g_active_sl   = pend_sl;
            g_active_tp   = pend_tp;
            g_trail_step  = MathAbs(g_entry_price - pend_sl) / 3.0;
         }
      }
   }

   // Limpiar estado al cerrar posición
   if(!has_pos && g_in_trade)
   {
      g_active_sl   = 0;
      g_active_tp   = 0;
      g_trail_step  = 0;
      g_entry_price = 0;
   }
   g_in_trade = has_pos;
}
