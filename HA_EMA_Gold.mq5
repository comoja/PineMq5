//+------------------------------------------------------------------+
//|                                               HA_EMA_Gold.mq5   |
//|            Estrategia Heikin-Ashi + EMA para ORO (XAUUSD)       |
//|    EMAs 21/55, iMACD-50, ADX, Sesión UTC, Trail 1/2 del riesgo  |
//+------------------------------------------------------------------+
#property copyright "Antigravity AI – Gold Edition"
#property version   "1.00"
#property description "HA+EMA Gold: Factor 2.59 en XAUUSD 15m (Ene-Jun 2026)"

#include <Trade\Trade.mqh>
CTrade trade;

// ════════════════════════════════════════════════════════════════════
// INPUTS: GESTIÓN DE RIESGO
// ════════════════════════════════════════════════════════════════════
input group "--- GESTIÓN DE RIESGO ---"
input double RiskPerc   = 1.0;   // Riesgo por operación (% de la equidad)
input bool   UseTP      = true;  // Usar Take Profit Fijo
input double RRRatio    = 3.0;   // Relación Riesgo/Recompensa (R:R) — Gold hace movimientos amplios

// ════════════════════════════════════════════════════════════════════
// INPUTS: INDICADORES (calibrados XAUUSD 15m)
// ════════════════════════════════════════════════════════════════════
input group "--- INDICADORES (XAUUSD 15m) ---"
input int    EmaFastPeriod  = 21;   // EMA Rápida — reduce whipsaw vs 9 original
input int    EmaSlowPeriod  = 55;   // EMA Lenta — EMA semanal adaptada a 15m
input int    SwingPeriod    = 8;    // Velas Swing SL — 2h en 15m, capta swing real del Oro
input double SlBuffer       = 2.0;  // Buffer SL en ticks — spread del Oro es mayor

// ════════════════════════════════════════════════════════════════════
// INPUTS: FILTRO iMACD
// ════════════════════════════════════════════════════════════════════
input group "--- FILTRO IMPULSE MACD ---"
input bool   UseImacdFilter = true;  // Filtro iMACD — ACTIVADO: bloquea longs en caída
input int    ImacdPeriod    = 50;    // Período iMACD — 50 = señal suave para Oro 15m

// ════════════════════════════════════════════════════════════════════
// INPUTS: FILTROS DE OPTIMIZACIÓN
// ════════════════════════════════════════════════════════════════════
input group "--- FILTROS DE OPTIMIZACIÓN ---"
input bool   UseEma200Filter     = false; // Filtro EMA 200 — desact: puede contradecir EMA 21/55
input int    Ema200Period        = 200;   // Período EMA Macro
input bool   UseHaStrengthFilter = false; // Filtro Fuerza HA (sin mechas) — desact: pocas perfectas

// ════════════════════════════════════════════════════════════════════
// INPUTS: FILTROS ESPECÍFICOS GOLD
// ════════════════════════════════════════════════════════════════════
input group "--- FILTROS GOLD ---"
input bool   UseSession   = true;   // Sesión Londres+NY (UTC) — ACTIVADO
input int    SessionStart = 800;    // Inicio sesión UTC (HHMM)  — 08:00 UTC
input int    SessionEnd   = 1700;   // Fin sesión UTC (HHMM)    — 17:00 UTC
input bool   UseAtrMin    = false;  // Filtro ATR mínimo — desactivado por defecto
input int    AtrLen       = 14;     // Período ATR
input double AtrMinUsd    = 2.0;    // ATR Mínimo en USD (15m)
input bool   UseAdx       = true;   // Filtro ADX — ACTIVADO: factor 1.1→2.6
input int    AdxLen       = 14;     // Período ADX
input double AdxMin       = 18.0;   // ADX Mínimo — 18+ = tendencia naciente
input bool   UseRsi       = false;  // Filtro RSI extremos — desactivado por defecto
input int    RsiLen       = 14;     // Período RSI
input double RsiOb        = 70.0;   // RSI sobrecomprado (límite longs)
input double RsiOs        = 30.0;   // RSI sobrevendido (límite shorts)
input int    ConfirmBars  = 2;      // Velas HA consecutivas requeridas — 2 = seguro
input bool   UseHtf       = false;  // Filtro HTF H1 — desact: sin impacto en tests
input int    HtfEmaLen    = 50;     // EMA en H1 (si filtro activo)

