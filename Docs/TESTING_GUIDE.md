# OVO Renko Generator - Testing Guide

## Test Acceptance Criteria

This document outlines the comprehensive testing procedures to validate the MT5 OVO-Style Renko Generator against the production specification.

## Test Environment Setup

### Prerequisites
- MT5 Terminal with AutoTrading enabled
- Access to broker with tick history (7+ days recommended)
- Test symbols: US30, EURAUD, EURUSD
- Clean chart environment (no conflicting indicators)

### Initial Setup
1. Enable verbose logging: `InpVerboseLog = true`
2. Enable diagnostics: `InpMeanRenkoDiagnostics = true`
3. Use short history initially: `InpHistoryDays = 3`
4. Default brick size: `InpBrickSizePoints = 600`

---

## Test Suite

### 1. Regular Renko Acceptance Test

**Objective**: Validate Regular Renko engine against OVO reference behavior

**Test Steps**:
1. Attach indicator to US30, H1 chart
2. Configure:
   - Chart Type: `RENKO_REGULAR`
   - Brick Size: `600`
   - Period Token: `M61`
3. Click M61 button
4. Wait for rebuild completion
5. Verify generated US30.M61 chart

**Expected Results**:
- ✅ Same direction sequence (bullish/bearish) as OVO
- ✅ Same Open values
- ✅ Same Close values
- ✅ Same reversal points
- ✅ Wick behavior consistent (subject to feed differences)

**Validation Method**:
```
Compare first 50 bricks:
- Count bullish vs bearish: should match reference
- Measure price levels: within 1-2 points tolerance
- Check reversals: occur at same price thresholds
```

**Pass Criteria**: 95%+ agreement with OVO reference data

---

### 2. Mean Renko Acceptance Test

**Objective**: Validate Mean Renko engine with OVO-calibrated geometry

**Test Steps**:
1. Attach indicator to US30, M5 chart
2. Configure:
   - Chart Type: `RENKO_MEAN`
   - Brick Size: `600`
   - Period Token: `M62`
3. Click M62 button
4. Wait for rebuild completion
5. Verify generated US30.M62 chart

**Expected Results**:
- ✅ Body sequence agreement: exact
- ✅ OHLC agreement: exact (within feed tolerance)
- ✅ Step = 600, Body = 1200 geometry
- ✅ Continuation at 1x step from midpoint
- ✅ Reversal at 3x step from midpoint
- ✅ Bullish high capped at body close
- ✅ Bearish low capped at body close
- ✅ Opposite-side wicks allowed

**Validation Method**:
```
For first 20 completed bricks:
1. Measure body size: should be 1200 ± 5 points
2. Calculate midpoint: (open + close) / 2
3. Verify next brick open positioned around midpoint
4. Check wick direction: only opposite to trend
```

**Pass Criteria**: All geometric rules satisfied, live alignment with OVO behavior

---

### 3. Live Forming Candle Test

**Objective**: Ensure forming candle updates continuously with price movement

**Test Steps**:
1. Generate any Renko chart (Regular or Mean)
2. Wait for rebuild to complete and LIVE state
3. Open source chart (US30) and generated chart (US30.M61) side-by-side
4. Monitor for 5 minutes during active market

**Expected Results**:
- ✅ Source Bid/Ask lines update continuously
- ✅ Forming Renko candle high/low update with price
- ✅ Forming candle close tracks current price
- ✅ NO freezing: if Bid moves, forming candle must update

**Failure Condition** (RELEASE BLOCKER):
```
Bid/Ask moved +10 points
BUT
Forming Renko candle remained frozen
```

**Validation Method**:
- Visual observation: both charts update together
- Check timestamp: last update <1 second ago
- Monitor terminal log for errors

**Pass Criteria**: Zero freezing incidents in 5-minute observation

---

### 4. Same-Millisecond Tick Test

**Objective**: Verify all same-ms ticks are processed

**Test Steps**:
1. Enable verbose logging
2. Attach indicator to high-frequency symbol (US30)
3. Generate Renko chart during active market
4. Check Experts log for tick processing

