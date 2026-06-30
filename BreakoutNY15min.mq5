//+------------------------------------------------------------------+
//|                                           BreakoutNY.mq5         |
//|         Derivado del MASTER: BreakoutNY15min.pine                |
//+------------------------------------------------------------------+
// ╔══════════════════════════════════════════════════════════════════╗
// ║  FUNCIONES CRÍTICAS — deben mantenerse sincronizadas con .pine  ║
// ╠══════════════════════════════════════════════════════════════════╣
// ║  [MQ5-CRITICAL #1]  GetOwnPositionType() → -1 / BUY / SELL     ║
// ║  [MQ5-CRITICAL #2]  try_long bloquea si pos_type==SELL          ║
// ║                     try_short bloquea si pos_type==BUY          ║
// ║  [MQ5-CRITICAL #3]  Trailing por tercios: trail_step=dist/3     ║
// ║  [MQ5-CRITICAL #4]  Filtro magic_number en GetOwnPositionType() ║
// ╚══════════════════════════════════════════════════════════════════╝
#property copyright "AI Translator"
#property version   "6.70"

#include <Trade\Trade.mqh>
CTrade trade;

// --- INPUTS ---
input group "--- CONFIGURACIÓN GENERAL ---"
input bool   panic_close   = false;       // 🚨 BOTÓN DE PÁNICO
input double risk_usd      = 5.0;         // Dólares a arriesgar por trade
input double rr            = 0.90;        // Relación RR para el BE / Target inicial
input int    magic_number  = 83095;       // Magic number único de esta estrategia

input group "--- NOTIFICACIONES DE TELEGRAM ---"
input bool   InpUseTelegram = false;       // Enviar alertas a Telegram
input string InpBotToken    = "";          // Token del Bot de Telegram
input string InpChatID      = "";          // Chat ID del Usuario/Canal

input group "--- HORARIO DE RANGO (HORA DEL BROKER) ---"
input int    start_hour    = 16;          // Hora de inicio del rango (Broker)
input int    start_minute  = 30;          // Minuto de inicio del rango (Broker)
input int    end_hour      = 16;          // Hora de fin del rango (Broker)
input int    end_minute    = 45;          // Minuto de fin del rango (Broker)

// --- VARIABLES GLOBALES E INDICADORES ---
int    handle_ema;
double r_high = 0.0;
double r_low  = 0.0;
int    trades_count = 0;
double current_sl = 0.0;
double profit_inicio_dia = 0.0;
datetime ultimo_dia = 0;

// VARIABLES PARA EL TRAIL DINÁMICO POR TERCIOS
double t_ent = 0.0;       // Precio de entrada real
double trail_step = 0.0;  // 1/3 de la distancia Entrada-SL en puntos

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
  {
   handle_ema = iMA(_Symbol, _Period, 200, 0, MODE_EMA, PRICE_CLOSE);
   if(handle_ema == INVALID_HANDLE)
     {
      Print("Error al crear el handle de la EMA 200.");
      return(INIT_FAILED);
     }
     
   trade.SetExpertMagicNumber(magic_number);
   ultimo_dia = 0;
   return(INIT_SUCCEEDED);
  }

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   IndicatorRelease(handle_ema);
   Comment("");
  }

