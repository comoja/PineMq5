import re

replacements = {
    "alert_msg": "alertMsg",
    "bars_since_cross": "barsSinceCross",
    "base_json": "baseJson",
    "be_activated": "beActivated",
    "be_trail_dist": "beTrailDist",
    "bypass_adx": "bypassAdx",
    "cruces_ema": "crucesEma",
    "current_daily_drawdown": "currentDailyDrawdown",
    "current_day": "currentDay",
    "current_entry_price": "currentEntryPrice",
    "current_qty": "currentQty",
    "current_rr_mult": "currentRrMult",
    "daily_loss_limit_hit": "dailyLossLimitHit",
    "debug_txt": "debugTxt",
    "distancia_sl": "distanciaSl",
    "dynamic_tp_activated": "dynamicTpActivated",
    "entry_atr": "entryAtr",
    "entry_price": "entryPrice",
    "exit_price": "exitPrice",
    "filtro_adx": "filtroAdx",
    "filtro_chop": "filtroChop",
    "filtro_sesion": "filtroSesion",
    "filtro_volumen": "filtroVolumen",
    "in_session": "inSession",
    "is_lateral": "isLateral",
    "last_entry_bar": "lastEntryBar",
    "last_trades_count": "lastTradesCount",
    "meta_be": "metaBe",
    "original_tp": "originalTp",
    "p_entry": "pEntry",
    "p_sl": "pSl",
    "p_tp": "pTp",
    "pc_license_id": "pcLicenseId",
    "pc_symbol": "pcSymbol",
    "pendiente_rapida": "pendienteRapida",
    "prev_pos": "prevPos",
    "qty_correct": "qtyCorrect",
    "riesgo_monetario": "riesgoMonetario",
    "spread_ticks": "spreadTicks",
    "start_of_day_equity": "startOfDayEquity",
    "symbol_to_send": "symbolToSend",
    "tiene_vol": "tieneVol",
    "use_pc": "usePc",
    "vol_ma": "volMa",
    
    "body_pct": "bodyPct",
    "future_high": "futureHigh",
    "future_low": "futureLow",
    "fvg_group_high": "fvgGroupHigh",
    "fvg_group_high_cbi": "fvgGroupHighCbi",
    "fvg_group_low": "fvgGroupLow",
    "fvg_group_low_cbi": "fvgGroupLowCbi",
    "get_primer_maximo": "getPrimerMaximo",
    "get_primer_minimo": "getPrimerMinimo",
    "is_pivot": "isPivot",
    "lower_wick": "lowerWick",
    "lower_wick_pct": "lowerWickPct",
    "ltf_h0": "ltfHigh0",
    "ltf_h2": "ltfHigh2",
    "ltf_l0": "ltfLow0",
    "ltf_l2": "ltfLow2",
    "past_high": "pastHigh",
    "past_low": "pastLow",
    "upper_wick": "upperWick",
    "upper_wick_pct": "upperWickPct",
    "atr_val": "atrVal",
    "max_high": "maxHigh",
    "current_valley": "currentValley",
    "found_valley": "foundValley",
    "min_low": "minLow",
    "current_peak": "currentPeak",
    "found_peak": "foundPeak",
    "candle3_range": "candle3Range",
    "candle3_body": "candle3Body",
}

files = ['2EMAs.pine', 'liquidezIneficiencias.pine']

for filename in files:
    with open(filename, 'r') as f:
        content = f.read()
    
    for old, new in replacements.items():
        content = re.sub(r'\b' + old + r'\b', new, content)
        
    with open(filename, 'w') as f:
        f.write(content)
print("Done")
