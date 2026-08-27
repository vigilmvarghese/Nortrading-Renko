# Panel Disappearing Fix

## Problem

When adding a 2nd instance of the indicator:
- ✅ 2nd indicator window is created
- ✅ Panel appears in 2nd window (M62)
- ❌ **Panel disappears from 1st window (M61)**

## Root Cause

### Issue 1: Weak Window Occupancy Detection

The original window detection logic only checked for **markers**, not for actual panel objects:

```cpp
// OLD CODE (BROKEN)
for(int i = 0; i < total_objects; i++)
{
   string obj_name = ObjectName(ChartID(), i, w, -1);
   if(StringFind(obj_name, "_marker") >= 0)  // Only checking markers!
   {
      // Window occupied
   }
}
```

**Problem:**
- Markers might not be created yet during fast parallel initialization
- Panel objects (BG, TypeLabel, etc.) are created BEFORE markers in some cases
- Instance 2 could see window 1 as "free" even though Instance 1's panel is there

### Issue 2: Race Condition During Initialization

Timeline of the bug:
```
Time  Instance 1 (M61)                Instance 2 (M62)
----  ----------------------------    ----------------------------
T1    OnInit() called
T2    Token M61 claimed ✅
T3    OnTimer() starts
T4    Detect window 1 as free ✅
T5    Create panel in window 1 ✅     OnInit() called
T6    Panel visible in window 1 ✅    Token M62 claimed ✅
T7                                    OnTimer() starts
T8                                    Detect window 1 as "free" ❌ (marker not found)
T9                                    Try to create panel in window 1 ❌
T10                                   CreatePanel() calls DeletePanel() first
T11                                   DeletePanel() doesn't find M62 objects (none exist yet)
T12                                   Objects get created in window 1 (wrong window!)
T13   Panel disappears? ❌            Panel appears in window 1 ❌
```

The exact mechanism was:
- **ChartWindowFind()** returns the FIRST window with the indicator name
- Both instances have the same indicator name: "OVO_Renko_Generator"
- Instance 2's `ChartWindowFind()` returns window 1 (Instance 1's window)
- Instance 2 tries to create panel in window 1, conflict occurs

### Issue 3: No Pre-Creation Validation

The code didn't verify that the window was truly empty before creating the panel:

```cpp
// OLD CODE (BROKEN)
if(subwindow > 0)
{
   // ❌ No check if window already has another panel
   g_panel = new CPanelUI(ChartID(), subwindow, unique_prefix, InpVerboseLog);
   g_panel.CreatePanel();  // Creates objects, potentially in wrong window
}
```

## Solution

### Fix 1: Robust Window Occupancy Detection

**New Logic:**
```cpp
// Scan ALL objects in window, not just markers
for(int i = 0; i < obj_total; i++)
{
   string obj_name = ObjectName(ChartID(), i, w, -1);
   
   // Check if ANY OVORenko panel object exists
   if(StringFind(obj_name, "OVORenko_") == 0)  // Starts with "OVORenko_"
   {
      string our_prefix = StringFormat("OVORenko_%I64d_%s_", ChartID(), g_config.period_token);
      
      if(StringFind(obj_name, our_prefix) == 0)
      {
         // It's OUR object - we already claimed this window
         subwindow = w;
         break;
      }
      else
      {
         // It's ANOTHER instance's object - window is occupied!
         window_occupied = true;
         break;
      }
   }
}

if(window_occupied)
{
   continue;  // Skip this window, try next
}
```

**Benefits:**
- Detects **any** OVORenko panel object (BG, TypeLabel, PeriodButton, etc.)
- Distinguishes between "our" objects and "other instance" objects
- Works even if markers aren't created yet
- No false positives (window truly free vs. occupied)

### Fix 2: Pre-Creation Safety Check

**New Code:**
```cpp
if(subwindow > 0)
{
   // ✅ CRITICAL: Verify window doesn't have another instance's panel
   bool window_occupied = false;
   
   int obj_total = ObjectsTotal(ChartID(), subwindow, -1);
   for(int i = 0; i < obj_total; i++)
   {
      string obj_name = ObjectName(ChartID(), i, subwindow, -1);
      
      if(StringFind(obj_name, "OVORenko_") == 0)  // OVORenko panel object found
      {
         if(StringFind(obj_name, unique_prefix) < 0)  // NOT our prefix
         {
            window_occupied = true;
            Print("❌ Cannot use window ", subwindow, " - already occupied");
            break;
         }
      }
   }
   
   if(window_occupied)
   {
      return;  // Wait for MT5 to create our dedicated window
   }
   
   // Safe to create panel now
   g_panel = new CPanelUI(ChartID(), subwindow, unique_prefix, InpVerboseLog);
   g_panel.CreatePanel();
}
```

**Benefits:**
- Double-checks window is free immediately before panel creation
- Prevents accidental overwriting of another instance's panel
- Waits for MT5 to create the correct window instead of forcing creation

