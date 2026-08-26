# Quick Start Guide - OVO Renko Generator

## Installation (3 Minutes)

1. **Copy Files to MT5**
   ```
   Copy the entire Nortrading-Renko folder to:
   <MT5_DATA_FOLDER>/MQL5/
   ```

2. **Compile Indicator**
   - Open MetaEditor (F4 from MT5)
   - Navigate to: Indicators/OVO_Renko_Generator.mq5
   - Press F7 to compile
   - Check for errors (should compile clean)

3. **Enable AutoTrading**
   - MT5: Tools → Options → Expert Advisors
   - Check: "Allow automated trading"
   - Check: "Allow DLL imports" (not required but recommended)

## First Renko Chart (2 Minutes)

### Step 1: Attach Indicator
1. Open any broker chart (e.g., US30, H1)
2. Navigator → Indicators → Custom → OVO_Renko_Generator
3. Drag to chart or double-click
4. **Leave default settings** for first test
5. Click OK

**Result**: Compact control panel appears at bottom

### Step 2: Generate Chart
1. Click the **M61** button (blue button in panel)
2. Watch status: "Rebuilding 0%" → "Rebuilding 100%"
3. Wait for completion (typically 10-60 seconds)

**Result**: US30.M61 chart opens automatically

### Step 3: Verify Live Processing
1. Check panel status shows: **LIVE**
2. Observe forming Renko candle updating
3. Source Bid/Ask lines visible (dotted red/blue)

✅ **Success!** You have a working Renko chart.

---

## Common First-Time Settings

### Use Mean Renko (Recommended)
```
Chart Type: Mean Renko
Brick / Step Points: 600
```

### Use Regular Renko
```
Chart Type: Regular Renko
Brick / Step Points: 600
```

### Adjust Brick Size
```
Edit the [600] field in panel
Enter new value (e.g., 1200)
Click M61 button
Chart rebuilds automatically
```

### Use Custom Period Token
```
Custom Period ID: M2
Result: EURAUD.M2 chart generated
```

---

## What You'll See

### Control Panel
```
┌────────────────────────────────────────────────┐
│ Mean Renko: [600] [M61]    OVO C2      [X]    │
└────────────────────────────────────────────────┘
```

### Renko Chart (US30.M61)
- True M1 custom symbol
- Renko candles with proper OHLC
- Source Bid/Ask lines (if enabled)
- Can attach indicators (MA, RSI, etc.)
- Can attach EAs for trading
- Can draw objects

### During Rebuild
```
Panel shows: "Rebuilding 23%"
Terminal stays responsive
Can work on other charts
```

### When Live
```
Panel shows: "LIVE"
Forming candle updates continuously
New bricks appear as thresholds cross
```

---

## Testing Your Installation

### Test 1: Basic Generation
- Attach indicator to US30
- Click M61
- Wait for "LIVE"
- ✅ Pass: Chart generated and updating

### Test 2: Brick Size Change
- Edit [600] → [1200]
- Click M61
- Wait for rebuild
- ✅ Pass: Chart updated with larger bricks

### Test 3: Multiple Instances
- Attach to US30 with M61
- Attach to US30 again with M62
- Click both buttons
- ✅ Pass: US30.M61 and US30.M62 both exist

### Test 4: Restart Resume
- Generate any Renko chart
- Wait for "LIVE"
- Close MT5 completely
- Restart MT5
- ✅ Pass: Chart regenerated automatically

---

## Troubleshooting

### Panel Appears But No Chart
**Problem**: Clicked M61, nothing happens
**Solution**:
1. Check AutoTrading enabled
2. Check Experts tab for errors
3. Try different symbol (EURUSD)
4. Reduce History Days to 3

### Chart Not Updating
**Problem**: Chart frozen, no new bricks
**Solution**:
1. Check panel status: should show "LIVE"
2. Check source symbol has ticks
3. Remove and reattach indicator
4. Check Experts tab for errors

### "Indicator is too slow" Warning
**Problem**: MT5 shows performance warning
**Solution**:
1. Reduce History Days: 7 → 3
2. Increase Rebuild Budget: 8 → 15ms
3. Disable diagnostics
4. Use tick cache (should be enabled by default)

### No Source Bid/Ask Lines
**Problem**: Missing price lines on Renko chart
**Solution**:
1. Check: Show Source Bid/Ask = Yes
2. Wait 1-2 seconds for overlay update
3. Verify source symbol name matches

### Chart Jumps to Different Timeframe
**Problem**: Changed to H1, stays on H1
**Solution**:
- This is normal briefly
- Chart auto-returns to M1 within 2 seconds
- M1 is the carrier timeframe (required)

---

## Next Steps

### Learn More
- Read: README.md (full features)
- Read: Docs/ARCHITECTURE.md (technical details)
- Read: Docs/TESTING_GUIDE.md (validation)

