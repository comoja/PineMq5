//+------------------------------------------------------------------+
//|                                                HA_EMA_Multi.mq5  |
//|               Expert Advisor Unificado Heikin-Ashi + EMA         |
//|       para ORO (XAU), PLATA (XAG), BITCOIN (BTC) y NASDAQ (NAS)  |
//|          Con Autodetección de Activo, MTF y Break-Even           |
//+------------------------------------------------------------------+
#property copyright "Comoja / PineMq5"
#property link      "https://github.com/comoja/PineMq5"
#property version   "1.10"
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
   PROFILE_BITCOIN,  // Bitcoin (BTCUSD)
   PROFILE_NASDAQ,   // Nasdaq (NAS100)
   PROFILE_MANUAL    // Personalizado (Manual)
  };

// ════════════════════════════════════════════════════════════════════
// PARAMETROS DE ENTRADA (INPUTS)
// ════════════════════════════════════════════════════════════════════
input group "--- PERFIL DE CONFIGURACIÓN ---"
input ENUM_ASSET_PROFILE InpAssetProfile = PROFILE_AUTO; // Perfil de Activo

input group "--- GESTIÓN DE RIESGO ---"
input double InpRiskPerc       = 1.0;   // Riesgo por operación (%)
input bool   InpUseTP          = true;  // Usar Take Profit Fijo
input double InpRRRatio        = 3.3;   // Relación R:R
input bool   InpUseBE          = true;  // Usar Break-Even (Mover a Entrada)
input double InpBERatio        = 1.5;   // Multiplicador R:R para Break-Even
input bool   InpUseTPChase     = true;  // Usar Persecución de TP (TP Chasing)
input double InpTPChasePts     = 12.0;  // Distancia de Persecución TP (Pts)
input double InpTPChaseOffset  = 12.0;  // Avance del TP (Pts)

input group "--- PARÁMETROS MANUALES (Si perfil = Manual) ---"
input string InpEmaTF          = "Auto"; // Temporalidad de EMAs
input int    InpEmaFastLen     = 8;      // Período EMA Rápida manual
input int    InpEmaSlowLen     = 22;     // Período EMA Lenta manual
input int    InpSwingPeriod    = 8;      // Velas Swing High/Low manual
input double InpSlBufPoints    = 0.3;    // Buffer SL manual (Puntos/Ticks)
input bool   InpUseIMACD       = true;   // Usar iMACD manual
input int    InpIMACDLen       = 35;     // Período iMACD manual
input bool   InpUseEmaSpr      = true;   // Usar Abertura EMAs manual
input double InpEmaSprMult     = 0.15;   // Abertura Mínima EMAs manual (× ATR)
input bool   InpUseHaStr       = false;  // Fuerza Heikin-Ashi manual
input bool   InpUseEma200      = true;   // Filtro EMA 200 manual
input int    InpEma200Len      = 200;    // Período EMA 200 manual
input bool   InpUseATRMin      = true;   // Filtro ATR Mínimo manual
input double InpATRMinVal      = 3.5;    // ATR Mínimo manual (USD)
input bool   InpUseADX         = true;   // Filtro ADX manual
input double InpADXMin         = 22.0;   // ADX Mínimo manual
input int    InpConfirmBars    = 1;      // Velas de Confirmación manual
input int    InpHaColorLimit   = 6;      // Límite de Recencia de Color HA manual

input group "--- CONTROL DE SESIÓN ---"
input bool   InpUseSession     = true;  // Usar Sesión Horaria
input int    InpStartHour      = 7;     // Hora de Inicio (UTC)
input int    InpEndHour        = 17;    // Hora de Fin (UTC)

input group "--- AJUSTES DE EJECUCIÓN ---"
input ulong  InpMagicNumber    = 123456; // Número Mágico del EA

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
bool              m_use_tp_chase;
double            m_tp_chase_pts;
double            m_tp_chase_offset;

bool              m_use_imacd;
int               m_imacd_len;

bool              m_use_ema_spread;
double            m_ema_spread_mult;

bool              m_use_ha_strength;
bool              m_use_ema200;
int               m_ema200_len;

bool              m_use_atr_min;
double            m_atr_min_val;
bool              m_use_adx;
double            m_adx_min;

int               m_confirm_bars;
int               m_ha_color_change_limit;

bool              m_use_session;
int               m_start_hour;
int               m_end_hour;

