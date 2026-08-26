# OVO Renko Generator - Technical Architecture

## System Overview

The OVO Renko Generator is a production-grade MT5 indicator that generates authentic custom symbol Renko charts using real broker tick data. The architecture prioritizes correctness, performance, and maintainability through strict separation of concerns.

## Design Principles

### 1. Every Legitimate Tick Reaches the Renko Engine
No performance optimization may discard market data. The tick integrity layer ensures complete processing of all unique ticks, including same-millisecond events.

### 2. Single Forming Candle
At most ONE forming Renko candle exists at any time. Sub-partials merge into the same forming brick, preventing visual fragmentation.

### 3. Separation of Concerns
Renko mathematics remain isolated from tick transport, UI, persistence, and chart management. Each component has a single, well-defined responsibility.

### 4. Non-Blocking Operation
Heavy operations (historical reconstruction) execute asynchronously with configurable time budgets to maintain terminal responsiveness.

---

## Component Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    MT5 BROKER FEED                           │
└─────────────────┬───────────────────────────────────────────┘
                  │
                  ↓ Raw Ticks
┌─────────────────────────────────────────────────────────────┐
│              TICK INTEGRITY LAYER                            │
│  • Signature-based deduplication                             │
│  • Same-millisecond handling                                 │
│  • CopyTicksRange with fallback                              │
└─────────────────┬───────────────────────────────────────────┘
                  │
                  ↓ Validated Unique Ticks
          ┌───────┴────────┐
          │                │
          ↓                ↓
┌──────────────────┐ ┌──────────────────┐
│ REGULAR RENKO    │ │  MEAN RENKO      │
│ ENGINE           │ │  ENGINE          │
│ • Fixed brick    │ │ • Step geometry  │
│ • Multi-brick    │ │ • Body=2×step    │
│ • OVO validated  │ │ • Midpoint calc  │
└────────┬─────────┘ └────────┬─────────┘
         │                    │
         └────────┬───────────┘
                  │
                  ↓ Synthetic OHLC Bricks
┌─────────────────────────────────────────────────────────────┐
│           CUSTOM SYMBOL PUBLISHER                            │
│  • CustomRatesReplace (full history)                         │
│  • CustomRatesUpdate (incremental)                           │
│  • Dirty-state optimization                                  │
└─────────────────┬───────────────────────────────────────────┘
                  │
                  ↓ Custom Symbol Rates
┌─────────────────────────────────────────────────────────────┐
│                    US30.M61                                  │
│              (M1 Carrier Timeframe)                          │
└─────────────────┬───────────────────────────────────────────┘
                  │
                  ↓ Chart with Indicators/EAs
┌─────────────────────────────────────────────────────────────┐
│                RENKO CHART DISPLAY                           │
│  • Indicators attached                                       │
│  • EAs trading                                               │
│  • Objects drawn                                             │
│  • Source Bid/Ask overlay                                    │
│  • Position/SL/TP display                                    │
└─────────────────────────────────────────────────────────────┘
```

---

## Core Components

### 1. Tick Integrity Layer (`TickIntegrity.mqh`)

**Purpose**: Ensure every unique tick reaches the Renko engine without loss or duplication.

**Key Features**:
- **Tick Signature**: Compound key (time_msc, Bid, Ask, Last, Volume, Flags)
- **Same-ms Detection**: Multiple ticks sharing millisecond timestamp
- **Deduplication**: Signature comparison prevents reprocessing
- **Fallback Strategy**: SymbolInfoTick as backup if CopyTicksRange fails

**Critical Methods**:
```cpp
bool HasNewTick()              // Fast-path: check latest signature
int GetNewTicks(MqlTick &ticks[])  // Retrieve all new ticks since last
void MarkProcessed(const MqlTick &tick)  // Update last processed
```

**Performance**:
- HasNewTick(): <0.1ms (comparison only)
- GetNewTicks(): 1-5ms (includes CopyTicksRange)

---

### 2. Regular Renko Engine (`RegularRenkoEngine.mqh`)

**Purpose**: OVO-validated fixed brick size Renko calculation.

**Algorithm**:
```
Bullish Trend:
  Continuation: price ≥ trend_low + brick_size
  Reversal: price ≤ trend_high - (2 × brick_size)

Bearish Trend:
  Continuation: price ≤ trend_high - brick_size
  Reversal: price ≥ trend_low + (2 × brick_size)
