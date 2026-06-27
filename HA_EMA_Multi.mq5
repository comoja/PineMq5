//+------------------------------------------------------------------+
//|                                                HA_EMA_Multi.mq5  |
//|               Expert Advisor Unificado Heikin-Ashi + EMA         |
//|                    para ORO (XAU) y PLATA (XAG)                  |
//|          Con Autodetección de Activo, MTF y Break-Even           |
//+------------------------------------------------------------------+
#property copyright "Comoja / PineMq5"
#property link      "https://github.com/comoja/PineMq5"
#property version   "1.00"
#property strict

// Incluir librería estándar de trade
#include <Trade\Trade.mqh>
CTrade m_trade;

// Enumeradores de perfiles
enum ENUM_ASSET_PROFILE
  {
   PROFILE_AUTO,     // Auto-detección
   PROFILE_GOLD,     // Oro (XAUUSD)
   PROFILE_SILVER,   // Plata (XAGUSD)
   PROFILE_MANUAL    // Personalizado (Manual)
  };

// ════════════════════════════════════════════════════════════════════
// PARAMETROS DE ENTRADA (INPUTS)
// ════════════════════════════════════════════════════════════════════
input group "--- PERFIL DE CONFIGURACIÓN ---"
input ENUM_ASSET_PROFILE InpAssetProfile = PROFILE_AUTO; // Perfil de Activo

input group "--- GESTIÓN DE RIESGO ---"
input double InpRiskPerc   = 1.0;  // Riesgo por operación (%)
input bool   InpUseTP      = true; // Usar Take Profit Fijo
input double InpRRRatio    = 3.0;  // Relación R:R (Oro=3.0, Plata=2.5)
input bool   InpUseBE      = true; // Usar Break-Even (Mover a Entrada)
input double InpBERatio    = 1.0;  // Multiplicador R:R para Break-Even

input group "--- PARÁMETROS MANUALES (Si perfil = Manual) ---"
input string InpEmaTF      = "Auto"; // Temporalidad de EMAs (Auto, H3, M15...)
input int    InpEmaFastLen = 21;     // Período EMA Rápida manual
input int    InpEmaSlowLen = 55;     // Período EMA Lenta manual
input int    InpSwingPeriod = 8;     // Velas Swing High/Low manual
input double InpSlBufPoints = 2.0;   // Buffer SL manual (Puntos/Ticks)
input bool   InpUseIMACD    = false; // Usar iMACD manual
input int    InpIMACDLen    = 35;    // Período iMACD manual
input bool   InpUseEmaSpr   = true;  // Usar Abertura EMAs manual
input double InpEmaSprMult  = 0.4;   // Abertura Mínima EMAs manual (× ATR)
input bool   InpUseHaStr    = false; // Fuerza Heikin-Ashi manual
input bool   InpUseEma200   = false; // Filtro EMA 200 manual
input int    InpEma200Len   = 200;   // Período EMA 200 manual

input group "--- CONTROL DE SESIÓN ---"
input bool   InpUseSession = false; // Usar Sesión Horaria
input int    InpStartHour  = 8;     // Hora de Inicio (UTC)
input int    InpEndHour    = 17;    // Hora de Fin (UTC)

input group "--- AJUSTES DE EJECUCIÓN ---"
input ulong  InpMagicNumber = 123456; // Número Mágico del EA

// ════════════════════════════════════════════════════════════════════
// VARIABLES GLOBALES EFECTIVAS
// ════════════════════════════════════════════════════════════════════
ENUM_TIMEFRAMES   m_ema_tf;
int               m_ema_fast_len;
int               m_ema_slow_len;
int               m_swing_period;
double            m_sl_buffer_pts;

double            m_rr_ratio;
bool              m_use_be;
double            m_be_ratio;

bool              m_use_imacd;
int               m_imacd_len;

bool              m_use_ema_spread;
double            m_ema_spread_mult;

bool              m_use_ha_strength;
bool              m_use_ema200;
int               m_ema200_len;

// Handles de indicadores
int               h_ema_fast;
int               h_ema_slow;
int               h_ema200;
int               h_atr_local;

// Estado del EA
bool              m_is_gold = false;
bool              m_is_silver = false;
datetime          m_last_bar_time = 0;

// Estructura de Heikin-Ashi
struct HeikinAshi
  {
   double open;
   double high;
   double low;
   double close;
  };