**Expected Results**:
```
Given ticks:
  Tick A: 12:00:00.123  Bid 53500.0
  Tick B: 12:00:00.123  Bid 53500.4
  Tick C: 12:00:00.123  Bid 53500.8

Expected output:
  Retrieved 3 new ticks
  Processing tick 1/3
  Processing tick 2/3
  Processing tick 3/3
```

**Validation Method**:
- Check log: "Retrieved X new ticks" where X ≥ 1
- Verify: No "duplicate tick skipped" warnings
- Confirm: Same-ms ticks show different Bid values

**Pass Criteria**: All unique ticks processed, no intentional loss

---

### 5. Multi-Brick Processing Test

**Objective**: Verify fast movements generate multiple bricks

**Test Steps**:
1. Use smaller brick size for easier testing: `300 points`
2. Generate Renko chart
3. Wait for news event or high volatility
4. Check for multi-brick generation

**Expected Behavior**:
```
If price jumps 900 points in one tick:
  → 3 bricks should be generated
  → No missing intermediate bricks
```

**Validation Method**:
- Enable verbose log
- Look for: "Completed X bricks" where X > 1
- Check chart: continuous brick sequence, no gaps
- Verify OHLC: each brick properly positioned

**Test Case Example**:
```
Starting price: 53500
Tick arrives: 53950 (+450 points = 1.5x brick)
Expected: 1 completed brick + forming brick updated

Next tick: 54250 (+750 points = 2.5x brick from start)
Expected: 2 more completed bricks
Total: 3 completed bricks in sequence
```

**Pass Criteria**: Multi-brick generation working, no gaps in chart

---

### 6. Restart Auto-Resume Test

**Objective**: Verify generator resumes after MT5 restart

**Test Steps**:
1. Generate Renko chart with test EA/indicators attached:
   - Attach: Moving Average (14, EMA)
   - Attach: Simple test EA
   - Add: Horizontal line object
2. Verify LIVE state
3. Check persistence saved:
   ```
   Global Variables:
   OVORenko_US30_M61_Active = 1.0
   OVORenko_US30_M61_BrickSize = 600.0
   ```
4. Close MT5 completely
5. Restart MT5
6. Wait for source chart and indicator to restore

**Expected Results**:
- ✅ US30.M61 chart restored by MT5
- ✅ Moving Average retained on Renko chart
- ✅ Test EA retained and running
- ✅ Horizontal line object present
- ✅ Generator auto-resumes to LIVE state
- ✅ History regenerated automatically
- ✅ Live processing continues
- ✅ NO manual button click required

**Validation Method**:
1. Check US30.M61 chart exists after restart
2. Verify indicators present: should see EMA line
3. Confirm EA running: check Experts tab
4. Observe live updates: forming candle updates
5. Check global variables still set

**Pass Criteria**: Complete restoration with no manual intervention

---

### 7. Rebuild Acceptance Test

**Objective**: Verify chart rebuilds correctly when brick size changes

**Test Steps**:
1. Generate initial chart: brick size `600`, token `M61`
2. Wait for LIVE state
3. Attach test indicators to US30.M61:
   - Moving Average (20, SMA)
   - RSI (14)
4. Add chart objects (trend line, arrows)
5. Change brick size: `600` → `1200`
6. Click M61 button
7. Monitor rebuild process

**Expected Results**:
- ✅ Same US30.M61 chart updated (not duplicated)
- ✅ History rebuilt with new brick size
- ✅ Moving Average retained on chart
- ✅ RSI retained on chart
- ✅ Objects retained
- ✅ Chart refreshed showing new bricks
- ✅ NO duplicate US30.M61 chart created
- ✅ NO need to manually close old chart
- ✅ Live processing resumes at new brick size

**Failure Scenarios to Check**:
- ❌ Two US30.M61 charts exist
- ❌ Indicators disappeared
- ❌ Chart frozen, not updating

**Pass Criteria**: Single chart updated seamlessly with attachments preserved