// Handles de indicadores
int               h_ema_fast;
int               h_ema_slow;
int               h_ema200;
int               h_atr_local;
int               h_adx;

// Estado del EA
bool              m_is_gold = false;
bool              m_is_silver = false;
bool              m_is_bitcoin = false;
bool              m_is_nasdaq = false;
datetime          m_last_bar_time = 0;

// Estructura de Heikin-Ashi
struct HeikinAshi
  {
   double open;
   double high;
   double low;
   double close;
  };

// Prototipos de funciones
bool IsLongAligned(int j, const double &ema_fast[], const double &ema_slow[], const double &ema200[], const HeikinAshi &ha[], const double &atr[], const double &adx[], const MqlRates &rates[], double md);
bool IsShortAligned(int j, const double &ema_fast[], const double &ema_slow[], const double &ema200[], const HeikinAshi &ha[], const double &atr[], const double &adx[], const MqlRates &rates[], double md);
double CalcularIMACD(int len, int shift);
double CalcularLote(double risk_dist_points);
void GestionarPosiciones();

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
   bool is_btc_symbol    = (StringFind(sym, "BTC") >= 0 || StringFind(sym, "BITCOIN") >= 0);
   bool is_nas_symbol    = (StringFind(sym, "NAS") >= 0 || StringFind(sym, "NASDAQ") >= 0 || StringFind(sym, "US100") >= 0 || StringFind(sym, "USTEC") >= 0 || StringFind(sym, "NQ") >= 0 || StringFind(sym, "TECH") >= 0);
   
   m_is_gold    = (InpAssetProfile == PROFILE_GOLD)    || (InpAssetProfile == PROFILE_AUTO && is_gold_symbol);
   m_is_silver  = (InpAssetProfile == PROFILE_SILVER)  || (InpAssetProfile == PROFILE_AUTO && is_silver_symbol);
   m_is_bitcoin = (InpAssetProfile == PROFILE_BITCOIN) || (InpAssetProfile == PROFILE_AUTO && is_btc_symbol);
   m_is_nasdaq  = (InpAssetProfile == PROFILE_NASDAQ)  || (InpAssetProfile == PROFILE_AUTO && is_nas_symbol);
   
   // 2. RESOLVER PARAMETROS DINÁMICOS POR ACTIVO
   if(m_is_gold)
      m_ema_tf = _Period; // El Oro usa el TF local (15m sugerido)
   else if(m_is_silver)
      m_ema_tf = PERIOD_M15; // 15m para Plata
   else if(m_is_bitcoin)
      m_ema_tf = PERIOD_M15; // 15m para Bitcoin
   else if(m_is_nasdaq)
      m_ema_tf = _Period; // M5 local para Nasdaq
   else
     {
      // Resolución Manual
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
   m_ema_fast_len    = m_is_gold ? 8      : m_is_silver ? 9     : m_is_bitcoin ? 9     : m_is_nasdaq ? 9     : InpEmaFastLen;
   m_ema_slow_len    = m_is_gold ? 22     : m_is_silver ? 21    : m_is_bitcoin ? 21    : m_is_nasdaq ? 21    : InpEmaSlowLen;
   m_swing_period    = m_is_gold ? 8      : m_is_silver ? 5     : m_is_bitcoin ? 5     : m_is_nasdaq ? 5     : InpSwingPeriod;
   m_sl_buffer_pts   = m_is_gold ? 0.3    : m_is_silver ? 0.0   : m_is_bitcoin ? 0.0   : m_is_nasdaq ? 0.0   : InpSlBufPoints;
   
   m_rr_ratio        = m_is_gold ? 3.3    : m_is_silver ? 2.5   : m_is_bitcoin ? 1.8   : m_is_nasdaq ? 1.5   : InpRRRatio;
   m_use_be          = m_is_gold ? true   : m_is_silver ? true  : m_is_bitcoin ? true  : m_is_nasdaq ? true  : InpUseBE;
   m_be_ratio        = m_is_gold ? 1.5    : m_is_silver ? 1.0   : m_is_bitcoin ? 1.0   : m_is_nasdaq ? 1.0   : InpBERatio;
   
   m_use_tp_chase     = m_is_gold ? true   : m_is_silver ? true  : m_is_bitcoin ? true  : m_is_nasdaq ? true  : InpUseTPChase;
   m_tp_chase_pts     = m_is_gold ? 12.0   : m_is_silver ? 2.0   : m_is_bitcoin ? 150.0 : m_is_nasdaq ? 15.0  : InpTPChasePts;
   m_tp_chase_offset  = m_is_gold ? 12.0   : m_is_silver ? 2.0   : m_is_bitcoin ? 150.0 : m_is_nasdaq ? 15.0  : InpTPChaseOffset;
   
   m_use_imacd       = m_is_gold ? true   : m_is_silver ? true  : m_is_bitcoin ? true  : m_is_nasdaq ? false : InpUseIMACD;
   m_imacd_len       = m_is_gold ? 35     : m_is_silver ? 35    : m_is_bitcoin ? 35    : m_is_nasdaq ? 35    : InpIMACDLen;
   
   m_use_ema_spread  = m_is_gold ? true   : m_is_silver ? false : m_is_bitcoin ? true  : m_is_nasdaq ? false : InpUseEmaSpr;
   m_ema_spread_mult = m_is_gold ? 0.15   : m_is_silver ? 0.0   : m_is_bitcoin ? 0.3   : m_is_nasdaq ? 0.0    : InpEmaSprMult;
   
   m_use_ha_strength = m_is_gold ? false  : m_is_silver ? true  : m_is_bitcoin ? true  : m_is_nasdaq ? false : InpUseHaStr;
   m_use_ema200      = m_is_gold ? true   : m_is_silver ? true  : m_is_bitcoin ? true  : m_is_nasdaq ? false : InpUseEma200;
   m_ema200_len      = m_is_gold ? 200    : m_is_silver ? 200   : m_is_bitcoin ? 200   : m_is_nasdaq ? 200   : InpEma200Len;
   
   m_use_atr_min     = m_is_gold ? true   : m_is_silver ? false : m_is_bitcoin ? false : m_is_nasdaq ? false : InpUseATRMin;
   m_atr_min_val     = m_is_gold ? 3.5    : m_is_silver ? 2.0   : m_is_bitcoin ? 2.0   : m_is_nasdaq ? 2.0   : InpATRMinVal;
   
   m_use_adx         = m_is_gold ? true   : m_is_silver ? false : m_is_bitcoin ? false : m_is_nasdaq ? false : InpUseADX;
   m_adx_min         = m_is_gold ? 22.0   : m_is_silver ? 22.0  : m_is_bitcoin ? 22.0  : m_is_nasdaq ? 22.0  : InpADXMin;
   
   m_confirm_bars          = m_is_gold ? 1 : m_is_silver ? 1 : m_is_bitcoin ? 1 : m_is_nasdaq ? 1 : InpConfirmBars;
   m_ha_color_change_limit = m_is_gold ? 6 : m_is_silver ? 4 : m_is_bitcoin ? 6 : m_is_nasdaq ? 6 : InpHaColorLimit;
   
   m_use_session     = m_is_gold ? true   : m_is_silver ? false : m_is_bitcoin ? false : m_is_nasdaq ? false : InpUseSession;
   m_start_hour      = m_is_gold ? 7      : InpStartHour;
   m_end_hour        = m_is_gold ? 17     : InpEndHour;
   
   // 3. INICIALIZAR HANDLES DE INDICADORES
   h_ema_fast  = iMA(_Symbol, m_ema_tf, m_ema_fast_len, 0, MODE_EMA, PRICE_CLOSE);
   h_ema_slow  = iMA(_Symbol, m_ema_tf, m_ema_slow_len, 0, MODE_EMA, PRICE_CLOSE);
   h_ema200    = iMA(_Symbol, m_ema_tf, m_ema200_len, 0, MODE_EMA, PRICE_CLOSE);
   h_atr_local = iATR(_Symbol, _Period, 14);
   h_adx       = iADX(_Symbol, _Period, 14);
   
   if(h_ema_fast == INVALID_HANDLE || h_ema_slow == INVALID_HANDLE || h_ema200 == INVALID_HANDLE || h_atr_local == INVALID_HANDLE || h_adx == INVALID_HANDLE)
     {
      Print("Error inicializando handles de indicadores.");
      return(INIT_FAILED);
     }
     
   Print("EA HA_EMA Multi compilado y listo en MT5.");
   Print("Perfil actual cargado: ", m_is_gold ? "ORO" : m_is_silver ? "PLATA" : m_is_bitcoin ? "BITCOIN" : m_is_nasdaq ? "NASDAQ" : "MANUAL");
   
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
   IndicatorRelease(h_adx);
  }

