# Nortrading Renko - MT5 OVO-Style Renko Generator

Professional MT5 Renko chart generator that creates true custom symbol charts with Regular and Mean Renko engines.

## Overview

This indicator generates authentic custom symbol Renko charts in MetaTrader 5, reproducing OVO OmniaBar behavior. Unlike visual overlays, it creates real M1-carrier custom symbols that support all standard indicators, EAs, and trading operations.

## Key Features

### ✅ Core Capabilities
- **Regular Renko Engine**: OVO-compatible validated logic with multi-brick support
- **Mean Renko Engine**: Calibrated geometry (step=600, body=1200, continuation=600, reversal=1800)
- **True Custom Symbols**: Real MT5 custom symbols (e.g., US30.M61, EURAUD.M2)
- **Live Tick Processing**: 20ms default pump with zero intentional tick loss
- **Historical Reconstruction**: Asynchronous build from real tick data with progress tracking
- **Same-Millisecond Integrity**: Full support for multiple ticks per millisecond

### 🎨 User Interface
- **OVO-Style Panel**: Compact 24px control strip in indicator subwindow
- **Editable Brick Size**: Live adjustment without reattaching indicator
- **Custom Period Tokens**: M61, M62, M2, etc. for multiple instances
- **Status Display**: Real-time progress during rebuild, "LIVE" indicator

### 📊 Chart Features
- **M1 Carrier Timeframe**: Permanently locked to M1 for MT5 compatibility
- **Source Bid/Ask Display**: Shows original broker prices on Renko chart
- **Position Overlay**: Entry, SL, and TP lines with monetary labels
- **Chart Persistence**: Indicators, EAs, objects, and settings preserved across restarts

### ⚡ Performance
- **Fast-Path Optimization**: <1ms for no-new-tick events
- **Tick Cache**: Reuses historical data for rapid rebuilds
- **Asynchronous Building**: Non-blocking reconstruction with 8ms budget per pass
- **Dirty-State Management**: Minimal custom symbol updates

### 🔄 Auto-Resume
- **State Persistence**: Remembers active generators across MT5 restarts
- **Template Backup**: Periodic chart configuration saves
- **Seamless Recovery**: Automatic regeneration after terminal restart

## Installation

1. Copy the entire `Nortrading-Renko` folder to your MT5 installation:
   ```
   <MT5_DATA_FOLDER>/MQL5/
   ```

2. The folder structure should be:
   ```
   MQL5/
   ├── Indicators/
   │   └── OVO_Renko_Generator.mq5
   └── Include/
       └── Renko/
           ├── RenkoTypes.mqh
           ├── TickIntegrity.mqh
           ├── RegularRenkoEngine.mqh
           ├── MeanRenkoEngine.mqh
           ├── CustomSymbolPublisher.mqh
           ├── HistoricalBuilder.mqh
           ├── ChartManager.mqh
           ├── PanelUI.mqh
           └── TradeOverlay.mqh
   ```

3. Open MetaEditor and compile `OVO_Renko_Generator.mq5`

## Usage

### Basic Operation

1. **Attach Indicator**
   - Attach to any broker symbol chart (e.g., US30, H1)
   - Control panel appears in indicator subwindow
   - NO chart is generated yet

2. **Generate Renko Chart**
   - Click the period button (e.g., `M61`)
   - Historical build starts with progress display: "Rebuilding 47%"
   - Custom symbol chart opens automatically when complete
   - Status changes to "LIVE"

3. **Adjust Brick Size**
   - Edit the brick size field: `[600]` → `[1200]`
   - Click the period button again
   - Chart rebuilds with new brick size
   - Existing chart updates (no need to close first)

### Multiple Instances

Run multiple Renko configurations simultaneously:

```
Instance A: US30 + M61 + 600 points → US30.M61
Instance B: US30 + M62 + 1200 points → US30.M62
Instance C: EURAUD + M2 + 300 points → EURAUD.M2
```

