//+------------------------------------------------------------------+
//|                                       OVO_Renko_Generator.mq5    |
//|                        Copyright 2024, Nortrading Renko Project  |
//|                                      https://github.com/vigilm   |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024, Nortrading Renko Project"
#property link      "https://github.com/vigilmvarghese/Nortrading-Renko"
#property version   "3.00"
#property description "MT5 OVO-Style Renko Generator - Exact OVO Implementation"
#property description "Synchronous history build, instant completion"
#property indicator_separate_window
#property indicator_height 24
#property indicator_minimum 0
#property indicator_maximum 1
#property indicator_levelcolor clrNONE
#property indicator_plots   1
#property indicator_buffers 1
#property indicator_type1   DRAW_NONE
#property indicator_color1  clrNONE
#property indicator_label1  ""

//--- Include all components
#include "../Include/Renko/RenkoTypes.mqh"
#include "../Include/Renko/TickIntegrity.mqh"
#include "../Include/Renko/RegularRenkoEngine.mqh"
#include "../Include/Renko/MeanRenkoEngine.mqh"
#include "../Include/Renko/CustomSymbolPublisher.mqh"
#include "../Include/Renko/HistoricalBuilder.mqh"
#include "../Include/Renko/ChartManager.mqh"
#include "../Include/Renko/PanelUI.mqh"
#include "../Include/Renko/TradeOverlay.mqh"

//+------------------------------------------------------------------+
//| Input Parameters                                                 |
//+------------------------------------------------------------------+
input group "=== RENKO ENGINE ==="
input ENUM_RENKO_TYPE InpChartType = RENKO_MEAN;          // Chart Type
input double InpBrickSizePoints = 600;                     // Brick / Step Points
input bool InpSuppressWicks = false;                       // Suppress Candle Wicks
input bool InpRelocateOpen = true;                         // Relocate Reversal Open (gap style)

input group "=== CUSTOM CHART ==="
input string InpPeriodToken = "M61";                       // Custom Period ID (M61, M2, etc)
input int InpHistoryDays = 7;                              // History Days

input group "=== LIVE FEED ==="
input bool InpUseOnTick = true;                            // Use OnTick for zero-latency (fastest)
input int InpLivePumpMs = 20;                              // Timer fallback (if OnTick disabled)

input group "=== PERFORMANCE ==="
input bool InpEnableTickCache = true;                      // Enable Tick Cache
input int InpTickChunkMinutes = 180;                       // Tick load chunk size (minutes)

input group "=== PERSISTENCE ==="
input bool InpAutoResume = true;                           // Auto Resume After MT5 Restart
input bool InpPreserveChartSetup = true;                   // Preserve Generated Chart Setup

input group "=== TRADE DISPLAY ==="
input bool InpShowSourceBidAsk = true;                     // Show Source Bid/Ask
input bool InpShowEntrySlTp = true;                        // Show Entry / SL / TP
input bool InpShowMonetaryLabels = true;                   // Show Monetary SL/TP Labels

input group "=== DIAGNOSTICS ==="
input bool InpVerboseLog = true;                           // Verbose Log
input bool InpMeanRenkoDiagnostics = false;                // Mean Renko Diagnostics

//+------------------------------------------------------------------+
//| Global Variables                                                 |
//+------------------------------------------------------------------+
ENUM_RENKO_STATE g_state = STATE_INITIALIZING;
RenkoConfig g_config;
PersistenceState g_persistence;

// Dummy buffer to force separate window (MT5 requirement)
double g_dummy_buffer[];

// Core components
CTickIntegrityLayer* g_tick_integrity = NULL;
CRegularRenkoEngine* g_regular_engine = NULL;
CMeanRenkoEngine* g_mean_engine = NULL;
CCustomSymbolPublisher* g_publisher = NULL;
CHistoricalBuilder* g_builder = NULL;
CChartManager* g_chart_manager = NULL;
CPanelUI* g_panel = NULL;
CTradeOverlay* g_trade_overlay = NULL;

// Track our subwindow number
int g_our_subwindow = -1;

// Unique identifier for this instance (includes period token)
string g_unique_name = "";

// Timers
int g_live_pump_timer = 0;
datetime g_last_ui_update = 0;
datetime g_last_trade_update = 0;
datetime g_last_chart_check = 0;
ulong g_last_tick_msc = 0;

// Runtime state
double g_runtime_brick_size = 0;
bool g_rebuild_requested = false;
bool g_chart_needs_redraw = false;
bool g_explicit_button_click = false;