```

**Multi-Brick Logic**:
```cpp
while (threshold_crossed && safety_counter < 100)
{
   CompleteBrick();
   UpdateTrend();
   // Check same tick against new threshold
}
```

**State Variables**:
- `m_trend_high`: Current upside extreme
- `m_trend_low`: Current downside extreme
- `m_is_bullish`: Current trend direction
- `m_forming_brick`: Single active forming candle

**Wick Behavior**:
- Bullish: low may extend below open (opposite-side wick)
- Bearish: high may extend above open (opposite-side wick)
- Suppression: optional via `m_suppress_wicks`

---

### 3. Mean Renko Engine (`MeanRenkoEngine.mqh`)

**Purpose**: OVO-calibrated Mean Renko with body/wick geometry.

**Geometry (for step = 600)**:
```
Step              = 600 points
Body              = 1200 points (2 × step)
Continuation      = 600 points (1 × step from midpoint)
Reversal          = 1800 points (3 × step from midpoint)
```

**Midpoint Calculation**:
```cpp
m_last_body_midpoint = (completed.open + completed.close) / 2.0;
```

**New Brick Positioning**:
```cpp
Bullish:
  new_open = midpoint - step
  new_close = new_open + body

Bearish:
  new_open = midpoint + step
  new_close = new_open - body
```

**Directional Wick Rules**:
```cpp
Bullish Brick:
  high = close (capped at body close)
  low = min(current_low, open) (opposite-side wick allowed)

Bearish Brick:
  low = close (capped at body close)
  high = max(current_high, open) (opposite-side wick allowed)
```

**State Variables**:
- `m_last_body_midpoint`: Previous candle body center
- `m_current_high/low`: Price extremes since last brick
- `m_step_price`: Calibrated step in price units

---

### 4. Custom Symbol Publisher (`CustomSymbolPublisher.mqh`)

**Purpose**: Manage custom symbol creation and rate publication.

**Publication Strategies**:

1. **Full Replace** (ReplaceHistory):
   ```cpp
   CustomRatesDelete(from, to)
   CustomRatesReplace(from, to, rates[])
   ```
   Used for: Initial build, complete rebuild

2. **Incremental Update** (UpdateRates):
   ```cpp
   CustomRatesUpdate(rates[])
   ```
   Used for: Live processing (completed + forming)

3. **Forming Only** (UpdateFormingOnly):
   ```cpp
   CustomRatesUpdate(forming_rate[1])
   ```
   Used for: DIRTY_FORMING_CHANGED state

**Dirty State Optimization**:
```cpp
DIRTY_NONE             → No publication
DIRTY_FORMING_CHANGED  → Update forming only
DIRTY_BRICK_COMPLETED  → Update completed + forming
DIRTY_MULTI_BRICK      → Batch update all
```

**Custom Symbol Properties**:
- Inherits from source symbol (digits, spread, point, tick_value)
- Name format: `<SOURCE>.<TOKEN>` (e.g., US30.M61)
- Permanent M1 carrier timeframe

---

### 5. Historical Builder (`HistoricalBuilder.mqh`)

**Purpose**: Asynchronous historical Renko reconstruction.

**Tick Cache Architecture**:
```cpp
LoadTickCache(days)
  ↓
CopyTicks(source, days × 86400)
  ↓
Store in m_tick_cache[]
  ↓
Reuse for subsequent rebuilds
```

**Asynchronous Processing**:
```cpp
StartBuild()
  ↓
  ┌─────────────────┐
  │ ProcessBuildPass() │ ← Called every 20ms
  │   • Process N ticks  │
  │   • Check budget    │
  │   • Update progress │
  └─────┬───────────┘
        │
        ↓ (if more work)
        └──────┐
               │
        ↓ (if complete)
     GetResults()
```

**Budget Control**:
```cpp
int m_budget_ms = 8;  // Process for max 8ms per pass

