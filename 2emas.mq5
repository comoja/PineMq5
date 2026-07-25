//+------------------------------------------------------------------+
//|                                                        2EMAs.mq5 |
//|                                                    Antigravity   |
//+------------------------------------------------------------------+
#property copyright "Trading EA"
#property version   "1.00"

#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>

CTrade         trade;
CPositionInfo  posInfo;

//====================================================================
// VARIABLES GLOBALES (Parámetros Configurables)
//====================================================================
int      magicNumber       = 777222;  // Identificador único del EA
double   riskPercent       = 1.0;     // Riesgo por operación (%)
int      emaRapidaPeriod   = 10;      // Periodo de la EMA Rápida
int      emaLentaPeriod    = 80;      // Periodo de la EMA Lenta
int      swingLookback     = 10;      // Velas hacia atrás para calcular el SL (Mínimo/Máximo)
double   minDistancePuntos = 0.0;     // Distancia mínima entre EMAs para entrar (al mínimo)
double   pendienteMin      = 34.0;    // Pendiente mínima de la EMA Lenta en grados para permitir entrada
double   rrMult            = 2.2;     // Multiplicador ATR para SL y TP 
double   intraRR           = 2.0;     // Multiplicador ATR para SL y TP en operaciones posteriores rrMult/intraRR
int      diasTendencia     = 3;       // Días para evaluar la tendencia mayor
bool     bloqueoXtendencia = false;   // Bloquear entradas en contra de la tendencia mayor
double   proporcionRRcontraria = 0.5; // Proporcion del SL y TP cuando estan en contra de la tendencia mayor



// Handles y Búferes para los indicadores
int    handleEmaRapida;
int    handleEmaLenta;
int    handleAtr;
double bufferEmaRapida[];
double bufferEmaLenta[];
double bufferAtr[];

// Parámetros de Indicadores Internos
int    atrPeriod = 14;

// Variables de Control
double globalLotSize = 0.10; // Se puede sobreescribir dinámicamente

enum ENUM_TREND {
    TREND_NONE = 0,
    TREND_BUY = 1,
    TREND_SELL = -1
};
ENUM_TREND currentTrend = TREND_NONE;
double lastPositionExitPrice = 0.0;

// Control de velas
datetime lastBarTime = 0;

//====================================================================
// INICIALIZACIÓN (OnInit)
//====================================================================
int OnInit()
{
    // Configurar Magic Number para la clase CTrade
    trade.SetExpertMagicNumber(magicNumber);
    
    // Configuración condicional encapsulada por activo
    if(_Symbol == "XAUUSD" || _Symbol == "US100" || _Symbol == "USTEC")
    {
        // Aquí se reasignan parámetros globales dependiendo de la volatilidad del activo
        // globalLotSize = 0.50; // Ejemplo
    }
    else if(_Symbol == "BTCUSD")
    {
        // globalLotSize = 0.05; // Ajuste para crypto
    }

    // Inicialización de los Handles de las EMAs
    handleEmaRapida = iMA(_Symbol, PERIOD_CURRENT, emaRapidaPeriod, 0, MODE_EMA, PRICE_CLOSE);
    handleEmaLenta  = iMA(_Symbol, PERIOD_CURRENT, emaLentaPeriod, 0, MODE_EMA, PRICE_CLOSE);
    handleAtr       = iATR(_Symbol, PERIOD_CURRENT, atrPeriod);
    
    if(handleEmaRapida == INVALID_HANDLE || handleEmaLenta == INVALID_HANDLE || handleAtr == INVALID_HANDLE)
    {
        Print("Error al inicializar los indicadores");
        return INIT_FAILED;
    }
    
    // Configurar Arrays como Series (Index 0 = vela actual)
    ArraySetAsSeries(bufferEmaRapida, true);
    ArraySetAsSeries(bufferEmaLenta, true);
    ArraySetAsSeries(bufferAtr, true);
    
    // Añadir los indicadores al gráfico visual del Strategy Tester
    ChartIndicatorAdd(0, 0, handleEmaRapida);
    ChartIndicatorAdd(0, 0, handleEmaLenta);
   
    
    
    return(INIT_SUCCEEDED);
}

