# Panel Visibility Fix - Commit 77e5aac

## Problem
Panel UI objects were not visible in indicator subwindows despite being created. The logs showed windows being detected but panels remained invisible.

## Root Causes

### 1. Window Detection Method Was Wrong
**Previous approach (3-tier search):**
- Method 1: ChartWindowFind() with short name → Returned -1 (window not registered with that name)
- Method 2: Alternative name format → Still -1
- Method 3: Iterate from window 1 → Found first available window, but wrong one for 2nd instance

**Problem:** When iterating windows 1, 2, 3... we were finding the FIRST available window, but:
- First instance should use window 1
- Second instance should use window 2
- But iteration would make second instance also try window 1 (already taken)

**Solution:** Use the LAST window (newest)
```cpp
int total_windows = (int)ChartGetInteger(ChartID(), CHART_WINDOWS_TOTAL);
int subwindow = total_windows - 1;  // Last window is ours (just created)
```

When an indicator is attached to a chart, MT5 creates a new subwindow at the END of the window list. So:
- Chart has 1 window (main) → attach indicator → now 2 windows, use window 1
- Chart has 2 windows → attach 2nd indicator → now 3 windows, use window 2
- Each instance gets its own dedicated window automatically

### 2. Objects Were Behind the Chart
**Previous setting:**
```cpp
ObjectSetInteger(m_chart_id, name, OBJPROP_BACK, true);  // Behind chart
```

**Problem:** `OBJPROP_BACK = true` means objects are drawn BEHIND the chart canvas, making them invisible in subwindows.

**Solution:**
```cpp
ObjectSetInteger(m_chart_id, name, OBJPROP_BACK, false);  // In front of chart
```

Applied to ALL panel objects:
- Background (OBJ_RECTANGLE_LABEL)
- Chart type label (OBJ_LABEL)
- Brick field (OBJ_EDIT)
- Period button (OBJ_BUTTON)
- Status label (OBJ_LABEL)
- Close button (OBJ_BUTTON)

### 3. No Error Checking
**Previous code:**
```cpp
ObjectCreate(m_chart_id, name, OBJ_LABEL, m_subwindow, 0, 0);
// No validation - if it failed, we'd never know
```

**Solution:** Check return value and log errors
```cpp
if(!ObjectCreate(m_chart_id, name, OBJ_LABEL, m_subwindow, 0, 0))
{
   Print("❌ ERROR: Failed to create object. Error: ", GetLastError());
   return;
}
```

### 4. No Chart Redraw
After creating panel objects, the chart wasn't being refreshed to show them.

**Solution:** Force immediate redraw
```cpp
ChartRedraw(ChartID());
```

## Changes Made

### File: `/Indicators/OVO_Renko_Generator.mq5`
**Function: `OnTimer()` - Panel creation section**

```cpp
// ✅ CRITICAL: Use the LAST window (newest indicator window)
int total_windows = (int)ChartGetInteger(ChartID(), CHART_WINDOWS_TOTAL);
int subwindow = -1;

if(total_windows > 1)
{
   // The LAST window (total_windows - 1) should be ours
   subwindow = total_windows - 1;
   Print("📊 Total windows: ", total_windows, ", using LAST window: ", subwindow);
}

// ✅ Verify we can create objects in this window
if(subwindow > 0)
{
   string test_name = StringFormat("Test_%s_%I64d", g_config.period_token, ChartID());
   if(ObjectCreate(ChartID(), test_name, OBJ_LABEL, subwindow, 0, 0))
   {
      ObjectDelete(ChartID(), test_name);
      Print("✅ Verified window ", subwindow, " is accessible");
   }
   else
   {
      Print("❌ Cannot create objects in window ", subwindow);
      subwindow = -1;
   }
}

if(subwindow > 0)
{
   // Create panel...
   bool panel_created = g_panel.CreatePanel();
   
   if(panel_created)
   {
      Print("✅ Panel created successfully in subwindow ", subwindow);
      
      // ✅ Force a chart redraw to make objects visible
      ChartRedraw(ChartID());
      
      g_state = STATE_PANEL_ONLY;
   }
}
```