while (m_build_index < m_total_ticks)
{
   ProcessTick();
   
   if (GetTickCount() - start_time >= m_budget_ms)
      break;  // Yield back to MT5
}
```

**Progress Tracking**:
```cpp
struct BuildProgress
{
   int processed_ticks;
   int total_ticks;
   int GetProgressPercent() const {
      return (processed_ticks * 100) / total_ticks;
   }
};
```

---

### 6. Chart Manager (`ChartManager.mqh`)

**Purpose**: Chart lifecycle and M1 enforcement.

**Chart Operations**:

1. **Find Existing**:
   ```cpp
   ChartFirst() → ChartNext() loop
   Match: ChartSymbol() == custom_symbol
   ```

2. **Create New**:
   ```cpp
   ChartOpen(custom_symbol, PERIOD_M1)
   ConfigureChart()
   ApplyTemplate() if exists
   ```

3. **Enforce M1**:
   ```cpp
   if (ChartPeriod() != PERIOD_M1)
      ChartSetInteger(CHART_PERIOD, PERIOD_M1)
   ```
   Runs periodically without bringing chart to foreground

**Template Persistence**:
```cpp
Periodic: ChartSaveTemplate(template_name)
Restore: ChartApplyTemplate(template_name)

Template Name: "OVORenko_<SYMBOL>_<TOKEN>"
Example: "OVORenko_US30_M61.tpl"
```

**Lifecycle**:
- Creation: On first period button click
- Reuse: On subsequent rebuilds (same token)
- Preservation: Indicators, EAs, objects retained

---

### 7. Panel UI (`PanelUI.mqh`)

**Purpose**: OVO-style compact control panel.

**Layout** (24px height):
```
┌─────────────────────────────────────────────────────────────┐
│ Mean Renko: [ 600 ] [ M61 ]          OVO C2           [X]  │
└─────────────────────────────────────────────────────────────┘
     ↑         ↑       ↑               ↑                ↑
   label    editable button         status           close
            field
```

**Components**:
1. **Type Label**: "Renko:" or "Mean Renko:"
2. **Brick Field**: OBJ_EDIT, editable, white background
3. **Period Button**: OBJ_BUTTON, triggers generation
4. **Status Label**: Shows state or progress
5. **Close Button**: "X", removes indicator
6. **Background**: Rectangle label, matches chart width

**Dynamic Behavior**:
- Width adjusts with chart width
- Status updates: "OVO C2", "Rebuilding 47%", "LIVE"
- No empty space: compact professional appearance

---

### 8. Trade Overlay (`TradeOverlay.mqh`)

**Purpose**: Display source symbol positions on Renko chart.

**Elements Displayed**:

1. **Source Bid/Ask**:
   ```cpp
   SymbolInfoDouble(source_symbol, SYMBOL_BID)
   Draw: OBJ_HLINE, dotted, red/blue
   ```

2. **Entry Lines**:
   ```cpp
   For each position on source_symbol:
     Entry: OBJ_HLINE, solid, blue/red
     Label: "BUY 0.10" or "SELL 0.10"
   ```

3. **SL/TP Lines**:
   ```cpp
   SL: OBJ_HLINE, dashed, red
   TP: OBJ_HLINE, dashed, green
   ```

4. **Monetary Labels**:
   ```cpp
   OrderCalcProfit(type, symbol, volume, entry, sl, profit)
   Label: "SL: - $18.00" or "TP: + $36.00"
   Currency: Account currency (USD, EUR, etc.)
   ```

**Update Frequency**: 1 second (slower than live pump)

**Positioning**: Labels anchored left, near line, avoid price scale

---

### 9. State Machine

**States**:
```cpp
INITIALIZING          → Component creation, initial setup
PANEL_ONLY            → Panel visible, no chart generated
REBUILD_REQUESTED     → User clicked period button
REBUILDING            → Async historical build in progress
PUBLISHING            → Writing completed history
LIVE                  → Real-time tick processing
STOPPING              → Cleanup during shutdown
```

**Transitions**:
```
INITIALIZING
    ↓
PANEL_ONLY ←──────────┐
    ↓ (button click)   │
REBUILD_REQUESTED      │
    ↓                  │
REBUILDING             │
    ↓ (complete)       │
PUBLISHING             │
    ↓                  │
LIVE ──────────────────┘
    ↓ (shutdown)
STOPPING
```

**State Guards**:
- OnTimer checks current state
- Only one state active at a time
- Rebuild cannot start during LIVE without request

---

### 10. Persistence Manager

**Storage**: MT5 Global Variables

**Format**:
```
Prefix: OVORenko_<SYMBOL>_<TOKEN>_

Variables:
  Active       : 1.0 (active) / 0.0 (inactive)
  ChartType    : 0 (Regular) / 1 (Mean)
  BrickSize    : Current brick size (e.g., 600.0)
  ChartID      : Generated chart ID
