//+------------------------------------------------------------------+
//|                                                   RenkoTypes.mqh |
//|                        Copyright 2024, Nortrading Renko Project  |
//|                                      https://github.com/vigilm   |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024, Nortrading Renko Project"
#property link      "https://github.com/vigilmvarghese/Nortrading-Renko"
#property version   "1.00"
#property strict

//+------------------------------------------------------------------+
//| Renko Type Enumeration                                           |
//+------------------------------------------------------------------+
enum ENUM_RENKO_TYPE
{
   RENKO_REGULAR = 0,    // Regular Renko
   RENKO_MEAN    = 1     // Mean Renko
};

//+------------------------------------------------------------------+
//| System State Enumeration                                         |
//+------------------------------------------------------------------+
enum ENUM_RENKO_STATE
{
   STATE_INITIALIZING = 0,      // Initializing
   STATE_PANEL_ONLY,            // Panel only (no chart)
   STATE_REBUILD_REQUESTED,     // Rebuild requested
   STATE_REBUILDING,            // Rebuilding history
   STATE_PUBLISHING,            // Publishing to custom symbol
   STATE_LIVE,                  // Live processing
   STATE_STOPPING               // Stopping/cleanup
};

//+------------------------------------------------------------------+
//| Dirty State Flags                                                |
//+------------------------------------------------------------------+
enum ENUM_DIRTY_STATE
{
   DIRTY_NONE = 0,              // No changes
   DIRTY_FORMING_CHANGED,       // Forming candle changed
   DIRTY_BRICK_COMPLETED,       // One brick completed
   DIRTY_MULTI_BRICK_COMPLETED  // Multiple bricks completed
};

//+------------------------------------------------------------------+
//| Tick Signature Structure                                         |
//+------------------------------------------------------------------+
struct TickSignature
{
   long              time_msc;        // Millisecond timestamp
   double            bid;             // Bid price
   double            ask;             // Ask price
   double            last;            // Last price
   double            volume_real;     // Real volume
   uint              flags;           // Tick flags
   
   //--- Constructor
   TickSignature() : time_msc(0), bid(0), ask(0), last(0), volume_real(0), flags(0) {}
   
   //--- Equality operator
   bool operator==(const TickSignature &other) const
   {
      return (time_msc == other.time_msc &&
              MathAbs(bid - other.bid) < 0.000001 &&
              MathAbs(ask - other.ask) < 0.000001 &&
              MathAbs(last - other.last) < 0.000001 &&
              MathAbs(volume_real - other.volume_real) < 0.000001 &&
              flags == other.flags);
   }
   
   //--- Inequality operator
   bool operator!=(const TickSignature &other) const
   {
      return !(*this == other);
   }
   
   //--- Set from MqlTick
   void Set(const MqlTick &tick)
   {
      time_msc = tick.time_msc;
      bid = tick.bid;
      ask = tick.ask;
      last = tick.last;
      volume_real = tick.volume_real;
      flags = tick.flags;
   }
   
   //--- Check if valid
   bool IsValid() const
   {
      return (time_msc > 0 && (bid > 0 || ask > 0 || last > 0));
   }
   
   //--- Reset
   void Reset()
   {
      time_msc = 0;
      bid = 0;
      ask = 0;
      last = 0;
      volume_real = 0;
      flags = 0;
   }
};

//+------------------------------------------------------------------+
//| Renko Brick Structure                                            |
//+------------------------------------------------------------------+
struct RenkoBrick
{
   datetime          time;            // Open time
   double            open;            // Open price
   double            high;            // High price
   double            low;             // Low price
   double            close;           // Close price
   long              tick_volume;     // Tick volume
   int               spread;          // Spread
   long              real_volume;     // Real volume
   bool              is_forming;      // Is forming brick
   
   //--- Constructor
   RenkoBrick() : time(0), open(0), high(0), low(0), close(0), 
                  tick_volume(0), spread(0), real_volume(0), is_forming(false) {}
   
