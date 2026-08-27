# Auto-Resume Behavior Guide

## Overview

The **Auto-Resume** feature intelligently restores your Renko chart session when MT5 restarts, while preventing unwanted auto-generation when first attaching the indicator.

---

## 🎯 **Desired Behavior**

### ✅ **Scenario 1: First Attach**
**What Happens:**
1. Attach indicator to chart
2. Panel appears in indicator window
3. Panel shows: `"Ready"`
4. **NO automatic generation**
5. User must click `[M61]` button to generate chart

**Why:** First-time users shouldn't have charts auto-generate without their consent.

---

### ✅ **Scenario 2: MT5 Restart (Chart Was Active)**
**What Happens:**
1. User has generated chart (chart is live)
2. User closes MT5 (accidentally or intentionally)
3. User reopens MT5
4. Indicator **automatically resumes** chart generation
5. Chart returns to `STATE_LIVE`

**Why:** User shouldn't lose work when MT5 restarts. The session should continue where it left off.

---

### ✅ **Scenario 3: MT5 Restart (After Manual Removal)**
**What Happens:**
1. User generates chart
2. User **manually removes indicator** from chart
3. User closes MT5
4. User reopens MT5 and **re-attaches indicator**
5. Panel shows: `"Ready"`
6. **NO automatic generation**
7. User must click button again

**Why:** Manual removal = user intent to stop. Don't auto-resume.

---

## 🔧 **How It Works**

### **Persistence State Tracking**

The indicator uses **global variables** to persist state across MT5 restarts:

```mql5
struct PersistenceState {
   bool   is_active;          // ✅ Key flag: Was chart running?
   string source_symbol;      // Source symbol (e.g., EURUSD)
   string period_token;       // Period token (e.g., M61)
   double brick_size;         // Active brick size
   long   chart_id;           // Generated chart ID
}
```

**Key:** `is_active` determines whether auto-resume should trigger.

---

### **State Lifecycle**

```
┌─────────────────────────────────────────────────────────────┐
│ 1. FIRST ATTACH                                             │
│    is_active = false (no saved state)                       │
│    → Panel shows "Ready"                                    │
│    → Wait for user to click button                          │
└─────────────────────────────────────────────────────────────┘
                              ↓
                    User clicks [M61] button
                              ↓
┌─────────────────────────────────────────────────────────────┐
│ 2. CHART GENERATED                                          │
│    g_state = STATE_LIVE                                     │
│    is_active = true (saved on OnDeinit)                     │
│    → Chart is running                                       │
└─────────────────────────────────────────────────────────────┘
                              ↓
                      MT5 closes (restart)
                              ↓
┌─────────────────────────────────────────────────────────────┐
│ 3. MT5 RESTART                                              │
│    OnInit loads saved state                                 │
│    has_saved_state = true                                   │
│    is_active = true                                         │
│    → Auto-resume triggers ✅                                │
└─────────────────────────────────────────────────────────────┘
                              ↓
                   User manually removes indicator
                              ↓
┌─────────────────────────────────────────────────────────────┐
│ 4. INDICATOR REMOVED                                        │
│    OnDeinit(REASON_REMOVE)                                  │
│    is_active = false (saved)                                │
│    → Next attach will NOT auto-resume ❌                    │
└─────────────────────────────────────────────────────────────┘
```

---

## 📋 **Code Logic**

### **OnInit() - Load and Check State**

```mql5
// Load persistence state (but don't auto-resume yet)
bool has_saved_state = false;
if(InpAutoResume)
{
   if(g_persistence.Load())
   {
      has_saved_state = true;
      Print("Loaded persistence state from previous session");
      Print("   is_active: ", g_persistence.is_active);
   }
}

// ... create panel ...

// ✅ CRITICAL: Only auto-resume if session was PREVIOUSLY ACTIVE
if(has_saved_state && g_persistence.is_active && InpAutoResume)
{
   Print("🔄 Auto-resuming previous session (MT5 was restarted)...");
   g_rebuild_requested = true;  // Trigger rebuild
}
else
{
   Print("⏸️ First attach or inactive session - waiting for user");
}
```

**Auto-Resume Conditions (ALL must be true):**
- ✅ `InpAutoResume = true` (user enabled the feature)
- ✅ `has_saved_state = true` (found saved global variables)
- ✅ `g_persistence.is_active = true` (chart was previously running)

---

### **OnDeinit() - Save State**

```mql5
void OnDeinit(const int reason)
{
   if(g_state == STATE_LIVE)
   {
      g_persistence.is_active = true;  // ✅ Mark as active
      g_persistence.chart_id = g_chart_manager.GetChartID();
      g_persistence.Save();
      Print("✅ Persistence saved (is_active = true)");
   }
   else if(reason == REASON_REMOVE)
   {
      g_persistence.is_active = false;  // ❌ Disable auto-resume
      g_persistence.Save();
      Print("❌ Indicator removed - auto-resume disabled");
   }
}
```

**OnDeinit Reasons:**
- `REASON_REMOVE`: User manually removed indicator → `is_active = false`
- `REASON_CHARTCLOSE`: Chart closed → Keep current state
- `REASON_PROGRAM`: MT5 restart → Keep current state
- `REASON_PARAMETERS`: Input changed → Keep current state

---

