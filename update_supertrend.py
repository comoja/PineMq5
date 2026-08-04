import re

with open('/Volumes/TimeMachine/Pine/SupertrendEMA.pine', 'r') as f:
    content = f.read()

# Replace inputs with var definitions
content = re.sub(r'riesgo_perc = input\.float\(([\d\.]+)[^\)]+\)', r'var float riesgoPerc = \1', content)
content = re.sub(r'minRR = input\.float\(([\d\.]+)[^\)]+\)', r'var float minRR = \1', content)
content = re.sub(r'emaFastPeriod = input\.int\(([\d]+)[^\)]+\)', r'var int emaFastPeriod = \1', content)
content = re.sub(r'emaSlowPeriod = input\.int\(([\d]+)[^\)]+\)', r'var int emaSlowPeriod = \1', content)
content = re.sub(r'atrPeriod = input\.int\(([\d]+)[^\)]+\)', r'var int atrPeriod = \1', content)
content = re.sub(r'factor = input\.float\(([\d\.]+)[^\)]+\)', r'var float factor = \1', content)
content = re.sub(r'use_pc\s*=\s*input\.bool\((true|false)[^\)]+\)', r'var bool usePc = \1', content)
content = re.sub(r'pc_license_id\s*=\s*input\.string\("([^"]+)"[^\)]+\)', r'var string pcLicenseId = "\1"', content)
content = re.sub(r'pc_symbol\s*=\s*input\.string\("([^"]*)"[^\)]+\)', r'var string pcSymbol = "\1"', content)

# Variable names
replacements = {
    'riesgo_perc': 'riesgoPerc',
    'use_pc': 'usePc',
    'pc_license_id': 'pcLicenseId',
    'pc_symbol': 'pcSymbol',
    'atr_mult': 'atrMult',
    'vol_mult': 'volMult',
    'ny_time': 'nyTime',
    'en_sesion': 'enSesion',
    'ema9': 'emaFast',
    'ema21': 'emaSlow',
    'atr14': 'atrVal',
    'vol_sma': 'volSma',
    'tiene_vol': 'tieneVol',
    'vol_alto': 'volAlto',
    'supertrend': 'superTrend',
    'cruceAlcista': 'cruceAlcista',
    'cruceBajista': 'cruceBajista',
    'longC': 'longCond',
    'shortC': 'shortCond',
    'in_long': 'inLong',
    'in_short': 'inShort',
    'original_tp': 'originalTp',
    'sl_ini': 'slIni',
    'current_rr_mult': 'currentRrMult',
    'tp_fijo': 'tpFijo',
    'distancia_sl': 'distanciaSl',
    'riesgo_monetario': 'riesgoMonetario',
    'qty_correct': 'qtyCorrect',
    'entry_price': 'entryPrice',
    'current_entry_price': 'currentEntryPrice',
    'p_sl': 'pSl',
    'p_tp': 'pTp',
    'p_entry': 'pEntry',
    'prev_pos': 'prevPos',
    'symbol_to_send': 'symbolToSend',
    'alert_msg': 'alertMsg',
}

for old, new in replacements.items():
    # Only replace exact word boundaries to avoid partial matches
    content = re.sub(r'\b' + old + r'\b', new, content)

# Clean up any missed 'ta.superTrend' that shouldn't have been capitalized
content = content.replace('ta.superTrend', 'ta.supertrend')

with open('/Volumes/TimeMachine/Pine/SupertrendEMA.pine', 'w') as f:
    f.write(content)

print("Done")
