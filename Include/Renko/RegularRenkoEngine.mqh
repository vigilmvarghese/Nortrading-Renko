//+------------------------------------------------------------------+
//|                                          RegularRenkoEngine.mqh  |
//|                        Copyright 2024, Nortrading Renko Project  |
//|                                      https://github.com/vigilm   |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024, Nortrading Renko Project"
#property link      "https://github.com/vigilmvarghese/Nortrading-Renko"
#property version   "1.00"
#property strict

#include "RenkoTypes.mqh"

//+------------------------------------------------------------------+
//| Regular Renko Engine                                             |
//| OVO-compatible validated engine - FROZEN production logic        |
//+------------------------------------------------------------------+
class CRegularRenkoEngine
{
private:
   string            m_symbol;                 // Symbol
   double            m_point;                  // Point value
   int               m_digits;                 // Price digits
   
   double            m_brick_size_points;      // Brick size in points
   double            m_brick_size_price;       // Brick size in price
   bool              m_suppress_wicks;         // Suppress wicks flag
   bool              m_verbose;                // Verbose logging
   
   RenkoBrick        m_forming_brick;          // Current forming brick
   RenkoBrick        m_completed_bricks[];     // Buffer for completed bricks
   int               m_completed_count;        // Count of completed bricks
   
   double            m_trend_high;             // Current trend high
   double            m_trend_low;              // Current trend low
   bool              m_is_bullish;             // Current trend direction
   bool              m_initialized;            // Initialization flag
   
public:
   //--- Constructor
   CRegularRenkoEngine(string symbol = "", bool verbose = false)
      : m_symbol(symbol), m_brick_size_points(600), m_suppress_wicks(false),
        m_verbose(verbose), m_completed_count(0), m_is_bullish(true),
        m_initialized(false)
   {
      if(m_symbol == "")
         m_symbol = _Symbol;
      
      m_point = SymbolInfoDouble(m_symbol, SYMBOL_POINT);
      m_digits = (int)SymbolInfoInteger(m_symbol, SYMBOL_DIGITS);
      
      m_brick_size_price = m_brick_size_points * m_point;
      m_trend_high = 0;
      m_trend_low = 0;
      
      ArrayResize(m_completed_bricks, 0, 1000);
   }
   
   //--- Destructor
   ~CRegularRenkoEngine() {}
   
   //--- Initialize with first price
   bool Initialize(double initial_price, datetime initial_time)
   {
      if(initial_price <= 0)
         return false;
      
      m_forming_brick.Reset();
      m_forming_brick.time = initial_time;
      m_forming_brick.open = NormalizeDouble(initial_price, m_digits);
      m_forming_brick.high = m_forming_brick.open;
      m_forming_brick.low = m_forming_brick.open;
      m_forming_brick.close = m_forming_brick.open;
      m_forming_brick.is_forming = true;
      m_forming_brick.tick_volume = 1;
      
      m_trend_high = m_forming_brick.open;
      m_trend_low = m_forming_brick.open;
      m_is_bullish = true;
      m_initialized = true;
      m_completed_count = 0;
      
      ArrayResize(m_completed_bricks, 0);
      
      if(m_verbose)
         Print("RegularRenko initialized at ", initial_price, " time ", TimeToString(initial_time));
      
      return true;
   }
   
   //--- Configure engine
   void Configure(double brick_size_points, bool suppress_wicks)
   {
      m_brick_size_points = brick_size_points;
      m_brick_size_price = brick_size_points * m_point;
      m_suppress_wicks = suppress_wicks;
      
      if(m_verbose)
         Print("RegularRenko configured: brick_size=", brick_size_points, 
               " suppress_wicks=", suppress_wicks);
   }
   
   //--- Process incoming tick
   ENUM_DIRTY_STATE ProcessTick(double price, datetime tick_time)
   {
      if(!m_initialized)
      {
         Initialize(price, tick_time);
         return DIRTY_FORMING_CHANGED;
      }
      
      m_completed_count = 0;
      ArrayResize(m_completed_bricks, 0);
      
      // Update forming brick extremes
      if(price > m_forming_brick.high)
         m_forming_brick.high = NormalizeDouble(price, m_digits);
      if(price < m_forming_brick.low)
         m_forming_brick.low = NormalizeDouble(price, m_digits);
      
      m_forming_brick.close = NormalizeDouble(price, m_digits);
      m_forming_brick.tick_volume++;
      
      // Update trend extremes
      if(price > m_trend_high)
         m_trend_high = price;
      if(price < m_trend_low)
         m_trend_low = price;
      
      // Check for brick completion - MULTI-BRICK LOOP
      bool completed_any = false;
      int safety_counter = 0;
      const int MAX_BRICKS_PER_TICK = 100;
      
      while(safety_counter < MAX_BRICKS_PER_TICK)
      {
         bool completed_this_pass = false;
         
         if(m_is_bullish)
         {
            // Check for bullish continuation
            if(price >= m_trend_low + m_brick_size_price)
            {
               CompleteBullishBrick(tick_time);
               completed_this_pass = true;
               completed_any = true;
            }
            // Check for bearish reversal
            else if(price <= m_trend_high - (2.0 * m_brick_size_price))
            {
               CompleteBearishBrick(tick_time);
               completed_this_pass = true;
               completed_any = true;
            }
         }
         else
         {
            // Check for bearish continuation
            if(price <= m_trend_high - m_brick_size_price)
            {
               CompleteBearishBrick(tick_time);
               completed_this_pass = true;
               completed_any = true;
            }
            // Check for bullish reversal
            else if(price >= m_trend_low + (2.0 * m_brick_size_price))
            {
               CompleteBullishBrick(tick_time);
               completed_this_pass = true;
               completed_any = true;
            }
         }
         
         if(!completed_this_pass)
            break;
         
         safety_counter++;
      }
      
      if(safety_counter >= MAX_BRICKS_PER_TICK && m_verbose)
         Print("WARNING: Hit max bricks per tick limit");
      
      // Determine dirty state
      if(m_completed_count > 1)
         return DIRTY_MULTI_BRICK_COMPLETED;
      else if(m_completed_count == 1)
         return DIRTY_BRICK_COMPLETED;
      else if(completed_any)
         return DIRTY_BRICK_COMPLETED;
      else
         return DIRTY_FORMING_CHANGED;
   }
   
