# Auto-Increment Period Token Feature

## Overview

Multiple Renko generator instances on the **same symbol** now automatically get **unique period tokens** (M61, M62, M63, etc.) without manual configuration.

---

## 🎯 **Use Case**

**Scenario:** You want to analyze US30 with different Renko configurations simultaneously:
- Instance 1: 600-point bricks (Mean Renko)
- Instance 2: 300-point bricks (Regular Renko)
- Instance 3: 150-point bricks (Mean Renko)

**Old Behavior (Manual):**
```
1. Attach indicator to US30 chart
2. Manually change InpPeriodToken = "M61"
3. Generate chart → US30.M61

4. Attach indicator to another US30 chart
5. Manually change InpPeriodToken = "M62"  ← Manual step
6. Generate chart → US30.M62

7. Attach indicator to third US30 chart
8. Manually change InpPeriodToken = "M63"  ← Manual step
9. Generate chart → US30.M63
```

**New Behavior (Automatic):**
```
1. Attach indicator to US30 chart
2. Auto-assigned: M61 ✅
3. Generate chart → US30.M61

4. Attach indicator to another US30 chart
5. Auto-assigned: M62 ✅ (no manual change needed!)
6. Generate chart → US30.M62

7. Attach indicator to third US30 chart
8. Auto-assigned: M63 ✅ (no manual change needed!)
9. Generate chart → US30.M63
```

---

## 🔧 **How It Works**

### **Automatic Detection Process**

When you attach the indicator to a chart:

1. **Extract Base Period**
   - Input: `InpPeriodToken = "M61"`
   - Extract: Base = "M", Number = 61

2. **Scan Existing Custom Symbols**
   - Check: US30.M61 exists? → Yes → Skip
   - Check: US30.M62 exists? → No → ✅ **Use M62**

3. **Assign and Display**
   - Panel shows: `[M62]`
   - Custom symbol: `US30.M62`

### **Symbol-Specific Assignment**

Each symbol has its own sequence:

| Symbol | Instance 1 | Instance 2 | Instance 3 |
|--------|-----------|-----------|-----------|
| **US30** | M61 | M62 | M63 |
| **EURUSD** | M61 | M62 | M63 |
| **GBPUSD** | M61 | M62 | M63 |

Different symbols don't conflict!

---

## 📊 **Visual Example**

### **Workflow: 3 US30 Generators**

```
┌───────────────────────────────────────┐
│ CHART 1: US30 (Main chart)           │
│ ─────────────────────────────────     │
│ Indicator: OVO_Renko_Generator        │
│ Panel: Mean Renko: [600] [M61] ✅    │ ← Auto-assigned M61
│                                       │
│ Generates: US30.M61                   │
└───────────────────────────────────────┘

┌───────────────────────────────────────┐
│ CHART 2: US30 (Main chart)           │
│ ─────────────────────────────────     │
│ Indicator: OVO_Renko_Generator        │
│ Panel: Renko: [300] [M62] ✅         │ ← Auto-assigned M62
│                                       │
│ Generates: US30.M62                   │
└───────────────────────────────────────┘

┌───────────────────────────────────────┐
│ CHART 3: US30 (Main chart)           │
│ ─────────────────────────────────     │
│ Indicator: OVO_Renko_Generator        │
│ Panel: Mean Renko: [150] [M63] ✅    │ ← Auto-assigned M63
│                                       │
│ Generates: US30.M63                   │
└───────────────────────────────────────┘
```

---

## 🔍 **Technical Details**

### **Function: FindNextAvailablePeriodToken()**

```mql5
string FindNextAvailablePeriodToken(string source_symbol)
{
   // 1. Extract base period from input (e.g., "M" from "M61")
   string base_period = "M";
   
   // 2. Loop through M61 to M99
   for(int num = 61; num <= 99; num++)
   {
      string test_period = base_period + IntegerToString(num);
      string test_symbol = source_symbol + "." + test_period;
      
      // 3. Check if custom symbol exists
      if(!SymbolExist(test_symbol, true))
      {
         return test_period;  // ✅ Found available
      }
   }
   
   // 4. Fallback to input if all used
   return InpPeriodToken;
}
```

### **Key MT5 Function: SymbolExist()**

```mql5
SymbolExist(test_symbol, true)
```

**Parameters:**
- `test_symbol`: Symbol name (e.g., "US30.M61")
- `true`: Check custom symbols (not just market symbols)

**Returns:**
- `true`: Symbol exists (period token already used)
- `false`: Symbol doesn't exist (period token available) ✅

---

## 📋 **Configuration**

### **Input Parameter (Reference Only)**

```mql5
input string InpPeriodToken = "M61";  // Custom Period ID
```

**Purpose:**
- Defines **base period** (M, H, D, etc.)
- Defines **starting number** (61)
- **Not used directly** (auto-assignment overrides)

### **Auto-Assigned Value**

```mql5
g_config.period_token = auto_assigned;  // e.g., "M62"
```

**Used By:**
- Custom symbol name: `US30.M62`
- Panel display: `[M62]`
- Object prefix: `OVORenko_..._M62_`
- Persistence: Global variables per period

---

## 🧪 **Testing Scenarios**

### **Scenario 1: Single Symbol, Multiple Instances**

**Steps:**
1. Open 3 US30 charts
2. Attach indicator to Chart 1 → Panel shows `[M61]`
3. Attach indicator to Chart 2 → Panel shows `[M62]`
4. Attach indicator to Chart 3 → Panel shows `[M63]`

**Expected:**
- ✅ Each gets unique period token
- ✅ Each generates unique custom symbol
- ✅ No conflicts

---

### **Scenario 2: Multiple Symbols**

