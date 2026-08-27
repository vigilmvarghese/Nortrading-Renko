# Window Detection Fix - Multiple Instance Support

## Problem: Second Instance Panel Not Showing

**Symptom:**
- First instance (M61): Panel visible ✅
- Second instance (M62): Panel invisible ❌

**Root Cause:**
The "LAST window" detection approach was flawed for multiple instances.

### What Went Wrong

**Original Code (BROKEN):**
```cpp
// ❌ WRONG: Uses dynamic window count
int total_windows = (int)ChartGetInteger(ChartID(), CHART_WINDOWS_TOTAL);
int subwindow = total_windows - 1;  // "Last" window
```

**Timeline of the bug:**
1. **First instance attaches:**
   - total_windows = 2 (main + indicator 1)
   - subwindow = 1 ✅
   - Panel created in window 1 ✅

2. **Second instance attaches:**
   - total_windows = 3 (main + indicator 1 + indicator 2)
   - subwindow = 2 ✅
   - Panel tries to create in window 2 ✅

3. **BUT... first instance's timer still running:**
   - First instance sees total_windows = 3 (changed!)
   - First instance recalculates subwindow = 2 ❌
   - **CONFLICT:** Both instances think they own window 2!

**Race Condition:**
- `total_windows` is a **global chart property**
- Every instance sees the **same value**
- When new instances attach, ALL instances see the new count
- "Last window" logic breaks down

### The Solution: ChartWindowFind by Name (OVO Pattern)

**Fixed Code:**
```cpp
// ✅ CORRECT: Find window by unique indicator name
string short_name = StringFormat("OVO Renko [%s] %s", 
                                  g_config.period_token,
                                  (InpChartType == RENKO_MEAN ? "Mean" : "Regular"));

int subwindow = ChartWindowFind(ChartID(), short_name);
```

**Why This Works:**

1. **Each instance has a unique name:**
   - Instance 1: `"OVO Renko [M61] Mean"`
   - Instance 2: `"OVO Renko [M62] Mean"`
   - Instance 3: `"OVO Renko [M63] Mean"`

2. **ChartWindowFind() returns the window FOR THAT NAME:**
   - M61 always finds window 1
   - M62 always finds window 2
   - M63 always finds window 3

3. **No race conditions:**
   - Each instance finds its OWN window by name
   - Window assignments never change
   - Stable and reliable

4. **This is the OVO reference pattern:**
   ```cpp
   // From OVO_Style_Omnia_MT5.mq5
   g_subwindow=ChartWindowFind(0,g_short_name);
   if(g_subwindow>=1)
      ChartSetInteger(0,CHART_HEIGHT_IN_PIXELS,g_subwindow,24);
   ```

## Implementation Details

### OnInit: Set Unique Short Name

```cpp
int OnInit()
{
   // ... other init code ...
   
   // ✅ CRITICAL: Set unique short name using auto-assigned period token
   string short_name = StringFormat("OVO Renko [%s] %s", 
                                     g_config.period_token,
                                     (InpChartType == RENKO_MEAN ? "Mean" : "Regular"));
   IndicatorSetString(INDICATOR_SHORTNAME, short_name);
   
   // ... rest of init ...
}
```

### OnTimer: Find Window by Name

```cpp
void OnTimer()
{
   // Enforce height for our assigned window
   if(g_our_subwindow > 0)
   {
      ChartSetInteger(ChartID(), CHART_HEIGHT_IN_PIXELS, g_our_subwindow, 24);
   }
   
   // Panel creation: Find our window by name
   if(g_state == STATE_INITIALIZING && g_panel == NULL)
   {
      string short_name = StringFormat("OVO Renko [%s] %s", 
                                        g_config.period_token,
                                        (InpChartType == RENKO_MEAN ? "Mean" : "Regular"));
      
      int subwindow = ChartWindowFind(ChartID(), short_name);
      
      if(subwindow < 0)
      {
         // Window not ready yet, try again next timer tick
         return;
      }
      
      // Found our window! Create panel...
      g_our_subwindow = subwindow;  // Lock it in
      // ... create panel objects ...
   }
}
```

## Why "Last Window" Failed

**The Fundamental Problem:**
- `CHART_WINDOWS_TOTAL` returns a **snapshot** of the current state
- It's not "which window am I in?" but "how many windows exist right now?"
- This value **changes** when indicators are added/removed

