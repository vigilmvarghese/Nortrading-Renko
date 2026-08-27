# Period Token Reuse - Gap Filling

## Feature: Automatic Token Reuse When Instances Are Removed

### Problem (Before Fix)

**Old Behavior:**
```
Chart with instances: M61, M62, M63
User removes M62 (middle instance)
Chart now has: M61, __, M63
User adds new instance
New instance gets: M64 ❌

Result: Tokens accumulate forever, gaps never filled
```

**Issues:**
- Period tokens kept incrementing (M64, M65, M66...)
- Middle tokens (M62) remained unused
- Could eventually run out of tokens (M61-M99 = only 39 slots)
- Inefficient resource usage

### Solution (After Fix)

**New Behavior:**
```
Chart with instances: M61, M62, M63
User removes M62 (middle instance)
Chart now has: M61, __, M63
User adds new instance
New instance gets: M62 ✅

Result: Gaps are automatically filled, tokens reused efficiently
```

**Benefits:**
- ✅ Tokens reused when instances removed
- ✅ Always uses lowest available number
- ✅ Gaps filled automatically
- ✅ Maximum efficiency (can reuse all 39 slots)

## How It Works

### 1. Marker Objects for Tracking

Each instance creates a **hidden marker object** when it finds its window:

```cpp
// Instance with M61 creates:
string marker = "OVO_Renko_M61_Mean_marker";
ObjectCreate(ChartID(), marker, OBJ_LABEL, subwindow, 0, 0);
ObjectSetInteger(ChartID(), marker, OBJPROP_HIDDEN, true);
```

**Marker Properties:**
- Hidden from user view
- Unique per instance (includes period token)
- Persists as long as instance is active
- Deleted when instance is removed

### 2. Token Assignment Logic

**FindNextAvailablePeriodToken()** searches for the lowest free token:

```cpp
for(int num = 61; num <= 99; num++)  // M61 to M99
{
   string test_period = "M" + IntegerToString(num);
   
   // Check if any instance is using this token
   bool token_in_use = false;
   
   // Search all windows for markers with this token
   string mean_marker = "OVO_Renko_" + test_period + "_Mean_marker";
   string regular_marker = "OVO_Renko_" + test_period + "_Regular_marker";
   
   if(ObjectFind(ChartID(), mean_marker) >= 0 || 
      ObjectFind(ChartID(), regular_marker) >= 0)
   {
      token_in_use = true;
   }
   
   if(!token_in_use)
   {
      // This token is available!
      return test_period;
   }
}
```

**Process:**
1. Start from M61 (lowest token)
2. Check if marker exists for that token
3. If marker exists → token in use, try next
4. If marker doesn't exist → token available, use it!
5. Always returns the lowest available number

### 3. Cleanup on Removal

**OnDeinit()** deletes the marker to free the token:

```cpp
void OnDeinit(const int reason)
{
   // Delete our marker object
   string marker = g_unique_name + "_marker";
   if(ObjectFind(ChartID(), marker) >= 0)
   {
      ObjectDelete(ChartID(), marker);
      Print("✅ Released period token ", g_config.period_token);
   }
   
   // ... other cleanup
}
```

**When Instance Is Removed:**
1. OnDeinit() is called
2. Marker object is deleted
3. Period token is now available for reuse
4. Next instance will find it free and use it

## Examples

### Example 1: Fill Middle Gap

```
Initial State:
  Window 1: M61 ✅
  Window 2: M62 ✅
  Window 3: M63 ✅

User removes M62 (window 2):
  Window 1: M61 ✅
  Window 2: [empty]
  Window 3: M63 ✅
  
Marker "OVO_Renko_M62_Mean_marker" is deleted ✅

User adds new instance:
  FindNextAvailablePeriodToken() scans:
    M61 → marker exists → in use
    M62 → marker missing → AVAILABLE! ✅
    
  New instance assigned: M62
  
Final State:
  Window 1: M61 ✅
  Window 2: M62 ✅ (reused!)
  Window 3: M63 ✅
```

### Example 2: Fill First Gap

```
Initial State:
  Window 1: M61 ✅
  Window 2: M62 ✅
  Window 3: M63 ✅

User removes M61 (window 1):
  Window 1: [empty]
  Window 2: M62 ✅
  Window 3: M63 ✅
  
Marker "OVO_Renko_M61_Mean_marker" is deleted ✅

User adds new instance:
  FindNextAvailablePeriodToken() scans:
    M61 → marker missing → AVAILABLE! ✅
    
  New instance assigned: M61
  
Final State:
  Window 1: M61 ✅ (reused!)
  Window 2: M62 ✅
  Window 3: M63 ✅
```

### Example 3: Multiple Gaps

```
Initial State:
  M61, M62, M63, M64, M65

User removes M62 and M64:
  M61, __, M63, __, M65
  
Markers deleted for M62 and M64 ✅

User adds first new instance:
  Scan finds M62 first (lowest available)
  Assigned: M62 ✅
  
Current: M61, M62, M63, __, M65

User adds second new instance:
  Scan finds M64 (next lowest available)
  Assigned: M64 ✅
  
Final: M61, M62, M63, M64, M65 ✅
```