//====================================================================
// [MQ5-CRITICAL #1] Detección de Posición Propia
//====================================================================
int getOwnPositionType()
{
    int posType = -1; 
    for(int i = PositionsTotal() - 1; i >= 0; i--)
    {
        if(posInfo.SelectByIndex(i))
        {
            // Validar Símbolo y Magic Number [MQ5-CRITICAL #4]
            if(posInfo.Symbol() == _Symbol && posInfo.Magic() == magicNumber)
            {
                posType = (int)posInfo.PositionType();
                break;
            }
        }
    }
    return posType;
}

//====================================================================
// HELPER: Dibujar Flecha de Cruce
//====================================================================
void drawArrow(bool isUp)
{
    datetime time0 = iTime(_Symbol, PERIOD_CURRENT, 0);
    string objName = (isUp ? "cruceAlcista_" : "cruceBajista_") + TimeToString(time0);
    
    if(ObjectFind(0, objName) < 0) // Si no existe en la vela actual
    {
        double price = isUp ? iLow(_Symbol, PERIOD_CURRENT, 0) - 50 * _Point : iHigh(_Symbol, PERIOD_CURRENT, 0) + 50 * _Point;
        if(ObjectCreate(0, objName, isUp ? OBJ_ARROW_UP : OBJ_ARROW_DOWN, 0, time0, price))
        {
            ObjectSetInteger(0, objName, OBJPROP_COLOR, isUp ? clrGreen : clrRed);
            ObjectSetInteger(0, objName, OBJPROP_WIDTH, 4); // Más gruesa/llena
            ObjectSetInteger(0, objName, OBJPROP_ANCHOR, isUp ? ANCHOR_TOP : ANCHOR_BOTTOM);
        }
    }
}

//====================================================================
// FUNCIONES AUXILIARES
//====================================================================

// Cálculo dinámico de lotaje basado en Riesgo %
double CalculateDynamicLot(double entryPrice, double slPrice)
{
    // Si el SL está igual o muy cerca de la entrada, devolver el lote mínimo por seguridad
    double distance = MathAbs(entryPrice - slPrice);
    if(distance == 0) return SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
    
    double balance = AccountInfoDouble(ACCOUNT_BALANCE);
    double riskMoney = balance * (riskPercent / 100.0);
    
    double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
    double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
    
    if(tickSize == 0) return SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
    
    // ¿Cuánto dinero pierdo por cada 1 Lote de volumen?
    double lossPerLot = (distance / tickSize) * tickValue;
    
    if(lossPerLot == 0) return SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
    
    double calculatedLot = riskMoney / lossPerLot;
    
    // Normalizar al broker (min, max, step)
    double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
    double maxLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
    double volStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
    
    calculatedLot = MathFloor(calculatedLot / volStep) * volStep;
    
    if(calculatedLot < minLot) calculatedLot = minLot;
    if(calculatedLot > maxLot) calculatedLot = maxLot;
    
    return calculatedLot;
}

//====================================================================
// FILTRO HTF (Macro Tendencia Diaria)
//====================================================================
ENUM_TREND GetDailyTrend(int days)
{
    if(days <= 0) return TREND_NONE;
    
    double closeYesterday = iClose(_Symbol, PERIOD_D1, 1);
    double openPast = iOpen(_Symbol, PERIOD_D1, days);
    
    if(closeYesterday > 0 && openPast > 0)
    {
        if(closeYesterday > openPast) return TREND_BUY;
        if(closeYesterday < openPast) return TREND_SELL;
    }
    
    return TREND_NONE;
}