// ════════════════════════════════════════════════════════════════════
// INPUTS: CONTROL GENERAL
// ════════════════════════════════════════════════════════════════════
input group "--- CONTROL GENERAL ---"
input double MaxSpread   = 100.0;    // Spread Máximo Permitido (puntos) — Gold spread amplio
input int    MagicNumber = 202406;   // Magic Number del EA
input bool   PanicClose  = false;    // Cerrar todo y detener trading

// ════════════════════════════════════════════════════════════════════
// HANDLES DE INDICADORES
// ════════════════════════════════════════════════════════════════════
int handle_ema_fast;
int handle_ema_slow;
int handle_ema_200;
int handle_adx;
int handle_atr;
int handle_rsi;
int handle_htf_ema;

// ════════════════════════════════════════════════════════════════════
// ESTADO GLOBAL
// ════════════════════════════════════════════════════════════════════
double global_md_val     = 0.0;
double global_adx_val    = 0.0;
double profit_inicio_dia = 0.0;
datetime ultimo_dia      = 0;
int    trades_count      = 0;

// Contadores de velas consecutivas alineadas (equivalente al long_count/short_count de Pine)
int    long_count  = 0;
int    short_count = 0;

// Estructura Heikin-Ashi
struct HeikinAshiBar {
   double open;
   double high;
   double low;
   double close;
};