Each maintains independent state and custom chart.

### Custom Period Tokens

- **M61-M99**: Standard numbered periods
- **M2**: Alternative short token
- **Blank**: Auto-assigns sequential M61, M62, M63...

## Configuration

### Renko Engine Settings

```cpp
Chart Type: Regular Renko / Mean Renko
Brick / Step Points: 600 (default)
Suppress Candle Wicks: No
Initial History Candles: 1000
```

### Custom Chart Settings

```cpp
Custom Period ID: M61 (or M2, M62, etc.)
History Days: 7
```

### Performance Settings

```cpp
Live Pump Milliseconds: 20 (min 5)
Historical Rebuild Budget: 8 ms
Enable Tick Cache: Yes
```

### Trade Display

```cpp
Show Source Bid/Ask: Yes
Show Entry / SL / TP: Yes
Show Monetary SL/TP Labels: Yes
```

## Architecture

### Component Overview

```
MT5 BROKER
    │
    ↓ (ticks)
TICK INTEGRITY LAYER
    │ (unique ticks, same-ms recovery)
    ↓
RENKO ENGINE (Regular or Mean)
    │ (synthetic OHLC)
    ↓
CUSTOM SYMBOL PUBLISHER
    │ (CustomRatesUpdate/Replace)
    ↓
CUSTOM SYMBOL CHART (M1 carrier)
    │
    ↓
INDICATORS / EAs / OBJECTS
```

### State Machine

1. **INITIALIZING**: Component creation
2. **PANEL_ONLY**: Panel visible, no chart generated
3. **REBUILD_REQUESTED**: User clicked period button
4. **REBUILDING**: Asynchronous historical build in progress
5. **PUBLISHING**: Writing completed history to custom symbol
6. **LIVE**: Real-time tick processing active
7. **STOPPING**: Cleanup during shutdown

### Regular Renko Logic

- Fixed brick size (e.g., 600 points)
- Bullish continuation: price ≥ trend_low + brick_size
- Bearish continuation: price ≤ trend_high - brick_size
- Bullish reversal: price ≥ trend_high - (2 × brick_size)
- Bearish reversal: price ≤ trend_low + (2 × brick_size)
- Multi-brick support: one tick can generate multiple bricks

### Mean Renko Geometry

For step = 600 points:

```
Step = 600 points
Body = 1200 points (2 × step)
Continuation threshold = 600 points (1 × step)
Reversal threshold = 1800 points (3 × step)
```

- Brick open positioned around previous body midpoint
- Bullish: high capped at body close, opposite-side lower wick allowed
- Bearish: low capped at body close, opposite-side upper wick allowed

## Technical Specifications

### Performance Targets

| Operation | Target | Achieved |
|-----------|--------|----------|
| No-new-tick event | <1ms | ✅ |
| Live tick processing | Minimal | ✅ |
| Rebuild pass budget | 8ms | ✅ |
| Indicator blocking | Never >3s | ✅ |

### Tick Integrity

- **Signature**: time_msc + Bid + Ask + Last + Volume + Flags
- **Same-millisecond**: Multiple ticks at .123 processed separately
- **Duplicate protection**: Signature-based filtering
- **Fallback**: Latest tick direct processing if CopyTicksRange fails

### Memory Optimization

- Reserved capacity for arrays
- Chunk growth (not +1 per element)
- Preallocated historical buffers
- Configurable tick cache upper limit

## Troubleshooting

### Chart Not Generating

- **Check**: AutoTrading enabled in Tools → Options → Expert Advisors
- **Check**: Custom symbols allowed (should be automatic)
- **Solution**: Restart MT5 if custom symbol creation fails

### Forming Candle Frozen

- **Cause**: Tick integrity issue or timer not firing
- **Check**: Verbose logging to diagnose
- **Solution**: Reattach indicator

### Performance Warning

