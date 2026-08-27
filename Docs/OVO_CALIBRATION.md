# OVO-Style Renko Calibration

## Overview

The Nortrading Renko system has been completely rewritten to match the **proven OVO_Style_Omnia_MT5** reference implementation. This document explains the key architectural patterns extracted from the working OVO codebase.

---

## 🎯 **Core OVO Patterns**

### **1. State Management**

```mql5
// OVO uses simple globals for engine state
bool     g_seeded = false;
double   g_last_close = 0.0;
int      g_last_dir = 0;       // +1 up, -1 down, 0 none
double   g_pending_high = 0.0;
double   g_pending_low = 0.0;
double   g_last_price = 0.0;
ulong    g_tick_volume = 0;
datetime g_next_bar_time = D'2000.01.01 00:00';
```

### **2. Brick Timestamp Sequencing**

```mql5
// Initial value
g_next_bar_time = D'2000.01.01 00:00';

// On each completed brick
r.time = g_next_bar_time;
g_next_bar_time += 60;  // 60 seconds between bricks
```

**Why this works:**
- MT5 custom symbols need unique, monotonically increasing timestamps
- Fixed 60-second spacing provides visual separation
- Prevents timestamp collision that causes vertical stacking

---

## 📦 **Regular Renko Logic**

### **Critical: Prior Extremes Pattern**

```mql5
int ProcessPrice(const double raw_price, const bool history_mode=false)
{
   const double price = NormalizeToTick(raw_price);
   
   if(!g_seeded) {
      SeedEngine(price);
      return 0;
   }
   
   // ✅ CRITICAL: Save extremes BEFORE processing
   const double prior_high = g_pending_high;
   const double prior_low = g_pending_low;
   const ulong prior_vol = g_tick_volume;
   
   g_last_price = price;
   g_tick_volume++;
   
   int made = 0;
   bool first_emitted = true;
   
   // Multi-brick loop
   for(int guard=0; guard<10000; guard++) {
      bool emitted = false;
      
      if(g_last_dir == 0) {
         // Check both directions
      }
      else if(g_last_dir > 0) {
         // Continuation: price >= last_close + box
         if(price >= g_last_close + g_box) {
            CompleteUpBrick(false,
                           first_emitted ? prior_high : g_last_close,
                           first_emitted ? prior_low : g_last_close,
                           prior_vol);
            emitted = true;
         }
         // Reversal: price <= last_close - 2*box
         else if(price <= g_last_close - 2.0*g_box) {
            CompleteUpBrick(true,  // reversal=true
                           first_emitted ? prior_high : g_last_close,
                           first_emitted ? prior_low : g_last_close,
                           prior_vol);
            emitted = true;
         }
      }
      // ... bearish logic
      
      if(!emitted) break;
      made++;
      first_emitted = false;
   }
   
   // Reset extremes after completing bricks
   if(made > 0) {
      g_pending_high = MathMax(g_last_close, price);
      g_pending_low = MathMin(g_last_close, price);
      g_tick_volume = 1;
   }
   else {
      g_pending_high = MathMax(g_pending_high, price);
      g_pending_low = MathMin(g_pending_low, price);
   }
   
   return made;
}
```

### **Key Insight:**

**First brick from a tick:**
- Uses `prior_high` and `prior_low` (extremes that existed BEFORE the tick)
- Wicks come from these prior extremes

**Subsequent bricks in same tick:**
- Use `g_last_close` for both high and low extremes
- No wicks carried over - each brick starts fresh

This prevents **wick duplication** and ensures proper box structure.

---

## 🧱 **Brick Completion Functions**

### **Up Brick (Bullish)**

```mql5
void CompleteUpBrick(const bool reversal,
                     const double prior_high,
                     const double prior_low,
                     const ulong volume)
{
   double o, c;
   
   if(reversal) {
      // Reversal DOWN from uptrend (classic Renko 2-box move)
      o = g_last_close - g_box;
      c = g_last_close - 2.0*g_box;
   }
   else {
      // Continuation UP
      o = g_last_close;
      c = g_last_close + g_box;
   }
   
   double hi = MathMax(o, c);
   double lo = MathMin(o, c);
   
   if(UseWicksForSelectedType()) {
      if(reversal)
         lo = MathMin(lo, prior_low);  // Down brick: low wick
      else
         lo = MathMin(lo, prior_low);  // Up brick: low wick
   }
   
   AppendCompleted(o, c, hi, lo, reversal ? -1 : +1, volume);
}
```

### **Down Brick (Bearish)**