//+------------------------------------------------------------------+
//| Custom indicator initialization                                  |
//+------------------------------------------------------------------+
int OnInit()
{
   Print("=== OVO Renko Generator V3.0 Initializing ===");
   
   // ✅ CRITICAL: Set buffer binding to force separate window creation
   SetIndexBuffer(0, g_dummy_buffer, INDICATOR_DATA);
   PlotIndexSetInteger(0, PLOT_DRAW_TYPE, DRAW_NONE);
   PlotIndexSetString(0, PLOT_LABEL, "");  // ✅ Empty label (no text in data window)
   
   if(!ValidateInputs())
      return INIT_PARAMETERS_INCORRECT;
   
   // ✅ Initialize config FIRST (auto-assigns period token)
   InitializeConfig();
   
   g_persistence.source_symbol = _Symbol;
   g_persistence.period_token = g_config.period_token;  // ✅ Use auto-assigned period
   g_persistence.chart_type = InpChartType;
   g_persistence.brick_size = InpBrickSizePoints;
   
   // ✅ Load persistence state (but don't auto-resume yet)
   bool has_saved_state = false;
   if(InpAutoResume)
   {
      if(g_persistence.Load())
      {
         has_saved_state = true;
         Print("Loaded persistence state from previous session");
         Print("   is_active: ", g_persistence.is_active);
         Print("   chart_id: ", g_persistence.chart_id);
      }
   }
   
   CreateComponents();
   
   // ✅ Set a simple display name for the indicator list
   IndicatorSetString(INDICATOR_SHORTNAME, "OVO_Renko_Generator");
   
   // ✅ Store unique identifier for internal use (includes period token)
   g_unique_name = StringFormat("OVO_Renko_%s_%s", 
                                 g_config.period_token,
                                 (InpChartType == RENKO_MEAN ? "Mean" : "Regular"));
   
   // ✅ IMPORTANT: Panel creation is deferred to OnTimer
   // During OnInit, the indicator window may not be fully created yet
   // We'll detect our subwindow and create the panel on first timer call
   g_state = STATE_INITIALIZING;
   
   int timer_ms = MathMax(InpLivePumpMs, 5);
   EventSetMillisecondTimer(timer_ms);
   g_live_pump_timer = timer_ms;
   
   Print("✅ Indicator initialized");
   Print("   Period: ", g_config.period_token, " (auto-assigned)");
   Print("   Type: ", (InpChartType == RENKO_MEAN ? "Mean Renko" : "Regular Renko"));
   Print("   Display name: OVO_Renko_Generator");
   Print("   Unique ID: ", g_unique_name);
   Print("   Panel will be created after window is ready...");
   
   // ✅ DISABLED AUTO-RESUME FOR NOW
   // Fresh attach always waits for user to click button
   // This prevents auto-generation on every instance attach
   Print("⏸️ Waiting for user to click the period button to generate chart");
   
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Custom indicator deinitialization                                |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   Print("=== OVO Renko Generator [", g_config.period_token, "] Deinitializing ===");
   Print("Reason: ", GetDeinitReasonText(reason));
   Print("Current state: ", g_state);
   Print("Our subwindow: ", g_our_subwindow);
   Print("Our prefix: OVORenko_", ChartID(), "_", g_config.period_token, "_");
   
   // ⚠️ CRITICAL: Only clean up if we're being removed, not if it's a recompile/reinit
   // During parallel initialization of multiple instances, we might get spurious OnDeinit calls
   if(reason == REASON_RECOMPILE || reason == REASON_INITFAILED)
   {
      Print("⏭️ Skipping cleanup (recompile/init) - objects should persist");
      return;  // Don't delete objects, MT5 will reinitialize
   }
   
   // ✅ Save persistence state based on current state
   // - If STATE_LIVE: Mark as active so auto-resume works on MT5 restart
   // - If REASON_REMOVE: User manually removed indicator, disable auto-resume
   // - Otherwise: Keep existing state
   
   if(g_state == STATE_LIVE)
   {
      g_persistence.is_active = true;  // ✅ Chart was active, enable auto-resume
      g_persistence.chart_id = g_chart_manager != NULL ? g_chart_manager.GetChartId() : 0;
      g_persistence.Save();
      Print("✅ Persistence state saved (is_active = true) - will auto-resume on restart");
   }
   else if(reason == REASON_REMOVE)
   {
      g_persistence.is_active = false;  // ❌ User removed indicator, disable auto-resume
      g_persistence.Save();
      Print("❌ Indicator removed - auto-resume disabled");
   }
   
   EventKillTimer();
   
   // ✅ Clean up panel objects first
   if(g_panel != NULL)
   {
      Print("Deleting panel objects with prefix: OVORenko_", ChartID(), "_", g_config.period_token, "_");
      delete g_panel;  // Destructor calls DeletePanel()
      g_panel = NULL;
   }
   
   // ✅ Delete our marker object to free up the period token for reuse
   string marker = g_unique_name + "_marker";
   if(ObjectFind(ChartID(), marker) >= 0)
   {
      ObjectDelete(ChartID(), marker);
      Print("✅ Deleted marker for ", g_config.period_token);
   }
   
   // ✅ CRITICAL FIX: Delete global variable with ChartID included
   string gv_name = StringFormat("OVORenko_Token_%I64d_%s_%s", ChartID(), _Symbol, g_config.period_token);
   if(GlobalVariableDel(gv_name))
   {
      Print("✅ Released period token ", g_config.period_token, " (deleted global variable: ", gv_name, ")");
   }
   else
   {
      Print("⚠️ Could not delete global variable: ", gv_name, ", error: ", GetLastError());
   }
   
   // ✅ Release ownership of custom symbol
   string custom_symbol = _Symbol + "." + g_config.period_token;
   string owner_gv = StringFormat("OVORenko_Owner_%s", custom_symbol);
   if(GlobalVariableDel(owner_gv))
   {
      Print("✅ Released ownership of ", custom_symbol);
   }
   
   // ✅ Force delete any remaining objects with our prefix ONLY IN OUR WINDOW
   string prefix = StringFormat("OVORenko_%I64d_%s_", ChartID(), g_config.period_token);
   if(g_our_subwindow > 0)
   {
      int deleted = ObjectsDeleteAll(ChartID(), prefix, g_our_subwindow, -1);  // -1 = all object types
      Print("Deleted ", deleted, " objects with prefix '", prefix, "' from window ", g_our_subwindow);
   }
   
   DestroyComponents();
   
   Print("Deinitialization complete for ", g_config.period_token);
}

