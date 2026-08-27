# Debugging Thin Lines Issue

## Current Status

**Symptom:** Chart shows thin vertical lines instead of proper Renko boxes  
**Expected:** Clear boxes with visible bodies (like reference screenshot)

## Diagnostic Steps

### 1. Enable Verbose Logging

**In indicator inputs:**
```
DIAGNOSTICS:
├─ Verbose Log = true    ← Enable this!
└─ Mean Renko Diagnostics = false
```

### 2. Check Chart Type

**Make sure you select:**
```
RENKO ENGINE:
├─ Chart Type = Renko Chart    ← For Regular Renko
├─ Brick / Step Points = 600
└─ Suppress Candle Wicks = false
```

### 3. Recompile and Attach

1. Open `OVO_Renko_Generator.mq5` in MetaEditor
2. Press **F7** to compile
3. Attach to US30 chart
4. Set inputs as above
5. Click **M61** button
6. Check **Experts** tab in Terminal for output

### 4. Expected Verbose Output

You should see:
```
=== Completed UP brick ===
  Time: 2000.01.01 00:01
  Open: 42000.00
  High: 42006.00
  Low: 42000.00
  Close: 42006.00
  Body: 6.00             ← Should be 6.00 (600 points * 0.01)
  Volume: 1
```

### 5. Check Custom Symbol Properties

In MT5:
1. View → Market Watch
2. Find `US30.M61` symbol
3. Right-click → Specification
4. Check:
   - **Digits:** Should match US30 (usually 2)
   - **Point:** Should be 0.01

---

## Possible Causes

| Issue | Symptom | Fix |
|-------|---------|-----|
| **Open = Close** | Body = 0.00 in logs | Brick calculation broken |
| **Wrong Point** | Body = 0.06 instead of 6.00 | Point value incorrect |
| **Wrong Chart Type** | Using Mean Renko by mistake | Change input to "Renko Chart" |
| **MT5 Rendering** | Logs show correct values | Chart zoom/scale issue |

---

## Quick Test Commands

### Check Symbol Info
```mql5
Print("Symbol: ", _Symbol);
Print("Point: ", SymbolInfoDouble(_Symbol, SYMBOL_POINT));
Print("Digits: ", SymbolInfoInteger(_Symbol, SYMBOL_DIGITS));
Print("Tick Size: ", SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE));
```

### For US30 Expected Values:
- Point: **0.01**
- Digits: **2**
- Tick Size: **0.01**
- Brick size (600 points): **6.00**

---

## If Logs Show Correct Values But Chart Still Shows Lines

This means the brick data is correct but MT5 isn't rendering properly:

### Solution 1: Chart Scale
1. Right-click chart → Properties
2. Ensure "Show OHLC" is enabled
3. Try zooming out (Ctrl + Mouse Wheel)

### Solution 2: Custom Symbol Refresh
1. Close the `US30.M61` chart
2. On source US30 chart, click M61 button again
3. Chart will reopen with fresh data

### Solution 3: Template Reset
1. On generated chart: Chart → Template → Default
2. Reapply any indicators/settings

---

## Next Steps

1. Enable verbose logging
2. Generate chart
3. Copy the brick output from Experts tab
4. Share the output so we can see exact OHLC values

**If brick body shows 6.00 in logs but chart shows lines:**  
→ MT5 rendering issue, not logic problem

**If brick body shows 0.00 in logs:**  
→ Logic problem, Open = Close

---

**Commit:** `1587ab7` - "Add verbose brick logging"