// ════════════════════════════════════════════════════════════════════
// ENTORNO DE INICIALIZACIÓN (OnInit)
// ════════════════════════════════════════════════════════════════════
int OnInit()
  {
   m_trade.SetExpertMagicNumber(InpMagicNumber);
   
   // 1. AUTODETECCIÓN DE PERFILES
   string sym = _Symbol;
   StringToUpper(sym);
   
   bool is_gold_symbol   = (StringFind(sym, "XAU") >= 0 || StringFind(sym, "GOLD") >= 0);
   bool is_silver_symbol = (StringFind(sym, "XAG") >= 0 || StringFind(sym, "SILVER") >= 0);
   
   m_is_gold   = (InpAssetProfile == PROFILE_GOLD)   || (InpAssetProfile == PROFILE_AUTO && is_gold_symbol);
   m_is_silver = (InpAssetProfile == PROFILE_SILVER) || (InpAssetProfile == PROFILE_AUTO && is_silver_symbol);
   
   // 2. RESOLVER PARAMETROS DINÁMICOS
   // Temporalidad de EMAs
   if(m_is_gold)
      m_ema_tf = PERIOD_H3; // Forzado a 3h para el Oro en intradía
   else if(m_is_silver)
      m_ema_tf = PERIOD_M15; // Local a 15m para Plata
   else
     {
      // Resolución Manual o personalizada
      if(InpEmaTF == "Auto")
        {
         if(_Period <= PERIOD_H3) m_ema_tf = PERIOD_H3;
         else m_ema_tf = PERIOD_D1;
        }
      else if(InpEmaTF == "15")   m_ema_tf = PERIOD_M15;
      else if(InpEmaTF == "30")   m_ema_tf = PERIOD_M30;
      else if(InpEmaTF == "60")   m_ema_tf = PERIOD_H1;
      else if(InpEmaTF == "180")  m_ema_tf = PERIOD_H3;
      else if(InpEmaTF == "240")  m_ema_tf = PERIOD_H4;
      else if(InpEmaTF == "1440") m_ema_tf = PERIOD_D1;
      else m_ema_tf = _Period;
     }
     
   // Resto de variables efectivas
   m_ema_fast_len    = m_is_gold ? 21    : m_is_silver ? 9     : InpEmaFastLen;
   m_ema_slow_len    = m_is_gold ? 55    : m_is_silver ? 21    : InpEmaSlowLen;
   m_swing_period    = m_is_gold ? 8     : m_is_silver ? 5     : InpSwingPeriod;
   m_sl_buffer_pts   = m_is_gold ? 2.0   : m_is_silver ? 0.0   : InpSlBufPoints;
   
   m_rr_ratio        = m_is_gold ? 3.0   : m_is_silver ? 2.5   : InpRRRatio;
   m_use_be          = m_is_gold ? false : m_is_silver ? true  : InpUseBE;
   m_be_ratio        = m_is_gold ? 1.0   : m_is_silver ? 1.0   : InpBERatio;
   
   m_use_imacd       = m_is_gold ? false : m_is_silver ? true  : InpUseIMACD;
   m_imacd_len       = m_is_gold ? 35    : m_is_silver ? 35    : InpIMACDLen;
   
   m_use_ema_spread  = m_is_gold ? true  : m_is_silver ? false : InpUseEmaSpr;
   m_ema_spread_mult = m_is_gold ? 0.4   : m_is_silver ? 0.0   : InpEmaSprMult;
   
   m_use_ha_strength = m_is_gold ? false : m_is_silver ? true  : InpUseHaStr;
   m_use_ema200      = m_is_gold ? false : m_is_silver ? true  : InpUseEma200;
   m_ema200_len      = m_is_gold ? 200   : is_silver ? 200     : InpEma200Len;
   
   // 3. INICIALIZAR HANDLES DE INDICADORES
   h_ema_fast = iMA(_Symbol, m_ema_tf, m_ema_fast_len, 0, MODE_EMA, PRICE_CLOSE);
   h_ema_slow = iMA(_Symbol, m_ema_tf, m_ema_slow_len, 0, MODE_EMA, PRICE_CLOSE);
   h_ema200   = iMA(_Symbol, m_ema_tf, m_ema200_len, 0, MODE_EMA, PRICE_CLOSE);
   h_atr_local = iATR(_Symbol, _Period, 14);
   
   if(h_ema_fast == INVALID_HANDLE || h_ema_slow == INVALID_HANDLE || h_ema200 == INVALID_HANDLE || h_atr_local == INVALID_HANDLE)
     {
      Print("Error inicializando handles de indicadores.");
      return(INIT_FAILED);
     }
     
   Print("EA HA_EMA Multi inicializado correctamente.");
   Print("Perfil cargado: ", m_is_gold ? "ORO" : m_is_silver ? "PLATA" : "MANUAL");
   Print("TF EMAs: ", EnumToString(m_ema_tf));
   
   return(INIT_SUCCEEDED);
  }

