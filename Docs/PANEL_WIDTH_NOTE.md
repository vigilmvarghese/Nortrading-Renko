# Panel Width and Indicator Window Height

## Issue: "Panel width are not fixed for both indicator window"

### Understanding MT5 Indicator Subwindows

**What's Fixed:**
- ✅ Panel **width** automatically adjusts to chart width (full span)
- ✅ Panel **height** is 24px (fixed in code)
- ✅ Initial indicator window height is 30px (via `#property indicator_height 30`)

**What's NOT Fixed (MT5 Limitation):**
- ❌ **Indicator subwindow height** cannot be "locked" in MT5
- ❌ Users can always drag the window border to resize vertically
- ❌ There is no MT5 property or API to prevent subwindow resizing

### Why the Window Can Be Resized

MT5's `indicator_separate_window` creates a subwindow that:
1. Starts at the height specified by `indicator_height` (default: 30px)
2. Has a draggable border between it and the main chart
3. Can be resized by the user at any time
4. Cannot be programmatically locked

This is **by design** in MetaTrader 5 - all indicator subwindows are resizable.

### What We've Implemented

#### Panel Width Handling (Adaptive)
The panel **width** automatically adjusts when the chart is resized:

```cpp
// In PanelUI.mqh - UpdateWidth()
void UpdateWidth()
{
   int new_width = (int)ChartGetInteger(m_chart_id, CHART_WIDTH_IN_PIXELS);
   
   if(new_width != m_panel_width)
   {
      m_panel_width = new_width;
      CalculatePositions();
      
      // Update background to span full width
      ObjectSetInteger(m_chart_id, m_prefix + "BG", OBJPROP_XSIZE, m_panel_width);
      
      // Reposition controls based on new width
      ObjectSetInteger(m_chart_id, m_prefix + "Status", OBJPROP_XDISTANCE, m_status_x);
      ObjectSetInteger(m_chart_id, m_prefix + "CloseButton", OBJPROP_XDISTANCE, m_close_button_x);
   }
}
```

This is called periodically in `OnTimer()` to ensure the panel always spans the full chart width.

#### Panel Height (Fixed at 24px)
```cpp
m_panel_height = 24;  // Fixed in constructor
```

The panel UI itself is always 24px tall. The objects are positioned at:
- Background: y=0, height=24px
- Controls: y=2 to y=4 (within the 24px strip)

#### Indicator Window Height (Initial 30px)
```cpp
#property indicator_height 30
```

This sets the INITIAL height when the indicator is first attached. After that, the user can resize it.

### Visual Layout

```
┌─────────────────────────────────────────────────────────────┐
│ Mean Renko: [600] [M61] ........ Ready ................ [X] │  ← 24px panel (fixed)
├─────────────────────────────────────────────────────────────┤
│                                                             │
│                    (6px empty space)                        │  ← indicator_height 30 - 24 = 6px
└─────────────────────────────────────────────────────────────┘
```

**If user drags the border:**
```
┌─────────────────────────────────────────────────────────────┐
│ Mean Renko: [600] [M61] ........ Ready ................ [X] │  ← 24px panel (still fixed)
├─────────────────────────────────────────────────────────────┤
│                                                             │
│                                                             │
│                   (extra space added by user)               │  ← User dragged border down
│                                                             │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

The **panel stays at 24px**, but the **subwindow** can be larger if the user resizes it.

## Workarounds

### 1. User Training
Inform users that the indicator window should be kept narrow (30px height). They can:
- Drag the border to make it smaller
- MT5 will remember the height per chart template

### 2. Chart Template
Save a chart template with the ideal window height:
1. Adjust indicator window to desired height (30px)
2. File → Template → Save Template
3. Apply this template to new charts

The indicator already supports this via:
```cpp
input bool InpPreserveChartSetup = true;  // Preserve Generated Chart Setup
```

### 3. Periodic Height Enforcement (Not Recommended)
We could add code to FORCE the window height back to 30px periodically, but:
- ❌ Fights against user actions (bad UX)
- ❌ Can cause flickering
- ❌ Still doesn't prevent user from resizing again

**Not implemented** because it creates a poor user experience.

## Comparison with OVO

**OVO (NinjaTrader):**
- Can lock indicator panel height (NinjaTrader API supports it)
- Panel is part of the main chart canvas (not a separate window)

**MT5:**
- No API to lock subwindow height
- Indicator subwindows are separate from main chart
- All subwindows are user-resizable by design

## Recommendation

**Accept MT5's behavior** as a platform limitation. The panel UI correctly:
1. ✅ Spans full chart width (adapts to resizing)
2. ✅ Has fixed 24px height
3. ✅ Positioned at top of subwindow
4. ✅ Visible in all instances

The **subwindow height** being resizable is a **MetaTrader 5 platform feature**, not a bug. Users who prefer narrow windows can resize once and save as a template.

## Alternative: Use Main Chart Instead?

If the resizable subwindow is unacceptable, we could change to:
```cpp
#property indicator_chart_window
```

**Pros:**
- Panel overlaid on main chart (no separate window)
- No resizing issues

**Cons:**
- ❌ Panel overlaps price action
- ❌ All instances share the same window (conflict!)
- ❌ Doesn't match OVO reference (separate window per indicator)

**Decision:** Keep `indicator_separate_window` as it's the correct approach for multiple independent instances.