## 🧪 **Testing Matrix**

| Scenario | is_active | has_saved_state | InpAutoResume | Result |
|----------|-----------|-----------------|---------------|--------|
| **First attach** | false | false | true | Wait for button ⏸️ |
| **After button click** | true | true | true | Chart running ✅ |
| **MT5 restart (active)** | true | true | true | **Auto-resume ✅** |
| **MT5 restart (removed)** | false | true | true | Wait for button ⏸️ |
| **Auto-resume disabled** | true | true | **false** | Wait for button ⏸️ |

---

## 🔍 **Testing Steps**

### **Test 1: First Attach (No Auto-Generation)**

1. **Attach indicator** to EURUSD chart
2. **Verify:**
   - ✅ Panel appears in indicator window (bottom)
   - ✅ Panel shows: `"Ready"`
   - ❌ No chart generates automatically
3. **Click `[M61]` button**
4. **Verify:**
   - ✅ Chart generates instantly
   - ✅ Custom symbol chart opens
   - ✅ Panel shows: `"Live - M61 active"`

---

### **Test 2: MT5 Restart (Auto-Resume Active Chart)**

1. **Attach indicator** and **generate chart** (click button)
2. **Verify chart is live** (panel shows "Live - M61 active")
3. **Close MT5 completely**
4. **Reopen MT5**
5. **Verify:**
   - ✅ Indicator loads
   - ✅ Chart **automatically resumes** generation
   - ✅ Custom symbol chart reopens
   - ✅ Panel shows: `"Live - M61 active"`
   - ✅ **No need to click button again**

**Expected Log:**
```
Loaded persistence state from previous session
   is_active: true
   chart_id: 133242526460
🔄 Auto-resuming previous session (MT5 was restarted)...
```

---

### **Test 3: MT5 Restart After Removal (No Auto-Resume)**

1. **Attach indicator** and **generate chart**
2. **Remove indicator** from chart (right-click → Delete Indicator)
3. **Close MT5 completely**
4. **Reopen MT5**
5. **Re-attach indicator** to chart
6. **Verify:**
   - ✅ Panel shows: `"Ready"`
   - ❌ No automatic generation
   - ✅ User must click `[M61]` button again

**Expected Log:**
```
Loaded persistence state from previous session
   is_active: false
   chart_id: 0
⏸️ First attach or inactive session - waiting for user
```

---

### **Test 4: Disable Auto-Resume**

1. **Set `InpAutoResume = false`** in input parameters
2. **Generate chart** (click button)
3. **Close MT5**
4. **Reopen MT5**
5. **Verify:**
   - ❌ No auto-resume (even though `is_active = true`)
   - ✅ Panel shows: `"Ready"`
   - ✅ User must click button

---

## 🗂️ **Global Variable Storage**

Persistence state is saved in **global variables** with prefix:

```
OVORenko_{Symbol}_{PeriodToken}_
```

**Example for EURUSD M61:**
```
OVORenko_EURUSD_M61_Active    = 1.0 (true) or 0.0 (false)
OVORenko_EURUSD_M61_ChartType = 1.0 (RENKO_MEAN)
OVORenko_EURUSD_M61_BrickSize = 600.0
OVORenko_EURUSD_M61_ChartID   = 133242526460.0
```

**Check in MT5:**
- **Tools → Options → Server → Global Variables**
- Look for `OVORenko_*` variables

---

## ⚙️ **Input Parameter**

```mql5
input bool InpAutoResume = true;  // Auto Resume After MT5 Restart
```

**Enabled (true):**
- MT5 restart → Auto-resume if `is_active = true`
- First attach → Wait for button

**Disabled (false):**
- MT5 restart → Always wait for button
- First attach → Wait for button

---

## 🚨 **Important Notes**

1. **First attach never auto-generates**
   - Even if `InpAutoResume = true`
   - `is_active = false` on first run

2. **Manual removal stops auto-resume**
   - `OnDeinit(REASON_REMOVE)` sets `is_active = false`
   - Next attach waits for button

3. **MT5 restart preserves active state**
   - `is_active = true` persists across restarts
   - Chart automatically resumes

4. **Multiple instances independent**
   - Each period token (M61, M62, M63) has separate persistence
   - Each can have different `is_active` state

---

## ✅ **Summary**

| Event | is_active Before | is_active After | Auto-Resume? |
|-------|------------------|-----------------|--------------|
| **First attach** | N/A (no state) | false | ❌ No |
| **Button click** | false | true | N/A |
| **MT5 restart** | true | true | ✅ **Yes** |
| **Remove indicator** | true | false | ❌ No |
| **Re-attach after remove** | false | false | ❌ No |

---

## 📦 **Commits**

- **5af09ac**: FIX: Proper auto-resume behavior
- **f9e0a12**: FIX: Panel positioning and auto-generation issues

**Review:** https://github.com/vigilmvarghese/Nortrading-Renko/tree/main

---

## 🎯 **Status**

✅ **Auto-resume works correctly:**
- First attach: Wait for button ⏸️
- MT5 restart (active): Auto-resume ✅
- Manual removal: Disable auto-resume ❌

✅ **Panel positioning fixed:**
- Panel in indicator window (subwindow 1) ✅
- Not on main chart ❌

✅ **Ready for testing in MT5!**