   //--- Reset
   void Reset()
   {
      time = 0;
      open = 0;
      high = 0;
      low = 0;
      close = 0;
      tick_volume = 0;
      spread = 0;
      real_volume = 0;
      is_forming = false;
   }
   
   //--- Convert to MqlRates
   void ToMqlRates(MqlRates &rate) const
   {
      rate.time = time;
      rate.open = open;
      rate.high = high;
      rate.low = low;
      rate.close = close;
      rate.tick_volume = tick_volume;
      rate.spread = spread;
      rate.real_volume = real_volume;
   }
   
   //--- Set from MqlRates
   void FromMqlRates(const MqlRates &rate)
   {
      time = rate.time;
      open = rate.open;
      high = rate.high;
      low = rate.low;
      close = rate.close;
      tick_volume = rate.tick_volume;
      spread = rate.spread;
      real_volume = rate.real_volume;
   }
   
   //--- Check if bullish
   bool IsBullish() const
   {
      return close > open;
   }
   
   //--- Check if bearish
   bool IsBearish() const
   {
      return close < open;
   }
};

//+------------------------------------------------------------------+
//| Renko Engine State                                               |
//+------------------------------------------------------------------+
struct RenkoEngineState
{
   ENUM_RENKO_TYPE   type;                  // Renko type
   double            brick_size_points;     // Brick size in points
   bool              suppress_wicks;        // Suppress wicks flag
   
   RenkoBrick        forming_brick;         // Current forming brick
   double            trend_price;           // Trend tracking price
   bool              is_bullish;            // Current trend direction
   
   datetime          last_brick_time;       // Last completed brick time
   int               total_bricks;          // Total bricks generated
   
   //--- Mean Renko specific
   double            mean_step;             // Mean Renko step
   double            mean_body;             // Mean Renko body size
   double            last_body_midpoint;    // Last candle body midpoint
   
   //--- Constructor
   RenkoEngineState() : type(RENKO_REGULAR), brick_size_points(600), suppress_wicks(false),
                        trend_price(0), is_bullish(true), last_brick_time(0), 
                        total_bricks(0), mean_step(600), mean_body(1200), 
                        last_body_midpoint(0) {}
   
   //--- Reset
   void Reset()
   {
      forming_brick.Reset();
      trend_price = 0;
      is_bullish = true;
      last_brick_time = 0;
      total_bricks = 0;
      last_body_midpoint = 0;
   }
   
   //--- Calculate Mean Renko parameters
   void CalculateMeanParameters()
   {
      mean_step = brick_size_points;
      mean_body = brick_size_points * 2.0;  // Body = 2x step
   }
};

//+------------------------------------------------------------------+
//| Persistence State                                                |
//+------------------------------------------------------------------+
struct PersistenceState
{
   bool              is_active;             // Is generator active
   string            source_symbol;         // Source symbol
   ENUM_RENKO_TYPE   chart_type;           // Chart type
   double            brick_size;            // Active brick size
   string            period_token;          // Period token (M61, M2, etc)
   string            custom_symbol_name;    // Generated custom symbol name
   long              chart_id;              // Generated chart ID
   
   //--- Constructor
   PersistenceState() : is_active(false), source_symbol(""), chart_type(RENKO_REGULAR),
                        brick_size(600), period_token("M61"), custom_symbol_name(""),
                        chart_id(0) {}
   
   //--- Get global variable prefix
   string GetGlobalPrefix() const
   {
      return "OVORenko_" + source_symbol + "_" + period_token + "_";
   }
   
   //--- Save to global variables
   bool Save()
   {
      string prefix = GetGlobalPrefix();
      
      GlobalVariableSet(prefix + "Active", is_active ? 1.0 : 0.0);
      GlobalVariableSet(prefix + "ChartType", (double)chart_type);
      GlobalVariableSet(prefix + "BrickSize", brick_size);
      GlobalVariableSet(prefix + "ChartID", (double)chart_id);
      
      return true;
   }
   