//+------------------------------------------------------------------+
//| OnInit                                                           |
//+------------------------------------------------------------------+
int OnInit() {
   if(EmaFastPeriod >= EmaSlowPeriod) {
      Alert("EMA rápida debe ser menor que la lenta.");
      return(INIT_FAILED);
   }

   handle_ema_fast = iMA(_Symbol, _Period, EmaFastPeriod, 0, MODE_EMA, PRICE_CLOSE);
   handle_ema_slow = iMA(_Symbol, _Period, EmaSlowPeriod, 0, MODE_EMA, PRICE_CLOSE);
   handle_ema_200  = iMA(_Symbol, _Period, Ema200Period,  0, MODE_EMA, PRICE_CLOSE);
   handle_adx      = iADX(_Symbol, _Period, AdxLen);
   handle_atr      = iATR(_Symbol, _Period, AtrLen);
   handle_rsi      = iRSI(_Symbol, _Period, RsiLen, PRICE_CLOSE);
   handle_htf_ema  = iMA(_Symbol, PERIOD_H1, HtfEmaLen, 0, MODE_EMA, PRICE_CLOSE);

   if(handle_ema_fast == INVALID_HANDLE || handle_ema_slow == INVALID_HANDLE ||
      handle_ema_200  == INVALID_HANDLE || handle_adx == INVALID_HANDLE      ||
      handle_atr      == INVALID_HANDLE || handle_rsi == INVALID_HANDLE      ||
      handle_htf_ema  == INVALID_HANDLE) {
      Print("Error inicializando handles de indicadores.");
      return(INIT_FAILED);
   }

   trade.SetExpertMagicNumber(MagicNumber);
   ultimo_dia  = 0;
   long_count  = 0;
   short_count = 0;
   LimpiarVariablesGlobales();

   Print("HA_EMA_Gold EA iniciado. Magic:", MagicNumber, " Símbolo:", _Symbol, " TF:", EnumToString(_Period));
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| OnDeinit                                                         |
//+------------------------------------------------------------------+
void OnDeinit(const int reason) {
   IndicatorRelease(handle_ema_fast);
   IndicatorRelease(handle_ema_slow);
   IndicatorRelease(handle_ema_200);
   IndicatorRelease(handle_adx);
   IndicatorRelease(handle_atr);
   IndicatorRelease(handle_rsi);
   IndicatorRelease(handle_htf_ema);
   Comment("");
   Print("HA_EMA_Gold EA retirado.");
}

//+------------------------------------------------------------------+
//| OnTick                                                           |
//+------------------------------------------------------------------+
void OnTick() {
   // --- BOTÓN DE PÁNICO ---
   if(PanicClose) {
      CerrarTodo();
      DibujarPanel(0.0);
      return;
   }

   // --- RESETEO DIARIO ---
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   datetime dia_actual = StringToTime(
      IntegerToString(dt.year) + "." +
      IntegerToString(dt.mon)  + "." +
      IntegerToString(dt.day));
   if(dia_actual != ultimo_dia) {
      profit_inicio_dia = AccountInfoDouble(ACCOUNT_PROFIT);
      trades_count = 0;
      ultimo_dia   = dia_actual;
   }
   double daily_profit = AccountInfoDouble(ACCOUNT_PROFIT) - profit_inicio_dia;

   // --- TRAILING STOP (cada tick) ---
   GestionarTrailingStop();

   // --- SÓLO EN VELA NUEVA para entradas ---
   if(!IsNewBar()) {
      DibujarPanel(daily_profit);
      return;
   }

   // Limpiar variables globales huérfanas
   LimpiarVariablesGlobales();

   // Si ya hay posición, no buscar entrada
   if(PositionSelect(_Symbol)) {
      DibujarPanel(daily_profit);
      return;
   }

   // --- VALIDAR SPREAD ---
   double spread = (double)SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);
   if(spread > MaxSpread) {
      DibujarPanel(daily_profit);
      return;
   }

   // --- HANDLES VÁLIDOS ---
   if(handle_ema_fast == INVALID_HANDLE || handle_ema_slow == INVALID_HANDLE) return;

   // --- FILTRO DE SESIÓN (UTC) ---
   bool in_session = InSession();
   if(!in_session) {
      // Sesión cerrada: resetear contadores
      long_count  = 0;
      short_count = 0;
      DibujarPanel(daily_profit);
      return;
   }

   // --- LEER EMAs (barra 1 = última cerrada, barra 2 = anterior) ---
   double ema_fast_arr[], ema_slow_arr[], ema_200_arr[];
   ArraySetAsSeries(ema_fast_arr, true);
   ArraySetAsSeries(ema_slow_arr, true);
   ArraySetAsSeries(ema_200_arr,  true);

   if(CopyBuffer(handle_ema_fast, 0, 1, 3, ema_fast_arr) < 3 ||
      CopyBuffer(handle_ema_slow, 0, 1, 3, ema_slow_arr) < 3 ||
      CopyBuffer(handle_ema_200,  0, 1, 3, ema_200_arr)  < 3) return;

   // --- VELAS HEIKIN-ASHI (3 velas: [0]=actual, [1]=cerrada, [2]=anterior) ---
   HeikinAshiBar ha_bars[];
   if(!GetHeikinAshi(3, ha_bars)) return;

   // --- VELAS RAW para Swing SL ---
   MqlRates rates[];
   ArraySetAsSeries(rates, true);
   if(CopyRates(_Symbol, _Period, 1, SwingPeriod + 2, rates) < SwingPeriod + 2) return;

   // --- FILTRO ADX ---
   bool adx_ok = true;
   if(UseAdx) {
      double adx_arr[];
      ArraySetAsSeries(adx_arr, true);
      if(CopyBuffer(handle_adx, 0, 1, 1, adx_arr) >= 1) {
         global_adx_val = adx_arr[0];
         adx_ok = (adx_arr[0] >= AdxMin);
      }
   }

   // --- FILTRO ATR ---
   bool atr_ok = true;
   if(UseAtrMin) {
      double atr_arr[];
      ArraySetAsSeries(atr_arr, true);
      if(CopyBuffer(handle_atr, 0, 1, 1, atr_arr) >= 1)
         atr_ok = (atr_arr[0] >= AtrMinUsd);
   }

   // --- FILTRO RSI ---
   bool rsi_long_ok  = true;
   bool rsi_short_ok = true;
   if(UseRsi) {
      double rsi_arr[];
      ArraySetAsSeries(rsi_arr, true);
      if(CopyBuffer(handle_rsi, 0, 1, 1, rsi_arr) >= 1) {
         rsi_long_ok  = (rsi_arr[0] < RsiOb);
         rsi_short_ok = (rsi_arr[0] > RsiOs);
      }
   }

   // --- FILTRO HTF H1 ---
   bool htf_long_ok  = true;
   bool htf_short_ok = true;
   if(UseHtf) {
      double htf_arr[];
      ArraySetAsSeries(htf_arr, true);
      if(CopyBuffer(handle_htf_ema, 0, 0, 1, htf_arr) >= 1) {
         double current_price = SymbolInfoDouble(_Symbol, SYMBOL_BID);
         htf_long_ok  = (current_price > htf_arr[0]);
         htf_short_ok = (current_price < htf_arr[0]);
      }
   }

   // --- FILTRO iMACD ---
   double md_val = 0.0;
   if(UseImacdFilter) {
      int bars_needed = ImacdPeriod * 3;
      if(bars_needed < 150) bars_needed = 150;

      MqlRates imacd_rates[];
      int copied = CopyRates(_Symbol, _Period, 1, bars_needed, imacd_rates);
      if(copied >= bars_needed) {
         double high_arr[], low_arr[], hlc3_arr[];
         ArrayResize(high_arr,  bars_needed);
         ArrayResize(low_arr,   bars_needed);
         ArrayResize(hlc3_arr,  bars_needed);

         for(int i = 0; i < bars_needed; i++) {
            high_arr[i]  = imacd_rates[i].high;
            low_arr[i]   = imacd_rates[i].low;
            hlc3_arr[i]  = (imacd_rates[i].high + imacd_rates[i].low + imacd_rates[i].close) / 3.0;
         }

         double hi_val = CalculateSMMA(high_arr,  ImacdPeriod, bars_needed);
         double lo_val = CalculateSMMA(low_arr,   ImacdPeriod, bars_needed);
         double mi_val = CalculateZLEMA(hlc3_arr, ImacdPeriod, bars_needed);

         md_val = mi_val > hi_val ? mi_val - hi_val :
                  mi_val < lo_val ? mi_val - lo_val : 0.0;
      }
   }
   global_md_val = md_val;

   // --- CONDICIONES DE ALINEACIÓN (barra 1 = última cerrada) ---
   bool imacd_long_ok  = !UseImacdFilter || (md_val > 0.0);
   bool imacd_short_ok = !UseImacdFilter || (md_val < 0.0);

   bool ema200_long_ok  = !UseEma200Filter || (rates[0].close > ema_200_arr[0]);
   bool ema200_short_ok = !UseEma200Filter || (rates[0].close < ema_200_arr[0]);

   bool ha_strength_long  = !UseHaStrengthFilter ||
      (NormalizeDouble(ha_bars[1].low,  _Digits) == NormalizeDouble(ha_bars[1].open, _Digits));
   bool ha_strength_short = !UseHaStrengthFilter ||
      (NormalizeDouble(ha_bars[1].high, _Digits) == NormalizeDouble(ha_bars[1].open, _Digits));

   bool ha_green_1 = ha_bars[1].close > ha_bars[1].open;
   bool ha_red_1   = ha_bars[1].close < ha_bars[1].open;

   bool is_long_aligned  = (ema_fast_arr[0] > ema_slow_arr[0]) && ha_green_1 &&
                            imacd_long_ok && ema200_long_ok && ha_strength_long &&
                            htf_long_ok   && atr_ok         && adx_ok && rsi_long_ok;

   bool is_short_aligned = (ema_fast_arr[0] < ema_slow_arr[0]) && ha_red_1 &&
                            imacd_short_ok && ema200_short_ok && ha_strength_short &&
                            htf_short_ok   && atr_ok          && adx_ok && rsi_short_ok;

   // --- CONTADORES DE CONFIRMACIÓN (equivalente Pine: long_count/short_count) ---
   if(is_long_aligned) {
      long_count++;
      short_count = 0;
   } else if(is_short_aligned) {
      short_count++;
      long_count = 0;
   } else {
      long_count  = 0;
      short_count = 0;
   }

   // Gatillo: dispara exactamente cuando el contador alcanza ConfirmBars
   bool trigger_long  = (long_count  == ConfirmBars);
   bool trigger_short = (short_count == ConfirmBars);

   if(!trigger_long && !trigger_short) {
      DibujarPanel(daily_profit);
      return;
   }

   // --- STOP LOSS DINÁMICO POR SWINGS ---
   if(trigger_long) {
      double entry_price = SymbolInfoDouble(_Symbol, SYMBOL_ASK);

      double lowest_low = rates[0].low;
      for(int i = 1; i < SwingPeriod; i++)
         if(rates[i].low < lowest_low) lowest_low = rates[i].low;

      double sl_price = NormalizeDouble(lowest_low - SlBuffer * _Point, _Digits);
      if(entry_price - sl_price <= 0)
         sl_price = NormalizeDouble(entry_price - _Point, _Digits);

      double sl_dist_price  = entry_price - sl_price;
      double sl_dist_points = sl_dist_price / _Point;

      if(sl_dist_points > 0) {
         double lot      = CalcularLote(sl_dist_points);
         double tp_price = UseTP ? NormalizeDouble(entry_price + sl_dist_price * RRRatio, _Digits) : 0.0;

         if(trade.Buy(lot, _Symbol, 0, sl_price, tp_price, "HA_Gold Largo")) {
            trades_count++;
            Sleep(150);
            if(PositionSelect(_Symbol)) {
               ulong  ticket     = PositionGetInteger(POSITION_TICKET);
               double real_entry = PositionGetDouble(POSITION_PRICE_OPEN);
               double trail_step = MathAbs(real_entry - sl_price) / 2.0;
               GlobalVariableSet("HA_Gold_step_" + IntegerToString(ticket), trail_step);
            }
         }
      }
   }
   else if(trigger_short) {
      double entry_price = SymbolInfoDouble(_Symbol, SYMBOL_BID);

      double highest_high = rates[0].high;
      for(int i = 1; i < SwingPeriod; i++)
         if(rates[i].high > highest_high) highest_high = rates[i].high;

      double sl_price = NormalizeDouble(highest_high + SlBuffer * _Point, _Digits);
      if(sl_price - entry_price <= 0)
         sl_price = NormalizeDouble(entry_price + _Point, _Digits);

      double sl_dist_price  = sl_price - entry_price;
      double sl_dist_points = sl_dist_price / _Point;

      if(sl_dist_points > 0) {
         double lot      = CalcularLote(sl_dist_points);
         double tp_price = UseTP ? NormalizeDouble(entry_price - sl_dist_price * RRRatio, _Digits) : 0.0;

         if(trade.Sell(lot, _Symbol, 0, sl_price, tp_price, "HA_Gold Corto")) {
            trades_count++;
            Sleep(150);
            if(PositionSelect(_Symbol)) {
               ulong  ticket     = PositionGetInteger(POSITION_TICKET);
               double real_entry = PositionGetDouble(POSITION_PRICE_OPEN);
               double trail_step = MathAbs(sl_price - real_entry) / 2.0;
               GlobalVariableSet("HA_Gold_step_" + IntegerToString(ticket), trail_step);
            }
         }
      }
   }

   DibujarPanel(daily_profit);
}