//+------------------------------------------------------------------+
//| Custom indicator iteration - ZERO LATENCY TICK PROCESSING       |
//+------------------------------------------------------------------+
int OnCalculate(const int rates_total,
                const int prev_calculated,
                const datetime &time[],
                const double &open[],
                const double &high[],
                const double &low[],
                const double &close[],
                const long &tick_volume[],
                const long &volume[],
                const int &spread[])
{
   // ⚡ ZERO-LATENCY MODE: Process ticks immediately on arrival
   if(InpUseOnTick && g_state == STATE_LIVE)
   {
      ProcessLiveTicks();
   }
   
   return rates_total;
}

//+------------------------------------------------------------------+
//| Timer event - Hybrid mode (OnTick primary, Timer fallback)      |
//+------------------------------------------------------------------+
void OnTimer()
{
   // ✅ CRITICAL: Enforce fixed 24px subwindow height (OVO reference pattern)
   // MT5 allows users to drag the subwindow border, so we continuously restore
   // the compact panel height every timer tick
   if(g_our_subwindow > 0)
   {
      ChartSetInteger(ChartID(), CHART_HEIGHT_IN_PIXELS, g_our_subwindow, 24);
   }
   
   // ✅ FIRST: Check if we need to create the panel (deferred from OnInit)
   if(g_state == STATE_INITIALIZING && g_panel == NULL)
   {
      // ✅ NEW STRATEGY: Don't use ChartWindowFind (returns same window for all instances)
      // Instead: Iterate through ALL windows and find first unclaimed one
      
      int subwindow = -1;
      int total_windows = (int)ChartGetInteger(ChartID(), CHART_WINDOWS_TOTAL);
      
      static int init_attempts = 0;
      init_attempts++;
      
      if(init_attempts == 1 || init_attempts % 10 == 0)
      {
         Print("📊 [", g_config.period_token, "] Looking for window (attempt ", init_attempts, ")");
         Print("   Total windows on chart: ", total_windows);
      }
      
      // Scan all windows to find an unclaimed one
      for(int w = 1; w < total_windows; w++)
      {
         bool window_has_our_panel = false;
         bool window_has_other_panel = false;
         string other_panel_name = "";
         
         // Check all objects in this window
         int obj_total = ObjectsTotal(ChartID(), w, -1);
         
         if(init_attempts == 1 || init_attempts % 10 == 0)
            Print("   Window ", w, " - checking ", obj_total, " objects...");
         
         for(int i = 0; i < obj_total; i++)
         {
            string obj_name = ObjectName(ChartID(), i, w, -1);
            
            // Look for ANY OVORenko panel object (BG, TypeLabel, etc.)
            if(StringFind(obj_name, "OVORenko_") == 0)
            {
               // Extract the period token from the object name
               // Format: OVORenko_{ChartID}_{Token}_ObjectName
               // Example: OVORenko_123456789_M61_BG
               
               string our_prefix = StringFormat("OVORenko_%I64d_%s_", ChartID(), g_config.period_token);
               
               if(StringFind(obj_name, our_prefix) == 0)
               {
                  // This is OUR panel object
                  window_has_our_panel = true;
                  subwindow = w;
                  if(init_attempts == 1 || init_attempts % 10 == 0)
                     Print("      ✅ Found our panel object: ", obj_name);
                  break;
               }
               else
               {
                  // This is ANOTHER instance's panel object
                  window_has_other_panel = true;
                  other_panel_name = obj_name;
                  if(init_attempts == 1 || init_attempts % 10 == 0)
                     Print("      ⚠️ Found other instance's object: ", obj_name);
                  break;
               }
            }
         }
         
         // If we found our panel, use this window
         if(window_has_our_panel)
         {
            subwindow = w;
            if(init_attempts == 1)
               Print("   ✅ [", g_config.period_token, "] Using existing panel in window ", w);
            break;
         }
         
         // If window is occupied by another instance, skip it
         if(window_has_other_panel)
         {
            if(init_attempts == 1 || init_attempts % 10 == 0)
               Print("   ⏭️ Skipping window ", w, " (occupied by another instance)");
            continue;
         }
         
         // Window is free - try to claim it
         if(subwindow < 0)
         {
            // Try to create a test marker to claim this window
            string marker = g_unique_name + "_marker";
            
            if(ObjectCreate(ChartID(), marker, OBJ_LABEL, w, 0, 0))
            {
               ObjectSetInteger(ChartID(), marker, OBJPROP_HIDDEN, true);
               ObjectSetString(ChartID(), marker, OBJPROP_TEXT, g_unique_name);
               ObjectSetInteger(ChartID(), marker, OBJPROP_TIMEFRAMES, OBJ_NO_PERIODS);  // Hide on all timeframes
               
               subwindow = w;
               Print("   ✅ [", g_config.period_token, "] Claimed window ", w, " with marker");
               break;
            }
            else
            {
               if(init_attempts == 1)
                  Print("   ❌ Failed to create marker in window ", w, ", error: ", GetLastError());
            }
         }
      }
      
      // If no window found, wait for MT5 to create one
      if(subwindow < 0 || subwindow == 0)
      {
         if(init_attempts == 1 || init_attempts % 50 == 0)
            Print("⏳ [", g_config.period_token, "] Waiting for window to be available (attempt ", init_attempts, ")");
         
         // ⚠️ CRITICAL: If we've been waiting too long, MT5 might not create our window
         // This can happen if the indicator is being rapidly added/removed
         if(init_attempts > 200)  // 200 timer ticks = ~1-4 seconds depending on timer
         {
            Print("❌ [", g_config.period_token, "] ERROR: Could not find window after ", init_attempts, " attempts");
            Print("   This usually means MT5 didn't create a dedicated window for this instance");
            Print("   Try removing ALL instances and adding them one at a time with a 2-second pause");
            g_state = STATE_PANEL_ONLY;  // Give up, but don't crash
         }
         return;  // Try again on next timer tick
      }
      
      Print("📊 [", g_config.period_token, "] Using subwindow: ", subwindow);
      
      // ✅ Create panel in the claimed window
      if(subwindow > 0)
      {
         string unique_prefix = StringFormat("OVORenko_%I64d_%s_", ChartID(), g_config.period_token);
         
         Print("🎨 [", g_config.period_token, "] Creating panel:");
         Print("   Subwindow: ", subwindow);
         Print("   Prefix: ", unique_prefix);
         
         // ⚠️ CRITICAL DEBUG: List ALL objects in this window BEFORE creating panel
         int obj_count_before = ObjectsTotal(ChartID(), subwindow, -1);
         Print("   Objects in window ", subwindow, " BEFORE creation: ", obj_count_before);
         if(obj_count_before > 0)
         {
            Print("   ⚠️ WARNING: Window is not empty! Listing objects:");
            for(int i = 0; i < obj_count_before; i++)
            {
               string obj = ObjectName(ChartID(), i, subwindow, -1);
               Print("      [", i, "] ", obj);
            }
         }
         
         g_panel = new CPanelUI(ChartID(), subwindow, unique_prefix, InpVerboseLog);
         g_panel.SetChartType(InpChartType);
         g_panel.SetBrickSize(DoubleToString(InpBrickSizePoints, 0));
         g_panel.SetPeriodText(g_config.period_token);
         g_panel.SetStatusText("Ready");
         
         g_our_subwindow = subwindow;
         
         bool panel_created = g_panel.CreatePanel();
         
         if(panel_created)
         {
            Print("✅ [", g_config.period_token, "] Panel created in window ", subwindow);
            
            // ⚠️ CRITICAL DEBUG: List ALL objects in this window AFTER creating panel
            int obj_count_after = ObjectsTotal(ChartID(), subwindow, -1);
            Print("   Objects in window ", subwindow, " AFTER creation: ", obj_count_after);
            Print("   Objects created: ", (obj_count_after - obj_count_before));
            
            // List our objects
            Print("   Our objects:");
            string obj_names[] = {"BG", "TypeLabel", "BrickField", "PeriodButton", "Status", "CloseButton"};
            for(int i = 0; i < ArraySize(obj_names); i++)
            {
               string obj_name = unique_prefix + obj_names[i];
               int found_window = ObjectFind(ChartID(), obj_name);
               if(found_window >= 0)
               {
                  Print("      ✅ ", obj_names[i], " in window ", found_window);
               }
               else
               {
                  Print("      ❌ ", obj_names[i], " NOT FOUND");
               }
            }
            
            // Verify panel objects are visible
            string bg_name = unique_prefix + "BG";
            int bg_window = ObjectFind(ChartID(), bg_name);
            
            if(bg_window == subwindow)
            {
               Print("✅ [", g_config.period_token, "] Verified: Objects in window ", subwindow);
               ChartRedraw(ChartID());
               g_state = STATE_PANEL_ONLY;
               init_attempts = 0;  // Reset counter for next instance
            }
            else
            {
               Print("❌ [", g_config.period_token, "] ERROR: Objects in wrong window!");
               Print("   Expected window: ", subwindow);
               Print("   BG object found in window: ", bg_window);
               // Don't change state - will retry
            }
         }
         else
         {
            Print("❌ [", g_config.period_token, "] ERROR: Panel creation failed!");
            // Don't change state - will retry
         }
      }
      
      return;  // Don't process other states yet
   }
   
   // Timer only handles UI updates and non-live states when OnTick is enabled
   if(InpUseOnTick)
   {
      // Lightweight: Only UI and state management
      switch(g_state)
      {
         case STATE_PANEL_ONLY:
            HandlePanelOnly();
            break;
         
         case STATE_REBUILD_REQUESTED:
            StartRebuild();
            break;
         
         case STATE_LIVE:
            // Tick processing handled by OnCalculate (zero latency)
            // Timer only does UI updates
            break;
      }
      
      PeriodicUIUpdate();
   }
   else
   {
      // Full timer-driven mode (legacy/fallback)
      switch(g_state)
      {
         case STATE_INITIALIZING:
            break;
         
         case STATE_PANEL_ONLY:
            HandlePanelOnly();
            break;
         
         case STATE_REBUILD_REQUESTED:
            StartRebuild();
            break;
         
         case STATE_LIVE:
            ProcessLiveTicks();
            break;
         
         case STATE_STOPPING:
            break;
      }
      
      PeriodicUIUpdate();
   }
}

