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
   Print("=== OVO Renko Generator Deinitializing ===");
   Print("Reason: ", GetDeinitReasonText(reason));
   
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
   
   // ✅ Delete global variable to free up the period token
   string gv_name = StringFormat("OVORenko_Token_%I64d_%s_%s", ChartID(), _Symbol, g_config.period_token);
   if(GlobalVariableDel(gv_name))
   {
      Print("✅ Released period token ", g_config.period_token, " (deleted global variable)");
   }
   
   // ✅ Force delete any remaining objects with our prefix
   string prefix = StringFormat("OVORenko_%I64d_%s_", ChartID(), g_config.period_token);
   ObjectsDeleteAll(ChartID(), prefix, g_our_subwindow, -1);  // -1 = all object types
   
   DestroyComponents();
   
   Print("Deinitialization complete");
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
      // ✅ Find our subwindow - MT5 assigns windows in order
      // First instance gets window 1, second gets window 2, etc.
      // We need to find which window THIS instance is in
      
      int subwindow = -1;
      
      // Try ChartWindowFind first with the display name
      subwindow = ChartWindowFind(ChartID(), "OVO_Renko_Generator");
      
      if(subwindow > 0)
      {
         Print("📊 ChartWindowFind returned: ", subwindow);
      }
      
      if(subwindow < 0 || subwindow == 0)
      {
         // If that doesn't work, iterate through windows and test object creation
         // with our unique prefix to find an unclaimed window
         int total_windows = (int)ChartGetInteger(ChartID(), CHART_WINDOWS_TOTAL);
         Print("📊 Total windows on chart: ", total_windows);
         
         for(int w = 1; w < total_windows; w++)
         {
            Print("   Checking window ", w, "...");
            
            // Try to create a marker object with our unique name
            string marker = g_unique_name + "_marker";
            
            // Check if our marker already exists in this window (we already claimed it)
            int marker_window = ObjectFind(ChartID(), marker);
            if(marker_window == w)
            {
               subwindow = w;
               Print("   ✅ Found our marker in window ", w);
               break;
            }
            
            // Check if window is unclaimed by trying to find any of our objects
            string test_bg = StringFormat("OVORenko_%I64d_%s_BG", ChartID(), g_config.period_token);
            int bg_window = ObjectFind(ChartID(), test_bg);
            if(bg_window == w)
            {
               // We already have a panel in this window
               subwindow = w;
               Print("   ✅ Found our panel objects in window ", w);
               break;
            }
            
            // Check if this window is empty (no other instance's marker)
            bool window_free = true;
            int total_objects = ObjectsTotal(ChartID(), w, -1);  // All objects in window
            
            for(int i = 0; i < total_objects; i++)
            {
               string obj_name = ObjectName(ChartID(), i, w, -1);
               if(StringFind(obj_name, "_marker") >= 0 && StringFind(obj_name, g_unique_name) < 0)
               {
                  // Another instance's marker found
                  Print("   ⚠️ Window ", w, " has another marker: ", obj_name);
                  window_free = false;
                  break;
               }
            }
            
            if(window_free)
            {
               // This window is free - claim it
               if(ObjectCreate(ChartID(), marker, OBJ_LABEL, w, 0, 0))
               {
                  ObjectSetInteger(ChartID(), marker, OBJPROP_HIDDEN, true);
                  ObjectSetString(ChartID(), marker, OBJPROP_TEXT, g_unique_name);
                  subwindow = w;
                  Print("   ✅ Claimed free window: ", w, " with marker: ", marker);
                  break;
               }
               else
               {
                  Print("   ❌ Failed to create marker in window ", w, ", error: ", GetLastError());
               }
            }
         }
      }
      
      if(subwindow < 0 || subwindow == 0)
      {
         // Window not found yet - MT5 may still be creating it
         static int wait_count = 0;
         wait_count++;
         if(wait_count % 10 == 0)  // Log every 10 attempts
            Print("⏳ Waiting for indicator window... (attempt ", wait_count, ", unique_name: ", g_unique_name, ")");
         return;  // Try again on next timer tick
      }
      
      Print("📊 Using subwindow: ", subwindow, " for ", g_unique_name);
      
      if(subwindow > 0)
      {
         // ✅ Window found! Create panel now
         string unique_prefix = StringFormat("OVORenko_%I64d_%s_", ChartID(), g_config.period_token);
         
         g_panel = new CPanelUI(ChartID(), subwindow, unique_prefix, InpVerboseLog);
         g_panel.SetChartType(InpChartType);
         g_panel.SetBrickSize(DoubleToString(InpBrickSizePoints, 0));
         g_panel.SetPeriodText(g_config.period_token);
         g_panel.SetStatusText("Ready");
         
         // ✅ Save our subwindow number for later use
         g_our_subwindow = subwindow;
         
         Print("🎨 Creating panel with:");
         Print("   Chart ID: ", ChartID());
         Print("   Subwindow: ", subwindow);
         Print("   Prefix: ", unique_prefix);
         Print("   Chart Type: ", (InpChartType == RENKO_MEAN ? "Mean Renko" : "Regular Renko"));
         Print("   Period: ", g_config.period_token);
         
         bool panel_created = g_panel.CreatePanel();
         
         if(panel_created)
         {
            Print("✅ Panel created successfully in subwindow ", subwindow);
            
            // ✅ Force a chart redraw to make objects visible
            ChartRedraw(ChartID());
            
            g_state = STATE_PANEL_ONLY;
         }
         else
         {
            Print("❌ ERROR: Panel creation failed!");
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
   
   // ✅ Use Global Variables - most reliable method for cross-instance tracking
   for(int num = 61; num <= 99; num++)
   {
      string test_period = base_period + IntegerToString(num);
      
      // Check global variable for this token
      string gv_name = StringFormat("OVORenko_Token_%I64d_%s_%s", ChartID(), source_symbol, test_period);
      
      if(GlobalVariableCheck(gv_name))
      {
         Print("⚠️ Period token ", test_period, " in use (global variable exists)");
         continue;  // Token in use
      }
      
      // Token is available!
      Print("✅ Auto-assigned period token: ", test_period, " (available slot)");
      return test_period;
   }
   
   // Fallback: use the input token
   Print("⚠️ All period tokens M61-M99 in use, using input token: ", InpPeriodToken);
   return InpPeriodToken;
}

//+------------------------------------------------------------------+
//| Initialize configuration                                         |
//+------------------------------------------------------------------+
void InitializeConfig()
{
   g_config.chart_type = InpChartType;
   g_config.brick_size_points = InpBrickSizePoints;
   g_config.suppress_wicks = InpSuppressWicks;
   
   // ✅ AUTO-INCREMENT PERIOD TOKEN: Find next available for this symbol
   string auto_period = FindNextAvailablePeriodToken(_Symbol);
   g_config.period_token = auto_period;  // Use auto-assigned token instead of input
   
   // ✅ IMMEDIATELY register this token using Global Variable (most reliable)
   string gv_name = StringFormat("OVORenko_Token_%I64d_%s_%s", ChartID(), _Symbol, auto_period);
   GlobalVariableSet(gv_name, 1.0);  // Set to 1 to mark as in-use
   Print("✅ Registered period token: ", auto_period, " (global variable: ", gv_name, ")");
   
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
   
   // ⚡ Force chart to reload data after clean regeneration
   string custom_symbol = g_publisher.GetCustomSymbolName();
   
   // Find existing chart first
   long existing_chart_id = g_chart_manager.FindChart(custom_symbol);
   if(existing_chart_id > 0)
   {
      // Chart exists - refresh it to clear old cached data
      ChartSetSymbolPeriod(existing_chart_id, custom_symbol, PERIOD_M1);
      ChartNavigate(existing_chart_id, CHART_END, 0);
      ChartRedraw(existing_chart_id);
      
      if(InpVerboseLog)
         Print("Refreshed existing chart to show new data");
   }
   
   // Open/switch to chart
   long chart_id = g_chart_manager.OpenChart(custom_symbol, g_explicit_button_click);
   
   if(chart_id == 0)
   {
      Print("ERROR: Failed to open chart");
      g_state = STATE_PANEL_ONLY;
      if(g_panel != NULL)
         g_panel.SetStatusText("ERROR: Chart failed");
      return;
   }
   
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
}

//+------------------------------------------------------------------+
//| Check generated chart                                            |
//+------------------------------------------------------------------+
void CheckGeneratedChart()
{
   datetime now = TimeCurrent();
   
   if(now - g_last_chart_check < 2)
      return;
   
   g_last_chart_check = now;
   
   if(g_chart_manager != NULL)
   {
      g_chart_manager.EnforceM1();
      
      if(InpPreserveChartSetup)
         g_chart_manager.PeriodicTemplateSave();
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
