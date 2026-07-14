//+------------------------------------------------------------------+
//|                                             SniperSHA.mq5        |
//|                                  Copyright 2026, Antigravity AI  |
//|                                             https://google.com   |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, Antigravity AI"
#property link      "https://google.com"
#property version   "2.00"

#include <Trade\Trade.mqh>
CTrade trade;

// ============================================================================
// GRUPO: IDENTIFICACIÓN
// ============================================================================
input bool InpDebugMode = true; // Activar Prints de Depuración
input group "═══ Identificación ═══"
input ulong InpMagicNumber = 334455; // Magic Number

// ============================================================================
// GRUPO: TIPO DE ACTIVO
// ============================================================================
input group "═══ Tipo de Activo ═══"
input string InpMarketType = "auto"; // Tipo de activo (auto, indice, forex, crypto, plata, oro)

// ============================================================================
// GRUPO: GESTIÓN DE RIESGO
// ============================================================================
input group "═══ Gestión de Riesgo ═══"
input double InpRiesgoPct = 1.0; // Riesgo por operación (%)
input double InpMinRR = 1.8; // RR mínimo (TP/SL)
input double InpAtrMult = 1.0; // Multiplicador ATR para SL
input bool   InpUseTrailing = false; // Usar Trailing Stop (Dinámico)
input bool   InpUseDynTP = true; // Usar TP Dinámico (Cierre x SHA)
input double InpBeRR = 1.5; // Break-even trigger (× riesgo)
input int    InpCooldownBars = 8; // Velas de enfriamiento

// ============================================================================
// GRUPO: FILTROS DE ENTRADA
// ============================================================================
input group "═══ Filtros de Entrada ═══"
input bool   InpUseAdxFilter = true; // Usar Filtro ADX
input int    InpAdxMin = 23; // ADX mínimo
input bool   InpAdxRising = false; // Exigir ADX subiendo
input bool   InpUseHtf = true; // Filtro HTF 1H (solo índices)
input bool   InpUseMacro = true; // Filtro Macro 14D (Bloqueos)
input double InpMaxDist = 1.0; // Distancia máx. a EMA (× ATR)

// ============================================================================
// GRUPO: FILTRO RANGO (IMACD)
// ============================================================================
input group "═══ Filtro Rango (IMACD) ═══"
input bool   InpUseImacd = true; // Usar Impulse MACD
input int    InpImacdPer = 34; // Período IMACD
input int    InpImacdSmooth = 9; // Suavizado histograma
input double InpImacdThresh = 0.3; // Umbral mínimo (× ATR)

// ============================================================================
// GRUPO: SHA Y SMC
// ============================================================================
input group "═══ Velas SHA ═══"
input int InpShaLen = 10; // Período SHA

input group "═══ SMC Sniper Entry ═══"
input bool InpUseSMC = true; // Activar Sniper Entry (SMC)
input bool InpSmcOnly = false; // Modo Exclusivo SMC
input int InpSmcPivotLen = 5; // Longitud de Pivots (Velas L/R)

// ============================================================================
// VARIABLES GLOBALES
// ============================================================================
double atrMult = 1.0;
double beRR = 1.5;
int adxMin = 23;
double finalRR = 1.8;
double fVol = 1.0;
bool restricNY = false;
int emaPer = 50;

datetime lastBarTime = 0;
int barIndexSinceClose = 999;
int previousPosType = -1;

double tSl = 0.0;
double tEnt = 0.0;
double slInicial = 0.0;
double tRisk = 0.0;
double slTercio = 0.0;
double tpDist = 0.0;
double tTp = 0.0;
int tStep = 0;

int h1_handle = INVALID_HANDLE;
int adx_handle = INVALID_HANDLE;
int macro_handle = INVALID_HANDLE;
int rsi_handle = INVALID_HANDLE;
int bb_handle = INVALID_HANDLE;

double flipLongZone = 0.0;
double flipShortZone = 0.0;
double lastPH = 0.0;
double lastPL = 0.0;