//+------------------------------------------------------------------+
//| Chart event handler                                              |
//+------------------------------------------------------------------+
void OnChartEvent(const int id,
                  const long &lparam,
                  const double &dparam,
                  const string &sparam)
{
   if(id == CHARTEVENT_OBJECT_CLICK)
   {
      if(g_panel != NULL)
      {
         if(g_panel.IsPeriodButtonClicked())
            OnPeriodButtonClick();
         
         if(g_panel.IsCloseButtonClicked())
            OnCloseButtonClick();
      }
   }
}

//+------------------------------------------------------------------+
//| Validate inputs                                                  |
//+------------------------------------------------------------------+
bool ValidateInputs()
{
   if(InpBrickSizePoints <= 0)
   {
      Print("ERROR: Brick size must be positive");
      return false;
   }
   
   if(InpLivePumpMs < 5)
   {
      Print("ERROR: Live pump minimum is 5 ms");
      return false;
   }
   
   if(InpHistoryDays < 1)
   {
      Print("ERROR: History days must be at least 1");
      return false;
   }
   
   return true;
}

//+------------------------------------------------------------------+
//| Find next available period token for this symbol                |
//+------------------------------------------------------------------+
//| Find next available period token for this symbol                |
//| Uses Global Variables for reliable cross-instance detection     |
//| CRITICAL FIX: Atomic check-and-claim to prevent race condition  |
//+------------------------------------------------------------------+
string FindNextAvailablePeriodToken(string source_symbol)
{
   // Extract base period (M or any prefix) from InpPeriodToken
   string base_period = "M";
   
   // Find where the number starts in InpPeriodToken
   for(int i = 0; i < StringLen(InpPeriodToken); i++)
   {
      if(StringGetCharacter(InpPeriodToken, i) >= '0' && StringGetCharacter(InpPeriodToken, i) <= '9')
      {
         base_period = StringSubstr(InpPeriodToken, 0, i);
         break;
      }
   }
   
   if(base_period == "") base_period = "M";  // Default to M if no prefix found
   
   // ✅ AUTO-INCREMENT: Each chart tries M61 first, then auto-increments if taken
   // Chart A (US30): M61 is free → Gets M61
   // Chart B (US30): M61 is taken → Auto-increments to M62
   // Chart C (US30): M62 is taken → Auto-increments to M63
   
   long chart_id = ChartID();
   
   Print("🔍 Scanning for available period token (auto-increment on collision)...");
   Print("   Chart ID: ", chart_id);
   Print("   Symbol: ", source_symbol);
   Print("   Base period: ", base_period);
   Print("   Starting from: ", base_period, "61");
   
   for(int num = 61; num <= 99; num++)
   {
      string test_period = base_period + IntegerToString(num);
      string test_custom_symbol = source_symbol + "." + test_period;
      
      // ✅ Check 1: Token allocation per chart
      string gv_name = StringFormat("OVORenko_Token_%I64d_%s_%s", chart_id, source_symbol, test_period);
      
      // ✅ Check 2: Custom symbol ownership (the key check for collision)
      string owner_gv = StringFormat("OVORenko_Owner_%s", test_custom_symbol);
      
      // Check if token is already allocated for THIS chart
      if(!GlobalVariableCheck(gv_name))
      {
         // Token not yet allocated to this chart
         // Now check if the custom symbol is taken by ANOTHER chart
         if(GlobalVariableCheck(owner_gv))
         {
            long owner_chart = (long)GlobalVariableGet(owner_gv);
            
            // Check if owner chart still exists
            if(owner_chart != chart_id && ChartSymbol(owner_chart) != "")
            {
               // Another chart owns this custom symbol - skip and try next
               Print("   ⚠️ ", test_period, " → ", test_custom_symbol, " owned by Chart ", owner_chart, " - trying next");
               continue;
            }
            else
            {
               // Owner chart no longer exists - we can take over
               Print("   ✓ ", test_period, " → Previous owner gone, can reuse");
            }
         }
         else
         {
            // Custom symbol is not owned by anyone - available!
            Print("   ✓ ", test_period, " → ", test_custom_symbol, " is FREE");
         }
         
         // Attempt to claim this token atomically
         if(GlobalVariableSet(gv_name, GetTickCount()))
         {
            Print("✅ AUTO-ASSIGNED: ", test_period, " (", test_custom_symbol, ")");
            Print("   Token claimed for Chart ", chart_id);
            return test_period;
         }
         else
         {
            Print("   ⚠️ Failed to claim ", test_period, ", error: ", GetLastError(), " - trying next");
            continue;
         }
      }
      else
      {
         // Token already allocated to this chart (recompile scenario)
         Print("   ⚠️ ", test_period, " already allocated to this chart");
         continue;
      }
   }
   
   // Fallback: All M61-M99 taken
   string fallback = base_period + IntegerToString((int)(TimeCurrent() % 100));
   Print("⚠️ All tokens M61-M99 in use, using fallback: ", fallback);
   return fallback;
}

