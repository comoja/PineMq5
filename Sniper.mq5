//+------------------------------------------------------------------+
//|                                  SniperSilverMultiDivisa.mq5    |
//|                                  Traducido de Pine Script v6     |
//+------------------------------------------------------------------+
#property copyright "AI Translator"
#property link ""
#property version "1.70"

// Incluir librería nativa de trading
#include <Trade\Trade.mqh>
CTrade trade;

// --- INPUTS ---
input double RiskPercent = 8.0; // % de Equidad para cada operación

// --- INDICADORES ---
int handle_emaXAG, handle_adxXAG, handle_atrXAG;
int handle_emaUNI, handle_adxUNI, handle_atrUNI;

// --- VARIABLES DE CONTROL (PERSISTENTES) ---
bool isSilver = false;
double t_sl = 0.0, t_tp = 0.0, t_ent = 0.0;
int gold_cooldown_bar = 0;
bool had_open_position = false;

// VARIABLES PARA EL TRAIL DINÁMICO POR TERCIOS
double trail_step = 0.0; // 1/3 de la distancia Entrada-SL en puntos

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit() {
  string symbol = _Symbol;
  StringToUpper(symbol);

  // Detección de Activo (Plata)
  if (StringFind(symbol, "XAG") >= 0 || StringFind(symbol, "SILVER") >= 0)
    isSilver = true;
  else
    isSilver = false;

  // Inicializar Indicadores para Motor 1 (Plata)
  handle_emaXAG = iMA(symbol, _Period, 9, 0, MODE_EMA, PRICE_CLOSE);
  handle_adxXAG = iADX(symbol, _Period, 14);
  handle_atrXAG = iATR(symbol, _Period, 14);

  // Inicializar Indicadores para Motor 2 (Oro y otros)
  handle_emaUNI = iMA(symbol, _Period, 200, 0, MODE_EMA, PRICE_CLOSE);
  handle_adxUNI = iADX(symbol, _Period, 14);
  handle_atrUNI = iATR(symbol, _Period, 14);

  // VALIDACIÓN: Si algún indicador falla al crearse, avisar en el diario
  if (handle_emaXAG == INVALID_HANDLE || handle_adxXAG == INVALID_HANDLE ||
      handle_atrXAG == INVALID_HANDLE || handle_emaUNI == INVALID_HANDLE ||
      handle_adxUNI == INVALID_HANDLE || handle_atrUNI == INVALID_HANDLE) {
    Print("ALERTA: Uno de los indicadores no se pudo inicializar en este "
          "símbolo o temporalidad.");
  }

  trade.SetExpertMagicNumber(998877); // ID único de la estrategia
  return (INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason) {
  // Liberar memoria de los handles al retirar el robot
  IndicatorRelease(handle_emaXAG);
  IndicatorRelease(handle_adxXAG);
  IndicatorRelease(handle_atrXAG);
  IndicatorRelease(handle_emaUNI);
  IndicatorRelease(handle_adxUNI);
  IndicatorRelease(handle_atrUNI);
  Comment("");
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick() {
  // Control estricto de vela nueva para evitar ejecuciones masivas por tick
  static datetime last_time;
  datetime current_time = iTime(_Symbol, _Period, 0);
  if (current_time == last_time)
    return;

  // Si los indicadores fallaron al crearse, detenemos la ejecución de este tick
  if (handle_emaXAG == INVALID_HANDLE || handle_adxXAG == INVALID_HANDLE ||
      handle_atrXAG == INVALID_HANDLE || handle_emaUNI == INVALID_HANDLE ||
      handle_adxUNI == INVALID_HANDLE || handle_atrUNI == INVALID_HANDLE) {
    return;
  }

  last_time = current_time;

  // Comprobar si hay una posición abierta en este símbolo
  bool has_position = PositionSelect(_Symbol);

  // --- SISTEMA COOLDOWN (Para activos que no son Plata) ---
  if (!isSilver) {
    if (had_open_position && !has_position) // Detecta el momento de cierre
    {
      int total_bars = iBars(_Symbol, _Period);
      gold_cooldown_bar = total_bars + 50;
    }
    had_open_position = has_position;
  }

  // --- LECTURA DE ARRAYS (Copiar datos de precios recientes) ---
  double close[], close1, high[], high1, low[], low1;
  if (CopyClose(_Symbol, _Period, 0, 3, close) < 3 ||
      CopyHigh(_Symbol, _Period, 0, 3, high) < 3 ||
      CopyLow(_Symbol, _Period, 0, 3, low) < 3) {
    return; // Esperar a que cargue suficiente historial en el gráfico
  }

  ArraySetAsSeries(close, true);
  ArraySetAsSeries(high, true);
  ArraySetAsSeries(low, true);

  // Sincronización exacta con las variables históricas: vela [1] es la vela
  // cerrada anterior
  close1 = close[1];
  high1 = high[1];
  low1 = low[1];

  // --- PROCESAMIENTO DE VALORES DE INDICADORES ---
  double emaXAG_val[], adxXAG_main[], atrXAG_val[];
  double emaUNI_val[], adxUNI_main[], atrUNI_val[];

  if (CopyBuffer(handle_emaXAG, 0, 0, 3, emaXAG_val) < 3 ||
      CopyBuffer(handle_adxXAG, 0, 0, 3, adxXAG_main) < 3 ||
      CopyBuffer(handle_atrXAG, 0, 0, 3, atrXAG_val) < 3 ||
      CopyBuffer(handle_emaUNI, 0, 0, 3, emaUNI_val) < 3 ||
      CopyBuffer(handle_adxUNI, 0, 0, 3, adxUNI_main) < 3 ||
      CopyBuffer(handle_atrUNI, 0, 0, 3, atrUNI_val) < 3) {
    return; // Esperar que los buffers de los indicadores se llenen
  }

  ArraySetAsSeries(emaXAG_val, true);
  ArraySetAsSeries(adxXAG_main, true);
  ArraySetAsSeries(atrXAG_val, true);
  ArraySetAsSeries(emaUNI_val, true);
  ArraySetAsSeries(adxUNI_main, true);
  ArraySetAsSeries(atrUNI_val, true);

  // Precios máximos y mínimos para canales de ruptura (80 velas)
  int highest_idx = iHighest(_Symbol, _Period, MODE_HIGH, 80, 1);
  int lowest_idx = iLowest(_Symbol, _Period, MODE_LOW, 80, 1);

  double u_prices[], l_prices[];
  if (CopyHigh(_Symbol, _Period, highest_idx, 1, u_prices) < 1 ||
      CopyLow(_Symbol, _Period, lowest_idx, 1, l_prices) < 1)
    return;

  double upperUNI_price = u_prices[0];
  double lowerUNI_price = l_prices[0];

  // --- FILTROS DE TENDENCIA Y VOLATILIDAD (Equivalente exacto a Pine) ---
  bool filtroXAG = (adxXAG_main[1] > 23) && (adxXAG_main[1] > adxXAG_main[2]);
  bool filtroUNI = (adxUNI_main[1] > 22);

  int current_bars = iBars(_Symbol, _Period);
  bool respiro_ok = isSilver || (current_bars > gold_cooldown_bar);

  // --- LÓGICA DE DISPARO DE ENTRADAS ---
  bool longC = false;
  bool shortC = false;

  if (!has_position) {
    if (isSilver) {
      longC = (close1 > emaXAG_val[1]) && (close1 > high[2]) && filtroXAG;
      shortC = (close1 < emaXAG_val[1]) && (close1 < low[2]) && filtroXAG;
    } else {
      longC = respiro_ok &&
              (close[2] <= upperUNI_price && close1 > upperUNI_price) &&
              (close1 > emaUNI_val[1]) && filtroUNI;
      shortC = respiro_ok &&
               (close[2] >= lowerUNI_price && close1 < lowerUNI_price) &&
               (close1 < emaUNI_val[1]) && filtroUNI;
    }
  }

  // --- GESTIÓN DE RIESGO Y LOTAJE ---
  double lot = ElLotaje(RiskPercent);

  // --- EJECUCIÓN DE TRADES ---
  if (!has_position && longC) {
    t_ent = close1;
    t_sl = isSilver ? (low1 - (atrXAG_val[1] * 0.1))
                    : (low1 - (atrUNI_val[1] * 1.5));
    t_tp = close1 + (MathAbs(close1 - t_sl) * (isSilver ? 1.1 : 2.0));

    trail_step = MathAbs(t_ent - t_sl) /
                 3.0; // Guardar valor de 1/3 de la distancia de riesgo

    trade.Buy(lot, _Symbol, 0, t_sl, t_tp, "Sniper L");
    return;
  }

  if (!has_position && shortC) {
    t_ent = close1;
    t_sl = isSilver ? (high1 + (atrXAG_val[1] * 0.1))
                    : (high1 + (atrUNI_val[1] * 2.0));
    t_tp = close1 - (MathAbs(close1 - t_sl) * (isSilver ? 1.2 : 3.0));

    trail_step = MathAbs(t_ent - t_sl) /
                 3.0; // Guardar valor de 1/3 de la distancia de riesgo

    trade.Sell(lot, _Symbol, 0, t_sl, t_tp, "Sniper S");
    return;
  }

  // --- GESTIÓN DE SALIDA / TRAILING STOP POR TERCIOS COMPLETOS ---
  if (has_position) {
    if (t_ent == 0.0 || trail_step == 0.0) {
      t_ent = PositionGetDouble(POSITION_PRICE_OPEN);
      double sl_inicial = PositionGetDouble(POSITION_SL);
      if (sl_inicial > 0)
        trail_step = MathAbs(t_ent - sl_inicial) / 3.0;
    }

    long type = PositionGetInteger(POSITION_TYPE);
    double current_position_sl = PositionGetDouble(POSITION_SL);
    double current_position_tp = PositionGetDouble(POSITION_TP);
    double close_curr = SymbolInfoDouble(_Symbol, SYMBOL_LAST);
    if (close_curr == 0)
      close_curr = SymbolInfoDouble(_Symbol, SYMBOL_BID);

    if (trail_step > 0) {
      if (type == POSITION_TYPE_BUY) {
        double recorrido = close_curr - t_ent;
        int niveles_superados = (int)MathFloor(recorrido / trail_step);

        if (niveles_superados > 0) {
          double nuevo_sl =
              (t_ent - (trail_step * 3.0)) + (trail_step * niveles_superados);
          nuevo_sl = NormalizeDouble(nuevo_sl, _Digits);

          if (nuevo_sl > current_position_sl) {
            trade.PositionModify(_Symbol, nuevo_sl, current_position_tp);
          }
        }
      } else if (type == POSITION_TYPE_SELL) {
        double recorrido = t_ent - close_curr;
        int niveles_superados = (int)MathFloor(recorrido / trail_step);

        if (niveles_superados > 0) {
          double nuevo_sl =
              (t_ent + (trail_step * 3.0)) - (trail_step * niveles_superados);
          nuevo_sl = NormalizeDouble(nuevo_sl, _Digits);

          if (nuevo_sl < current_position_sl || current_position_sl == 0) {
            trade.PositionModify(_Symbol, nuevo_sl, current_position_tp);
          }
        }
      }
    }
  } else {
    t_ent = 0.0;
    trail_step = 0.0;
  }
  // Panel visual impreso en pantalla
  string info = "=== SNIPER MULTI-DIVISA ===\n";
  info += "Activo: " + (isSilver ? "PLATA (XAG)" : "OTRO ACTIVO") + "\n";
  info += "Paso del Trail (1/3 Puntos): " + DoubleToString(trail_step, _Digits);
  Comment(info);
}
//+------------------------------------------------------------------+//|
// Función auxiliar para cálculo dinámico del lotaje según equidad
// //+------------------------------------------------------------------+
double ElLotaje(double porcentaje) {
  double equity = AccountInfoDouble(ACCOUNT_EQUITY);
  double marginReq = 0.0;
  if (!OrderCalcMargin(ORDER_TYPE_BUY, _Symbol, 1.0,
                       SymbolInfoDouble(_Symbol, SYMBOL_ASK), marginReq)) {
    Print("Error calculando  el margen requerido. Usando lote mínimo de "
          "seguridad.");
    return SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
  }
  if (marginReq <= 0)
    return SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
  double max_risk_money = equity * (porcentaje / 100.0);
  double lot = max_risk_money / marginReq;
  double min_lot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
  double max_lot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
  double step_lot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
  lot = MathFloor(lot / step_lot) * step_lot;
  if (lot < min_lot)
    lot = min_lot;
  if (lot > max_lot)
    lot = max_lot;
  return lot;
}