void UpdateDashboard(ENUM_TREND macroTrend)
{
    int buysWin = 0, buysLoss = 0;
    int sellsWin = 0, sellsLoss = 0;
    
    datetime from_date = TimeCurrent() - (diasTendencia * 86400);
    HistorySelect(from_date, TimeCurrent());
    
    for(int i = 0; i < HistoryDealsTotal(); i++)
    {
        ulong ticket = HistoryDealGetTicket(i);
        if(HistoryDealGetInteger(ticket, DEAL_MAGIC) == magicNumber && HistoryDealGetString(ticket, DEAL_SYMBOL) == _Symbol)
        {
            if(HistoryDealGetInteger(ticket, DEAL_ENTRY) == DEAL_ENTRY_OUT)
            {
                double profit = HistoryDealGetDouble(ticket, DEAL_PROFIT) + HistoryDealGetDouble(ticket, DEAL_SWAP) + HistoryDealGetDouble(ticket, DEAL_COMMISSION);
                long dealType = HistoryDealGetInteger(ticket, DEAL_TYPE);
                
                // Deal OUT de SELL significa que cerramos una COMPRA
                if(dealType == DEAL_TYPE_SELL)
                {
                    if(profit > 0) buysWin++; else buysLoss++;
                }
                // Deal OUT de BUY significa que cerramos una VENTA
                else if(dealType == DEAL_TYPE_BUY)
                {
                    if(profit > 0) sellsWin++; else sellsLoss++;
                }
            }
        }
    }
    
    string trendStr = "RANGO";
    if(macroTrend == TREND_BUY) trendStr = "ALCISTA";
    if(macroTrend == TREND_SELL) trendStr = "BAJISTA";
    
    string dash = "=========================\n";
    dash += "   ESTADO DEL MERCADO    \n";
    dash += "=========================\n";
    dash += "Tendencia " + IntegerToString(diasTendencia) + "D: " + trendStr + "\n\n";
    dash += "--- RESULTADOS (Últimos " + IntegerToString(diasTendencia) + " Días) ---\n";
    dash += "Compras Exitosas: " + IntegerToString(buysWin) + "\n";
    dash += "Compras Fallidas: " + IntegerToString(buysLoss) + "\n";
    dash += "Ventas Exitosas:  " + IntegerToString(sellsWin) + "\n";
    dash += "Ventas Fallidas:  " + IntegerToString(sellsLoss) + "\n";
    
    Comment(dash);
}