### File: `/Include/Renko/PanelUI.mqh`
**All object creation functions updated:**

1. **Error checking added:** All `ObjectCreate()` calls now validate return value
2. **OBJPROP_BACK = false:** All objects set to draw in front
3. **Error logging:** Failed creates print error code via `GetLastError()`

Example (CreateBackground):
```cpp
if(!ObjectCreate(m_chart_id, name, OBJ_RECTANGLE_LABEL, m_subwindow, 0, 0))
{
   Print("❌ ERROR: Failed to create background object in subwindow ", m_subwindow);
   Print("   Error code: ", GetLastError());
   return;
}

// ... set properties ...

ObjectSetInteger(m_chart_id, name, OBJPROP_BACK, false);  // ✅ FRONT (not behind chart)
```

## Expected Behavior After Fix

### First Instance (M61)
1. User attaches indicator to chart
2. MT5 creates subwindow 1
3. OnTimer detects: total_windows=2, uses window 1
4. Panel created with prefix `OVORenko_<ChartID>_M61_`
5. All objects visible at top of subwindow
6. Log shows:
   ```
   📊 Total windows: 2, using LAST window: 1
   ✅ Verified window 1 is accessible
   🎨 Creating panel with:
      Chart ID: <id>
      Subwindow: 1
      Prefix: OVORenko_<id>_M61_
      Chart Type: Mean Renko
      Period: M61
   ✅ Panel created successfully in subwindow 1
   ```

### Second Instance (M62)
1. User attaches another indicator to same chart
2. MT5 creates subwindow 2
3. OnTimer detects: total_windows=3, uses window 2
4. Panel created with prefix `OVORenko_<ChartID>_M62_`
5. All objects visible at top of subwindow (independent from first)
6. Log shows:
   ```
   📊 Total windows: 3, using LAST window: 2
   ✅ Verified window 2 is accessible
   ✅ Panel created successfully in subwindow 2
   ```

### Visual Result
Each indicator window shows:
```
┌─────────────────────────────────────────────────────────────┐
│ Mean Renko: [600] [M61] ........ Ready ................ [X] │  ← 24px panel
├─────────────────────────────────────────────────────────────┤
│                                                             │
│                    (empty indicator space)                  │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

- **Black background** spanning full width
- **White "Mean Renko:" label** on left
- **White input field** showing brick size (editable)
- **Blue button** with period token (M61, M62, etc.)
- **Green status text** in center ("Ready", "LIVE", etc.)
- **Red X button** on right to close indicator
- **No unwanted text** (indicator labels suppressed)

## Testing Instructions

1. **Remove old instances:** Delete any existing OVO Renko indicators from chart
2. **Recompile:** Compile `OVO_Renko_Generator.mq5` in MetaEditor
3. **Attach first instance:**
   - Drag indicator to chart
   - Should see new subwindow with panel visible
   - Check Experts log for "✅ Panel created successfully in subwindow 1"
4. **Attach second instance:**
   - Drag indicator to chart again
   - Should see second subwindow with panel visible
   - Check Experts log for "✅ Panel created successfully in subwindow 2"
5. **Verify independence:**
   - Each panel should have different period token (M61, M62)
   - Edit brick size in one → doesn't affect the other
   - Click period button in one → generates chart for that instance only

## Related Issues Fixed
- Panel objects were invisible (OBJPROP_BACK=true)
- Multiple instances conflicted (wrong window detection)
- No error feedback (silent failures)
- Chart not refreshing (objects created but not shown)

## Commit
- **Hash:** 77e5aac
- **Branch:** main
- **Date:** 2024-01-XX
- **Files Changed:** 
  - `/Indicators/OVO_Renko_Generator.mq5`
  - `/Include/Renko/PanelUI.mqh`