**Example Timeline:**
```
Time 0: Attach instance 1 (M61)
  → CHART_WINDOWS_TOTAL = 2
  → M61 uses window 1 ✅

Time 1: M61's OnTimer runs
  → CHART_WINDOWS_TOTAL = 2
  → M61 calculates: subwindow = 2 - 1 = 1 ✅

Time 2: Attach instance 2 (M62)
  → CHART_WINDOWS_TOTAL = 3
  → M62 uses window 2 ✅

Time 3: M61's OnTimer runs AGAIN
  → CHART_WINDOWS_TOTAL = 3 (changed!)
  → M61 calculates: subwindow = 3 - 1 = 2 ❌
  → M61 now thinks it owns window 2 (M62's window!)

Time 4: M62's OnTimer runs
  → CHART_WINDOWS_TOTAL = 3
  → M62 calculates: subwindow = 3 - 1 = 2 ✅
  → But M61 also thinks it owns window 2!
  → CONFLICT: Panel objects overwrite each other
```

**Result:** Second instance's panel disappears because first instance keeps recreating its panel in window 2.

## Why ChartWindowFind Works

**MT5 Internal Behavior:**
- Each indicator subwindow is **registered with its indicator's short name**
- `ChartWindowFind(chart_id, name)` searches the registry
- Returns the window index where that named indicator is located
- This is a **lookup**, not a calculation

**Stable Window Assignment:**
```
Chart Window Registry:
  Window 0: "Main Chart"
  Window 1: "OVO Renko [M61] Mean"  → ChartWindowFind finds 1
  Window 2: "OVO Renko [M62] Mean"  → ChartWindowFind finds 2
  Window 3: "OVO Renko [M63] Mean"  → ChartWindowFind finds 3
```

No matter when you call `ChartWindowFind()`, it always returns the same window for the same name.

## Testing the Fix

### Before Fix (Broken)
1. Attach M61 → Panel appears ✅
2. Attach M62 → Panel appears briefly, then disappears ❌
3. Check window 2 → Empty (panel missing) ❌

**Experts Log:**
```
M61: 📊 Total windows: 2, using LAST window: 1
M61: ✅ Panel created successfully in subwindow 1
M62: 📊 Total windows: 3, using LAST window: 2
M62: ✅ Panel created successfully in subwindow 2
M61: 📊 Total windows: 3, using LAST window: 2  ← WRONG!
M61: 🎨 Creating panel... Subwindow: 2            ← CONFLICT!
```

### After Fix (Working)
1. Attach M61 → Panel appears ✅
2. Attach M62 → Panel appears and STAYS ✅
3. Check both windows → Both have panels ✅

**Experts Log:**
```
M61: 📊 Found our subwindow: 1 (by name: OVO Renko [M61] Mean)
M61: ✅ Panel created successfully in subwindow 1
M62: 📊 Found our subwindow: 2 (by name: OVO Renko [M62] Mean)
M62: ✅ Panel created successfully in subwindow 2
[M61 timer continues but never changes subwindow - locked at 1]
[M62 timer continues but never changes subwindow - locked at 2]
```

## Key Differences

| Approach | First Instance | Second Instance | Stable? |
|----------|---------------|-----------------|---------|
| **LAST window** | ✅ Works initially | ❌ Gets overwritten | ❌ No |
| **ChartWindowFind** | ✅ Works | ✅ Works | ✅ Yes |

## Commits

- **77e5aac** - Initial "last window" approach (broken for multiple instances)
- **4841a0e** - Fixed with ChartWindowFind by name (OVO pattern) ✅

## Lessons Learned

1. **Don't use dynamic chart properties for window detection**
   - `CHART_WINDOWS_TOTAL` changes over time
   - Can't be used to determine "my window"

2. **Use unique identifiers**
   - Short name includes period token (M61, M62, etc.)
   - Each instance is uniquely identifiable

3. **Follow the reference code closely**
   - OVO uses ChartWindowFind for a reason
   - It's the correct MT5 pattern

4. **Lock in values early**
   - Once window is found, save it: `g_our_subwindow = subwindow`
   - Never recalculate after initial assignment

## Related Documentation

- `/Docs/AUTO_INCREMENT_PERIOD.md` - How M61, M62, M63 are assigned
- `/Docs/PANEL_VISIBILITY_FIX.md` - Panel object creation fixes
- `/Docs/PANEL_WIDTH_NOTE.md` - Window height enforcement