//====================================================================
// CICLO PRINCIPAL (OnTick)
//====================================================================
void OnTick()
{
    datetime currentBarTime = iTime(_Symbol, PERIOD_CURRENT, 0);
    if(currentBarTime == lastBarTime) return;
    lastBarTime = currentBarTime;



    // 1. Detectar el Uso Horario (Base NY vs Local)
    // TODO: Implementar lógica de bloqueo de horario de NY o CDMX según el ecosistema
    
    // 2. Obtener datos de los Indicadores
    if(CopyBuffer(handleEmaRapida, 0, 0, 3, bufferEmaRapida) <= 0) return;
    if(CopyBuffer(handleEmaLenta, 0, 0, 3, bufferEmaLenta) <= 0) return;
    if(CopyBuffer(handleAtr, 0, 0, 3, bufferAtr) <= 0) return;
    

    
    double emaRapidaActual = bufferEmaRapida[0];
    double emaRapidaPrevia = bufferEmaRapida[1];
    
    double emaLentaActual  = bufferEmaLenta[0];
    double emaLentaPrevia  = bufferEmaLenta[1];
    
    // Obtener precios actuales
    double closeActual = iClose(_Symbol, PERIOD_CURRENT, 0);
    double tickAsk     = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
    double tickBid     = SymbolInfoDouble(_Symbol, SYMBOL_BID);
    
    // Obtener el tipo de posición activa (si existe)
    int ownPosType = getOwnPositionType();
    
    static bool wasInMarket = false;
    if(ownPosType == -1 && wasInMarket)
    {
        // Acabamos de salir del mercado, buscar el precio de cierre en el historial
        HistorySelect(TimeCurrent() - 86400, TimeCurrent());
        for(int i = HistoryDealsTotal() - 1; i >= 0; i--)
        {
            ulong ticket = HistoryDealGetTicket(i);
            if(HistoryDealGetInteger(ticket, DEAL_MAGIC) == magicNumber && HistoryDealGetString(ticket, DEAL_SYMBOL) == _Symbol)
            {
                if(HistoryDealGetInteger(ticket, DEAL_ENTRY) == DEAL_ENTRY_OUT)
                {
                    lastPositionExitPrice = HistoryDealGetDouble(ticket, DEAL_PRICE);
                    break;
                }
            }
        }
    }
    wasInMarket = (ownPosType != -1);
    
    // Variables para controlar la línea visual del SL y TP
    static string activeSlLineName = "";
    static string activeTpLineName = "";
    
    if(ownPosType != -1)
    {
        datetime currentTime = TimeCurrent();
        if(activeSlLineName != "") ObjectSetInteger(0, activeSlLineName, OBJPROP_TIME, 1, currentTime);
        if(activeTpLineName != "") ObjectSetInteger(0, activeTpLineName, OBJPROP_TIME, 1, currentTime);
    }
    
    //================================================================
    // LÓGICA DE SALIDA
    //================================================================
    
    
    if(ownPosType == POSITION_TYPE_BUY)
    {
        // Cierre Forzado local se remueve porque ya lo hace el broker con el TP modificado
        
        // Salida Compras: Cruce Bajista o si el Precio cierra por debajo de la EMA Lenta
        if((emaRapidaActual < emaLentaActual && emaRapidaPrevia >= emaLentaPrevia) || (closeActual < emaLentaActual))
        {
            //trade.PositionClose(_Symbol);
            Print("Cerrando COMPRA: Condición de Salida (Cruce bajista o Precio < EMA Lenta)");
            return;
        }
    }
    else if(ownPosType == POSITION_TYPE_SELL)
    {
        // Cierre Forzado local se remueve porque ya lo hace el broker con el TP modificado

        // Salida Ventas: Cruce Alcista o si el Precio cierra por encima de la EMA Lenta
        if((emaRapidaActual > emaLentaActual && emaRapidaPrevia <= emaLentaPrevia) || (closeActual > emaLentaActual))
        {
            //trade.PositionClose(_Symbol);
            Print("Cerrando VENTA: Condición de Salida (Cruce alcista o Precio > EMA Lenta)");
            return;
        }
    }

    //================================================================
    // LÓGICA DE ENTRADA [MQ5-CRITICAL #2 - Filtro Posición Contraria]
    // =================================================================
    
    // Solo permitimos buscar entrada si no hay operaciones abiertas de nuestro EA
    if(ownPosType == -1)
    {
        activeSlLineName = ""; // La operación se cerró, dejamos de actualizar las líneas
        activeTpLineName = "";
        
        datetime currentBar = iTime(_Symbol, PERIOD_CURRENT, 0);
        
        // Validar si hubo un cruce de EMAs usando VELAS CERRADAS (índices 1 y 2)
        bool cruceAlcistaEmas = (bufferEmaRapida[1] > bufferEmaLenta[1] && bufferEmaRapida[2] <= bufferEmaLenta[2]);
        bool cruceBajistaEmas = (bufferEmaRapida[1] < bufferEmaLenta[1] && bufferEmaRapida[2] >= bufferEmaLenta[2]);
        
        // --- 1. ACTUALIZAR BANDERA DE TENDENCIA ---
        if(cruceAlcistaEmas)
        {
            currentTrend = TREND_BUY;
            lastPositionExitPrice = 0.0;
            drawArrow(true);
        }
        else if(cruceBajistaEmas)
        {
            currentTrend = TREND_SELL;
            lastPositionExitPrice = 0.0;
            drawArrow(false);
        }
        
        // --- 2. LÓGICA DE ENTRADA MULTIPLE ---
        if(currentTrend != TREND_NONE)
        {
            static datetime lastTradeTry = 0;
            
            // Evaluamos la macro tendencia diaria
            ENUM_TREND macroTrend = GetDailyTrend(diasTendencia);
            
            // Calculamos la pendiente de la EMA RÁPIDA en PUNTOS
            double pendienteEmaRapida = (bufferEmaRapida[1] - bufferEmaRapida[2]) / _Point;
            
            // --- SEÑAL ALCISTA ---
            if(currentTrend == TREND_BUY)
            {
                MqlTick tick;
                SymbolInfoTick(_Symbol, tick);
                
                bool rompioArriba = (tick.ask > bufferEmaRapida[0]);
                
                bool macroAllowed = true;
                if(bloqueoXtendencia && GetDailyTrend(diasTendencia) == TREND_SELL) macroAllowed = false;
                
                bool velaVerde = (tick.ask > iOpen(_Symbol, PERIOD_CURRENT, 0));
                
                if(rompioArriba && currentBar != lastTradeTry && pendienteEmaRapida > pendienteMin && macroAllowed && velaVerde)
                {
                    double atrValue = bufferAtr[0];
                    double stopLoss = 0.0;
                    
                    double priceAsk = tick.ask;
                    
                    // SL Lógica: primer trade usa rrMult, subsecuentes usan rrMult/2 (o el cierre previo)
                    double effectiveRRMultTP = rrMult;
                    if(GetDailyTrend(diasTendencia) == TREND_SELL) effectiveRRMultTP *= proporcionRRcontraria;
                    
                    if(lastPositionExitPrice == 0.0)
                    {
                        stopLoss = priceAsk - (atrValue * rrMult);
                    }
                    else
                    {
                        if(lastPositionExitPrice < priceAsk)
                            stopLoss = lastPositionExitPrice;
                        else
                            stopLoss = priceAsk - (atrValue * (rrMult / intraRR));
                    }
                    
                    // Cálculo TP = effectiveRRMultTP * ATR
                    double takeProfit = priceAsk + (effectiveRRMultTP * atrValue);
                    
                    // Cálculo de Lotes Dinámico
                    double lotToTrade = CalculateDynamicLot(stopLoss, priceAsk);
                    
                    string lineNameSL = "SL_Buy_" + TimeToString(TimeCurrent());
                    ObjectCreate(0, lineNameSL, OBJ_TREND, 0, TimeCurrent(), stopLoss, TimeCurrent() + PeriodSeconds(), stopLoss);
                    ObjectSetInteger(0, lineNameSL, OBJPROP_COLOR, clrRed);
                    ObjectSetInteger(0, lineNameSL, OBJPROP_WIDTH, 2);
                    ObjectSetInteger(0, lineNameSL, OBJPROP_RAY_RIGHT, false); 
                    
                    string lineNameTP = "TP_Buy_" + TimeToString(TimeCurrent());
                    ObjectCreate(0, lineNameTP, OBJ_TREND, 0, TimeCurrent(), takeProfit, TimeCurrent() + PeriodSeconds(), takeProfit);
                    ObjectSetInteger(0, lineNameTP, OBJPROP_COLOR, clrGreen);
                    ObjectSetInteger(0, lineNameTP, OBJPROP_WIDTH, 2);
                    ObjectSetInteger(0, lineNameTP, OBJPROP_RAY_RIGHT, false);
                    
                    Print(">>> Intentando COMPRAR. SL: ", stopLoss, " TP: ", takeProfit, " Lotes: ", lotToTrade);
                    if(trade.Buy(lotToTrade, _Symbol, priceAsk, stopLoss, takeProfit, "2EMAs Buy"))
                    {
                        activeSlLineName = lineNameSL; 
                        activeTpLineName = lineNameTP;
                    }
                    lastTradeTry = currentBar;
                }
            }
            
            // --- SEÑAL BAJISTA ---
            if(currentTrend == TREND_SELL)
            {
                MqlTick tick;
                SymbolInfoTick(_Symbol, tick);
                
                bool rompioAbajo = (tick.bid < bufferEmaRapida[0]);
                
                bool macroAllowed = true;
                if(bloqueoXtendencia && GetDailyTrend(diasTendencia) == TREND_BUY) macroAllowed = false;
                
                bool velaRoja = (tick.bid < iOpen(_Symbol, PERIOD_CURRENT, 0));
                
                if(rompioAbajo && currentBar != lastTradeTry && pendienteEmaRapida < -pendienteMin && macroAllowed && velaRoja)
                {
                    double atrValue = bufferAtr[0];
                    double stopLoss = 0.0;
                    
                    double priceBid = tick.bid;
                    
                    // SL Lógica: primer trade usa rrMult, subsecuentes usan rrMult/2 (o el cierre previo)
                    double effectiveRRMultTP = rrMult;
                    if(GetDailyTrend(diasTendencia) == TREND_BUY) effectiveRRMultTP *= proporcionRRcontraria;
                    
                    if(lastPositionExitPrice == 0.0)
                    {
                        stopLoss = priceBid + (atrValue * rrMult);
                    }
                    else
                    {
                        if(lastPositionExitPrice > priceBid)
                            stopLoss = lastPositionExitPrice;
                        else
                            stopLoss = priceBid + (atrValue * (rrMult / intraRR));
                    }
                    
                    // Cálculo TP = effectiveRRMultTP * ATR
                    double takeProfit = priceBid - (effectiveRRMultTP * atrValue);
                    
                    // Cálculo de Lotes Dinámico
                    double lotToTrade = CalculateDynamicLot(stopLoss, priceBid);
                    
                    string lineNameSL = "SL_Sell_" + TimeToString(TimeCurrent());
                    ObjectCreate(0, lineNameSL, OBJ_TREND, 0, TimeCurrent(), stopLoss, TimeCurrent() + PeriodSeconds(), stopLoss);
                    ObjectSetInteger(0, lineNameSL, OBJPROP_COLOR, clrRed);
                    ObjectSetInteger(0, lineNameSL, OBJPROP_WIDTH, 2);
                    ObjectSetInteger(0, lineNameSL, OBJPROP_RAY_RIGHT, false); 
                    
                    string lineNameTP = "TP_Sell_" + TimeToString(TimeCurrent());
                    ObjectCreate(0, lineNameTP, OBJ_TREND, 0, TimeCurrent(), takeProfit, TimeCurrent() + PeriodSeconds(), takeProfit);
                    ObjectSetInteger(0, lineNameTP, OBJPROP_COLOR, clrGreen);
                    ObjectSetInteger(0, lineNameTP, OBJPROP_WIDTH, 2);
                    ObjectSetInteger(0, lineNameTP, OBJPROP_RAY_RIGHT, false);
                    
                    Print(">>> Intentando VENDER. SL: ", stopLoss, " TP: ", takeProfit, " Lotes: ", lotToTrade);
                    if(trade.Sell(lotToTrade, _Symbol, priceBid, stopLoss, takeProfit, "2EMAs Sell"))
                    {
                        activeSlLineName = lineNameSL; 
                        activeTpLineName = lineNameTP;
                    }
                    lastTradeTry = currentBar;
                }
            }
        }
    }
    
    // Actualizar el Dashboard Estadístico en cada Tick
    ENUM_TREND currentMacroTrend = GetDailyTrend(diasTendencia);
    UpdateDashboard(currentMacroTrend);
}
//+------------------------------------------------------------------+