bool prevShaGreen = false;
bool prevShaRed = false;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
    trade.SetExpertMagicNumber(InpMagicNumber);
    string sym = Symbol();
    StringToLower(sym);
    
    bool isSilver = (StringFind(sym, "xag") >= 0 || StringFind(sym, "silver") >= 0 || StringFind(sym, "plata") >= 0);
    bool isGold   = (StringFind(sym, "xau") >= 0 || StringFind(sym, "gold") >= 0 || StringFind(sym, "oro") >= 0);
    bool isCrypto = (StringFind(sym, "btc") >= 0 || StringFind(sym, "eth") >= 0); 
    bool isIndex  = (StringFind(sym, "nas") >= 0 || StringFind(sym, "us100") >= 0 || StringFind(sym, "us30") >= 0);
    
    bool effSilver = (InpMarketType == "plata") || (InpMarketType == "auto" && isSilver);
    bool effGold   = (InpMarketType == "oro") || (InpMarketType == "auto" && isGold);
    bool effCrypto = (InpMarketType == "crypto") || (InpMarketType == "auto" && isCrypto);
    bool effIndex  = (InpMarketType == "indice") || (InpMarketType == "auto" && isIndex);
    
    atrMult = effCrypto ? 2.5 : (effGold ? 1.5 : (effSilver ? 1.5 : (effIndex ? 1.5 : InpAtrMult)));
    beRR = effCrypto ? 0.5 : (effIndex ? InpBeRR : 1.5);
    adxMin = effIndex ? (int)MathMax(InpAdxMin, 28) : ((effGold || effSilver) ? 18 : InpAdxMin);
    finalRR = effSilver ? 2.3 : InpMinRR;
    fVol = effCrypto ? 1.0 : (effGold ? 1.1 : (effSilver ? 1.3 : (effIndex ? 1.2 : 1.0)));
    restricNY = false; // DESACTIVADO TEMPORALMENTE PARA DESCARTAR FALLO DEL TESTER
    emaPer = 50; 
    
    h1_handle = iMA(Symbol(), PERIOD_H1, 21, 0, MODE_EMA, PRICE_CLOSE);
    adx_handle = iADX(Symbol(), _Period, 14);
    macro_handle = iMA(Symbol(), PERIOD_D1, 4, 0, MODE_SMA, PRICE_CLOSE);
    rsi_handle = iRSI(Symbol(), _Period, 14, PRICE_CLOSE);
    bb_handle = iBands(Symbol(), _Period, 20, 0, 2.0, PRICE_CLOSE);
    
    return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Funciones Auxiliares                                             |
//+------------------------------------------------------------------+
int GetOwnPositionType()
{
    if(PositionSelect(Symbol()))
        if(PositionGetInteger(POSITION_MAGIC) == InpMagicNumber)
            return (int)PositionGetInteger(POSITION_TYPE);
    return -1;
}

double CalculateSMA(double &src[], int period, int index)
{
    if(index + period > ArraySize(src)) return 0.0;
    double sum = 0.0;
    for(int i = 0; i < period; i++) sum += src[index + i];
    return sum / period;
}

double CalculateEMA(double &src[], int period, int index, double prevEma)
{
    double alpha = 2.0 / (period + 1.0);
    if(prevEma == 0.0) return CalculateSMA(src, period, index);
    return alpha * src[index] + (1.0 - alpha) * prevEma;
}

double CalculateSMMA(double &src[], int period, int index, double prevSmma)
{
    if(prevSmma == 0.0) return CalculateSMA(src, period, index);
    return (prevSmma * (period - 1) + src[index]) / period;
}

double PivotHigh(double &highs[], int left, int right, int index)
{
    if (index + left + right >= ArraySize(highs)) return 0.0;
    double center = highs[index + right];
    for (int i = 1; i <= left; i++) if (highs[index + right + i] > center) return 0.0;
    for (int i = 1; i <= right; i++) if (highs[index + right - i] >= center) return 0.0;
    return center;
}