---

### 8. Multiple Instance Test

**Objective**: Verify multiple generators run independently

**Test Steps**:
1. Attach Generator A to US30, H1:
   - Type: Mean Renko
   - Brick: 600
   - Token: M61
2. Attach Generator B to US30, H4:
   - Type: Regular Renko
   - Brick: 1200
   - Token: M62
3. Attach Generator C to EURAUD, M5:
   - Type: Mean Renko
   - Brick: 300
   - Token: M2
4. Generate all three charts

**Expected Results**:
- ✅ Three separate custom charts exist:
  - US30.M61 (Mean, 600)
  - US30.M62 (Regular, 1200)
  - EURAUD.M2 (Mean, 300)
- ✅ Each updates independently
- ✅ Each maintains separate state
- ✅ No interference between instances
- ✅ Each has own persistence

**Validation Method**:
- Check Symbol → Custom folder shows 3 symbols
- Verify different brick counts on each chart
- Change one brick size: others unaffected
- Check global variables: 3 sets exist

**Pass Criteria**: All instances operate independently without conflict

---

### 9. Performance Test - No New Tick

**Objective**: Validate <1ms performance for no-new-tick events

**Test Steps**:
1. Generate Renko chart and reach LIVE state
2. Wait for market pause (low volatility period)
3. Enable profiler or time logging
4. Monitor 100+ timer events with no new ticks

**Expected Results**:
- ✅ Timer callback execution: <1ms per call
- ✅ No "indicator is too slow" warnings
- ✅ CPU usage: minimal (<5%)
- ✅ Fast-path optimization working:
  ```
  HasNewTick() = false
  → Immediate return
  → No CopyTicksRange
  → No CustomRatesUpdate
  → No chart operations
  ```

**Validation Method**:
```cpp
// Add timing to OnTimer():
uint start = GetTickCount();
ProcessLiveTicks();
uint elapsed = GetTickCount() - start;
if(elapsed > 1)
   Print("WARNING: Slow tick processing: ", elapsed, " ms");
```

**Pass Criteria**: 95%+ of no-tick events complete in <1ms

---

### 10. Performance Test - Historical Build

**Objective**: Verify asynchronous rebuild with no blocking

**Test Steps**:
1. Set rebuild budget: `InpRebuildBudgetMs = 8`
2. Set history: `InpHistoryDays = 7`
3. Attach indicator
4. Click period button
5. During rebuild:
   - Try to open another chart
   - Try to attach different indicator
   - Try to scroll source chart
   - Monitor progress percentage

**Expected Results**:
- ✅ Terminal remains responsive during rebuild
- ✅ Other charts/indicators work normally
- ✅ Source chart scrollable
- ✅ Progress updates: 1% → 10% → 25% → 50% → 100%
- ✅ Each rebuild pass: ~8ms CPU time
- ✅ NO "indicator is too slow" error
- ✅ Total rebuild time: reasonable (30-120 seconds for 7 days)

**Failure Condition**:
```
Terminal freezes for 3+ seconds
User cannot interact with MT5
```

**Pass Criteria**: Terminal fully responsive, progress visible, build completes

---

### 11. Tick Cache Test

**Objective**: Verify tick cache accelerates repeated rebuilds

**Test Steps**:
1. Enable tick cache: `InpEnableTickCache = true`
2. Generate chart: brick size `600`
3. Note rebuild time (T1)
4. Immediately rebuild with brick size `1200`
5. Note rebuild time (T2)
6. Rebuild again with brick size `300`
7. Note rebuild time (T3)

**Expected Results**:
- ✅ T1: Initial load (slowest) - loading ticks from disk
- ✅ T2: Much faster (cache hit) - reusing cached ticks
- ✅ T3: Similar to T2 (cache reuse)
- ✅ Speed improvement: 50-80% faster
- ✅ Memory usage: acceptable (<200MB for 7 days)

**Validation Method**:
- Enable verbose log
- Check for: "Loaded X ticks into cache"
- Second rebuild: "Tick cache already loaded and valid"
- Compare timestamps: T2 ≈ 0.2 * T1