//+------------------------------------------------------------------+
//| Initialize configuration                                         |
//+------------------------------------------------------------------+
void InitializeConfig()
{
   g_config.chart_type = InpChartType;
   g_config.brick_size_points = InpBrickSizePoints;
   g_config.suppress_wicks = InpSuppressWicks;
   
   // ✅ CRITICAL FIX: FindNextAvailablePeriodToken now does atomic check-and-claim
   // No separate registration needed - token is already claimed inside the function
   string auto_period = FindNextAvailablePeriodToken(_Symbol);
   g_config.period_token = auto_period;  // Use auto-assigned and claimed token
   
   // Token is already registered by FindNextAvailablePeriodToken (atomic operation)
   Print("✅ Period token claimed: ", auto_period);
   
   g_config.history_days = InpHistoryDays;
   g_config.live_pump_ms = InpLivePumpMs;
   g_config.enable_tick_cache = InpEnableTickCache;
   g_config.auto_resume = InpAutoResume;
   g_config.preserve_chart_setup = InpPreserveChartSetup;
   g_config.show_source_bid_ask = InpShowSourceBidAsk;
   g_config.show_entry_sl_tp = InpShowEntrySlTp;
   g_config.show_monetary_labels = InpShowMonetaryLabels;
   g_config.verbose_log = InpVerboseLog;
   g_config.enable_diagnostics = InpMeanRenkoDiagnostics;
   
   g_runtime_brick_size = InpBrickSizePoints;
   
   Print("📊 Configuration initialized:");
   Print("   Symbol: ", _Symbol);
   Print("   Period Token: ", g_config.period_token, " (auto-assigned)");
   Print("   Input Token: ", InpPeriodToken, " (reference only)");
}