   //--- Complete bullish brick
   void CompleteBullishBrick(datetime tick_time)
   {
      RenkoBrick completed = m_forming_brick;
      completed.is_forming = false;
      
      // Set bullish brick OHLC
      completed.open = NormalizeDouble(m_trend_low, m_digits);
      completed.close = NormalizeDouble(m_trend_low + m_brick_size_price, m_digits);
      completed.high = completed.close;
      
      if(m_suppress_wicks)
         completed.low = completed.open;
      else
         completed.low = NormalizeDouble(MathMin(m_forming_brick.low, completed.open), m_digits);
      
      // Store completed brick
      int idx = ArraySize(m_completed_bricks);
      ArrayResize(m_completed_bricks, idx + 1);
      m_completed_bricks[idx] = completed;
      m_completed_count++;
      
      // Update trend
      m_trend_low = completed.close;
      m_trend_high = completed.close;
      m_is_bullish = true;
      
      // Start new forming brick
      m_forming_brick.Reset();
      m_forming_brick.time = tick_time;
      m_forming_brick.open = completed.close;
      m_forming_brick.high = completed.close;
      m_forming_brick.low = completed.close;
      m_forming_brick.close = completed.close;
      m_forming_brick.is_forming = true;
      m_forming_brick.tick_volume = 1;
      
      if(m_verbose)
         Print("Completed bullish brick: ", completed.open, " -> ", completed.close);
   }
   
   //--- Complete bearish brick
   void CompleteBearishBrick(datetime tick_time)
   {
      RenkoBrick completed = m_forming_brick;
      completed.is_forming = false;
      
      // Set bearish brick OHLC
      completed.open = NormalizeDouble(m_trend_high, m_digits);
      completed.close = NormalizeDouble(m_trend_high - m_brick_size_price, m_digits);
      completed.low = completed.close;
      
      if(m_suppress_wicks)
         completed.high = completed.open;
      else
         completed.high = NormalizeDouble(MathMax(m_forming_brick.high, completed.open), m_digits);
      
      // Store completed brick
      int idx = ArraySize(m_completed_bricks);
      ArrayResize(m_completed_bricks, idx + 1);
      m_completed_bricks[idx] = completed;
      m_completed_count++;
      
      // Update trend
      m_trend_high = completed.close;
      m_trend_low = completed.close;
      m_is_bullish = false;
      
      // Start new forming brick
      m_forming_brick.Reset();
      m_forming_brick.time = tick_time;
      m_forming_brick.open = completed.close;
      m_forming_brick.high = completed.close;
      m_forming_brick.low = completed.close;
      m_forming_brick.close = completed.close;
      m_forming_brick.is_forming = true;
      m_forming_brick.tick_volume = 1;
      
      if(m_verbose)
         Print("Completed bearish brick: ", completed.open, " -> ", completed.close);
   }
   
   //--- Get completed bricks
   int GetCompletedBricks(RenkoBrick &bricks[])
   {
      ArrayResize(bricks, m_completed_count);
      for(int i = 0; i < m_completed_count; i++)
         bricks[i] = m_completed_bricks[i];
      
      return m_completed_count;
   }
   
   //--- Get forming brick
   RenkoBrick GetFormingBrick() const
   {
      return m_forming_brick;
   }
   
   //--- Reset engine
   void Reset()
   {
      m_forming_brick.Reset();
      ArrayResize(m_completed_bricks, 0);
      m_completed_count = 0;
      m_trend_high = 0;
      m_trend_low = 0;
      m_is_bullish = true;
      m_initialized = false;
   }
   
   //--- Get state
   bool IsInitialized() const { return m_initialized; }
   bool IsBullish() const { return m_is_bullish; }
   double GetTrendHigh() const { return m_trend_high; }
   double GetTrendLow() const { return m_trend_low; }
};

//+------------------------------------------------------------------+