double PivotLow(double &lows[], int left, int right, int index)
{
    if (index + left + right >= ArraySize(lows)) return 0.0;
    double center = lows[index + right];
    for (int i = 1; i <= left; i++) if (lows[index + right + i] < center) return 0.0;
    for (int i = 1; i <= right; i++) if (lows[index + right - i] <= center) return 0.0;
    return center;
}

//+------------------------------------------------------------------+
//| Trailing y TP Dinámico (Llamado tick a tick)                     |
//+------------------------------------------------------------------+
void ActualizarSlYTP(int posType, double currentPrecio, double atrVal, double tickVal)
{
    if(tSl <= 0) return;
    
    double nuevoSl = tSl;
    double nuevoTp = tTp;
    int nuevoStep = tStep;
    
    double tp85 = (posType == POSITION_TYPE_BUY) ? (tEnt + tpDist*0.85) : (tEnt - tpDist*0.85);
    double beVal = (posType == POSITION_TYPE_BUY) ? tEnt : tEnt;
    
    if (posType == POSITION_TYPE_BUY)
    {
        if (currentPrecio >= tp85)
        {
            if (nuevoStep < 2) nuevoStep = 2;
            if (InpUseTrailing) nuevoSl = currentPrecio - (atrVal * 0.5);
            if (InpUseDynTP && tTp != 0.0) nuevoTp = tTp + (tpDist * 0.5);
        }
        else if (currentPrecio >= tEnt + (tRisk * beRR)) // BE
        {
            if (nuevoStep < 1) nuevoStep = 1;
            nuevoSl = MathMax(nuevoSl, beVal);
        }
        
        if (nuevoSl > tSl + (tickVal*10) || (nuevoTp > tTp + (tickVal*10) && InpUseDynTP))
        {
            tSl = MathMax(tSl, nuevoSl);
            if (InpUseDynTP) tTp = MathMax(tTp, nuevoTp);
            tStep = nuevoStep;
            trade.PositionModify(Symbol(), tSl, tTp);
        }
    }
    else if (posType == POSITION_TYPE_SELL)
    {
        if (currentPrecio <= tp85)
        {
            if (nuevoStep < 2) nuevoStep = 2;
            if (InpUseTrailing) nuevoSl = currentPrecio + (atrVal * 0.5);
            if (InpUseDynTP && tTp != 0.0) nuevoTp = tTp - (tpDist * 0.5);
        }
        else if (currentPrecio <= tEnt - (tRisk * beRR))
        {
            if (nuevoStep < 1) nuevoStep = 1;
            nuevoSl = MathMin(nuevoSl, beVal);
        }
        
        if (nuevoSl < tSl - (tickVal*10) || (nuevoTp < tTp - (tickVal*10) && InpUseDynTP))
        {
            tSl = (nuevoSl == 0.0) ? tSl : ((tSl == slInicial) ? nuevoSl : MathMin(tSl, nuevoSl));
            if (InpUseDynTP) tTp = (tTp == 0.0) ? tTp : MathMin(tTp, nuevoTp);
            tStep = nuevoStep;
            trade.PositionModify(Symbol(), tSl, tTp);
        }
    }
}

