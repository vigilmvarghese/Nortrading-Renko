//+------------------------------------------------------------------+
//|                                       OVO_Renko_Generator.mq5    |
//|                        Copyright 2024, Nortrading Renko Project  |
//|                                      https://github.com/vigilm   |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024, Nortrading Renko Project"
#property link      "https://github.com/vigilmvarghese/Nortrading-Renko"
#property version   "1.00"
#property description "MT5 OVO-Style Renko Generator"
#property description "Generates true custom symbol Renko charts"
#property indicator_chart_window
#property indicator_buffers 0
#property indicator_plots   0

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
input int InpInitialHistoryCandles = 1000;                 // Initial History Candles

input group "=== CUSTOM CHART ==="
input string InpPeriodToken = "M61";                       // Custom Period ID (M61, M2, etc)
input int InpHistoryDays = 7;                              // History Days

input group "=== LIVE FEED ==="
input int InpLivePumpMs = 20;                              // Live Pump Milliseconds (min 5)

input group "=== PERFORMANCE ==="
input int InpRebuildBudgetMs = 8;                          // Historical Rebuild Budget (ms)
input bool InpEnableTickCache = true;                      // Enable Tick Cache

input group "=== PERSISTENCE ==="
input bool InpAutoResume = true;                           // Auto Resume After MT5 Restart
input bool InpPreserveChartSetup = true;                   // Preserve Generated Chart Setup

input group "=== TRADE DISPLAY ==="
input bool InpShowSourceBidAsk = true;                     // Show Source Bid/Ask
input bool InpShowEntrySlTp = true;                        // Show Entry / SL / TP
input bool InpShowMonetaryLabels = true;                   // Show Monetary SL/TP Labels

input group "=== DIAGNOSTICS ==="
input bool InpVerboseLog = false;                          // Verbose Log
input bool InpMeanRenkoDiagnostics = false;                // Mean Renko Diagnostics

//+------------------------------------------------------------------+
//| Global Variables                                                 |
//+------------------------------------------------------------------+
ENUM_RENKO_STATE g_state = STATE_INITIALIZING;
RenkoConfig g_config;
PersistenceState g_persistence;

// Core components
CTickIntegrityLayer* g_tick_integrity = NULL;
CRegularRenkoEngine* g_regular_engine = NULL;
CMeanRenkoEngine* g_mean_engine = NULL;
CCustomSymbolPublisher* g_publisher = NULL;
CHistoricalBuilder* g_builder = NULL;
CChartManager* g_chart_manager = NULL;
CPanelUI* g_panel = NULL;
CTradeOverlay* g_trade_overlay = NULL;

// Timers
int g_live_pump_timer = 0;
datetime g_last_ui_update = 0;
datetime g_last_trade_update = 0;
datetime g_last_chart_check = 0;

// Runtime state
double g_runtime_brick_size = 0;
bool g_rebuild_requested = false;
bool g_chart_needs_redraw = false;
bool g_explicit_button_click = false;  // Track if user explicitly clicked button

//+------------------------------------------------------------------+
//| Custom indicator initialization                                  |
//+------------------------------------------------------------------+
int OnInit()
{
   Print("=== OVO Renko Generator Initializing ===");
   
   // Validate inputs
   if(!ValidateInputs())
      return INIT_PARAMETERS_INCORRECT;
   
   // Initialize configuration
   InitializeConfig();
   
   // Initialize persistence
   g_persistence.source_symbol = _Symbol;
   g_persistence.period_token = InpPeriodToken;
   g_persistence.chart_type = InpChartType;
   g_persistence.brick_size = InpBrickSizePoints;
   
   // Try to load persistence state
   if(InpAutoResume)
   {
      if(g_persistence.Load())
      {
         Print("Loaded persistence state - will auto-resume");
      }
   }
   
   // Create components
   CreateComponents();
   
   // Create panel
   g_state = STATE_PANEL_ONLY;
   g_panel = new CPanelUI(ChartID(), 0, "OVORenko_", InpVerboseLog);
   g_panel.SetChartType(InpChartType);
   g_panel.SetBrickSize(DoubleToString(InpBrickSizePoints, 0));
   g_panel.SetPeriodText(InpPeriodToken);
   g_panel.SetStatusText("OVO C2");
   g_panel.CreatePanel();
   
   // Set up timer
   int timer_ms = MathMax(InpLivePumpMs, 5);
   EventSetMillisecondTimer(timer_ms);
   g_live_pump_timer = timer_ms;
   
   Print("Indicator initialized successfully");
   Print("State: PANEL_ONLY");
   Print("Click period button (", InpPeriodToken, ") to generate Renko chart");
   
   // Auto-resume if enabled
   if(InpAutoResume && g_persistence.is_active)
   {
      Print("Auto-resuming previous session...");
      g_explicit_button_click = false;  // Auto-resume doesn't switch charts
      g_rebuild_requested = true;
   }
   
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Custom indicator deinitialization                                |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   Print("=== OVO Renko Generator Deinitializing ===");
   Print("Reason: ", GetDeinitReasonText(reason));
   
   // Save persistence state
   if(g_state == STATE_LIVE || g_state == STATE_REBUILDING)
   {
      g_persistence.is_active = true;
      g_persistence.Save();
      Print("Persistence state saved");
   }
   else if(reason == REASON_REMOVE)
   {
      // User explicitly removed indicator
      g_persistence.is_active = false;
      g_persistence.Save();
      Print("Indicator removed - auto-resume disabled");
   }
   
   // Kill timer
   EventKillTimer();
   
   // Clean up components
   DestroyComponents();
   
   // Delete panel
   if(g_panel != NULL)
   {
      delete g_panel;
      g_panel = NULL;
   }
   
   Print("Deinitialization complete");
}