//+------------------------------------------------------------------+
//| Verifica si la hora actual está dentro de la sesión UTC          |
//+------------------------------------------------------------------+
bool InSession() {
   if(!UseSession) return true;
   datetime gmt = TimeGMT();
   MqlDateTime dt;
   TimeToStruct(gmt, dt);
   int now_hhmm = dt.hour * 100 + dt.min;
   return (now_hhmm >= SessionStart && now_hhmm < SessionEnd);
}

//+------------------------------------------------------------------+
//| Trailing Stop por Medios (1/2 del riesgo inicial)                |
//+------------------------------------------------------------------+
void GestionarTrailingStop() {
   if(!PositionSelect(_Symbol)) return;

   ulong  ticket      = PositionGetInteger(POSITION_TICKET);
   long   pos_type    = PositionGetInteger(POSITION_TYPE);
   double entry_price = PositionGetDouble(POSITION_PRICE_OPEN);
   double current_sl  = PositionGetDouble(POSITION_SL);
   double current_tp  = PositionGetDouble(POSITION_TP);

   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);

   string gv_name    = "HA_Gold_step_" + IntegerToString(ticket);
   double trail_step = 0.0;

   if(GlobalVariableCheck(gv_name)) {
      trail_step = GlobalVariableGet(gv_name);
   } else {
      if(current_sl > 0) {
         trail_step = MathAbs(entry_price - current_sl) / 2.0;
         GlobalVariableSet(gv_name, trail_step);
      }
   }

   if(trail_step <= 0) return;

   if(pos_type == POSITION_TYPE_BUY) {
      double recorrido = bid - entry_price;
      int    niveles   = (int)MathFloor(recorrido / trail_step);
      if(niveles > 0) {
         double initial_sl = entry_price - (trail_step * 2.0);
         double nuevo_sl   = NormalizeDouble(initial_sl + trail_step * niveles, _Digits);
         if(nuevo_sl > current_sl)
            trade.PositionModify(ticket, nuevo_sl, current_tp);
      }
   }
   else if(pos_type == POSITION_TYPE_SELL) {
      double recorrido = entry_price - ask;
      int    niveles   = (int)MathFloor(recorrido / trail_step);
      if(niveles > 0) {
         double initial_sl = entry_price + (trail_step * 2.0);
         double nuevo_sl   = NormalizeDouble(initial_sl - trail_step * niveles, _Digits);
         if(nuevo_sl < current_sl || current_sl == 0)
            trade.PositionModify(ticket, nuevo_sl, current_tp);
      }
   }
}