// ════════════════════════════════════════════════════════════════════
// PROCESAMIENTO POR TICK (OnTick)
// ════════════════════════════════════════════════════════════════════
void OnTick()
  {
   // 1. EVALUAR GESTIÓN INTERNA DE POSICIONES ACTIVAS (TP Chase, BE y Trailing)
   GestionarPosiciones();

   // 2. CONTROL DE NUEVA BARRA
   datetime current_bar_time = iTime(_Symbol, _Period, 0);
   if(current_bar_time == m_last_bar_time)
      return; // Evaluar solo al cierre/apertura de vela
      
   // 3. COPIAR VALORES DE INDICADORES (Se copian 4 elementos para analizar j=0, 1, 2)
   double ema_fast_arr[], ema_slow_arr[], ema200_arr[], atr_arr[], adx_arr[];
   ArraySetAsSeries(ema_fast_arr, true);
   ArraySetAsSeries(ema_slow_arr, true);
   ArraySetAsSeries(ema200_arr, true);
   ArraySetAsSeries(atr_arr, true);
   ArraySetAsSeries(adx_arr, true);
   
   if(CopyBuffer(h_ema_fast, 0, 1, 4, ema_fast_arr) < 4 ||
      CopyBuffer(h_ema_slow, 0, 1, 4, ema_slow_arr) < 4 ||
      CopyBuffer(h_ema200, 0, 1, 4, ema200_arr) < 4 ||
      CopyBuffer(h_atr_local, 0, 1, 4, atr_arr) < 4 ||
      CopyBuffer(h_adx, 0, 1, 4, adx_arr) < 4)
     {
      return; // Error leyendo EMAs / Volatilidad
     }
   
   // 4. COPIAR VELAS HEIKIN-ASHI LOCALES
   MqlRates rates[];
   ArraySetAsSeries(rates, true);
   if(CopyRates(_Symbol, _Period, 1, 40, rates) < 40)
      return;
      
   HeikinAshi ha[];
   ArrayResize(ha, 40);
   
   // Inicializar recursión HA
   int oldest_idx = 39;
   ha[oldest_idx].open  = (rates[oldest_idx].open + rates[oldest_idx].close) / 2.0;
   ha[oldest_idx].close = (rates[oldest_idx].open + rates[oldest_idx].high + rates[oldest_idx].low + rates[oldest_idx].close) / 4.0;
   
   for(int i = oldest_idx - 1; i >= 0; i--)
     {
      ha[i].close = (rates[i].open + rates[i].high + rates[i].low + rates[i].close) / 4.0;
      ha[i].open  = (ha[i+1].open + ha[i+1].close) / 2.0;
     }

   // 5. CALCULAR VALORES DEL IMPULSE MACD
   double md_0 = 0.0, md_1 = 0.0, md_2 = 0.0;
   if(m_use_imacd)
     {
      md_0 = CalcularIMACD(m_imacd_len, 0);
      md_1 = CalcularIMACD(m_imacd_len, 1);
      md_2 = CalcularIMACD(m_imacd_len, 2);
     }

   // 6. COMPROBAR ALINEACIÓN DE CRUCES
   bool trigger_long = false;
   bool trigger_short = false;
   
   bool is_long_aligned_0 = IsLongAligned(0, ema_fast_arr, ema_slow_arr, ema200_arr, ha, atr_arr, adx_arr, rates, md_0);
   bool is_long_aligned_1 = IsLongAligned(1, ema_fast_arr, ema_slow_arr, ema200_arr, ha, atr_arr, adx_arr, rates, md_1);
   
   bool is_short_aligned_0 = IsShortAligned(0, ema_fast_arr, ema_slow_arr, ema200_arr, ha, atr_arr, adx_arr, rates, md_0);
   bool is_short_aligned_1 = IsShortAligned(1, ema_fast_arr, ema_slow_arr, ema200_arr, ha, atr_arr, adx_arr, rates, md_1);
   
   if(m_confirm_bars == 1)
     {
      trigger_long  = is_long_aligned_0 && !is_long_aligned_1;
      trigger_short = is_short_aligned_0 && !is_short_aligned_1;
     }
   else if(m_confirm_bars == 2)
     {
      bool is_long_aligned_2 = IsLongAligned(2, ema_fast_arr, ema_slow_arr, ema200_arr, ha, atr_arr, adx_arr, rates, md_2);
      bool is_short_aligned_2 = IsShortAligned(2, ema_fast_arr, ema_slow_arr, ema200_arr, ha, atr_arr, adx_arr, rates, md_2);
      
      trigger_long  = is_long_aligned_0 && is_long_aligned_1 && !is_long_aligned_2;
      trigger_short = is_short_aligned_0 && is_short_aligned_1 && !is_short_aligned_2;
     }

   // 7. EJECUCIÓN DE ENTRADAS
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
      double sl_buffer = m_sl_buffer_pts; // Pinescript buffer directo en puntos

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
// GESTIONAR POSICIONES EN TICK (TP Chase, Break-Even y Trailing)
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
         long type      = PositionGetInteger(POSITION_TYPE);
         
         double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
         double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
         
         double bar_high = iHigh(_Symbol, _Period, 0);
         double bar_low  = iLow(_Symbol, _Period, 0);
         
         // 1. MOTOR DE GESTIÓN DINÁMICA: PERSECUCIÓN DE TAKE PROFIT (TP CHASING)
         if(m_use_tp_chase && curr_tp > 0.0)
           {
            if(type == POSITION_TYPE_BUY)
              {
               if((curr_tp - bar_high) <= m_tp_chase_pts)
                 {
                  double nuevo_tp = bar_high + m_tp_chase_offset;
                  m_trade.PositionModify(ticket, curr_sl, nuevo_tp);
                  Print("TP Chase activado para Long. Nuevo TP: ", nuevo_tp);
                  curr_tp = nuevo_tp; // Actualizar variable local
                 }
              }
            else if(type == POSITION_TYPE_SELL)
              {
               if((bar_low - curr_tp) <= m_tp_chase_pts)
                 {
                  double nuevo_tp = bar_low - m_tp_chase_offset;
                  m_trade.PositionModify(ticket, curr_sl, nuevo_tp);
                  Print("TP Chase activado para Short. Nuevo TP: ", nuevo_tp);
                  curr_tp = nuevo_tp; // Actualizar variable local
                 }
              }
           }
         
         double risk_inicial = MathAbs(open_p - curr_sl);
         double step = risk_inicial / 5.0; // Quintos
         
         // 2. GESTIÓN DEL BREAK-EVEN
         if(m_use_be && curr_sl != open_p)
           {
            if(type == POSITION_TYPE_BUY)
              {
               double recorrido = bid - open_p;
               if(recorrido >= (risk_inicial * m_be_ratio))
                 {
                  m_trade.PositionModify(ticket, open_p, curr_tp);
                  Print("Break-even activado para Long.");
                  curr_sl = open_p; // Actualizar local
                 }
              }
            else if(type == POSITION_TYPE_SELL)
              {
               double recorrido = open_p - ask;
               if(recorrido >= (risk_inicial * m_be_ratio))
                 {
                  m_trade.PositionModify(ticket, open_p, curr_tp);
                  Print("Break-even activado para Short.");
                  curr_sl = open_p; // Actualizar local
                 }
              }
           }
           
         // 3. GESTIÓN DEL TRAILING STOP POR QUINTOS
         if(type == POSITION_TYPE_BUY)
           {
            double recorrido = bid - open_p;
            int niveles = (int)MathFloor(recorrido / step);
            if(niveles > 0)
              {
               double initial_sl = open_p - (step * 5.0);
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
               double initial_sl = open_p + (step * 5.0);
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
// VALIDACIONES DE ALINEACIÓN POR BARRA J (0=Actual Completada, 1=Prev Completada, etc)
// ════════════════════════════════════════════════════════════════════
bool IsLongAligned(int j, const double &ema_fast[], const double &ema_slow[], const double &ema200[], const HeikinAshi &ha[], const double &atr[], const double &adx[], const MqlRates &rates[], double md)
  {
   double fast = ema_fast[j];
   double slow = ema_slow[j];
   double ema200_val = ema200[j];
   
   bool ha_green = (ha[j].close > ha[j].open);
   bool imacd_ok = !m_use_imacd || (md >= 0.0);
   bool ema200_ok = !m_use_ema200 || (rates[j].close > ema200_val);
   bool ha_strength_ok = !m_use_ha_strength || (ha[j].low == ha[j].open);
   
   double dist = MathAbs(fast - slow);
   bool spread_ok = !m_use_ema_spread || (dist >= (atr[j] * m_ema_spread_mult));
   
   bool atr_ok = !m_use_atr_min || (atr[j] >= m_atr_min_val);
   bool adx_ok = !m_use_adx || (adx[j] >= m_adx_min);
   
   // Session
   bool session_ok = true;
   if(m_use_session)
     {
      MqlDateTime dt;
      TimeToStruct(rates[j].time, dt);
      if(dt.hour < m_start_hour || dt.hour >= m_end_hour)
         session_ok = false;
     }
   
   // Límite de giro Heikin-Ashi: mirar hacia atrás desde la barra j
   int bars_since_change = 99;
   for(int i = j; i < j + 20; i++)
     {
      bool green_i = (ha[i].close > ha[i].open);
      bool red_ip1 = (ha[i+1].close < ha[i+1].open);
      if(green_i && red_ip1)
        {
         bars_since_change = i - j;
         break;
        }
     }
   bool color_ok = (bars_since_change <= m_ha_color_change_limit);
   
   return (fast > slow) && ha_green && imacd_ok && ema200_ok && ha_strength_ok && spread_ok && atr_ok && adx_ok && color_ok && session_ok;
  }

bool IsShortAligned(int j, const double &ema_fast[], const double &ema_slow[], const double &ema200[], const HeikinAshi &ha[], const double &atr[], const double &adx[], const MqlRates &rates[], double md)
  {
   double fast = ema_fast[j];
   double slow = ema_slow[j];
   double ema200_val = ema200[j];
   
   bool ha_red = (ha[j].close < ha[j].open);
   bool imacd_ok = !m_use_imacd || (md <= 0.0);
   bool ema200_ok = !m_use_ema200 || (rates[j].close < ema200_val);
   bool ha_strength_ok = !m_use_ha_strength || (ha[j].high == ha[j].open);
   
   double dist = MathAbs(fast - slow);
   bool spread_ok = !m_use_ema_spread || (dist >= (atr[j] * m_ema_spread_mult));
   
   bool atr_ok = !m_use_atr_min || (atr[j] >= m_atr_min_val);
   bool adx_ok = !m_use_adx || (adx[j] >= m_adx_min);
   
   // Session
   bool session_ok = true;
   if(m_use_session)
     {
      MqlDateTime dt;
      TimeToStruct(rates[j].time, dt);
      if(dt.hour < m_start_hour || dt.hour >= m_end_hour)
         session_ok = false;
     }
   
   // Límite de giro Heikin-Ashi: mirar hacia atrás desde la barra j
   int bars_since_change = 99;
   for(int i = j; i < j + 20; i++)
     {
      bool red_i = (ha[i].close < ha[i].open);
      bool green_ip1 = (ha[i+1].close > ha[i+1].open);
      if(red_i && green_ip1)
        {
         bars_since_change = i - j;
         break;
        }
     }
   bool color_ok = (bars_since_change <= m_ha_color_change_limit);
   
   return (fast < slow) && ha_red && imacd_ok && ema200_ok && ha_strength_ok && spread_ok && atr_ok && adx_ok && color_ok && session_ok;
  }

// ════════════════════════════════════════════════════════════════════
// CALCULAR IMPULSE MACD MANUAL CON SHIFT
// ════════════════════════════════════════════════════════════════════
double CalcularIMACD(int len, int shift)
  {
   MqlRates rates[];
   ArraySetAsSeries(rates, true);
   int copied = CopyRates(_Symbol, _Period, 1 + shift, len * 3, rates);
   if(copied < len * 3) return 0.0;
   
   double src[];
   ArrayResize(src, copied);
   for(int i = 0; i < copied; i++)
      src[i] = (rates[i].high + rates[i].low + rates[i].close) / 3.0;
      
   // Zero-Lag EMA
   int lag = (len - 1) / 2;
   double src_zlag[];
   ArrayResize(src_zlag, copied - lag);
   for(int i = 0; i < copied - lag; i++)
      src_zlag[i] = src[i] + (src[i] - src[i + lag]);
      
   // EMA de Zlag
   double alpha = 2.0 / (len + 1.0);
   double mi = src_zlag[ArraySize(src_zlag) - 1]; 
   for(int i = ArraySize(src_zlag) - 2; i >= 0; i--)
     {
      mi = src_zlag[i] * alpha + mi * (1.0 - alpha);
     }
     
   // RMA de High y Low
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
   
   lot = MathFloor(lot / lot_step) * lot_step;
   
   if(lot < min_lot) lot = min_lot;
   if(lot > max_lot) lot = max_lot;
   
   return lot;
  }