```mql5
void CompleteDownBrick(const bool reversal,
                       const double prior_high,
                       const double prior_low,
                       const ulong volume)
{
   double o, c;
   
   if(reversal) {
      // Reversal UP from downtrend
      o = g_last_close + g_box;
      c = g_last_close + 2.0*g_box;
   }
   else {
      // Continuation DOWN
      o = g_last_close;
      c = g_last_close - g_box;
   }
   
   double hi = MathMax(o, c);
   double lo = MathMin(o, c);
   
   if(UseWicksForSelectedType()) {
      if(reversal)
         lo = MathMin(lo, prior_low);  // Up brick: low wick
      else
         hi = MathMax(hi, prior_high);  // Down brick: high wick
   }
   
   AppendCompleted(o, c, hi, lo, reversal ? +1 : -1, volume);
}
```

---

## 📊 **Brick Structure**

### **OHLC Integrity**

```mql5
void AppendCompleted(const double open_price,
                     const double close_price,
                     const double wick_high,
                     const double wick_low,
                     const int direction,
                     const ulong volume)
{
   MqlRates r;
   ZeroMemory(r);
   
   r.time = g_next_bar_time;
   r.open = NormalizeToTick(open_price);
   r.close = NormalizeToTick(close_price);
   r.high = NormalizeToTick(MathMax(MathMax(r.open, r.close), wick_high));
   r.low = NormalizeToTick(MathMin(MathMin(r.open, r.close), wick_low));
   r.tick_volume = (long)MathMax((double)volume, 1.0);
   
   // ✅ CRITICAL: Ensure OHLC integrity
   if(r.high < MathMax(r.open, r.close))
      r.high = MathMax(r.open, r.close);
   if(r.low > MathMin(r.open, r.close))
      r.low = MathMin(r.open, r.close);
   
   g_completed[n] = r;
   g_next_bar_time += 60;
   g_brick_serial++;
   g_last_dir = direction;
   g_last_close = r.close;
}
```

---

## 🎨 **Mean Renko Specifics**

### **Geometry**

```mql5
// Mean Renko uses STEP as input
double step = g_box;           // Input parameter
double body = 2.0 * step;      // Body is always 2x step

// Thresholds
double continuation = step;     // 1 step
double reversal = 3.0 * step;   // 3 steps
```

### **Open Price Calculation**

```mql5
// Mean Renko: open at midpoint of previous brick body
double open_price = (g_prev_body_open + g_prev_body_close) / 2.0;
```

### **Directional Wick Clipping**

```mql5
// OVO Mean Renko wick rule:
//   UP brick: high capped at body close, only LOW wick allowed
//   DOWN brick: low capped at body close, only HIGH wick allowed

if(UseWicksForSelectedType() && made==0) {
   if(dir > 0) {
      // UP brick: cap high, allow low wick
      hi = close_target;
      lo = MathMin(lo, pre_tick_low);
   }
   else {
      // DOWN brick: cap low, allow high wick
      lo = close_target;
      hi = MathMax(hi, pre_tick_high);
   }
}
```

---

## 🛡️ **Safety Guards**

### **Infinite Loop Protection**

```mql5
for(int guard=0; guard<10000; guard++) {
   bool emitted = false;
   
   // ... brick logic
   
   if(!emitted) break;
}
```

### **Price Validation**

```mql5
if(raw_price <= 0.0 || g_box <= 0.0)
   return 0;

const double price = NormalizeToTick(raw_price);
```

---

## 📁 **Files Updated**

| File | Status | Changes |
|------|--------|---------|
| `RegularRenkoEngine.mqh` | ✅ Rewritten | Complete OVO implementation |
| `MeanRenkoEngine.mqh` | ⏳ Pending | Needs OVO calibration |
| `CustomSymbolPublisher.mqh` | ✅ Fixed | Error 5304 handling |
| `RenkoTypes.mqh` | ✅ OK | Brick structure correct |

---

## 🎯 **Expected Results**

### **Before (Broken):**
```
|||||||||||  <- Thin vertical lines
```

### **After (Fixed):**
```
📦📦📦📦📦  <- Proper Renko boxes with body
```

---

## 📚 **Reference**

**Source:** `OVO_Style_Omnia_MT5.mq5`
- **Lines 1520-1603:** ProcessPrice() (Regular Renko)
- **Lines 869-997:** ProcessMeanRenko() (Mean Renko)
- **Lines 410-477:** Complete brick functions
- **Lines 337-343:** Timestamp management

**Key OVO Principles:**
1. Save prior extremes before processing tick
2. First brick uses prior extremes, subsequent bricks use last_close
3. Sequential timestamps (60-second spacing)
4. OHLC integrity checks
5. Multi-brick loop with guard

---

**Status:** ✅ Regular Renko implemented  
**Next:** Mean Renko calibration  
**Commit:** `8e61ce4` - "REWRITE: Implement proven OVO-style Renko logic"