//+------------------------------------------------------------------+
//| Lotaje basado en % de equidad y distancia al SL                  |
//+------------------------------------------------------------------+
double CalcularLote(double sl_dist_points) {
   if(sl_dist_points <= 0) return 0.0;

   double equity     = AccountInfoDouble(ACCOUNT_EQUITY);
   double risk_amt   = equity * (RiskPerc / 100.0);
   double tick_size  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   double tick_value = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);

   double sl_dist_price  = sl_dist_points * _Point;
   double risk_per_lot   = (sl_dist_price / tick_size) * tick_value;
   if(risk_per_lot <= 0) return 0.0;

   double lot      = risk_amt / risk_per_lot;
   double min_lot  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double max_lot  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double step_lot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);

   lot = MathFloor(lot / step_lot) * step_lot;
   if(lot < min_lot) lot = min_lot;
   if(lot > max_lot) lot = max_lot;
   return lot;
}

//+------------------------------------------------------------------+
//| SMMA — equivalente a ta.rma() de Pine Script                     |
//+------------------------------------------------------------------+
double CalculateSMMA(const double &price[], int len, int N) {
   double smma = 0;
   for(int i = 0; i < len; i++) smma += price[i];
   smma /= len;
   for(int i = len; i < N; i++)
      smma = (smma * (len - 1) + price[i]) / len;
   return smma;
}