```

**Operations**:

1. **Save**:
   ```cpp
   GlobalVariableSet(prefix + "Active", is_active ? 1.0 : 0.0)
   Called: During LIVE state, on explicit close
   ```

2. **Load**:
   ```cpp
   GlobalVariableGet(prefix + "Active")
   Called: OnInit() if auto-resume enabled
   ```

3. **Clear**:
   ```cpp
   GlobalVariableDel(prefix + "Active")
   Called: On explicit remove ([X] button)
   ```

**Auto-Resume Logic**:
```cpp
OnInit():
  if (InpAutoResume && persistence.Load() && persistence.is_active)
     g_rebuild_requested = true
```

---

## Data Flow

### Live Tick Processing Flow

```
1. OnTimer() fires (every 20ms)
       ↓
2. ProcessLiveTicks()
       ↓
3. TickIntegrity.HasNewTick()
       ↓ (if false)
   RETURN (fast path <1ms)
       ↓ (if true)
4. TickIntegrity.GetNewTicks()
       ↓
5. For each tick:
     RegularRenko.ProcessTick()
     or
     MeanRenko.ProcessTick()
       ↓
6. Get dirty state + completed bricks
       ↓
7. Publisher.UpdateRates()
       ↓
8. Mark ticks processed
       ↓
9. Optional: ChartRedraw()
```

### Historical Build Flow

```
1. OnPeriodButtonClick()
       ↓
2. State → REBUILD_REQUESTED
       ↓
3. OnTimer() → StartRebuild()
       ↓
4. Builder.LoadTickCache(days)
       ↓
5. Builder.StartBuild()
       ↓
6. State → REBUILDING
       ↓
7. OnTimer() → ContinueRebuild()
   ┌────────────────┐
   │ ProcessBuildPass()│
   │   8ms budget    │
   └────┬───────────┘
        │
        ↓ (repeat until complete)
   Builder.GetResults()
       ↓
8. State → PUBLISHING
       ↓
9. Publisher.ReplaceHistory()
       ↓
10. ChartManager.OpenChart()
       ↓
11. State → LIVE
```

---

## Performance Optimizations

### 1. Fast-Path No-Tick Exit
```cpp
if (!TickIntegrity.HasNewTick())
   return;  // Immediate exit, <0.1ms
```

### 2. Dirty-State Publication
```cpp
DIRTY_NONE              → Skip publication
DIRTY_FORMING_CHANGED   → Update 1 rate
DIRTY_BRICK_COMPLETED   → Update N + 1 rates
DIRTY_MULTI_BRICK       → Batch update
```

### 3. Tick Cache Reuse
```cpp
First build: Load from disk (slow)
Subsequent: Reuse cache (3-5x faster)
Append: Only new ticks since cache_end_time
```

### 4. Asynchronous Rebuild
```cpp
Budget: 8ms per pass
Effect: Terminal remains responsive
User: Can navigate, trade during rebuild
```

### 5. Conditional Redraw
```cpp
Only redraw if:
  - New bricks completed
  - Visible state changed
  
Not redraw if:
  - No new tick
  - Only forming candle update (small movement)
```

### 6. Separate Update Frequencies
```cpp
Live pump:        20ms   (tick processing)
UI update:        100ms  (panel width)
Trade overlay:    1000ms (position lines)
Template save:    60s    (chart backup)
```

---

## Memory Management

### Array Growth Strategy
```cpp
// AVOID: Expensive
ArrayResize(array, size + 1)  // Every element