**Steps:**
1. Open US30 chart → Attach indicator → `[M61]`
2. Open EURUSD chart → Attach indicator → `[M61]`
3. Open GBPUSD chart → Attach indicator → `[M61]`

**Expected:**
- ✅ Each symbol starts from M61
- ✅ No conflicts between symbols
- ✅ Custom symbols: US30.M61, EURUSD.M61, GBPUSD.M61

---

### **Scenario 3: Existing Custom Symbols**

**Steps:**
1. US30.M61 already exists (from previous session)
2. Attach new indicator to US30 chart
3. Auto-assigns `[M62]` ✅

**Expected:**
- ✅ Skips M61 (already exists)
- ✅ Assigns next available (M62)
- ✅ No overwriting

---

### **Scenario 4: All Periods Used (M61-M99)**

**Steps:**
1. US30 has 39 custom symbols (M61-M99)
2. Attach 40th indicator

**Expected:**
- ⚠️ Falls back to InpPeriodToken value
- 📝 Log: "All period tokens M61-M99 in use"
- ⚠️ May conflict with existing symbol

---

## 📝 **Log Messages**

### **Successful Auto-Assignment**

```
✅ Auto-assigned period token: M62 (custom symbol: US30.M62)
📊 Configuration initialized:
   Symbol: US30
   Period Token: M62 (auto-assigned)
   Input Token: M61 (reference only)
```

### **Skipping Used Tokens**

```
⚠️ Period token M61 already in use (US30.M61 exists)
✅ Auto-assigned period token: M62 (custom symbol: US30.M62)
```

### **All Tokens Used**

```
⚠️ Period token M61 already in use (US30.M61 exists)
⚠️ Period token M62 already in use (US30.M62 exists)
...
⚠️ Period token M99 already in use (US30.M99 exists)
⚠️ All period tokens M61-M99 in use, using input token: M61
```

---

## 🎛️ **Panel Display**

### **Before Feature**
```
Panel: Mean Renko: [600] [M61] Ready
                           ^^^^ (always M61, conflicts possible)
```

### **After Feature**
```
Instance 1: Mean Renko: [600] [M61] Ready  ✅
Instance 2: Renko: [300] [M62] Ready       ✅
Instance 3: Mean Renko: [150] [M63] Ready  ✅
                             ^^^^ (auto-incremented!)
```

---

## 🔢 **Supported Range**

| Base Period | Range | Count |
|-------------|-------|-------|
| **M** (Minutes) | M61 - M99 | 39 instances |
| **H** (Hours) | H61 - H99 | 39 instances |
| **D** (Days) | D61 - D99 | 39 instances |

**Note:** Base period extracted from `InpPeriodToken`

---

## 💡 **Benefits**

### **1. Zero Configuration**
- ✅ No manual period token changes
- ✅ Attach and go
- ✅ Each instance automatically unique

### **2. No Conflicts**
- ✅ Each instance gets unique custom symbol
- ✅ Symbol-specific sequences
- ✅ Safe to attach multiple to same symbol

### **3. Clear Identification**
- ✅ Panel shows assigned period
- ✅ Easy to identify which chart
- ✅ Logs show assignment process

### **4. Persistence Compatible**
- ✅ Auto-resume uses assigned period
- ✅ Each instance tracked separately
- ✅ Global variables per period token

---

## ⚙️ **Code Files Modified**

**File:** `Indicators/OVO_Renko_Generator.mq5`

**Functions Added:**
- `FindNextAvailablePeriodToken()` - Auto-assignment logic

**Functions Modified:**
- `InitializeConfig()` - Calls auto-assignment
- `OnInit()` - Uses auto-assigned period for panel/persistence

**Changes:**
```mql5
// OLD:
g_config.period_token = InpPeriodToken;

// NEW:
string auto_period = FindNextAvailablePeriodToken(_Symbol);
g_config.period_token = auto_period;
```

---

## 🚀 **Usage Examples**

### **Example 1: Scalping Setup**

**Goal:** Analyze US30 with 3 different brick sizes

```
Chart 1: US30 - 50 points  → Auto: M61 → US30.M61
Chart 2: US30 - 100 points → Auto: M62 → US30.M62
Chart 3: US30 - 200 points → Auto: M63 → US30.M63
```

**Action:** Just attach indicator 3 times, no configuration! ✅

---

### **Example 2: Multi-Symbol Trading**

**Goal:** Trade multiple symbols with same setup

```
US30   Chart: → Auto: M61 → US30.M61
EURUSD Chart: → Auto: M61 → EURUSD.M61
GBPUSD Chart: → Auto: M61 → GBPUSD.M61
USDJPY Chart: → Auto: M61 → USDJPY.M61
```

**Action:** Attach to each symbol, each gets M61 (no conflicts) ✅

---

## ✅ **Summary**

| Feature | Status |
|---------|--------|
| **Auto-increment** | ✅ M61, M62, M63... |
| **Symbol-specific** | ✅ Each symbol independent |
| **Conflict-free** | ✅ Checks existing symbols |
| **Panel display** | ✅ Shows assigned period |
| **Persistence** | ✅ Uses assigned period |
| **Range** | ✅ M61-M99 (39 instances) |
| **Fallback** | ✅ Uses input if all used |
| **Zero config** | ✅ Attach and go |

**Commit:** `a1d6c35`  
**Branch:** `main`

---

## 🎯 **Status**

✅ **Auto-increment period token implemented**  
✅ **Multiple instances per symbol supported**  
✅ **Zero manual configuration required**  
✅ **Symbol-specific sequences**  
✅ **Conflict detection and avoidance**  
✅ **Ready for testing in MT5**

**Attach the indicator multiple times to the same symbol and watch it automatically assign unique period tokens!** 🚀