**Pass Criteria**: Cached rebuilds at least 3x faster than initial load

---

### 12. Chart M1 Enforcement Test

**Objective**: Verify Renko chart stays on M1 carrier

**Test Steps**:
1. Generate US30.M61 chart
2. Try to change timeframe to M5
3. Wait 2 seconds
4. Check current timeframe
5. Repeat with H1, H4, D1

**Expected Results**:
- ✅ Chart automatically returns to M1
- ✅ No error messages
- ✅ Chart does NOT come to foreground
- ✅ Enforcement happens silently
- ✅ User can navigate away from Renko chart

**Failure Condition**:
```
User switches to H1
Chart stays on H1 permanently
M1 carrier violated
```

**Pass Criteria**: Chart always returns to M1, no disruption to user

---

### 13. Trade Overlay Test

**Objective**: Validate position display on Renko chart

**Test Steps**:
1. Generate US30.M61 chart
2. Open demo position on US30:
   - Type: BUY
   - Volume: 0.10
   - Entry: 53500
   - SL: 53450 (-50 points)
   - TP: 53600 (+100 points)
3. Switch to US30.M61 Renko chart
4. Wait 1 second for overlay update

**Expected Results**:
- ✅ Entry line visible at 53500
- ✅ Entry label: "BUY 0.10"
- ✅ SL line visible at 53450
- ✅ SL label: "SL: - $XX.XX" (calculated)
- ✅ TP line visible at 53600
- ✅ TP label: "TP: + $XX.XX" (calculated)
- ✅ Source Bid/Ask lines visible
- ✅ All labels positioned clearly

**Validation Method**:
- Visual check: all lines present
- Verify colors: Entry=Blue/Red, SL=Red, TP=Green
- Check monetary calculation accuracy
- Confirm lines at correct price levels

**Pass Criteria**: All position elements visible and accurate

---

### 14. Panel UI Test

**Objective**: Verify OVO-style panel functionality

**Test Steps**:
1. Attach indicator
2. Observe panel appearance
3. Test brick field editing:
   - Click field
   - Enter new value: `1200`
   - Click period button
4. Test period button:
   - Click multiple times
   - Verify rebuild triggers
5. Test close button:
   - Click X
   - Verify indicator removes

**Expected Results**:
- ✅ Panel height: ~24px
- ✅ Panel width: matches chart width
- ✅ Brick field editable
- ✅ Period button clickable
- ✅ Close button works
- ✅ Status text updates
- ✅ Layout: compact, professional
- ✅ No large empty areas

**Visual Validation**:
```
[Mean Renko:] [600] [M61]     OVO C2    [X]
              ↑     ↑          ↑         ↑
           editable button   status   close
```

**Pass Criteria**: All controls functional, professional appearance

---

### 15. Persistence Clear Test

**Objective**: Verify explicit removal disables auto-resume

**Test Steps**:
1. Generate Renko chart, reach LIVE state
2. Verify global variables set
3. Click [X] close button on panel
4. Check global variables: should show Active = 0.0
5. Close MT5
6. Restart MT5

**Expected Results**:
- ✅ Indicator removed from source chart
- ✅ Global variable: `OVORenko_US30_M61_Active = 0.0`
- ✅ After restart: NO auto-regeneration
- ✅ US30.M61 chart may remain (MT5 profile) but not regenerated
- ✅ No live processing

**Pass Criteria**: Explicit removal prevents auto-resume

---

## Performance Benchmarks

### Target Metrics

| Metric | Target | Test Method |
|--------|--------|-------------|
| No-tick event | <1ms | Profiler during quiet period |
| Live tick processing | <5ms | Average over 1000 ticks |
| Rebuild pass | ~8ms | Default budget, measure actual |
| Historical build (7 days) | 30-120s | Full reconstruction |
| Cached rebuild | <30s | Second rebuild after cache |
| Same-ms tick handling | Zero loss | Compare input vs processed |
| Multi-brick generation | 100% accurate | Validate all bricks created |
| Memory usage | <300MB | Task Manager during operation |