If you see: "indicator is too slow, 3031 ms"

- Reduce history days (7 → 3)
- Increase rebuild budget (8ms → 15ms)
- Disable diagnostics
- Check CPU usage

### Missing Positions

- **Cause**: Trade overlay looking at wrong symbol
- **Check**: Source symbol matches position symbol
- **Solution**: Positions must be on source symbol (e.g., US30, not US30.M61)

## Advanced Features

### Diagnostics

Enable Mean Renko diagnostics for CSV output:

```cpp
Mean Renko Diagnostics: Yes
```

Creates: `MeanRenko_Diagnostic_<SYMBOL>.csv`

Contains: Event, Time, Price, BricksCompleted, FormingOpen, FormingClose

### Template Persistence

Templates saved as: `OVORenko_<SYMBOL>_<TOKEN>`

Example: `OVORenko_US30_M61.tpl`

Restores:
- Attached indicators
- Attached EAs
- Chart colors
- Zoom level
- Objects

### Verbose Logging

Enable for detailed diagnostics:

```cpp
Verbose Log: Yes
```

Outputs to Experts tab:
- Tick counts
- Same-millisecond detections
- Brick completions
- State transitions
- Performance metrics

## API for Developers

### Custom Integration

The modular architecture allows custom extensions:

```cpp
// Example: Custom Renko engine
class CCustomRenkoEngine : public CRegularRenkoEngine
{
public:
   ENUM_DIRTY_STATE ProcessTick(double price, datetime time) override
   {
      // Your custom logic
      return DIRTY_FORMING_CHANGED;
   }
};
```

### Component Access

All components are in separate .mqh files:

- `RenkoTypes.mqh`: Data structures and enums
- `TickIntegrity.mqh`: Tick signature and deduplication
- `RegularRenkoEngine.mqh`: Standard Renko logic
- `MeanRenkoEngine.mqh`: Mean Renko with OVO geometry
- `CustomSymbolPublisher.mqh`: Custom symbol management
- `HistoricalBuilder.mqh`: Asynchronous tick processing
- `ChartManager.mqh`: Chart lifecycle and M1 enforcement
- `PanelUI.mqh`: Control panel UI
- `TradeOverlay.mqh`: Position display on Renko chart

## Acceptance Criteria

### ✅ Regular Renko
- Same direction sequence as OVO reference
- Identical OHLC values
- Matching reversal points
- Wick behavior within feed differences

### ✅ Mean Renko
- Body sequence agreement: exact
- OHLC agreement: exact (excluding feed differences)
- Live alignment with OVO behavior

### ✅ Live Forming Candle
- Updates continuously with price movement
- Never freezes while Bid/Ask moving

### ✅ Same-Millisecond Ticks
- 3 ticks at .123 → 3 processed ticks
- No loss, no duplicates

### ✅ Multi-Brick Processing
- Fast movement crossing 3 thresholds → 3 bricks generated
- No missing intermediate candles

### ✅ Restart Auto-Resume
- MT5 restart → generator auto-resumes
- Chart restored with indicators/EAs
- Live processing continues

## License

Copyright 2024, Nortrading Renko Project

This project is open source. See LICENSE file for details.

## Support

- **Issues**: https://github.com/vigilmvarghese/Nortrading-Renko/issues
- **Documentation**: https://github.com/vigilmvarghese/Nortrading-Renko/wiki
- **Discussions**: https://github.com/vigilmvarghese/Nortrading-Renko/discussions

## Version History

### v1.0.0 (Current)
- Initial production release
- Regular Renko engine (OVO-validated)
- Mean Renko engine (OVO-calibrated)
- Asynchronous historical builder
- OVO-style panel UI
- Trade overlay with monetary labels
- Auto-resume after restart
- Chart persistence
- Performance optimizations

## Credits

Developed using MQL5 best practices and the OVO OmniaBar specification as reference for behavioral compatibility.