// ════════════════════════════════════════════════════════════════════
// ENTORNO DE DESINICIALIZACIÓN (OnDeinit)
// ════════════════════════════════════════════════════════════════════
void OnDeinit(const int reason)
  {
   IndicatorRelease(h_ema_fast);
   IndicatorRelease(h_ema_slow);
   IndicatorRelease(h_ema200);
   IndicatorRelease(h_atr_local);
  }

// ════════════════════════════════════════════════════════════════════
// PROCESAMIENTO POR TICK (OnTick)
// ════════════════════════════════════════════════════════════════════
void OnTick()
  {
   // 1. EVALUAR GESTIÓN INTERNA DE POSICIONES ACTIVAS (Break-Even y Trailing)
   GestionarPosiciones();

   // 2. CONTROL DE NUEVA BARRA
   datetime current_bar_time = iTime(_Symbol, _Period, 0);
   if(current_bar_time == m_last_bar_time)
      return; // Evaluar solo en el cierre de barra
      
   // 3. CONTROL DE SESIÓN HORARIA
   if(InpUseSession)
     {
      MqlDateTime dt;
      TimeToStruct(TimeCurrent(), dt);
      if(dt.hour < InpStartHour || dt.hour >= InpEndHour)
         return; // Fuera de horario
     }
     
   // 4. COPIAR VALORES DE EMAs
   double ema_fast_arr[2], ema_slow_arr[2], ema200_arr[2];
   ArraySetAsSeries(ema_fast_arr, true);
   ArraySetAsSeries(ema_slow_arr, true);
   ArraySetAsSeries(ema200_arr, true);
   
   if(CopyBuffer(h_ema_fast, 0, 1, 2, ema_fast_arr) < 2 ||
      CopyBuffer(h_ema_slow, 0, 1, 2, ema_slow_arr) < 2 ||
      CopyBuffer(h_ema200, 0, 1, 2, ema200_arr) < 2)
     {
      return; // Error leyendo EMAs
     }
   double ema_fast_val = ema_fast_arr[0];
   double ema_slow_val = ema_slow_arr[0];
   double ema200_val   = ema200_arr[0];

   // 5. CALCULAR VELAS HEIKIN-ASHI LOCALES
   MqlRates rates[];
   ArraySetAsSeries(rates, true);
   if(CopyRates(_Symbol, _Period, 1, 20, rates) < 20)
      return;
      
   HeikinAshi ha[];
   ArrayResize(ha, 20);
   
   // Inicializar recursión HA
   int oldest_idx = 19;
   ha[oldest_idx].open  = (rates[oldest_idx].open + rates[oldest_idx].close) / 2.0;
   ha[oldest_idx].close = (rates[oldest_idx].open + rates[oldest_idx].high + rates[oldest_idx].low + rates[oldest_idx].close) / 4.0;
   ha[oldest_idx].high  = rates[oldest_idx].high;
   ha[oldest_idx].low   = rates[oldest_idx].low;
   
   for(int i = oldest_idx - 1; i >= 0; i--)
     {
      ha[i].close = (rates[i].open + rates[i].high + rates[i].low + rates[i].close) / 4.0;
      ha[i].open  = (ha[i+1].open + ha[i+1].close) / 2.0;
      ha[i].high  = MathMax(rates[i].high, MathMax(ha[i].open, ha[i].close));
      ha[i].low   = MathMin(rates[i].low,  MathMin(ha[i].open, ha[i].close));
     }
     
   bool ha_green = (ha[0].close > ha[0].open);
   bool ha_red   = (ha[0].close < ha[0].open);
   bool ha_green_prev = (ha[1].close > ha[1].open);
   bool ha_red_prev   = (ha[1].close < ha[1].open);

   // 6. FILTRO DE ABERTURA DE EMAs
   double atr_arr[1];
   if(CopyBuffer(h_atr_local, 0, 1, 1, atr_arr) < 1)
      return;
   double atr = atr_arr[0];
   double distancia_emas = MathAbs(ema_fast_val - ema_slow_val);
   bool abertura_ok = !m_use_ema_spread || (distancia_emas >= (atr * m_ema_spread_mult));

   // 7. CALCULAR IMPULSE MACD (iMACD) MANUAL EN MQL5
   bool imacd_long_ok = true;
   bool imacd_short_ok = true;
   
   if(m_use_imacd)
     {
      double md = CalcularIMACD(m_imacd_len);
      imacd_long_ok  = (md > 0.0);
      imacd_short_ok = (md < 0.0);
     }

   // 8. FILTROS DE OPTIMIZACIÓN SECUNDARIOS
   bool ema200_long_ok  = !m_use_ema200 || (rates[0].close > ema200_val);
   bool ema200_short_ok = !m_use_ema200 || (rates[0].close < ema200_val);
   
   bool ha_strength_long  = !m_use_ha_strength || (ha[0].low == ha[0].open);
   bool ha_strength_short = !m_use_ha_strength || (ha[0].high == ha[0].open);

   // 9. CONDICIONES DE ALINEACIÓN
   bool is_long_aligned = (ema_fast_val > ema_slow_val) && ha_green && 
                          imacd_long_ok && ema200_long_ok && ha_strength_long && abertura_ok;
                          
   bool is_short_aligned = (ema_fast_val < ema_slow_val) && ha_red && 
                           imacd_short_ok && ema200_short_ok && ha_strength_short && abertura_ok;
                           
   // Para confirmación consecutiva de 2 velas, evaluamos también la barra previa:
   bool is_long_aligned_prev = (ema_fast_arr[1] > ema_slow_arr[1]) && ha_green_prev && 
                               ema200_long_ok && abertura_ok; // filtros simplificados para barra previa
                               
   bool is_short_aligned_prev = (ema_fast_arr[1] < ema_slow_arr[1]) && ha_red_prev && 
                                ema200_short_ok && abertura_ok;

   bool trigger_long  = is_long_aligned && is_long_aligned_prev;
   bool trigger_short = is_short_aligned && is_short_aligned_prev;

   // 10. EJECUCIÓN DE ENTRADAS
   if(PositionsTotal() == 0)
     {
      double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      
      // Encontrar Swing de Stop Loss
      double lowest_low = rates[0].low;
      double highest_high = rates[0].high;
      for(int k = 0; k < m_swing_period; k++)
        {
         if(rates[k].low < lowest_low) lowest_low = rates[k].low;
         if(rates[k].high > highest_high) highest_high = rates[k].high;
        }
      double sl_buffer = m_sl_buffer_pts * _Point;

      if(trigger_long)
        {
         double sl = lowest_low - sl_buffer;
         if(ask - sl <= 0) sl = ask - _Point;
         
         double risk = ask - sl;
         double tp = InpUseTP ? (ask + risk * m_rr_ratio) : 0.0;
         double lot = CalcularLote(risk);
         
         if(lot > 0)
           {
            m_trade.Buy(lot, _Symbol, ask, sl, tp, "HA_EMA Long");
            m_last_bar_time = current_bar_time;
           }
        }
      else if(trigger_short)
        {
         double sl = highest_high + sl_buffer;
         if(sl - bid <= 0) sl = bid + _Point;
         
         double risk = sl - bid;
         double tp = InpUseTP ? (bid - risk * m_rr_ratio) : 0.0;
         double lot = CalcularLote(risk);
         
         if(lot > 0)
           {
            m_trade.Sell(lot, _Symbol, bid, sl, tp, "HA_EMA Short");
            m_last_bar_time = current_bar_time;
           }
        }
     }
  }

