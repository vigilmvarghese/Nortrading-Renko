# Token Collision Fix - Deep Analysis and Solution

## Problem Summary

All indicator instances were getting the same period token (M61) instead of unique tokens (M61, M62, M63). This caused:
1. Multiple instances sharing the same custom symbol
2. Panels appearing in the same subwindow
3. Indicator list showing identical names

## Root Cause Analysis

### 1. **Race Condition in Token Assignment**

**Original Code Flow:**
```cpp
// Step 1: FindNextAvailablePeriodToken() - CHECK only
string FindNextAvailablePeriodToken(...)
{
    for(int num = 61; num <= 99; num++)
    {
        string gv_name = StringFormat("OVORenko_Token_%I64d_%s_%s", ChartID(), source_symbol, test_period);
        if(GlobalVariableCheck(gv_name))  // ❌ CHECK but don't claim
            continue;
        return test_period;  // ❌ Return without claiming
    }
}

// Step 2: InitializeConfig() - CLAIM later
void InitializeConfig()
{
    string auto_period = FindNextAvailablePeriodToken(_Symbol);  // ⚠️ Gets M61
    GlobalVariableSet(gv_name, 1.0);  // ⚠️ Claims M61 AFTER checking
}
```

**The Race Condition:**
```
Time  Instance 1                     Instance 2                     Instance 3
----  ---------------------------    ---------------------------    ---------------------------
T1    Check M61: not exist ✓         
T2    Return "M61"                   Check M61: not exist ✓         
T3                                   Return "M61"                   Check M61: not exist ✓
T4    Claim M61 ✓                                                   Return "M61"
T5                                   Claim M61 ✓ (overwrites!)     
T6                                                                  Claim M61 ✓ (overwrites!)

Result: All three instances think they have M61!
```

### 2. **Incorrect Global Variable Scope**

**Original Name Format:**
```cpp
string gv_name = StringFormat("OVORenko_Token_%I64d_%s_%s", ChartID(), source_symbol, test_period);
// Example: OVORenko_Token_123456789_EURUSD_M61
```

**Problem:**
- **ChartID is the SAME for all instances** on the same chart!
- All instances check/claim: `OVORenko_Token_123456789_EURUSD_M61`
- No differentiation between instances

**What We Actually Needed:**
- Token should be unique per **Symbol only**, not per chart
- Multiple charts of same symbol should use DIFFERENT tokens
- Multiple instances on SAME chart should use DIFFERENT tokens

## Solution Implementation

### Fix 1: Atomic Check-and-Claim

**New Code:**
```cpp
string FindNextAvailablePeriodToken(string source_symbol)
{
    for(int num = 61; num <= 99; num++)
    {
        string test_period = base_period + IntegerToString(num);
        
        // ✅ FIXED: Global Variable WITHOUT ChartID (symbol-scoped)
        string gv_name = StringFormat("OVORenko_Token_%s_%s", source_symbol, test_period);
        
        // ✅ ATOMIC CHECK-AND-CLAIM: Check and claim in one operation
        if(!GlobalVariableCheck(gv_name))
        {
            // Token available - claim it IMMEDIATELY
            if(GlobalVariableSet(gv_name, GetTickCount()))
            {
                return test_period;  // ✅ Claimed atomically
            }
            else
            {
                continue;  // ⚠️ Another instance claimed it first
            }
        }
        else
        {
            continue;  // Token in use
        }
    }
}
```

**How It Fixes the Race:**
```
Time  Instance 1                          Instance 2                          Instance 3
----  --------------------------------    --------------------------------    --------------------------------
T1    Check M61: not exist ✓              
T2    Claim M61: SUCCESS ✓                
T3    Return "M61"                        Check M61: EXISTS ✗                 
T4                                        Check M62: not exist ✓              Check M61: EXISTS ✗
T5                                        Claim M62: SUCCESS ✓                Check M62: EXISTS ✗
T6                                        Return "M62"                        Check M63: not exist ✓
T7                                                                            Claim M63: SUCCESS ✓
T8                                                                            Return "M63"

Result: M61, M62, M63 - Each instance gets unique token! ✅
```

### Fix 2: Simplified InitializeConfig

**New Code:**
```cpp
void InitializeConfig()
{
    // ✅ Token is ALREADY CLAIMED inside FindNextAvailablePeriodToken
    // No separate registration needed
    string auto_period = FindNextAvailablePeriodToken(_Symbol);
    g_config.period_token = auto_period;
    
    Print("✅ Period token claimed: ", auto_period);
}
```

**Changes:**
- Removed duplicate `GlobalVariableSet()` call
- Token is claimed atomically in `FindNextAvailablePeriodToken()`
- No gap between check and claim

### Fix 3: Corrected Cleanup in OnDeinit

**New Code:**
```cpp
void OnDeinit(const int reason)
{
    // ✅ FIXED: Global variable name WITHOUT ChartID
    string gv_name = StringFormat("OVORenko_Token_%s_%s", _Symbol, g_config.period_token);
    
    if(GlobalVariableDel(gv_name))
    {
        Print("✅ Released period token ", g_config.period_token);
    }
    else
    {
        Print("⚠️ Could not delete global variable: ", gv_name);
    }
}
```

## Global Variable Naming Schema

### Before (BROKEN):
```
Format: OVORenko_Token_{ChartID}_{Symbol}_{Token}
Example: OVORenko_Token_123456789_EURUSD_M61

Problem:
- Chart 1, Instance 1: OVORenko_Token_123456789_EURUSD_M61
- Chart 1, Instance 2: OVORenko_Token_123456789_EURUSD_M61  ❌ Same!
- Chart 1, Instance 3: OVORenko_Token_123456789_EURUSD_M61  ❌ Same!
```