//+------------------------------------------------------------------+
//| Retorna el tipo de posición propia:                              |
//|   POSITION_TYPE_BUY  (0) = hay un LONG abierto                  |
//|   POSITION_TYPE_SELL (1) = hay un SHORT abierto                 |
//|   -1                     = sin posición                         |
//+------------------------------------------------------------------+
int GetOwnPositionType()
  {
   for(int i = 0; i < PositionsTotal(); i++)
     {
      if(PositionGetSymbol(i) == _Symbol &&
         PositionGetInteger(POSITION_MAGIC) == magic_number)
         return (int)PositionGetInteger(POSITION_TYPE);
     }
   return -1;  // sin posición
  }

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
  {
   if(panic_close)
     {
      CerrarTodo();
      DibujarTabla(0.0);
      return;
     }

   // --- RESETEO DIARIO ---
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   datetime dia_actual = StringToTime(IntegerToString(dt.year)+"."+IntegerToString(dt.mon)+"."+IntegerToString(dt.day));
   
   if(dia_actual != ultimo_dia)
     {
      profit_inicio_dia = AccountInfoDouble(ACCOUNT_PROFIT);
      r_high = 0.0;
      r_low = 0.0;
      trades_count = 0;
      ultimo_dia = dia_actual;
     }

   double daily_profit = AccountInfoDouble(ACCOUNT_PROFIT) - profit_inicio_dia;

   // --- ESCANEO HISTÓRICO DE VELAS PARA ASIGNAR EL RANGO ---
   if(r_high == 0.0)
     {
      MqlRates rates[];
      ArraySetAsSeries(rates, true);
      int copiados = CopyRates(_Symbol, _Period, 0, 100, rates);
      
      double temp_high = 0.0;
      double temp_low = 999999.0;
      bool rango_encontrado = false;
      
      for(int i = 0; i < copiados; i++)
        {
         MqlDateTime bar_dt;
         TimeToStruct(rates[i].time, bar_dt);
         
         if(bar_dt.day == dt.day && bar_dt.mon == dt.mon && bar_dt.year == dt.year)
           {
            int m_actual = bar_dt.hour * 60 + bar_dt.min;
            int m_inicio = start_hour * 60 + start_minute;
            int m_fin    = end_hour * 60 + end_minute;
            
            if(m_actual >= m_inicio && m_actual < m_fin)
              {
               if(rates[i].high > temp_high) temp_high = rates[i].high;
               if(rates[i].low < temp_low)   temp_low  = rates[i].low;
               rango_encontrado = true;
              }
           }
        }
        
      if(rango_encontrado)
        {
         r_high = temp_high;
         r_low  = temp_low;
        }
     }

   // --- EVALUACIÓN DE SESIÓN ACTUAL VIVA ---
   int minutos_actuales = dt.hour * 60 + dt.min;
   int minutos_inicio   = start_hour * 60 + start_minute;
   int minutos_fin      = end_hour * 60 + end_minute;
   bool in_sess = (minutos_actuales >= minutos_inicio && minutos_actuales < minutos_fin);

   if(in_sess)
     {
      double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      if(r_high == 0.0 || ask > r_high) r_high = ask;
      if(r_low == 0.0 || bid < r_low)   r_low  = bid;
     }

   // --- CONDICIONES DE ENTRADA ---
   double close_curr = SymbolInfoDouble(_Symbol, SYMBOL_LAST);
   if(close_curr == 0) close_curr = SymbolInfoDouble(_Symbol, SYMBOL_BID);

   double ema_vals[];
   ArraySetAsSeries(ema_vals, true);
   if(CopyBuffer(handle_ema, 0, 0, 1, ema_vals) < 1) return;
   double ema_trend = ema_vals[0];

   int  pos_type     = GetOwnPositionType(); // -1=ninguna, 0=BUY, 1=SELL
   bool has_position = (pos_type != -1);

   if(!in_sess && r_high > 0.0 && !has_position && trades_count < 3)
     {
      bool body_up = (close_curr > r_high);
      bool body_dn = (close_curr < r_low);
      
      // body_up: solo abre LONG si NO hay ya un SHORT contrario
      // body_dn: solo abre SHORT si NO hay ya un LONG contrario
      bool try_long  = body_up && close_curr > ema_trend && pos_type != POSITION_TYPE_SELL;
      bool try_short = body_dn && close_curr < ema_trend && pos_type != POSITION_TYPE_BUY;

      if(try_long || try_short)
        {
         current_sl = try_long ? r_low : r_high;
         double dist_puntos = MathAbs(close_curr - current_sl);
         
         if(dist_puntos > 0)
           {
            double tick_size  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
            double tick_value = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
            double pos_size   = risk_usd / ((dist_puntos / tick_size) * tick_value);
            
            double min_lot  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
            double max_lot  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
            double step_lot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
            pos_size = MathFloor(pos_size / step_lot) * step_lot;
            if(pos_size < min_lot) pos_size = min_lot;
            if(pos_size > max_lot) pos_size = max_lot;

            double target_p = try_long ? (close_curr + dist_puntos * rr)
                                       : (close_curr - dist_puntos * rr);

            if(try_long)
              {
               if(trade.Buy(pos_size, _Symbol, 0, current_sl, target_p, "8:30 NY Largo"))
                 {
                  trades_count++;
                  t_ent = close_curr;
                  trail_step = dist_puntos / 3.0;
                  string msg = StringFormat("🔔 BreakoutNY - Nueva Compra (BUY) en %s\nPrecio: %s\nStop Loss: %s\nTake Profit: %s\nLote: %s", 
                                            _Symbol, DoubleToString(close_curr, _Digits), DoubleToString(current_sl, _Digits), DoubleToString(target_p, _Digits), DoubleToString(pos_size, 2));
                  EnviarMensajeTelegram(msg);
                 }
              }
            else
              {
               if(trade.Sell(pos_size, _Symbol, 0, current_sl, target_p, "8:30 NY Corto"))
                 {
                  trades_count++;
                  t_ent = close_curr;
                  trail_step = dist_puntos / 3.0;
                  string msg = StringFormat("🔔 BreakoutNY - Nueva Venta (SELL) en %s\nPrecio: %s\nStop Loss: %s\nTake Profit: %s\nLote: %s", 
                                            _Symbol, DoubleToString(close_curr, _Digits), DoubleToString(current_sl, _Digits), DoubleToString(target_p, _Digits), DoubleToString(pos_size, 2));
                  EnviarMensajeTelegram(msg);
                 }
              }
           }
        }
     }

   // --- GESTIÓN DE TRAILING STOP POR TERCIOS COMPLETOS ---
   if(has_position)
     {
      if(t_ent == 0.0 || trail_step == 0.0)
        {
         t_ent = PositionGetDouble(POSITION_PRICE_OPEN);
         double sl_inicial = PositionGetDouble(POSITION_SL);
         if(sl_inicial > 0) trail_step = MathAbs(t_ent - sl_inicial) / 3.0;
        }

      long   type               = PositionGetInteger(POSITION_TYPE);
      long   ticket             = PositionGetInteger(POSITION_TICKET);   // ticket para modify seguro
      double current_position_sl = PositionGetDouble(POSITION_SL);

      if(trail_step > 0)
        {
         if(type == POSITION_TYPE_BUY)
           {
            double recorrido = close_curr - t_ent;
            int niveles_superados = (int)MathFloor(recorrido / trail_step);
            
            if(niveles_superados > 0)
              {
               double nuevo_sl = (t_ent - (trail_step * 3.0)) + (trail_step * niveles_superados);
               nuevo_sl = NormalizeDouble(nuevo_sl, _Digits);
               
               double current_tp = PositionGetDouble(POSITION_TP);
               if(nuevo_sl > current_position_sl)
                 {
                  trade.PositionModify(ticket, nuevo_sl, current_tp);  // usa ticket, no símbolo
                 }
              }
           }
         else if(type == POSITION_TYPE_SELL)
           {
            double recorrido = t_ent - close_curr;
            int niveles_superados = (int)MathFloor(recorrido / trail_step);
            
            if(niveles_superados > 0)
              {
               double nuevo_sl = (t_ent + (trail_step * 3.0)) - (trail_step * niveles_superados);
               nuevo_sl = NormalizeDouble(nuevo_sl, _Digits);
               
               double current_tp = PositionGetDouble(POSITION_TP);
               if(nuevo_sl < current_position_sl || current_position_sl == 0)
                 {
                  trade.PositionModify(ticket, nuevo_sl, current_tp);  // usa ticket, no símbolo
                 }
              }
           }
        }
     }
   else
     {
      t_ent = 0.0;
      trail_step = 0.0;
     }

   DibujarTabla(daily_profit);
  }