// ════════════════════════════════════════════════════════════════════
// GESTIONAR POSICIONES EN TICK (Break-Even y Trailing)
// ════════════════════════════════════════════════════════════════════
void GestionarPosiciones()
  {
   if(PositionsTotal() == 0) return;
   
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      if(PositionGetSymbol(i) == _Symbol && PositionGetInteger(POSITION_MAGIC) == InpMagicNumber)
        {
         ulong ticket = PositionGetInteger(POSITION_TICKET);
         double open_p  = PositionGetDouble(POSITION_PRICE_OPEN);
         double curr_sl = PositionGetDouble(POSITION_SL);
         double curr_tp = PositionGetDouble(POSITION_TP);
         double type    = PositionGetInteger(POSITION_TYPE);
         
         double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
         double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
         
         double risk_inicial = MathAbs(open_p - curr_sl);
         double step = risk_inicial / 3.0; // Tercios
         
         // 1. GESTIÓN DEL BREAK-EVEN
         if(m_use_be && curr_sl != open_p)
           {
            if(type == POSITION_TYPE_BUY)
              {
               double recorrido = bid - open_p;
               if(recorrido >= (risk_inicial * m_be_ratio))
                 {
                  m_trade.PositionModify(ticket, open_p, curr_tp);
                  Print("Break-even activado para Long.");
                  continue;
                 }
              }
            else if(type == POSITION_TYPE_SELL)
              {
               double recorrido = open_p - ask;
               if(recorrido >= (risk_inicial * m_be_ratio))
                 {
                  m_trade.PositionModify(ticket, open_p, curr_tp);
                  Print("Break-even activado para Short.");
                  continue;
                 }
              }
           }
           
         // 2. GESTIÓN DEL TRAILING STOP POR TERCIOS
         if(type == POSITION_TYPE_BUY)
           {
            double recorrido = bid - open_p;
            int niveles = (int)MathFloor(recorrido / step);
            if(niveles > 0)
              {
               double initial_sl = open_p - (step * 3.0);
               double nuevo_sl = initial_sl + (step * niveles);
               if(nuevo_sl > curr_sl)
                 {
                  m_trade.PositionModify(ticket, nuevo_sl, curr_tp);
                  Print("Trailing Stop ajustado para Long: ", nuevo_sl);
                 }
              }
           }
         else if(type == POSITION_TYPE_SELL)
           {
            double recorrido = open_p - ask;
            int niveles = (int)MathFloor(recorrido / step);
            if(niveles > 0)
              {
               double initial_sl = open_p + (step * 3.0);
               double nuevo_sl = initial_sl - (step * niveles);
               if(nuevo_sl < curr_sl || curr_sl == 0.0)
                 {
                  m_trade.PositionModify(ticket, nuevo_sl, curr_tp);
                  Print("Trailing Stop ajustado para Short: ", nuevo_sl);
                 }
              }
           }
        }
     }
  }