## Technical Implementation

### Marker Search Function

```cpp
bool IsTokenInUse(string period_token)
{
   int total_windows = (int)ChartGetInteger(ChartID(), CHART_WINDOWS_TOTAL);
   
   for(int w = 0; w < total_windows; w++)
   {
      string mean_marker = StringFormat("OVO_Renko_%s_Mean_marker", period_token);
      if(ObjectFind(ChartID(), mean_marker) >= 0)
         return true;
      
      string regular_marker = StringFormat("OVO_Renko_%s_Regular_marker", period_token);
      if(ObjectFind(ChartID(), regular_marker) >= 0)
         return true;
   }
   
   return false;  // Token is free
}
```

### Why Markers Instead of Custom Symbols?

**Previous approach (WRONG):**
```cpp
// Checked if custom symbol exists
string test_symbol = _Symbol + "." + test_period;
bool symbol_exists = SymbolInfoInteger(test_symbol, SYMBOL_CUSTOM, dummy);
```

**Problems:**
- Custom symbols persist after indicator removal
- Can't tell if symbol is from active or dead instance
- Symbols accumulate forever
- Gaps never filled

**Current approach (CORRECT):**
```cpp
// Check if marker object exists
string marker = "OVO_Renko_" + test_period + "_Mean_marker";
bool token_in_use = (ObjectFind(ChartID(), marker) >= 0);
```

**Benefits:**
- Marker deleted when instance removed
- Directly tracks active instances
- Gaps filled automatically
- Accurate real-time tracking

## Edge Cases Handled

### Case 1: All Tokens In Use (M61-M99)
```cpp
if(no_token_available)
{
   // Fallback to input parameter
   return InpPeriodToken;
}
```

### Case 2: Instance Crashes Without Cleanup
- MT5 automatically deletes objects when indicator removed
- Markers are cleaned up even if OnDeinit doesn't run
- Token becomes available on next check

### Case 3: Chart Closed and Reopened
- Markers are chart-specific objects
- New chart session starts fresh
- All tokens available (M61 onwards)

### Case 4: Multiple Charts Same Symbol
- Markers are per-chart (`ChartID()`)
- US30 chart 1 can have M61
- US30 chart 2 can also have M61
- No conflict (different charts)

## Testing the Feature

### Test 1: Basic Gap Filling
1. Attach 3 instances → M61, M62, M63
2. Remove M62 (middle)
3. Attach new instance
4. **Expected:** New instance gets M62 ✅

### Test 2: Remove First
1. Attach 3 instances → M61, M62, M63
2. Remove M61 (first)
3. Attach new instance
4. **Expected:** New instance gets M61 ✅

### Test 3: Remove Last
1. Attach 3 instances → M61, M62, M63
2. Remove M63 (last)
3. Attach new instance
4. **Expected:** New instance gets M63 ✅

### Test 4: Multiple Gaps
1. Attach 5 instances → M61-M65
2. Remove M62, M64 (two gaps)
3. Attach first new instance
4. **Expected:** Gets M62 (lowest gap) ✅
5. Attach second new instance
6. **Expected:** Gets M64 (next gap) ✅

### Test 5: Remove All and Restart
1. Attach 3 instances → M61, M62, M63
2. Remove all instances
3. Attach new instance
4. **Expected:** Gets M61 (starts from lowest) ✅

## Log Messages

**Token Assignment:**
```
✅ Auto-assigned period token: M61 (available slot on chart)
⚠️ Period token M62 in use by active instance
✅ Auto-assigned period token M63 (available slot on chart)
```

**Token Release:**
```
✅ Released period token M62 (deleted marker)
```

**Reuse Confirmation:**
```
✅ Auto-assigned period token: M62 (available slot on chart)
[Previously used, now reused after removal]
```

## Performance Impact

**Minimal:**
- Token search: O(n) where n = 39 tokens (M61-M99)
- Only runs once during OnInit
- Marker deletion: instant (single ObjectDelete)
- No performance impact on runtime

## Comparison: Before vs After

| Scenario | Before | After |
|----------|--------|-------|
| M61, M62, M63 → remove M62 → add new | Gets M64 ❌ | Gets M62 ✅ |
| Remove first (M61) → add new | Gets M64 ❌ | Gets M61 ✅ |
| Remove all → add new | Gets M64 ❌ | Gets M61 ✅ |
| Maximum instances possible | 39 (M61-M99), but gaps waste slots | 39 (M61-M99), all reusable |

## Commit

- **Hash:** 423f742
- **Feature:** Period token reuse with gap filling
- **Files Changed:** `/Indicators/OVO_Renko_Generator.mq5`

## Related Documentation

- `/Docs/AUTO_INCREMENT_PERIOD.md` - Original auto-increment feature
- `/Docs/WINDOW_DETECTION_FIX.md` - Marker-based window detection