// PREFER: Efficient
ArrayResize(array, 0, 10000)  // Reserve capacity
```

### Tick Cache Limits
```cpp
Typical: 7 days = 500k-2M ticks
Memory: ~50-200 MB
Safety: Configurable max limit
```

### Completed Brick Buffer
```cpp
Preallocated: 10,000 bricks
Resets: After publication
Growth: Chunk-based if exceeded
```

---

## Error Handling

### Tick Retrieval Failure
```cpp
if (CopyTicksRange() <= 0)
{
   // Fallback to SymbolInfoTick()
   if (latest_tick.IsValid())
      ProcessTick(latest_tick)
}
```

### Custom Symbol Creation Failure
```cpp
if (!CustomSymbolCreate())
{
   Print("ERROR: Failed to create custom symbol");
   State → PANEL_ONLY
   Panel.SetStatusText("ERROR: Symbol creation failed")
   return
}
```

### Chart Open Failure
```cpp
if (ChartOpen() == 0)
{
   Print("ERROR: Failed to open chart");
   // Continue processing, retry later
}
```

### Recovery Strategy
- Log error with details
- Return to safe state (usually PANEL_ONLY)
- Update UI with error message
- Allow user to retry via button click

---

## Thread Safety

### MT5 Single-Threaded Model
- All code executes on main UI thread
- No multi-threading in MQL5 indicators
- No mutex/lock primitives needed

### Event Serialization
- OnTimer(), OnCalculate(), OnChartEvent() never concurrent
- State machine ensures single active operation
- Rebuild state prevents live processing

---

## Testing Architecture

### Unit Testing (Manual)
- Test each component in isolation
- Validate: TickIntegrity, RegularRenko, MeanRenko
- Check: Signature comparison, brick generation

### Integration Testing
- Full indicator operation
- Validate: Tick flow → Renko → Custom symbol → Chart
- Check: State transitions, persistence

### Performance Testing
- Measure: OnTimer execution time
- Target: <1ms no-tick, <5ms live tick
- Tool: GetTickCount(), MQL5 Profiler

### Acceptance Testing
- See TESTING_GUIDE.md
- 15 comprehensive test scenarios
- Validate against OVO reference behavior

---

## Extension Points

### Custom Renko Algorithms
```cpp
// Inherit from base engine
class CCustomRenkoEngine : public CRegularRenkoEngine
{
   ENUM_DIRTY_STATE ProcessTick(double price, datetime time) override;
};

// Add to router in main indicator
if (type == RENKO_CUSTOM)
   custom_engine.ProcessTick(price, time);
```

### Additional Chart Types
```cpp
enum ENUM_RENKO_TYPE
{
   RENKO_REGULAR,
   RENKO_MEAN,
   RENKO_CUSTOM,    // Add new type
   RENKO_HYBRID     // Another variant
};
```

### Custom UI Themes
```cpp
// Modify panel colors
ObjectSetInteger(name, OBJPROP_BGCOLOR, clrCustomColor);
ObjectSetInteger(name, OBJPROP_COLOR, clrCustomText);
```

---

## Deployment Architecture

### File Structure
```
MQL5/
├── Indicators/
│   └── OVO_Renko_Generator.mq5 (Main indicator)
│
└── Include/
    └── Renko/
        ├── RenkoTypes.mqh          (Data structures)
        ├── TickIntegrity.mqh       (Tick processing)
        ├── RegularRenkoEngine.mqh  (Regular Renko)
        ├── MeanRenkoEngine.mqh     (Mean Renko)
        ├── CustomSymbolPublisher.mqh
        ├── HistoricalBuilder.mqh
        ├── ChartManager.mqh
        ├── PanelUI.mqh
        └── TradeOverlay.mqh
```

### Compilation
```
MetaEditor → Open OVO_Renko_Generator.mq5 → F7 (Compile)
Output: Indicators/OVO_Renko_Generator.ex5
```

### Distribution
- Include all .mqh files in package
- Preserve directory structure
- Provide README.md and documentation
- Example configurations included

---

## Future Enhancements

### Potential Features
1. **Flex Renko**: Variable brick size based on volatility
2. **Hybrid Renko**: Regular + Mean hybrid logic
3. **Range Bars**: Time-independent range-based bars
4. **Point & Figure**: Traditional P&F charts
5. **Multi-Symbol**: Generate multiple symbols in one indicator
6. **Cloud Sync**: Cross-terminal state synchronization

### Architecture Support
The modular design supports these additions:
- New engine: Implement interface, add to router
- New feature: Create new .mqh component
- UI changes: Modify PanelUI.mqh only
- Persistence: Extend PersistenceState struct

---

## Conclusion

The OVO Renko Generator architecture achieves production-grade reliability through:

1. **Correctness**: Every tick processed, no data loss
2. **Performance**: <1ms fast path, non-blocking rebuild
3. **Maintainability**: Modular components, clear interfaces
4. **Extensibility**: Easy to add new Renko types
5. **Robustness**: Error handling, state recovery, persistence

The design follows software engineering best practices while working within MT5's constraints, delivering a professional trading tool that reproduces OVO behavior with high fidelity.