//+------------------------------------------------------------------+
//| Create components                                                |
//+------------------------------------------------------------------+
void CreateComponents()
{
   g_tick_integrity = new CTickIntegrityLayer(_Symbol, InpVerboseLog);
   g_tick_integrity.Initialize(_Symbol);
   
   g_regular_engine = new CRegularRenkoEngine(_Symbol, InpVerboseLog);
   g_mean_engine = new CMeanRenkoEngine(_Symbol, InpVerboseLog);
   
   if(InpMeanRenkoDiagnostics)
      g_mean_engine.EnableDiagnostics(true);
   
   g_publisher = new CCustomSymbolPublisher(InpVerboseLog);
   g_builder = new CHistoricalBuilder(_Symbol, InpVerboseLog);
   g_builder.EnableCache(InpEnableTickCache);
   
   g_chart_manager = new CChartManager(InpVerboseLog);
}

//+------------------------------------------------------------------+
//| Destroy components                                               |
//+------------------------------------------------------------------+
void DestroyComponents()
{
   if(g_tick_integrity != NULL)
   {
      delete g_tick_integrity;
      g_tick_integrity = NULL;
   }
   
   if(g_regular_engine != NULL)
   {
      delete g_regular_engine;
      g_regular_engine = NULL;
   }
   
   if(g_mean_engine != NULL)
   {
      delete g_mean_engine;
      g_mean_engine = NULL;
   }
   
   if(g_publisher != NULL)
   {
      delete g_publisher;
      g_publisher = NULL;
   }
   
   if(g_builder != NULL)
   {
      delete g_builder;
      g_builder = NULL;
   }
   
   if(g_chart_manager != NULL)
   {
      delete g_chart_manager;
      g_chart_manager = NULL;
   }
   
   if(g_trade_overlay != NULL)
   {
      delete g_trade_overlay;
      g_trade_overlay = NULL;
   }
}

//+------------------------------------------------------------------+
//| Handle panel-only state                                          |
//+------------------------------------------------------------------+
void HandlePanelOnly()
{
   if(g_panel != NULL)
      g_panel.UpdateWidth();
   
   if(g_rebuild_requested)
      g_state = STATE_REBUILD_REQUESTED;
}