//+------------------------------------------------------------------+
//| EMA auxiliar sobre array completo                                |
//+------------------------------------------------------------------+
void CalculateEMA(const double &src[], double &dest[], int len, int N) {
   ArrayResize(dest, N);
   double k   = 2.0 / (len + 1.0);
   double sum = 0;
   for(int i = 0; i < len; i++) sum += src[i];
   dest[len - 1] = sum / len;
   for(int i = len; i < N; i++)
      dest[i] = (src[i] - dest[i - 1]) * k + dest[i - 1];
}

//+------------------------------------------------------------------+
//| ZLEMA — equivalente Pine: ema1 + (ema1 - ema2)                  |
//+------------------------------------------------------------------+
double CalculateZLEMA(const double &src[], int len, int N) {
   double ema1[];
   CalculateEMA(src, ema1, len, N);

   double ema2[];
   ArrayResize(ema2, N);
   int    s2  = len - 1;
   double sum = 0;
   for(int i = 0; i < len; i++) sum += ema1[s2 + i];
   ema2[s2 + len - 1] = sum / len;
   double k = 2.0 / (len + 1.0);
   for(int i = s2 + len; i < N; i++)
      ema2[i] = (ema1[i] - ema2[i - 1]) * k + ema2[i - 1];

   double v1 = ema1[N - 1];
   double v2 = ema2[N - 1];
   return v1 + (v1 - v2);
}

//+------------------------------------------------------------------+
//| Construye velas Heikin-Ashi recursivamente                       |
//+------------------------------------------------------------------+
bool GetHeikinAshi(int count, HeikinAshiBar &ha_bars[]) {
   MqlRates rates[];
   ArraySetAsSeries(rates, true);
   int margin = count + 30;
   if(CopyRates(_Symbol, _Period, 0, margin, rates) < margin) return false;

   double ha_open[], ha_close[], ha_high[], ha_low[];
   ArrayResize(ha_open,  margin);
   ArrayResize(ha_close, margin);
   ArrayResize(ha_high,  margin);
   ArrayResize(ha_low,   margin);

   int oldest = margin - 1;
   ha_open[oldest]  = (rates[oldest].open + rates[oldest].close) / 2.0;
   ha_close[oldest] = (rates[oldest].open + rates[oldest].high +
                       rates[oldest].low  + rates[oldest].close) / 4.0;
   ha_high[oldest]  = rates[oldest].high;
   ha_low[oldest]   = rates[oldest].low;

   for(int i = oldest - 1; i >= 0; i--) {
      ha_close[i] = (rates[i].open + rates[i].high + rates[i].low + rates[i].close) / 4.0;
      ha_open[i]  = (ha_open[i + 1] + ha_close[i + 1]) / 2.0;
      ha_high[i]  = MathMax(rates[i].high, MathMax(ha_open[i], ha_close[i]));
      ha_low[i]   = MathMin(rates[i].low,  MathMin(ha_open[i], ha_close[i]));
   }

   ArrayResize(ha_bars, count);
   for(int i = 0; i < count; i++) {
      ha_bars[i].open  = ha_open[i];
      ha_bars[i].high  = ha_high[i];
      ha_bars[i].low   = ha_low[i];
      ha_bars[i].close = ha_close[i];
   }
   return true;
}