//+------------------------------------------------------------------+
//| OnTick Process                                                   |
//+------------------------------------------------------------------+
void OnTick()
{
    datetime currentBar = iTime(Symbol(), _Period, 0);
    bool newBar = false;
    if(currentBar != lastBarTime)
    {
        newBar = true;
        lastBarTime = currentBar;
        barIndexSinceClose++;
    }
    
    double ask = SymbolInfoDouble(Symbol(), SYMBOL_ASK);
    double bid = SymbolInfoDouble(Symbol(), SYMBOL_BID);
    double tickVal = SymbolInfoDouble(Symbol(), SYMBOL_POINT);
    
    int posType = GetOwnPositionType();
    
    if (posType == -1 && previousPosType != -1)
    {
        barIndexSinceClose = 0;
        tSl = 0; tTp = 0; tStep = 0;
    }
    previousPosType = posType;
    
    double atrBuf[14]; 
    double currentAtr = 0.0;
    
    if (posType != -1)
    {
        MqlRates atrRates[];
        if (CopyRates(Symbol(), _Period, 0, 15, atrRates) > 0) {
            ArraySetAsSeries(atrRates, true);
            for(int i=0; i<14; i++) {
                atrBuf[i] = MathMax(atrRates[i].high - atrRates[i].low, 
                            MathMax(MathAbs(atrRates[i].high - atrRates[i+1].close), 
                                    MathAbs(atrRates[i].low - atrRates[i+1].close)));
            }
            currentAtr = CalculateSMA(atrBuf, 14, 0);
        }
        double currentPrecio = (posType == POSITION_TYPE_BUY) ? bid : ask;
        ActualizarSlYTP(posType, currentPrecio, currentAtr, tickVal);
    }
    
    if(newBar && posType == -1)
    {
        int maxBars = 1000;
        int startIndex = maxBars - 100;
        MqlRates rates[];
        if (CopyRates(Symbol(), _Period, 0, maxBars, rates) <= 0) return;
        ArraySetAsSeries(rates, true);
        
        double srcOpen[], srcHigh[], srcLow[], srcClose[], srcHlc3[];
        ArrayResize(srcOpen, maxBars); ArrayResize(srcHigh, maxBars); ArrayResize(srcLow, maxBars); ArrayResize(srcClose, maxBars); ArrayResize(srcHlc3, maxBars);
        for(int i=0; i<maxBars; i++) {
            srcOpen[i] = rates[i].open; srcHigh[i] = rates[i].high; srcLow[i] = rates[i].low; srcClose[i] = rates[i].close;
            srcHlc3[i] = (rates[i].high + rates[i].low + rates[i].close) / 3.0;
        }
        
        double adxBuf[2]; double currentAdx = 0.0, pAdx = 0.0;
        if (CopyBuffer(adx_handle, 0, 1, 2, adxBuf) > 0) { currentAdx = adxBuf[1]; pAdx = adxBuf[0]; }
        
        double h1Buf[1]; double currentEma1h = 0.0;
        if (CopyBuffer(h1_handle, 0, 1, 1, h1Buf) > 0) currentEma1h = h1Buf[0];
        
        double macroBuf[1]; double macroVal = 0.0;
        if (CopyBuffer(macro_handle, 0, 1, 1, macroBuf) > 0) macroVal = macroBuf[0];
        
        MqlRates ratesD1[]; double currentCloseD = 0.0;
        if (CopyRates(Symbol(), PERIOD_D1, 0, 1, ratesD1) > 0) currentCloseD = ratesD1[0].close;
        
        bool macroBull = currentCloseD > macroVal;
        bool macroBear = currentCloseD < macroVal;
        
        double rsiBuf[1]; double currentRsi = 50.0;
        if (CopyBuffer(rsi_handle, 0, 1, 1, rsiBuf) > 0) currentRsi = rsiBuf[0];
        
        double bbUpBuf[1], bbLowBuf[1]; double bbUp = 0.0, bbLow = 0.0;
        if (CopyBuffer(bb_handle, UPPER_BAND, 1, 1, bbUpBuf) > 0) bbUp = bbUpBuf[0];
        if (CopyBuffer(bb_handle, LOWER_BAND, 1, 1, bbLowBuf) > 0) bbLow = bbLowBuf[0];
        
        bool modoTendencia = currentAdx > 25.0;
        bool modoRango = currentAdx < 20.0;
        
        bool revLongTrigger = modoRango && (srcLow[1] <= bbLow) && (currentRsi < 30.0);
        bool revShortTrigger = modoRango && (srcHigh[1] >= bbUp) && (currentRsi > 70.0);
        
        long volSmaArr[20]; long volSma = 0;
        if (CopyTickVolume(Symbol(), _Period, 1, 20, volSmaArr) > 0) {
            long sum = 0; for(int i=0; i<20; i++) sum += volSmaArr[i];
            volSma = sum / 20;
        }
        long currentVol = rates[1].tick_volume;
        bool volOk = (currentVol == 0 || volSma == 0) ? true : (currentVol > (volSma * fVol));
        
        datetime timeGMT = rates[1].time - TimeGMTOffset(); 
        datetime timeNY = timeGMT - (5 * 3600);
        MqlDateTime nyInfo; TimeToStruct(timeNY, nyInfo);
        int h = nyInfo.hour; int m = nyInfo.min;
        bool inNY = (h > 9 || (h == 9 && m >= 30)) && (h < 16);
        bool sesionOk = !restricNY || inNY;
        
        double pEma = 0.0;
        for(int i=startIndex; i>=0; i--) pEma = CalculateEMA(srcClose, emaPer, i, pEma);
        double currentEma = pEma;
        
        double pSmmaH = 0.0, pSmmaL = 0.0;
        double ema1Arr[]; ArrayResize(ema1Arr, maxBars); double pEma1 = 0.0, pEma2 = 0.0;
        for(int i=startIndex; i>=0; i--) { pEma1 = CalculateEMA(srcHlc3, InpImacdPer, i, pEma1); ema1Arr[i] = pEma1; }
        for(int i=startIndex; i>=0; i--) { pEma2 = CalculateEMA(ema1Arr, InpImacdPer, i, pEma2); } 
        
        pSmmaH = 0.0; pSmmaL = 0.0; pEma1 = 0.0; pEma2 = 0.0;
        double mdArr[]; ArrayResize(mdArr, maxBars); ArrayInitialize(mdArr, 0.0);
        for(int i=startIndex; i>=0; i--) {
            pSmmaH = CalculateSMMA(srcHigh, InpImacdPer, i, pSmmaH);
            pSmmaL = CalculateSMMA(srcLow, InpImacdPer, i, pSmmaL);
            pEma1 = CalculateEMA(srcHlc3, InpImacdPer, i, pEma1); ema1Arr[i] = pEma1;
            pEma2 = CalculateEMA(ema1Arr, InpImacdPer, i, pEma2);
            double zlema = pEma1 + (pEma1 - pEma2);
            double md = (zlema > pSmmaH) ? (zlema - pSmmaH) : ((zlema < pSmmaL) ? (zlema - pSmmaL) : 0.0);
            mdArr[i] = md;
        }
        
        double sb1 = CalculateSMA(mdArr, InpImacdSmooth, 1);
        double sb2 = CalculateSMA(mdArr, InpImacdSmooth, 2);
        double sh1 = mdArr[1] - sb1;
        double sh2 = mdArr[2] - sb2;
        
        bool imacdLongTrigger = (sh1 > 0 && sh2 <= 0);
        bool imacdShortTrigger = (sh1 < 0 && sh2 >= 0);
        
        for(int i=0; i<14; i++) atrBuf[i] = MathMax(srcHigh[i+1]-srcLow[i+1], MathMax(MathAbs(srcHigh[i+1]-srcClose[i+2]), MathAbs(srcLow[i+1]-srcClose[i+2])));
        currentAtr = CalculateSMA(atrBuf, 14, 0);
        
        double pHigh = PivotHigh(srcHigh, InpSmcPivotLen, InpSmcPivotLen, 1);
        double pLow = PivotLow(srcLow, InpSmcPivotLen, InpSmcPivotLen, 1);
        if (pHigh != 0.0) lastPH = pHigh;
        if (pLow != 0.0) lastPL = pLow;
        
        if (lastPH != 0.0 && srcClose[1] > lastPH && srcClose[2] <= lastPH) { flipLongZone = lastPH; flipShortZone = 0.0; }
        if (lastPL != 0.0 && srcClose[1] < lastPL && srcClose[2] >= lastPL) { flipShortZone = lastPL; flipLongZone = 0.0; }
        
        double eO = 0.0, eH = 0.0, eL = 0.0, eC = 0.0;
        double shaO = 0.0, shaC = 0.0;
        double currentShaO = 0.0, currentShaC = 0.0, prevS_O = 0.0, prevS_C = 0.0;
        
        for(int i=startIndex; i>=1; i--) {
            eO = CalculateEMA(srcOpen, InpShaLen, i, eO);
            eH = CalculateEMA(srcHigh, InpShaLen, i, eH);
            eL = CalculateEMA(srcLow, InpShaLen, i, eL);
            eC = CalculateEMA(srcClose, InpShaLen, i, eC);
            
            double hc = (eO + eH + eL + eC) / 4.0;
            double ho = (i == startIndex) ? ((eO + eC)/2.0) : ((shaO + shaC) / 2.0);
            shaO = ho; shaC = hc;
            
            if(i == 2) { prevS_O = shaO; prevS_C = shaC; }
            if(i == 1) { currentShaO = shaO; currentShaC = shaC; }
        }
        
        bool shaGreen = (currentShaC > currentShaO);
        bool shaRed = (currentShaC < currentShaO);
        prevShaGreen = (prevS_C > prevS_O);
        prevShaRed = (prevS_C < prevS_O);
        
        bool permitLong = (barIndexSinceClose >= InpCooldownBars);
        bool permitShort = (barIndexSinceClose >= InpCooldownBars);
        
        bool emaLongOk = srcClose[1] > currentEma;
        bool emaShortOk = srcClose[1] < currentEma;
        bool nearEma = MathAbs(srcClose[1] - currentEma) < (currentAtr * InpMaxDist);
        bool htfLongOk = (!InpUseHtf || srcClose[1] > currentEma1h);
        bool htfShortOk = (!InpUseHtf || srcClose[1] < currentEma1h);
        
        bool adxRising = (!InpAdxRising || currentAdx > pAdx);
        bool adxOk = (!InpUseAdxFilter || (modoTendencia && currentAdx > adxMin && adxRising));
        
        bool macroOkLong  = !InpUseMacro || !macroBear;
        bool macroOkShort = !InpUseMacro || !macroBull;
        
        bool priceActionLong  = srcClose[1] > srcOpen[1];
        bool priceActionShort = srcClose[1] < srcOpen[1];
        
        double tol = currentAtr * 1.0;
        bool inLongFlip = (flipLongZone != 0.0 && srcLow[1] <= flipLongZone + tol && srcHigh[1] >= flipLongZone - tol);
        bool inShortFlip = (flipShortZone != 0.0 && srcHigh[1] >= flipShortZone - tol && srcLow[1] <= flipShortZone + tol);
        
        bool smcLongTrigger = InpUseSMC && inLongFlip && shaGreen && !prevShaGreen && emaLongOk && htfLongOk;
        bool smcShortTrigger = InpUseSMC && inShortFlip && shaRed && !prevShaRed && emaShortOk && htfShortOk;
        
        bool indLongTrigger = false, indShortTrigger = false;
        bool shLongOk = (!InpUseImacd || imacdLongTrigger);
        bool shShortOk = (!InpUseImacd || imacdShortTrigger);
        
        if(adxOk && emaLongOk && nearEma && htfLongOk && shaGreen && !prevShaGreen && shLongOk) indLongTrigger = true;
        if(adxOk && emaShortOk && nearEma && htfShortOk && shaRed && !prevShaRed && shShortOk) indShortTrigger = true;
        
        bool baseLongTrigger = InpSmcOnly ? smcLongTrigger : (InpUseSMC ? (smcLongTrigger || indLongTrigger) : indLongTrigger);
        bool baseShortTrigger = InpSmcOnly ? smcShortTrigger : (InpUseSMC ? (smcShortTrigger || indShortTrigger) : indShortTrigger);
        
        bool finalLongTrigger = baseLongTrigger || revLongTrigger;
        bool finalShortTrigger = baseShortTrigger || revShortTrigger;
        
        bool longC  = permitLong  && finalLongTrigger  && priceActionLong  && volOk && sesionOk && macroOkLong;
        bool shortC = permitShort && finalShortTrigger && priceActionShort && volOk && sesionOk && macroOkShort;
        
        if (InpDebugMode && (adxOk || shaGreen || shaRed || inLongFlip)) {
            PrintFormat("DEBUG -> adxOk:%d emaL:%d emaS:%d near:%d htfL:%d macL:%d shaG:%d shaR:%d volOk:%d sesion:%d smcL:%d indL:%d",
                adxOk, emaLongOk, emaShortOk, nearEma, htfLongOk, macroOkLong, shaGreen, shaRed, volOk, sesionOk, smcLongTrigger, indLongTrigger);
        }
        
        if (longC)
        {
            flipLongZone = 0.0;
            tEnt = ask;
            slInicial = srcLow[1] - (currentAtr * atrMult);
            tSl = slInicial;
            tRisk = MathAbs(tEnt - tSl);
            tTp = tEnt + (tRisk * finalRR);
            slTercio = tRisk / 3.0;
            tpDist = MathAbs(tTp - tEnt);
            tStep = 0;
            
            double balance = AccountInfoDouble(ACCOUNT_BALANCE);
            double tSize = SymbolInfoDouble(Symbol(), SYMBOL_TRADE_TICK_SIZE);
            double tValue = SymbolInfoDouble(Symbol(), SYMBOL_TRADE_TICK_VALUE);
            double vStep = SymbolInfoDouble(Symbol(), SYMBOL_VOLUME_STEP);
            double vMin = SymbolInfoDouble(Symbol(), SYMBOL_VOLUME_MIN);
            double vMax = SymbolInfoDouble(Symbol(), SYMBOL_VOLUME_MAX);
            
            double lotes = (balance * (InpRiesgoPct / 100.0)) / ((tRisk / tSize) * tValue);
            lotes = MathFloor(lotes / vStep) * vStep;
            if(lotes < vMin) lotes = vMin;
            if(lotes > vMax) lotes = vMax;
            
            trade.Buy(lotes, Symbol(), ask, slInicial, tTp, "Sniper Long");
        }
        else if (shortC)
        {
            flipShortZone = 0.0;
            tEnt = bid;
            slInicial = srcHigh[1] + (currentAtr * atrMult);
            tSl = slInicial;
            tRisk = MathAbs(tEnt - tSl);
            tTp = tEnt - (tRisk * finalRR);
            slTercio = tRisk / 3.0;
            tpDist = MathAbs(tEnt - tTp);
            tStep = 0;
            
            double balance = AccountInfoDouble(ACCOUNT_BALANCE);
            double tSize = SymbolInfoDouble(Symbol(), SYMBOL_TRADE_TICK_SIZE);
            double tValue = SymbolInfoDouble(Symbol(), SYMBOL_TRADE_TICK_VALUE);
            double vStep = SymbolInfoDouble(Symbol(), SYMBOL_VOLUME_STEP);
            double vMin = SymbolInfoDouble(Symbol(), SYMBOL_VOLUME_MIN);
            double vMax = SymbolInfoDouble(Symbol(), SYMBOL_VOLUME_MAX);
            
            double lotes = (balance * (InpRiesgoPct / 100.0)) / ((tRisk / tSize) * tValue);
            lotes = MathFloor(lotes / vStep) * vStep;
            if(lotes < vMin) lotes = vMin;
            if(lotes > vMax) lotes = vMax;
            
            trade.Sell(lotes, Symbol(), bid, slInicial, tTp, "Sniper Short");
        }
    }
}