### Fix 3: Post-Creation Verification

**New Code:**
```cpp
bool panel_created = g_panel.CreatePanel();

if(panel_created)
{
   // ✅ Verify objects are in the correct window
   string bg_name = unique_prefix + "BG";
   int bg_window = ObjectFind(ChartID(), bg_name);
   
   if(bg_window == subwindow)
   {
      Print("✅ Verified: Panel objects in window ", subwindow);
   }
   else
   {
      Print("❌ ERROR: Panel objects not in expected window!");
      Print("   Expected: ", subwindow, ", Found: ", bg_window);
   }
}
```

**Benefits:**
- Confirms objects are in the expected window after creation
- Provides early warning if window detection failed
- Helps debugging if issue persists

### Fix 4: Improved OnDeinit

**New Code:**
```cpp
void OnDeinit(const int reason)
{
   Print("=== OVO Renko Generator [", g_config.period_token, "] Deinitializing ===");
   
   // ⚠️ CRITICAL: Skip cleanup on recompile/init failure
   if(reason == REASON_RECOMPILE || reason == REASON_INITFAILED)
   {
      Print("⏭️ Skipping cleanup (recompile/init) - objects should persist");
      return;  // Don't delete objects, MT5 will reinitialize
   }
   
   // Normal cleanup...
}
```

**Benefits:**
- Prevents spurious cleanup during parallel initialization
- Objects persist across recompilation
- Reduces interference between instances during startup

## Expected Behavior After Fix

### Scenario 1: Two Instances
```
1. Attach 1st instance
   - Gets M61 ✅
   - Creates panel in window 1 ✅
   - Panel visible ✅
   
2. Attach 2nd instance
   - Gets M62 ✅
   - Detects window 1 occupied (finds M61 objects) ✅
   - Skips window 1 ✅
   - Creates panel in window 2 ✅
   - Panel in window 1 REMAINS VISIBLE ✅
   - Panel in window 2 visible ✅
```

### Scenario 2: Three Instances
```
1. Instance 1: M61, window 1 ✅
2. Instance 2: M62, window 2 ✅
3. Instance 3: M63, window 3 ✅

All panels remain visible in their respective windows ✅
```

## Testing Instructions

### Test 1: Basic Two-Instance Test
```
1. Clean slate: Remove all instances, delete Global Variables
2. Attach 1st instance to EURUSD
   Expected: Panel in window 1 showing "M61"
   
3. WAIT 2 SECONDS (let it fully initialize)

4. Attach 2nd instance to EURUSD
   Expected: 
   - New window 2 created
   - Panel in window 2 showing "M62"
   - Panel in window 1 STILL VISIBLE showing "M61" ✅
```

### Test 2: Fast Sequential Attach
```
1. Remove all instances
2. Attach instances QUICKLY (without waiting):
   - Attach 1st
   - Attach 2nd immediately
   - Attach 3rd immediately
   
Expected: All three panels visible in windows 1, 2, 3
```

### Test 3: Check Logs
```
Look for in Experts tab:

Instance 1 (M61):
✅ Auto-assigned period token: M61 (claimed atomically)
📊 Total windows on chart: 2
   Checking window 1...
   ✅ Claimed free window: 1 with marker: OVO_Renko_M61_Regular_marker
✅ Panel created successfully in subwindow 1
✅ Verified: Panel objects in window 1

Instance 2 (M62):
✅ Auto-assigned period token: M62 (claimed atomically)
📊 Total windows on chart: 3
   Checking window 1...
   ⚠️ Window 1 occupied by another instance: OVORenko_<ChartID>_M61_BG
   Checking window 2...
   ✅ Claimed free window: 2 with marker: OVO_Renko_M62_Regular_marker
✅ Panel created successfully in subwindow 2
✅ Verified: Panel objects in window 2
```

## Failure Symptoms (If Bug Persists)

❌ **Panel disappears from window 1**
- Check log for: "Window 1 occupied by another instance"
- Should see M62 skip window 1 and claim window 2
- If not, window detection is still broken

❌ **Both panels in same window**
- Check log for: "Verified: Panel objects in window X"
- If both say window 1, pre-creation check failed
- Objects getting created in wrong window

❌ **Panel flickers or reappears**
- Check for multiple OnDeinit calls in log
- Should see: "Skipping cleanup (recompile/init)"
- If not, spurious cleanup is happening

## Related Issues

This fix also addresses:
1. Token collision (fixed in previous commit 62234d2)
2. Window height enforcement (24px, already working)
3. Close button functionality (already working)

## Commit

**Commit:** e7f56cb  
**Branch:** main  
**Files:** Indicators/OVO_Renko_Generator.mq5

## Next Steps

After testing:
- If panels both visible: ✅ **Issue resolved**
- If panel still disappears: Need deeper investigation of MT5 window creation timing
- If other issues: Check logs for window detection sequence