   //--- Load from global variables
   bool Load()
   {
      string prefix = GetGlobalPrefix();
      
      if(!GlobalVariableCheck(prefix + "Active"))
         return false;
      
      is_active = (GlobalVariableGet(prefix + "Active") > 0.5);
      chart_type = (ENUM_RENKO_TYPE)GlobalVariableGet(prefix + "ChartType");
      brick_size = GlobalVariableGet(prefix + "BrickSize");
      chart_id = (long)GlobalVariableGet(prefix + "ChartID");
      
      return true;
   }
   
   //--- Clear persistence
   void Clear()
   {
      string prefix = GetGlobalPrefix();
      
      GlobalVariableDel(prefix + "Active");
      GlobalVariableDel(prefix + "ChartType");
      GlobalVariableDel(prefix + "BrickSize");
      GlobalVariableDel(prefix + "ChartID");
   }
};

//+------------------------------------------------------------------+
//| Build Progress Information                                       |
//+------------------------------------------------------------------+
struct BuildProgress
{
   bool              is_building;           // Is currently building
   int               total_ticks;           // Total ticks to process
   int               processed_ticks;       // Ticks processed
   int               total_bricks;          // Total bricks generated
   datetime          start_time;            // Build start time
   datetime          end_time;              // Build end time
   
   //--- Constructor
   BuildProgress() : is_building(false), total_ticks(0), processed_ticks(0),
                     total_bricks(0), start_time(0), end_time(0) {}
   
   //--- Get progress percentage
   int GetProgressPercent() const
   {
      if(total_ticks <= 0)
         return 0;
      return (int)((processed_ticks * 100.0) / total_ticks);
   }
   
   //--- Reset
   void Reset()
   {
      is_building = false;
      total_ticks = 0;
      processed_ticks = 0;
      total_bricks = 0;
      start_time = 0;
      end_time = 0;
   }
   
   //--- Start build
   void Start(int total)
   {
      is_building = true;
      total_ticks = total;
      processed_ticks = 0;
      total_bricks = 0;
      start_time = TimeCurrent();
      end_time = 0;
   }
   
   //--- Complete build
   void Complete()
   {
      is_building = false;
      end_time = TimeCurrent();
   }
};

//+------------------------------------------------------------------+
//| Configuration Structure                                          |
//+------------------------------------------------------------------+
struct RenkoConfig
{
   //--- Engine Settings
   ENUM_RENKO_TYPE   chart_type;
   double            brick_size_points;
   bool              suppress_wicks;
   int               initial_history_candles;
   
   //--- Custom Chart
   string            period_token;
   int               history_days;
   
   //--- Live Feed
   int               live_pump_ms;
   
   //--- Performance
   int               rebuild_budget_ms;
   bool              enable_tick_cache;
   
   //--- Persistence
   bool              auto_resume;
   bool              preserve_chart_setup;
   
   //--- Trade Display
   bool              show_source_bid_ask;
   bool              show_entry_sl_tp;
   bool              show_monetary_labels;
   
   //--- Diagnostics
   bool              verbose_log;
   bool              enable_diagnostics;
   
   //--- Constructor with defaults
   RenkoConfig()
   {
      chart_type = RENKO_MEAN;
      brick_size_points = 600;
      suppress_wicks = false;
      initial_history_candles = 1000;
      
      period_token = "M61";
      history_days = 7;
      
      live_pump_ms = 20;
      
      rebuild_budget_ms = 8;
      enable_tick_cache = true;
      
      auto_resume = true;
      preserve_chart_setup = true;
      
      show_source_bid_ask = true;
      show_entry_sl_tp = true;
      show_monetary_labels = true;
      
      verbose_log = false;
      enable_diagnostics = false;
   }
};

//+------------------------------------------------------------------+