### Customize Settings
```cpp
=== RENKO ENGINE ===
Chart Type: Regular / Mean
Brick Size: Your preference
Suppress Wicks: Usually No

=== CUSTOM CHART ===
Period Token: M61, M62, M2, etc.
History Days: 7 (more = slower initial build)

=== LIVE FEED ===
Live Pump: 20ms (lower = more responsive, higher CPU)

=== PERFORMANCE ===
Rebuild Budget: 8ms (increase if slow warning)
Tick Cache: Yes (faster rebuilds)

=== TRADE DISPLAY ===
Show Source Bid/Ask: Yes
Show Entry/SL/TP: Yes
Show Monetary Labels: Yes
```

### Advanced Usage
1. **Attach EAs**: Drag EA to Renko chart for algo trading
2. **Add Indicators**: Standard MT5 indicators work
3. **Draw Objects**: Trend lines, S/R levels work normally
4. **Export Data**: Renko bars available via CopyRates()
5. **Multiple Symbols**: Run on EURUSD, GBPUSD, US30, etc.

---

## Tips for Best Results

### 1. Choose Appropriate Brick Size
```
Scalping: 100-300 points
Day Trading: 400-800 points
Swing Trading: 1000-2000 points

Symbol-dependent:
US30: 200-800 typical
EURUSD: 50-200 typical
```

### 2. Use Mean Renko for Smoother Charts
- Less noise than Regular Renko
- Better trend visualization
- OVO-calibrated geometry

### 3. Enable Tick Cache
- First build: slower (loads history)
- Subsequent: much faster (reuses cache)
- Rebuilding different brick sizes: instant

### 4. Start with Short History
- Test with 3 days first
- Increase to 7 days when confident
- 30 days only if needed (slower)

### 5. Monitor Panel Status
```
"OVO C2"        → Ready, no chart
"Rebuilding X%" → Building history
"LIVE"          → Processing real-time
"ERROR: ..."    → Problem occurred
```

---

## Keyboard Shortcuts

```
F4                  → Open MetaEditor
F7 (in MetaEditor)  → Compile indicator
Ctrl+I              → Indicators dialog
Ctrl+O              → Options dialog
Ctrl+T              → Terminal window (check Experts tab)
```

---

## Support Resources

### Documentation
- `README.md` - Complete feature overview
- `Docs/ARCHITECTURE.md` - Technical architecture
- `Docs/TESTING_GUIDE.md` - Comprehensive testing

### GitHub
- Issues: Report bugs or request features
- Discussions: Ask questions, share experiences
- Wiki: Additional guides and examples

### Community
- Share your configurations
- Post screenshots of your Renko charts
- Help other users getting started

---

## Success Checklist

Before considering your installation complete:

- [x] Compiled without errors
- [x] Generated first Renko chart
- [x] Status shows "LIVE"
- [x] Forming candle updates
- [x] Changed brick size successfully
- [x] Tested restart resume
- [x] Understand panel controls

If all checked, you're ready for production use!

---

## Example Configurations

### Day Trader Setup
```
Symbol: US30
Type: Mean Renko
Brick: 600
Token: M61
History: 7 days
Live Pump: 20ms
```

### Scalper Setup
```
Symbol: EURUSD
Type: Regular Renko
Brick: 100
Token: M2
History: 3 days
Live Pump: 10ms
```

### Swing Trader Setup
```
Symbol: EURAUD
Type: Mean Renko
Brick: 1500
Token: M61
History: 30 days
Live Pump: 50ms
```

---

## What's Next?

1. **Experiment**: Try different brick sizes
2. **Attach Indicators**: Add your favorite indicators
3. **Backtest Strategies**: Use Strategy Tester with Renko
4. **Develop EAs**: Code algorithms for Renko charts
5. **Share Results**: Help community with feedback

---

## Need Help?

### Check Experts Tab First
```
MT5 Terminal → Experts tab
Look for:
- Errors in red
- Warnings in yellow
- Info in white
```

### Enable Verbose Logging
```
Indicator Inputs:
Verbose Log: Yes

Reattach indicator
Check Experts tab for detailed info
```

### Common Log Messages
```
"Panel created successfully"        → ✅ Good
"Historical build started"          → ✅ Good
"Build completed: X bricks"         → ✅ Good
"State: LIVE"                       → ✅ Good
"ERROR: Failed to create symbol"    → ❌ Problem
"ERROR: Failed to load ticks"       → ❌ Problem
```

---

## Final Note

The OVO Renko Generator is designed to work "out of the box" with minimal configuration. If you experience issues, check:

1. AutoTrading is enabled
2. Symbol has tick history (broker-dependent)
3. No conflicting indicators attached
4. Clean MT5 environment (restart if needed)

Most issues resolve with a simple MT5 restart. The indicator includes robust error handling and will guide you through any problems via panel status messages.

**Happy Trading with Renko Charts!** 🚀