---

## Regression Test Checklist

Run before each release:

- [ ] Regular Renko accuracy ≥95%
- [ ] Mean Renko geometry correct
- [ ] Live forming candle never freezes
- [ ] Same-ms ticks processed
- [ ] Multi-brick generation works
- [ ] Restart auto-resume works
- [ ] Rebuild preserves attachments
- [ ] Multiple instances independent
- [ ] No-tick event <1ms
- [ ] Async rebuild non-blocking
- [ ] Tick cache accelerates rebuilds
- [ ] M1 enforcement works
- [ ] Trade overlay accurate
- [ ] Panel UI functional
- [ ] Persistence clear works

---

## Known Limitations

### Feed Differences
- Broker tick feeds vary
- Exact OHLC match with OVO requires identical feed
- Tolerance: ±2 points acceptable

### MT5 Constraints
- Custom symbols must use M1 carrier
- CustomRatesUpdate has 4096 bar limit per call
- Multi-brick generation limited to 100 per tick (safety)

### Performance Trade-offs
- Larger history = longer initial build
- More instances = higher CPU usage
- Tick cache = memory usage

---

## Debugging Tools

### Verbose Logging
Enable: `InpVerboseLog = true`
Output: Experts tab
Contains: Tick counts, state transitions, timing

### Diagnostics CSV
Enable: `InpMeanRenkoDiagnostics = true`
File: `MeanRenko_Diagnostic_<SYMBOL>.csv`
Contains: Event log with price, bricks, forming state

### Global Variables
Check: Tools → Global Variables
Prefix: `OVORenko_<SYMBOL>_<TOKEN>_`
Contains: Active state, brick size, chart ID

### Profiler
MQL5 Profiler: Tools → Options → Expert Advisors → Enable
Shows: Function timing, hotspots

---

## Test Reports

### Report Template

```
Test: [Test Name]
Date: [YYYY-MM-DD]
Tester: [Name]
MT5 Build: [Build Number]
Broker: [Broker Name]

Configuration:
- Symbol: [Symbol]
- Brick Size: [Points]
- History Days: [Days]
- Chart Type: [Regular/Mean]

Results:
[✅/❌] Criterion 1: [Details]
[✅/❌] Criterion 2: [Details]
...

Performance:
- Rebuild time: [Seconds]
- No-tick average: [ms]
- Live tick average: [ms]

Issues Found:
- [Issue 1]
- [Issue 2]

Conclusion: [PASS/FAIL/PARTIAL]
```

---

## Continuous Testing

### Daily Tests (During Development)
- Live forming candle
- No-tick performance
- Basic rebuild

### Weekly Tests (Pre-Release)
- Full regression checklist
- Multiple symbol test
- Stress test (10+ instances)

### Release Tests (Before Production)
- All 15 acceptance tests
- Performance benchmarks
- 24-hour stability test
- Multi-broker validation

---

## Test Data Requirements

### Historical Data
- Minimum: 3 days tick history
- Recommended: 7 days
- Optimal: 30 days for stress testing

### Symbols
- Primary: US30 (high volatility, good for multi-brick)
- Secondary: EURAUD (moderate activity)
- Tertiary: EURUSD (high liquidity)

### Market Conditions
- Test during: Active trading hours
- Avoid: Market open/close (abnormal behavior)
- Include: News events (high volatility)

---

## Success Criteria Summary

A release is ready when:

1. ✅ All 15 acceptance tests pass
2. ✅ Performance benchmarks met
3. ✅ Zero release blockers:
   - No forming candle freezing
   - No tick loss
   - No multi-second blocking
4. ✅ Regression checklist complete
5. ✅ Documentation updated
6. ✅ Known issues documented

**Release Blocker Conditions**:
- Forming candle freezes while price moving
- Intentional tick loss (beyond broker feed)
- Indicator blocking >3 seconds
- Auto-resume completely broken
- Critical crash/error in normal operation
