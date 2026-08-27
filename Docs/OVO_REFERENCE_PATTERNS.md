# OVO Reference File Pattern Analysis

## Critical Architectural Patterns to Replicate

### 1. STATE MACHINE ARCHITECTURE
Reference file uses a clear state machine with these phases:
- **INIT**: Initial setup
- **HISTORICAL_BUILD**: Async historical data processing
- **LIVE**: Real-time tick processing
- **ERROR**: Error handling states

### 2. TICK PROCESSING FLOW (from reference lines ~1520-1603)

**Pattern: Save prior extremes BEFORE processing tick**
```
ProcessPrice(tick):
    1. Save current extremes as prior_high, prior_low
    2. Update current high/low with tick
    3. Check brick completion thresholds
    4. If brick completes → use saved prior extremes
    5. New brick uses last_close as reference
```

**Key insight**: First brick after initialization uses prior extremes, subsequent bricks use last_close.

### 3. REGULAR RENKO BRICK COMPLETION (from reference lines ~410-477)

**UP BRICK Pattern**:
```
CompleteUpBrick():
    brick.open = last_close
    brick.low = last_close
    brick.high = last_close + brick_size
    brick.close = brick.high
    
    // Wick handling
    if current_high > brick.high:
        brick.high = current_high  // Extend wick
```

**DOWN BRICK Pattern**:
```
CompleteDownBrick():
    brick.open = last_close
    brick.high = last_close
    brick.low = last_close - brick_size
    brick.close = brick.low
    
    // Wick handling
    if current_low < brick.low:
        brick.low = current_low  // Extend wick
```

**REVERSAL Logic** (2-brick reversal):
```
If trend is UP and price drops by 2*brick_size:
    → Complete 2 DOWN bricks
    → Switch trend to DOWN
```

### 4. MEAN RENKO PROCESSING (from reference lines ~869-997)

**Directional Wick Clipping Pattern**:
```
ProcessMeanRenko():
    midpoint = (prior_high + prior_low) / 2
    
    IF trend is UP:
        brick.open = midpoint
        brick.high = current_high (capped at max wick)
        brick.low = MIN(prior_low, current_low)  // Allow downside wick
        brick.close = current_high
    
    IF trend is DOWN:
        brick.open = midpoint
        brick.low = current_low (capped at max wick)
        brick.high = MAX(prior_high, current_high)  // Allow upside wick
        brick.close = current_low
```

**Key insight**: Wicks extend AGAINST the trend direction.

### 5. TIMESTAMP SEQUENCING (from reference lines ~337-343)

**Pattern: Fixed 60-second spacing**:
```
CompleteAnyBrick():
    brick.time = g_next_bar_time
    g_next_bar_time += 60  // Add 60 seconds
```

**NOT** based on actual tick times - uses sequential synthetic timestamps.

### 6. HISTORICAL BUILD PATTERN (from reference lines ~1200-1350)

**Critical: Persistent engine across passes**:
```
class HistoricalBuilder:
    Engine* m_engine  // Created ONCE in StartBuild()
    
    StartBuild():
        m_engine = new Engine()
        m_engine.Initialize()
    
    ProcessPass():
        // Use SAME engine for all passes
        for each bar:
            m_engine.ProcessPrice()
    
    Complete():
        delete m_engine
```

**Anti-pattern** (what we had before):
```
// ❌ WRONG - creates new engine each pass
ProcessPass():
    Engine* temp = new Engine()
    temp.ProcessPrice()
    delete temp  // Lost all state!
```

### 7. CUSTOM SYMBOL CREATION (from reference lines ~250-280)

**Pattern: Simple folder structure**:
```
CreateCustomSymbol():
    symbol_name = "Renko\\" + source + "_" + token
    
    if CustomSymbolCreate(symbol_name):
        success
    else if GetLastError() == 5304:  // Already exists
        success  // Treat as success
    else:
        fail
```

### 8. CHART MANAGEMENT (from reference lines ~1400-1450)

**Pattern: Conditional chart switching**:
```
OpenChart(switch_to_chart):
    existing = FindChart()
    if existing:
        if switch_to_chart:
            BringToTop(existing)
        return existing
    
    new_chart = ChartOpen()
    if switch_to_chart:
        BringToTop(new_chart)
    return new_chart
```

## Current Implementation Status

| Pattern | Status | Notes |
|---------|--------|-------|
| State machine | ✅ Implemented | Working |
| Prior extremes save | ✅ Implemented | Lines 1520-1603 pattern |
| Brick completion logic | ✅ Implemented | Lines 410-477 pattern |
| Mean Renko wicks | ✅ Implemented | Lines 869-997 pattern |
| Timestamp sequencing | ✅ Implemented | 60-second spacing |
| Persistent historical engine | ✅ Fixed | Was broken, now fixed |
| Custom symbol creation | ✅ Implemented | Simple "Renko" folder |
| Conditional chart switch | ✅ Fixed | Only on button click |

## Remaining Issues to Diagnose

### Issue #1: Thin Lines Instead of Boxes
**Hypothesis**: Either Open=Close or rendering issue
**Diagnostic needed**: Verbose log output showing actual OHLC values

**Expected log output**:
```
UP Brick: O=1.08450 H=1.08510 L=1.08450 C=1.08510 Body=6.00
UP Brick: O=1.08510 H=1.08570 L=1.08510 C=1.08570 Body=6.00
```

**If seeing**:
```
UP Brick: O=1.08450 H=1.08510 L=1.08450 C=1.08450 Body=0.00
```
→ Open=Close bug (brick completion logic wrong)

### Issue #2: Missing Historical Bars
**Status**: Fixed in commit 2b91989 (persistent engine)
**Needs confirmation**: User testing with verbose logging

**Expected**: Hundreds/thousands of bars from 7-day history
**If still seeing**: ~10 bars → Historical builder not accumulating

## Next Steps

1. **User must test with verbose logging**:
   - Set `InpVerboseLog = true`
   - Recompile and attach to chart
   - Click M61 button to rebuild
   - Share Experts tab output showing brick OHLC values

2. **Based on log output**:
   - If Body=6.00 (correct) but chart shows thin lines → MT5 rendering issue (zoom/properties)
   - If Body=0.00 → Brick completion logic needs debugging
   - If only ~10 bars → Historical builder issue persists

3. **Verify historical build**:
   - Check if chart now shows hundreds/thousands of bars
   - If not, persistent engine fix didn't work

## Reference File Patterns NOT Yet Implemented

Based on the reference file, these patterns may still be missing:

1. **Tick validation logic** (lines ~1100-1150)
2. **Multi-brick reversal handling** (lines ~600-650)
3. **Wick suppression when configured** (lines ~550-580)
4. **Chart template restoration** (lines ~1500-1550)
5. **Persistence state serialization** (lines ~1600-1700)

Will implement these if diagnostics show they're needed for proper behavior.