//+------------------------------------------------------------------+
//| Detecta vela nueva                                               |
//+------------------------------------------------------------------+
bool IsNewBar() {
   static datetime last_bar = 0;
   datetime current_bar = iTime(_Symbol, _Period, 0);
   if(current_bar == 0) return false;
   if(current_bar != last_bar) { last_bar = current_bar; return true; }
   return false;
}

//+------------------------------------------------------------------+
//| Cierra todas las posiciones del símbolo                          |
//+------------------------------------------------------------------+
void CerrarTodo() {
   for(int i = PositionsTotal() - 1; i >= 0; i--) {
      string sym = PositionGetSymbol(i);
      if(sym == _Symbol) {
         ulong ticket = PositionGetTicket(i);
         trade.PositionClose(ticket);
         GlobalVariableDel("HA_Gold_step_" + IntegerToString(ticket));
      }
   }
}

//+------------------------------------------------------------------+
//| Limpia variables globales huérfanas                              |
//+------------------------------------------------------------------+
void LimpiarVariablesGlobales() {
   for(int i = GlobalVariablesTotal() - 1; i >= 0; i--) {
      string name = GlobalVariableName(i);
      if(StringFind(name, "HA_Gold_step_") == 0) {
         ulong ticket = (ulong)StringToInteger(StringSubstr(name, 13));
         if(!PositionSelectByTicket(ticket))
            GlobalVariableDel(name);
      }
   }
}

//+------------------------------------------------------------------+
//| Panel de control en pantalla                                     |
//+------------------------------------------------------------------+
void DibujarPanel(double daily_profit) {
   bool   in_trade    = PositionSelect(_Symbol);
   double spread      = (double)SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);

   string imacd_str = !UseImacdFilter ? "DESACTIVADO" :
                      global_md_val == 0.0 ? "RANGO" :
                      global_md_val >  0.0 ? "ALCISTA" : "BAJISTA";

   string adx_str   = !UseAdx ? "DESACT" :
                      StringFormat("%.1f (%s)", global_adx_val,
                      global_adx_val >= AdxMin ? "OK" : "BAJO");

   string session_str = InSession() ? "ACTIVA" : "CERRADA";
   string status_str  = PanicClose ? "PANICO" : (in_trade ? "EN TRADE" : "BUSCANDO");

   double trail_step = 0.0;
   if(in_trade) {
      ulong  ticket = PositionGetInteger(POSITION_TICKET);
      string gv     = "HA_Gold_step_" + IntegerToString(ticket);
      if(GlobalVariableCheck(gv)) trail_step = GlobalVariableGet(gv);
   }

   string txt = "";
   txt += "===== HA_EMA GOLD (XAUUSD) =====\n";
   txt += "Estado:       " + status_str + "\n";
   txt += "Sesión UTC:   " + session_str + " [" +
          IntegerToString(SessionStart) + "-" + IntegerToString(SessionEnd) + "]\n";
   txt += "Filtro iMACD: " + imacd_str + "\n";
   txt += "ADX:          " + adx_str + "\n";
   txt += "Long Count:   " + IntegerToString(long_count)  + " / " + IntegerToString(ConfirmBars) + "\n";
   txt += "Short Count:  " + IntegerToString(short_count) + " / " + IntegerToString(ConfirmBars) + "\n";
   txt += "Riesgo/Trade: " + DoubleToString(RiskPerc, 1) + "% equidad\n";
   txt += "R:R:          1:" + DoubleToString(RRRatio, 1) + "\n";
   txt += "Trail Step:   " + (trail_step > 0 ? DoubleToString(trail_step / _Point, 1) + " pts" : "-") + "\n";
   txt += "Profit hoy:   " + DoubleToString(daily_profit, 2) + " USD\n";
   txt += "Trades hoy:   " + IntegerToString(trades_count) + "\n";
   txt += "Spread:       " + DoubleToString(spread, 0) + " pts\n";
   txt += "Magic:        " + IntegerToString(MagicNumber) + "\n";
   txt += "================================";

   Comment(txt);
}