// ════════════════════════════════════════════════════════════════════
// CALCULAR IMPULSE MACD MANUAL
// ════════════════════════════════════════════════════════════════════
double CalcularIMACD(int len)
  {
   MqlRates rates[];
   ArraySetAsSeries(rates, true);
   int copied = CopyRates(_Symbol, _Period, 1, len * 3, rates);
   if(copied < len * 3) return 0.0;
   
   double src[];
   ArrayResize(src, copied);
   for(int i = 0; i < copied; i++)
      src[i] = (rates[i].high + rates[i].low + rates[i].close) / 3.0;
      
   // Zero-Lag EMA calculation
   int lag = (len - 1) / 2;
   double src_zlag[];
   ArrayResize(src_zlag, copied - lag);
   for(int i = 0; i < copied - lag; i++)
      src_zlag[i] = src[i] + (src[i] - src[i + lag]);
      
   // EMA de Zlag
   double alpha = 2.0 / (len + 1.0);
   double mi = src_zlag[ArraySize(src_zlag) - 1]; // Inicializar con el dato más antiguo
   for(int i = ArraySize(src_zlag) - 2; i >= 0; i--)
     {
      mi = src_zlag[i] * alpha + mi * (1.0 - alpha);
     }
     
   // RMA de High y Low (equivalente a EMA con alpha = 1.0 / len)
   double alpha_rma = 1.0 / len;
   double hi = rates[copied - 1].high;
   double lo = rates[copied - 1].low;
   for(int i = copied - 2; i >= 0; i--)
     {
      hi = rates[i].high * alpha_rma + hi * (1.0 - alpha_rma);
      lo = rates[i].low * alpha_rma + lo * (1.0 - alpha_rma);
     }
     
   double md = 0.0;
   if(mi > hi)      md = mi - hi;
   else if(mi < lo) md = mi - lo;
   
   return md;
  }

// ════════════════════════════════════════════════════════════════════
// CALCULAR LOTE AUTOMÁTICO EN BASE A RIESGO PORCENTUAL
// ════════════════════════════════════════════════════════════════════
double CalcularLote(double risk_dist_points)
  {
   if(risk_dist_points <= 0) return 0.0;
   
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   double risk_money = balance * (InpRiskPerc / 100.0);
   
   double tick_value = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double tick_size  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   double lot_step   = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   double min_lot    = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double max_lot    = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   
   if(tick_value <= 0 || tick_size <= 0) return min_lot;
   
   double risk_in_ticks = risk_dist_points / tick_size;
   double lot = risk_money / (risk_in_ticks * tick_value);
   
   // Redondear al paso de lote permitido
   lot = MathFloor(lot / lot_step) * lot_step;
   
   if(lot < min_lot) lot = min_lot;
   if(lot > max_lot) lot = max_lot;
   
   return lot;
  }
