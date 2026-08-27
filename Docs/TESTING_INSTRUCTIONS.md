# Testing Instructions - Token Collision Fix

## 🚨 CRITICAL: Clean Slate Required

Before testing, you MUST clean up old Global Variables that have the incorrect name format.

### Step 1: Clean Global Variables

1. Open MT5
2. Go to: **Tools → Global Variables** (or press `F3`)
3. Look for variables starting with `OVORenko_Token_`
4. **Delete ALL of them** (select and press Delete)
5. Close the Global Variables window

### Step 2: Remove All Instances

1. Open your chart with OVO_Renko_Generator instances
2. Remove **ALL** instances from the chart
3. Close all Renko custom symbol charts
4. Reopen a fresh chart (e.g., EURUSD)

### Step 3: Recompile Indicator

1. Open MetaEditor (F4)
2. Open: `Indicators/OVO_Renko_Generator.mq5`
3. Compile: Press F7 or click Compile button
4. Check for compilation errors (should compile successfully)
5. Close MetaEditor

## ✅ Test Scenario 1: Multiple Instances

### Test 1.1: Three Instances
```
1. Attach OVO_Renko_Generator to EURUSD chart
   Expected: 
   - Indicator window 1 created
   - Panel shows: M61
   - Log: "✅ Auto-assigned period token: M61 (claimed atomically)"
   
2. Attach OVO_Renko_Generator to EURUSD chart again
   Expected:
   - Indicator window 2 created
   - Panel shows: M62
   - Log: "✅ Auto-assigned period token: M62 (claimed atomically)"
   
3. Attach OVO_Renko_Generator to EURUSD chart third time
   Expected:
   - Indicator window 3 created
   - Panel shows: M63
   - Log: "✅ Auto-assigned period token: M63 (claimed atomically)"
```

### Test 1.2: Verify Logs

Open **Experts** tab in Terminal window, look for:
```
=== OVO Renko Generator V3.0 Initializing ===
🔍 Scanning for available period token...
   Symbol: EURUSD
   Base period: M
✅ Auto-assigned period token: M61 (claimed atomically)
   Global Variable: OVORenko_Token_EURUSD_M61
✅ Period token claimed: M61
```

**Each instance should show a DIFFERENT token!**

### Test 1.3: Verify Global Variables

1. Tools → Global Variables (F3)
2. Look for:
   ```
   OVORenko_Token_EURUSD_M61 = [some number]
   OVORenko_Token_EURUSD_M62 = [some number]
   OVORenko_Token_EURUSD_M63 = [some number]
   ```

**✅ SUCCESS if you see three different variables!**

## ✅ Test Scenario 2: Token Reuse

### Test 2.1: Remove Middle Instance
```
1. Have 3 instances running (M61, M62, M63)
2. Remove the SECOND instance (M62):
   - Right-click on indicator window 2
   - Indicators List → OVO_Renko_Generator → Delete
   
   Expected log:
   "✅ Released period token M62 (deleted global variable: OVORenko_Token_EURUSD_M62)"
   
3. Check Global Variables (F3)
   Expected: Only M61 and M63 remain, M62 is DELETED
```

### Test 2.2: Attach New Instance
```
1. Attach OVO_Renko_Generator to EURUSD chart
   
   Expected:
   - New indicator window created
   - Panel shows: M62 (REUSED the freed token!)
   - Log: "✅ Auto-assigned period token: M62 (claimed atomically)"
```

**✅ SUCCESS if new instance gets M62 (not M64)!**

## ✅ Test Scenario 3: Different Symbols

### Test 3.1: Same Tokens, Different Symbols
```
1. Have 3 EURUSD instances (M61, M62, M63)
2. Open GBPUSD chart
3. Attach OVO_Renko_Generator to GBPUSD
   
   Expected:
   - Gets M61 (same number, different symbol)
   - Global Variable: OVORenko_Token_GBPUSD_M61
   - No conflict with EURUSD M61
```

**✅ SUCCESS if GBPUSD can also use M61!**

## ❌ Failure Symptoms

### If tokens still collide:
```
❌ All instances show "M61" on panel
❌ Log shows same token for all instances
❌ Only ONE Global Variable created: OVORenko_Token_EURUSD_M61
❌ All panels appear in same window
```

**Solution:**
1. Check if you cleaned old Global Variables
2. Check if you recompiled the indicator
3. Check if you removed all old instances before testing
4. Verify you're testing with the latest commit (62234d2)

### If panels don't appear:
```
❌ Window created but no panel
❌ Log shows: "⏳ Waiting for indicator window..."
```

**This is a separate issue** - the token fix doesn't address window detection.
Report this separately if it happens.

## 📊 Expected Results Summary

| Test | Expected Result |
|------|----------------|
| **3 Instances** | M61, M62, M63 (different tokens) |
| **Global Variables** | 3 separate variables (one per token) |
| **Panels** | 3 separate windows with correct tokens shown |
| **Logs** | "claimed atomically" for each token |
| **Remove M62** | Global Variable deleted |
| **Add new instance** | Gets M62 (reused) |
| **Different symbol** | Same token numbers, different GV names |

## 🐛 Reporting Issues

If the test fails, please provide:

1. **Screenshots** of:
   - All indicator windows (showing panels)
   - Global Variables window (F3)
   - Experts log (full log from start)

2. **Information:**
   - How many instances did you attach?
   - What tokens are shown on the panels?
   - How many Global Variables were created?
   - Did you clean old variables before testing?

3. **Log excerpt:**
   - Copy the "Auto-assigned period token" lines for ALL instances
   - Copy any error messages

## 🎯 Success Criteria

✅ **TEST PASSED** if:
1. Three instances get M61, M62, M63 (all different)
2. Three Global Variables created (one per token)
3. Three panels appear in separate windows
4. Removing M62 deletes its Global Variable
5. New instance reuses M62 (not M64)
6. Logs show "claimed atomically" with different tokens

✅ **ISSUE FIXED** when all tests pass!
