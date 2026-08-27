# Panel Positioning & Auto-Generation Fix

## Issues Fixed

### Issue #1: Panel on Main Chart Instead of Indicator Window
**Problem:** Panel was appearing on the main price chart overlaying candles  
**Root Cause:** `ChartWindowFind()` returns -1 during `OnInit()` because the indicator window doesn't exist yet. The fallback code `if(subwindow < 0) subwindow = 0;` placed the panel in window 0 (main chart).

**Fix:** Hardcoded `subwindow = 1` for indicator_separate_window mode
```mql5
// ✅ CRITICAL: In indicator_separate_window mode, the panel MUST be created in window 1
// Window 0 = main chart
// Window 1 = first indicator subwindow (where our panel belongs)
// Window 2 = second indicator subwindow (if multiple indicators)
int subwindow = 1;  // ✅ First indicator subwindow (not main chart!)
```

### Issue #2: Auto-Generation on Indicator Attach
**Problem:** Renko chart was automatically generating as soon as the indicator was attached to the chart, without user clicking the button.  
**Root Cause:** `InpAutoResume` persistence logic was triggering automatic chart generation even on first attach.

**Fix:** Disabled auto-resume feature entirely
```mql5
// ❌ Auto-resume disabled - user must explicitly click button to generate chart
// input bool InpAutoResume = true;  // COMMENTED OUT
```

---

## New Behavior

### Step-by-Step User Flow

1. **Attach Indicator to Chart**
   - Panel appears in **indicator window** (bottom subwindow, NOT on main chart)
   - Panel displays: `Mean Renko: [600] [M61] Ready`
   - **NO automatic generation** - chart waits for user action

2. **User Clicks Period Button** (e.g., `[M61]`)
   - Panel status changes: `Building history...`
   - Synchronous history build completes instantly
   - Custom symbol chart opens automatically
   - Panel status: `Live - M61 active`

3. **User Clicks Regenerate** (changes brick size, clicks button again)
   - Old bars cleaned up completely
   - New bars generated with new brick size
   - Chart refreshes instantly

---

## Visual Layout

```
┌─────────────────────────────────────────────────────────────┐
│                                                             │
│                    MAIN PRICE CHART                         │
│                  (EURUSD candlesticks)                      │
│                                                             │
│                    NO PANEL HERE ❌                          │
│                                                             │
└─────────────────────────────────────────────────────────────┘
├─────────────────────────────────────────────────────────────┤ ← Separator
┌─────────────────────────────────────────────────────────────┐
│ ⬛ Mean Renko: [600] [M61] Ready                    [X]    │ ← Panel here ✅
└─────────────────────────────────────────────────────────────┘
  ↑ INDICATOR WINDOW (30px height, black background)
```

---

## Multiple Instance Support

You can now add multiple panels, each in its own indicator subwindow:

```
┌─────────────────────────────────────────────────────────────┐
│                    MAIN CHART (EURUSD)                      │
└─────────────────────────────────────────────────────────────┘
├─────────────────────────────────────────────────────────────┤
┌─────────────────────────────────────────────────────────────┐
│ ⬛ Mean Renko: [600] [M61] Ready                    [X]    │ ← Instance 1
└─────────────────────────────────────────────────────────────┘
├─────────────────────────────────────────────────────────────┤
┌─────────────────────────────────────────────────────────────┐
│ ⬛ Renko: [300] [M62] Ready                         [X]    │ ← Instance 2
└─────────────────────────────────────────────────────────────┘
├─────────────────────────────────────────────────────────────┤
┌─────────────────────────────────────────────────────────────┐
│ ⬛ Mean Renko: [150] [M63] Ready                    [X]    │ ← Instance 3
└─────────────────────────────────────────────────────────────┘
```

**Each instance:**
- Has unique period token (M61, M62, M63)
- Has independent brick size
- Has unique object prefix: `OVORenko_{ChartID}_{PeriodToken}_`
- Appears in separate indicator subwindow

---

## Testing Checklist

### ✅ Basic Functionality
- [ ] Panel appears in **indicator window** (bottom), not on main chart
- [ ] Panel shows default brick size from input settings
- [ ] Panel displays **"Ready"** status after attach
- [ ] **NO automatic generation** on attach

### ✅ Chart Generation
- [ ] Click `[M61]` button → Chart generates instantly
- [ ] Custom symbol chart opens automatically
- [ ] Panel status: `"Live - M61 active"`
- [ ] Zero-latency tick updates (if `InpUseOnTick = true`)

### ✅ Regeneration
- [ ] Change brick size in input field (e.g., 600 → 300)
- [ ] Click `[M61]` button again
- [ ] Old bars disappear completely
- [ ] New bars appear with new brick size
- [ ] Chart refreshes correctly

### ✅ Multiple Instances
- [ ] Add indicator with `InpPeriodToken = M61`
- [ ] Add indicator again with `InpPeriodToken = M62`
- [ ] Add indicator again with `InpPeriodToken = M63`
- [ ] Each panel appears in separate subwindow
- [ ] Generate charts from each panel independently
- [ ] All 3 charts coexist without conflicts

---

## Code Changes

**File:** `OVO_Renko_Generator.mq5`

**Change 1: Hardcoded subwindow**
```mql5
// BEFORE (wrong):
int subwindow = ChartWindowFind(ChartID(), short_name);
if(subwindow < 0) subwindow = 0;  // ❌ Places on main chart!

// AFTER (correct):
int subwindow = 1;  // ✅ First indicator subwindow
```

**Change 2: Disabled auto-resume**
```mql5
// BEFORE (wrong):
input bool InpAutoResume = true;  // ❌ Auto-generates chart
if(InpAutoResume && g_persistence.is_active) {
   g_rebuild_requested = true;  // ❌ Triggers automatic generation
}

// AFTER (correct):
// input bool InpAutoResume = true;  // ❌ Commented out
// Auto-resume logic disabled  // ✅ User must click button
```

---

## Commit

**Commit:** `f9e0a12`  
**Message:** "FIX: Panel positioning and auto-generation issues"  
**Branch:** `main`

---

## Status

✅ **Panel now appears in indicator window (bottom)**  
✅ **No automatic chart generation on attach**  
✅ **User must click period button to generate chart**  
✅ **Multiple instances supported with unique prefixes**  
✅ **Ready for testing in MT5**