//+------------------------------------------------------------------+
//| SYNCHRONOUS Start rebuild - OVO pattern (instant completion)    |
//| Reference: OVO BuildHistoricalModel() - no async                |
//+------------------------------------------------------------------+
void StartRebuild()
{
   Print("=== Starting SYNCHRONOUS Rebuild ===");
   
   // ✅ Token allocation already handled collision detection
   // FindNextAvailablePeriodToken() checked if custom symbol is in use
   // and auto-incremented to next available token (M61 → M62 → M63)
   
   string expected_symbol = _Symbol + "." + g_config.period_token;
   string ownership_gv = StringFormat("OVORenko_Owner_%s", expected_symbol);
   long this_chart = ChartID();
   
   // Claim ownership of this custom symbol
   GlobalVariableSet(ownership_gv, (double)this_chart);
   Print("✅ Claimed ownership: ", expected_symbol, " → Chart ", this_chart);
   
   g_rebuild_requested = false;
   
   // Get runtime brick size from panel
   if(g_panel != NULL)
   {
      string brick_text = g_panel.GetBrickSize();
      double brick_value = StringToDouble(brick_text);
      if(brick_value > 0)
         g_runtime_brick_size = brick_value;
   }
   
   Print("Brick size: ", g_runtime_brick_size);
   Print("Chart type: ", (g_config.chart_type == RENKO_MEAN ? "Mean Renko" : "Regular Renko"));
   
   // Reset engines
   if(g_config.chart_type == RENKO_REGULAR)
   {
      g_regular_engine.Reset();
      g_regular_engine.Configure(g_runtime_brick_size, g_config.suppress_wicks, InpRelocateOpen);
   }
   else
   {
      g_mean_engine.Reset();
      g_mean_engine.Configure(g_runtime_brick_size, g_config.suppress_wicks);
   }
   
   // Create/verify custom symbol
   if(!g_publisher.CreateCustomSymbol(_Symbol, g_config.period_token))
   {
      Print("ERROR: Failed to create custom symbol");
      g_state = STATE_PANEL_ONLY;
      if(g_panel != NULL)
         g_panel.SetStatusText("ERROR: Symbol failed");
      return;
   }
   
   // ✅ SYNCHRONOUS BUILD - Completes instantly (no async passes)
   if(g_panel != NULL)
      g_panel.SetStatusText("Building...");
   
   bool build_ok = g_builder.BuildHistory(g_config.chart_type,
                                           g_runtime_brick_size,
                                           g_config.suppress_wicks,
                                           g_config.history_days,
                                           InpRelocateOpen);
   
   if(!build_ok)
   {
      Print("ERROR: Historical build failed");
      g_state = STATE_PANEL_ONLY;
      if(g_panel != NULL)
         g_panel.SetStatusText("ERROR: Build failed");
      return;
   }
   
   // Get results
   RenkoBrick results[];
   int count = g_builder.GetResults(results);
   
   Print("Publishing ", count, " bricks (clean regeneration - old bars removed)");
   
   // Publish to custom symbol
   if(!g_publisher.ReplaceHistory(results, count))
   {
      Print("ERROR: Failed to publish history");
      g_state = STATE_PANEL_ONLY;
      if(g_panel != NULL)
         g_panel.SetStatusText("ERROR: Publish failed");
      return;
   }
   
   Print("✅ Published successfully - chart cleaned and regenerated");
   
   // ⚡ CRITICAL: Force complete chart reload to clear old cached bars
   string custom_symbol = g_publisher.GetCustomSymbolName();
   
   // ✅ FIXED: Only close charts that belong to THIS generator instance
   // Check ownership before closing
   string owner_gv = StringFormat("OVORenko_Owner_%s", custom_symbol);
   long current_chart = ChartID();
   long owner_chart_id = current_chart;  // Assume we own it
   
   if(GlobalVariableCheck(owner_gv))
   {
      owner_chart_id = (long)GlobalVariableGet(owner_gv);
   }
   
   // Find existing chart first
   long existing_chart_id = g_chart_manager.FindChart(custom_symbol);
   if(existing_chart_id > 0)
   {
      // ✅ CRITICAL FIX: Only close if WE own this chart
      if(owner_chart_id == current_chart)
      {
         if(InpVerboseLog)
            Print("Found existing chart ", existing_chart_id, " owned by US - closing it to force clean reload");
         
         // This ensures MT5 reloads data from custom symbol (which we just cleaned)
         ChartClose(existing_chart_id);
         
         // Give MT5 time to close and clear cache
         Sleep(300);
         
         if(InpVerboseLog)
            Print("Old chart closed - will reopen with fresh data");
      }
      else
      {
         if(InpVerboseLog)
            Print("Found existing chart ", existing_chart_id, " but it belongs to Chart ", 
                  owner_chart_id, " - NOT closing it");
      }
   }
   
   // Open/switch to chart (will create new chart with clean data)
   long chart_id = g_chart_manager.OpenChart(custom_symbol, g_explicit_button_click);
   
   if(chart_id == 0)
   {
      Print("ERROR: Failed to open chart");
      g_state = STATE_PANEL_ONLY;
      if(g_panel != NULL)
         g_panel.SetStatusText("ERROR: Chart failed");
      return;
   }
   
   if(InpVerboseLog)
      Print("✅ New chart opened with clean data: ", chart_id);
   
   g_explicit_button_click = false;
   
   // Create trade overlay
   g_trade_overlay = new CTradeOverlay(_Symbol, chart_id, "OVOTrade_", InpVerboseLog);
   g_trade_overlay.Configure(InpShowSourceBidAsk, InpShowEntrySlTp, InpShowMonetaryLabels);
   
   // Save template
   if(InpPreserveChartSetup)
   {
      string template_name = "OVORenko_" + _Symbol + "_" + g_config.period_token;
      g_chart_manager.SaveTemplate(template_name);
   }
   
   // Initialize live tick processing
   g_tick_integrity.Reset();
   g_tick_integrity.Initialize(_Symbol);
   
   // Reinitialize appropriate engine with last brick
   if(count > 0)
   {
      RenkoBrick last_brick = results[count - 1];
      double init_price = last_brick.close;
      datetime init_time = last_brick.time;
      
      if(g_config.chart_type == RENKO_REGULAR)
         g_regular_engine.Initialize(init_price, init_time);
      else
         g_mean_engine.Initialize(init_price, init_time);
   }
   
   g_last_tick_msc = 0;
   g_state = STATE_LIVE;
   
   if(g_panel != NULL)
      g_panel.SetStatusText("LIVE");
   
   Print("=== Build Complete - Now LIVE (history built instantly) ===");
   Print("Total bricks: ", count);
}

//+------------------------------------------------------------------+
//| ULTRA-FAST Process live ticks (optimized for zero latency)      |
//+------------------------------------------------------------------+
void ProcessLiveTicks()
{
   if(g_tick_integrity == NULL)
      return;
   
   // ⚡ CRITICAL FAST PATH: Check if there's a new tick
   if(!g_tick_integrity.HasNewTick())
      return;  // Zero overhead if no new tick
   
   // Get new ticks
   MqlTick new_ticks[];
   int tick_count = g_tick_integrity.GetNewTicks(new_ticks);
   
   if(tick_count <= 0)
      return;
   
   // ⚡ OPTIMIZED: Pre-allocate for completed bricks
   RenkoBrick completed[];
   int completed_count = 0;
   ENUM_DIRTY_STATE dirty_state = DIRTY_NONE;
   
   // Process each tick with minimal overhead
   for(int i = 0; i < tick_count; i++)
   {
      double price = new_ticks[i].bid > 0 ? new_ticks[i].bid : new_ticks[i].last;
      
      if(price > 0)
      {
         if(g_config.chart_type == RENKO_REGULAR)
            dirty_state = g_regular_engine.ProcessTick(price, new_ticks[i].time);
         else
            dirty_state = g_mean_engine.ProcessTick(price, new_ticks[i].time);
      }
      
      g_tick_integrity.MarkProcessed(new_ticks[i]);
   }
   
   // ⚡ FAST PATH: Skip if no changes
   if(dirty_state == DIRTY_NONE)
      return;
   
   // Get completed bricks only if needed
   if(dirty_state == DIRTY_BRICK_COMPLETED || dirty_state == DIRTY_MULTI_BRICK_COMPLETED)
   {
      if(g_config.chart_type == RENKO_REGULAR)
         completed_count = g_regular_engine.GetCompletedBricks(completed);
      else
         completed_count = g_mean_engine.GetCompletedBricks(completed);
   }
   
   // Get forming brick
   RenkoBrick forming;
   if(g_config.chart_type == RENKO_REGULAR)
      forming = g_regular_engine.GetFormingBrick();
   else
      forming = g_mean_engine.GetFormingBrick();
   
   // ⚡ INSTANT PUBLISH: No buffering, immediate update
   if(dirty_state == DIRTY_FORMING_CHANGED)
   {
      g_publisher.UpdateFormingOnly(forming);
   }
   else if(dirty_state == DIRTY_BRICK_COMPLETED || dirty_state == DIRTY_MULTI_BRICK_COMPLETED)
   {
      g_publisher.UpdateRates(completed, completed_count, forming);
      
      // ⚡ IMMEDIATE CHART REFRESH
      if(g_chart_manager != NULL)
         g_chart_manager.Redraw();
   }
}