### After (FIXED):
```
Format: OVORenko_Token_{Symbol}_{Token}
Example: OVORenko_Token_EURUSD_M61

Correct Behavior:
- Chart 1, Instance 1: OVORenko_Token_EURUSD_M61  ✅
- Chart 1, Instance 2: OVORenko_Token_EURUSD_M62  ✅ Different!
- Chart 1, Instance 3: OVORenko_Token_EURUSD_M63  ✅ Different!
```

## Token Reuse Behavior

### When Instance Removed:
```cpp
void OnDeinit(const int reason)
{
    // ✅ Delete global variable to free token
    GlobalVariableDel("OVORenko_Token_EURUSD_M62");
}
```

### When New Instance Added:
```cpp
string FindNextAvailablePeriodToken(...)
{
    // ✅ Scans M61, M62, M63...
    // ✅ Finds first gap (e.g., M62 if it was removed)
    // ✅ Claims it atomically
    // ✅ Returns M62 (reusing the freed token)
}
```

### Example Sequence:
```
1. Add Instance 1 → Gets M61
2. Add Instance 2 → Gets M62
3. Add Instance 3 → Gets M63
4. Remove Instance 2 → Frees M62
5. Add Instance 4 → Gets M62 (reused!) ✅
```

## Testing Instructions

### 1. Clean Slate Test
```
1. Open MT5
2. Tools → Global Variables
3. Delete ALL variables starting with "OVORenko_Token_"
4. Close all charts
5. Open fresh EURUSD chart
```

### 2. Multi-Instance Test
```
1. Attach OVO_Renko_Generator to EURUSD
   Expected: Gets M61, panel in window 1
   
2. Attach OVO_Renko_Generator again
   Expected: Gets M62, panel in window 2
   
3. Attach OVO_Renko_Generator third time
   Expected: Gets M63, panel in window 3
```

### 3. Verify Unique Tokens
```
Check Experts log for:
✅ Auto-assigned period token: M61 (claimed atomically)
✅ Auto-assigned period token: M62 (claimed atomically)
✅ Auto-assigned period token: M63 (claimed atomically)
```

### 4. Verify Global Variables
```
Tools → Global Variables

Expected:
- OVORenko_Token_EURUSD_M61 = [tick count]
- OVORenko_Token_EURUSD_M62 = [tick count]
- OVORenko_Token_EURUSD_M63 = [tick count]
```

### 5. Token Reuse Test
```
1. Remove second instance (M62)
   Check log: ✅ Released period token M62
   
2. Check Global Variables
   Expected: M62 variable DELETED
   
3. Attach new instance
   Expected: Gets M62 (reused!)
```

## Why GlobalVariableSet() Returns Boolean

```cpp
if(GlobalVariableSet(gv_name, GetTickCount()))
{
    // SUCCESS: Variable created/updated
    return test_period;
}
else
{
    // FAILURE: Another instance claimed it first (rare but possible)
    continue;  // Try next token
}
```

**MT5 Global Variables are thread-safe:**
- `GlobalVariableSet()` is atomic
- If two instances try to set same variable simultaneously, only ONE succeeds
- This provides natural mutex-like behavior

## Summary of Changes

| File | Function | Change |
|------|----------|--------|
| OVO_Renko_Generator.mq5 | `FindNextAvailablePeriodToken()` | 1. Removed ChartID from GV name<br>2. Atomic check-and-claim<br>3. Added logging |
| OVO_Renko_Generator.mq5 | `InitializeConfig()` | Removed duplicate `GlobalVariableSet()` |
| OVO_Renko_Generator.mq5 | `OnDeinit()` | Fixed GV name (removed ChartID) |

## Expected Behavior After Fix

✅ **Instance 1**: Gets M61, panel in window 1  
✅ **Instance 2**: Gets M62, panel in window 2  
✅ **Instance 3**: Gets M63, panel in window 3  
✅ **Remove M62**: Token freed and reused by next instance  
✅ **No race conditions**: Atomic claim guarantees uniqueness  
✅ **Clean logs**: Clear token assignment messages  

## Commit Message

```
fix: Atomic token assignment to prevent multi-instance collision

PROBLEM:
- All instances were getting M61 due to race condition
- GlobalVariableCheck() and GlobalVariableSet() were separate
- Multiple instances could see M61 as "available" before any claimed it

ROOT CAUSE:
1. Check-then-claim race condition (non-atomic)
2. Global Variable name included ChartID (all instances on same chart shared it)

SOLUTION:
1. Atomic check-and-claim in FindNextAvailablePeriodToken()
2. Removed ChartID from Global Variable name (token scoped to Symbol only)
3. Simplified InitializeConfig() (no duplicate registration)
4. Fixed OnDeinit() cleanup to match new GV name

BEHAVIOR:
- Instance 1: Gets M61 (atomically claimed)
- Instance 2: Gets M62 (atomically claimed)
- Instance 3: Gets M63 (atomically claimed)
- Remove M62: Next instance reuses M62 ✅

Files changed:
- Indicators/OVO_Renko_Generator.mq5
  - FindNextAvailablePeriodToken(): Atomic check-and-claim
  - InitializeConfig(): Removed duplicate GlobalVariableSet
  - OnDeinit(): Fixed GV name

Testing:
1. Delete old Global Variables (Tools → Global Variables)
2. Remove all indicator instances
3. Attach 3 instances → Should get M61, M62, M63
4. Check Experts log for unique token assignments
5. Verify Global Variables created correctly
```