//+------------------------------------------------------------------+
//| Custom indicator iteration                                       |
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
   // OnCalculate performs only lightweight duties
   // All heavy work is in OnTimer
   
   return(rates_total);
}

//+------------------------------------------------------------------+
//| Timer event                                                      |
//+------------------------------------------------------------------+
void OnTimer()
{
   // Handle different states
   switch(g_state)
   {
      case STATE_INITIALIZING:
         // Should not reach here
         break;
      
      case STATE_PANEL_ONLY:
         HandlePanelOnly();
         break;
      
      case STATE_REBUILD_REQUESTED:
         StartRebuild();
         break;
      
      case STATE_REBUILDING:
         ContinueRebuild();
         break;
      
      case STATE_PUBLISHING:
         CompletePublish();
         break;
      
      case STATE_LIVE:
         ProcessLiveTicks();
         break;
      
      case STATE_STOPPING:
         // Cleanup state
         break;
   }
   
   // Periodic UI maintenance (slower than live pump)
   PeriodicUIUpdate();
}

//+------------------------------------------------------------------+
//| Chart event handler                                              |
//+------------------------------------------------------------------+
void OnChartEvent(const int id,
                  const long &lparam,
                  const double &dparam,
                  const string &sparam)
{
   // Handle button clicks
   if(id == CHARTEVENT_OBJECT_CLICK)
   {
      if(g_panel != NULL)
      {
         // Period button clicked
         if(g_panel.IsPeriodButtonClicked())
         {
            OnPeriodButtonClick();
         }
         
         // Close button clicked
         if(g_panel.IsCloseButtonClicked())
         {
            OnCloseButtonClick();
         }
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
//| Initialize configuration                                         |
//+------------------------------------------------------------------+
void InitializeConfig()
{
   g_config.chart_type = InpChartType;
   g_config.brick_size_points = InpBrickSizePoints;
   g_config.suppress_wicks = InpSuppressWicks;
   g_config.initial_history_candles = InpInitialHistoryCandles;
   g_config.period_token = InpPeriodToken;
   g_config.history_days = InpHistoryDays;
   g_config.live_pump_ms = InpLivePumpMs;
   g_config.rebuild_budget_ms = InpRebuildBudgetMs;
   g_config.enable_tick_cache = InpEnableTickCache;
   g_config.auto_resume = InpAutoResume;
   g_config.preserve_chart_setup = InpPreserveChartSetup;
   g_config.show_source_bid_ask = InpShowSourceBidAsk;
   g_config.show_entry_sl_tp = InpShowEntrySlTp;
   g_config.show_monetary_labels = InpShowMonetaryLabels;
   g_config.verbose_log = InpVerboseLog;
   g_config.enable_diagnostics = InpMeanRenkoDiagnostics;
   
   g_runtime_brick_size = InpBrickSizePoints;
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
   g_builder.SetBudgetMs(InpRebuildBudgetMs);
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
   // Just maintain panel
   if(g_panel != NULL)
      g_panel.UpdateWidth();
   
   // Check for rebuild request
   if(g_rebuild_requested)
   {
      g_state = STATE_REBUILD_REQUESTED;
   }
}

//+------------------------------------------------------------------+
//| Start rebuild process                                            |
//+------------------------------------------------------------------+
void StartRebuild()
{
   Print("=== Starting Rebuild ===");
   
   // Get runtime brick size from panel
   if(g_panel != NULL)
   {
      string brick_text = g_panel.GetBrickSize();
      double brick_value = StringToDouble(brick_text);
      if(brick_value > 0)
         g_runtime_brick_size = brick_value;
   }
   
   Print("Brick size: ", g_runtime_brick_size);
   
   // Reset engines
   if(g_config.chart_type == RENKO_REGULAR)
   {
      g_regular_engine.Reset();
      g_regular_engine.Configure(g_runtime_brick_size, g_config.suppress_wicks);
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
         g_panel.SetStatusText("ERROR: Symbol creation failed");
      return;
   }
   
   // Start asynchronous build
   if(!g_builder.StartBuild(g_config.chart_type, g_runtime_brick_size,
                            g_config.suppress_wicks, g_config.history_days))
   {
      Print("ERROR: Failed to start historical build");
      g_state = STATE_PANEL_ONLY;
      if(g_panel != NULL)
         g_panel.SetStatusText("ERROR: Build failed");
      return;
   }
   
   g_state = STATE_REBUILDING;
   if(g_panel != NULL)
      g_panel.SetStatusText("Rebuilding...");
   
   Print("Historical build started");
}

//+------------------------------------------------------------------+
//| Continue asynchronous rebuild                                    |
//+------------------------------------------------------------------+
void ContinueRebuild()
{
   if(g_builder == NULL)
      return;
   
   // Process one pass
   bool more_work = g_builder.ProcessBuildPass(g_config.chart_type, g_runtime_brick_size,
                                                 g_config.suppress_wicks);
   
   // Update progress
   BuildProgress progress = g_builder.GetProgress();
   int percent = progress.GetProgressPercent();
   
   if(g_panel != NULL)
   {
      g_panel.SetStatusText("Rebuilding " + IntegerToString(percent) + "%");
   }
   
   // Check if finished
   if(!more_work)
   {
      Print("Historical build completed");
      g_state = STATE_PUBLISHING;
   }
}

//+------------------------------------------------------------------+
//| Complete publish to custom symbol                                |
//+------------------------------------------------------------------+
void CompletePublish()
{
   Print("=== Publishing History ===");
   
   // Get build results
   RenkoBrick results[];
   int count = g_builder.GetResults(results);
   
   Print("Publishing ", count, " bricks");
   
   // Replace history
   if(!g_publisher.ReplaceHistory(results, count))
   {
      Print("ERROR: Failed to publish history");
      g_state = STATE_PANEL_ONLY;
      if(g_panel != NULL)
         g_panel.SetStatusText("ERROR: Publish failed");
      return;
   }
   
   // Open/switch to chart (only if explicit button click)
   string custom_symbol = g_publisher.GetCustomSymbolName();
   long chart_id = g_chart_manager.OpenChart(custom_symbol, g_explicit_button_click);
   
   if(chart_id == 0)
   {
      Print("ERROR: Failed to open chart");
      g_state = STATE_PANEL_ONLY;
      if(g_panel != NULL)
         g_panel.SetStatusText("ERROR: Chart open failed");
      return;
   }
   
   // Reset button click flag after opening
   g_explicit_button_click = false;
   
   // Create trade overlay for Renko chart
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
   
   g_state = STATE_LIVE;
   if(g_panel != NULL)
      g_panel.SetStatusText("LIVE");
   
   Print("=== Live Processing Started ===");
}

//+------------------------------------------------------------------+
//| Process live ticks                                               |
//+------------------------------------------------------------------+
void ProcessLiveTicks()
{
   if(g_tick_integrity == NULL)
      return;
   
   // FAST PATH: Check if there's a new tick
   if(!g_tick_integrity.HasNewTick())
      return;  // No new tick - immediate return
   
   // Get new ticks
   MqlTick new_ticks[];
   int tick_count = g_tick_integrity.GetNewTicks(new_ticks);
   
   if(tick_count <= 0)
      return;
   
   // Process each tick
   ENUM_DIRTY_STATE dirty_state = DIRTY_NONE;
   RenkoBrick completed[];
   int completed_count = 0;
   
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
      
      // Mark processed
      g_tick_integrity.MarkProcessed(new_ticks[i]);
   }
   
   // Get completed bricks if any
   if(dirty_state != DIRTY_NONE)
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
   
   // Publish to custom symbol based on dirty state
   if(dirty_state == DIRTY_FORMING_CHANGED)
   {
      // Only forming changed
      g_publisher.UpdateFormingOnly(forming);
   }
   else if(dirty_state == DIRTY_BRICK_COMPLETED || dirty_state == DIRTY_MULTI_BRICK_COMPLETED)
   {
      // Bricks completed
      g_publisher.UpdateRates(completed, completed_count, forming, dirty_state);
      g_chart_needs_redraw = true;
   }
   
   // Periodic chart check
   CheckGeneratedChart();
}

//+------------------------------------------------------------------+
//| Periodic UI update (slower than live pump)                       |
//+------------------------------------------------------------------+
void PeriodicUIUpdate()
{
   datetime now = TimeCurrent();
   
   // Update panel width every 500ms
   if(now != g_last_ui_update || (GetTickCount() % 500) == 0)
   {
      if(g_panel != NULL)
         g_panel.UpdateWidth();
      
      g_last_ui_update = now;
   }
   
   // Update trade overlay every 1 second
   if(g_state == STATE_LIVE && g_trade_overlay != NULL)
   {
      if(now - g_last_trade_update >= 1)
      {
         g_trade_overlay.Update();
         g_last_trade_update = now;
      }
   }
   
   // Redraw chart if needed
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
      // Enforce M1 timeframe
      g_chart_manager.EnforceM1();
      
      // Periodic template save
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
      g_explicit_button_click = true;  // Mark as explicit user action
      g_rebuild_requested = true;
      g_state = STATE_REBUILD_REQUESTED;
   }
}

//+------------------------------------------------------------------+
//| Close button click handler                                       |
//+------------------------------------------------------------------+
void OnCloseButtonClick()
{
   Print("Close button clicked - removing indicator");
   
   // Disable auto-resume
   g_persistence.is_active = false;
   g_persistence.Save();
   
   // Remove from chart
   ChartIndicatorDelete(ChartID(), 0, "OVO_Renko_Generator");
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