//+------------------------------------------------------------------+
//| Periodic UI update                                               |
//+------------------------------------------------------------------+
void PeriodicUIUpdate()
{
   datetime now = TimeCurrent();
   
   if(now != g_last_ui_update || (GetTickCount() % 500) == 0)
   {
      if(g_panel != NULL)
         g_panel.UpdateWidth();
      
      g_last_ui_update = now;
   }
   
   if(g_state == STATE_LIVE && g_trade_overlay != NULL)
   {
      if(now - g_last_trade_update >= 1)
      {
         g_trade_overlay.Update();
         g_last_trade_update = now;
      }
   }
   
   if(g_chart_needs_redraw && g_chart_manager != NULL)
   {
      g_chart_manager.Redraw();
      g_chart_needs_redraw = false;
   }
   
   // ✅ Check if generated chart is still open (every 2 seconds)
   CheckGeneratedChart();
}

//+------------------------------------------------------------------+
//| Check generated chart status (detects if closed)                 |
//+------------------------------------------------------------------+
void CheckGeneratedChart()
{
   datetime now = TimeCurrent();
   
   if(now - g_last_chart_check < 2)
      return;
   
   g_last_chart_check = now;
   
   // ✅ CRITICAL: Check if we're in LIVE state but chart is closed
   if(g_state == STATE_LIVE && g_chart_manager != NULL)
   {
      long chart_id = g_chart_manager.GetChartId();
      
      if(chart_id > 0)
      {
         // ✅ Check if the chart still exists
         string chart_symbol = ChartSymbol(chart_id);
         
         if(chart_symbol == "")
         {
            // Chart was closed!
            Print("⚠️ Generated chart was closed - returning to Ready state");
            
            g_state = STATE_PANEL_ONLY;
            
            if(g_panel != NULL)
               g_panel.SetStatusText("Ready");
            
            // Clean up chart manager reference
            if(g_chart_manager != NULL)
               g_chart_manager.SetChartId(0);
            
            return;
         }
         
         // Chart still exists - do maintenance
         g_chart_manager.EnforceM1();
         
         if(InpPreserveChartSetup)
            g_chart_manager.PeriodicTemplateSave();
      }
   }
}

//+------------------------------------------------------------------+
//| Period button click handler                                      |
//+------------------------------------------------------------------+
void OnPeriodButtonClick()
{
   Print("Period button clicked");
   
   if(g_state == STATE_PANEL_ONLY || g_state == STATE_LIVE)
   {
      g_explicit_button_click = true;
      g_rebuild_requested = true;
      g_state = STATE_REBUILD_REQUESTED;
   }
}

//+------------------------------------------------------------------+
//| Close button click handler                                       |
//+------------------------------------------------------------------+
//| Close button click handler                                       |
//+------------------------------------------------------------------+
void OnCloseButtonClick()
{
   Print("Close button clicked - removing indicator");
   
   g_persistence.is_active = false;
   g_persistence.Save();
   
   // ✅ Use the actual indicator name (not the old formatted name)
   string indicator_name = "OVO_Renko_Generator";
   
   // Use our tracked subwindow number
   if(g_our_subwindow > 0)
   {
      if(ChartIndicatorDelete(ChartID(), g_our_subwindow, indicator_name))
      {
         Print("✅ Indicator removed successfully from subwindow ", g_our_subwindow);
         return;
      }
   }
   
   // Fallback: Try by window search
   int window = ChartWindowFind(ChartID(), indicator_name);
   if(window >= 0)
   {
      if(ChartIndicatorDelete(ChartID(), window, indicator_name))
      {
         Print("✅ Indicator removed successfully from window ", window);
         return;
      }
   }
   
   Print("⚠️ Could not remove indicator automatically - please use Indicators List");
}

//+------------------------------------------------------------------+
//| Get deinit reason text                                           |
//+------------------------------------------------------------------+
string GetDeinitReasonText(int reason)
{
   switch(reason)
   {
      case REASON_PROGRAM:     return "Program terminated";
      case REASON_REMOVE:      return "Indicator removed from chart";
      case REASON_RECOMPILE:   return "Indicator recompiled";
      case REASON_CHARTCHANGE: return "Chart symbol or period changed";
      case REASON_CHARTCLOSE:  return "Chart closed";
      case REASON_PARAMETERS:  return "Input parameters changed";
      case REASON_ACCOUNT:     return "Account changed";
      case REASON_TEMPLATE:    return "Template applied";
      case REASON_INITFAILED:  return "Initialization failed";
      case REASON_CLOSE:       return "Terminal closed";
      default:                 return "Unknown reason";
   }
}

//+------------------------------------------------------------------+