void CerrarTodo()
  {
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      if(PositionGetSymbol(i) == _Symbol &&
         PositionGetInteger(POSITION_MAGIC) == magic_number)  // solo posiciones de este EA
         trade.PositionClose(PositionGetTicket(i));
     }
  }

void DibujarTabla(double daily_profit)
  {
   string texto = "=== PANEL DE CONTROL NY ===\n";
   texto += "Profit Hoy: " + DoubleToString(daily_profit, 2) + " USD\n";
   texto += "Trades Realizados: " + IntegerToString(trades_count) + " / 3\n";
   texto += "Rango Alto: " + DoubleToString(r_high, _Digits) + "\n";
   texto += "Rango Bajo: " + DoubleToString(r_low, _Digits) + "\n";
   texto += "Trail Step (Puntos): " + DoubleToString(trail_step, _Digits) + "\n"; 
   texto += "Estado: " + (panic_close ? "🚨 PÁNICO ACTIVADO" : "🟢 OPERANDO AUTO");
   
   Comment(texto);
  }

//+------------------------------------------------------------------+
//| Enviar mensaje a Telegram                                        |
//+------------------------------------------------------------------+
void EnviarMensajeTelegram(string message)
  {
   if(!InpUseTelegram || InpBotToken == "" || InpChatID == "")
      return;
      
   if(MQLInfoInteger(MQL_TESTER))
     {
      Print("[Telegram Simulation] ", message);
      return;
     }
      
   string url = "https://api.telegram.org/bot" + InpBotToken + "/sendMessage";
   string headers = "Content-Type: application/x-www-form-urlencoded\r\n";
   string postData = "chat_id=" + InpChatID + "&text=" + message;
   
   char data[];
   char result[];
   string resHeaders;
   
   StringToCharArray(postData, data);
   
   int res = WebRequest("POST", url, headers, 3000, data, result, resHeaders);
   if(res == 200)
     {
      Print("Mensaje de Telegram enviado con éxito.");
     }
   else
     {
      Print("Error al enviar mensaje a Telegram. Código: ", GetLastError());
     }
  }
