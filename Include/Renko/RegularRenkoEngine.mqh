//+------------------------------------------------------------------+
//|                                          RegularRenkoEngine.mqh  |
//|                        Copyright 2024, Nortrading Renko Project  |
//|                                      https://github.com/vigilm   |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024, Nortrading Renko Project"
#property link      "https://github.com/vigilmvarghese/Nortrading-Renko"
#property version   "2.00"
#property strict

#include "RenkoTypes.mqh"

//+------------------------------------------------------------------+
//| Regular Renko Engine - OVO-calibrated implementation            |
//| Based on proven OVO_Style_Omnia_MT5 reference logic             |
//+------------------------------------------------------------------+
class CRegularRenkoEngine
{
private:
   string            m_symbol;                 // Symbol
   double            m_point;                  // Point value
   int               m_digits;                 // Price digits
   
   double            m_brick_size_points;      // Brick size in points
   double            m_brick_size_price;       // Brick size in price (g_box)
   bool              m_suppress_wicks;         // Suppress wicks flag
   bool              m_verbose;                // Verbose logging
   
   RenkoBrick        m_completed_bricks[];     // Buffer for completed bricks
   int               m_completed_count;        // Count of completed bricks
   
   // OVO-style state
   bool              m_seeded;                 // Engine seeded
   double            m_last_close;             // Last completed brick close
   int               m_last_dir;               // Last direction: +1 up, -1 down, 0 none
   double            m_pending_high;           // Forming brick high extreme
   double            m_pending_low;            // Forming brick low extreme
   double            m_last_price;             // Last tick price
   ulong             m_tick_volume;            // Forming brick tick volume
   
   datetime          m_next_bar_time;          // Next brick timestamp
   long              m_brick_serial;           // Brick sequence counter
   
   double            m_prev_body_open;         // Previous brick open (for Mean Renko compat)
   double            m_prev_body_close;        // Previous brick close (for Mean Renko compat)
   
public:
   //--- Constructor
   CRegularRenkoEngine(string symbol = "", bool verbose = false)
      : m_symbol(symbol), m_brick_size_points(600), m_suppress_wicks(false),
        m_verbose(verbose), m_completed_count(0), m_seeded(false),
        m_last_close(0), m_last_dir(0), m_pending_high(0), m_pending_low(0),
        m_last_price(0), m_tick_volume(0), m_brick_serial(0),
        m_next_bar_time(D'2000.01.01 00:00'), m_prev_body_open(0), m_prev_body_close(0)
   {
      if(m_symbol == "")
         m_symbol = _Symbol;
      
      m_point = SymbolInfoDouble(m_symbol, SYMBOL_POINT);
      m_digits = (int)SymbolInfoInteger(m_symbol, SYMBOL_DIGITS);
      
      m_brick_size_price = m_brick_size_points * m_point;
      
      ArrayResize(m_completed_bricks, 0, 1000);
   }
   
   //--- Destructor
   ~CRegularRenkoEngine() {}
   
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
   
   //--- Initialize with first price
   bool Initialize(double initial_price, datetime initial_time)
   {
      if(initial_price <= 0)
         return false;
      
      m_last_close = RoundAnchor(initial_price);
      m_last_price = initial_price;
      m_pending_high = initial_price;
      m_pending_low = initial_price;
      m_tick_volume = 1;
      m_seeded = true;
      m_last_dir = 0;
      m_brick_serial = 0;
      m_next_bar_time = initial_time;
      m_completed_count = 0;
      
      m_prev_body_open = m_last_close;
      m_prev_body_close = m_last_close;
      
      ArrayResize(m_completed_bricks, 0);
      
      if(m_verbose)
         Print("RegularRenko initialized at ", initial_price, " time ", TimeToString(initial_time));
      
      return true;
   }
   
   //--- Process incoming tick - OVO-style multi-brick logic
   ENUM_DIRTY_STATE ProcessTick(double price, datetime tick_time)
   {
      if(!m_seeded)
      {
         Initialize(price, tick_time);
         return DIRTY_FORMING_CHANGED;
      }
      
      if(price <= 0.0 || m_brick_size_price <= 0.0)
         return DIRTY_NONE;
      
      price = NormalizeDouble(price, m_digits);
      
      m_completed_count = 0;
      ArrayResize(m_completed_bricks, 0);
      
      // Save excursion BEFORE this tick - belongs to first brick only
      const double prior_high = m_pending_high;
      const double prior_low = m_pending_low;
      const ulong prior_vol = MathMax(m_tick_volume, (ulong)1);
      
      m_last_price = price;
      m_tick_volume++;
      
      int made = 0;
      bool first_emitted = true;
      
      // Guard against infinite loops
      for(int guard = 0; guard < 10000; guard++)
      {
         bool emitted = false;
         
         if(m_last_dir == 0)
         {
            // No direction yet - check both ways
            if(price >= m_last_close + m_brick_size_price)
            {
               CompleteUpBrick(false,
                              first_emitted ? prior_high : m_last_close,
                              first_emitted ? prior_low : m_last_close,
                              prior_vol);
               emitted = true;
            }
            else if(price <= m_last_close - m_brick_size_price)
            {
               CompleteDownBrick(false,
                                first_emitted ? prior_high : m_last_close,
                                first_emitted ? prior_low : m_last_close,
                                prior_vol);
               emitted = true;
            }
         }
         else if(m_last_dir > 0)
         {
            // Bullish - continuation or reversal
            if(price >= m_last_close + m_brick_size_price)
            {
               CompleteUpBrick(false,
                              first_emitted ? prior_high : m_last_close,
                              first_emitted ? prior_low : m_last_close,
                              prior_vol);
               emitted = true;
            }
            else if(price <= m_last_close - 2.0 * m_brick_size_price)
            {
               CompleteUpBrick(true,  // Reversal
                              first_emitted ? prior_high : m_last_close,
                              first_emitted ? prior_low : m_last_close,
                              prior_vol);
               emitted = true;
            }
         }
         else  // m_last_dir < 0
         {
            // Bearish - continuation or reversal
            if(price <= m_last_close - m_brick_size_price)
            {
               CompleteDownBrick(false,
                                first_emitted ? prior_high : m_last_close,
                                first_emitted ? prior_low : m_last_close,
                                prior_vol);
               emitted = true;
            }
            else if(price >= m_last_close + 2.0 * m_brick_size_price)
            {
               CompleteDownBrick(true,  // Reversal
                                first_emitted ? prior_high : m_last_close,
                                first_emitted ? prior_low : m_last_close,
                                prior_vol);
               emitted = true;
            }
         }
         
         if(!emitted)
            break;
         
         made++;
         first_emitted = false;
      }
      
      if(made > 0)
      {
         // After completing bricks, reset excursion to last_close + current price
         m_pending_high = MathMax(m_last_close, price);
         m_pending_low = MathMin(m_last_close, price);
         m_tick_volume = 1;
      }
      else
      {
         // No bricks completed - update forming brick extremes
         m_pending_high = MathMax(m_pending_high, price);
         m_pending_low = MathMin(m_pending_low, price);
      }
      
      // Determine dirty state
      if(m_completed_count > 1)
         return DIRTY_MULTI_BRICK_COMPLETED;
      else if(m_completed_count == 1)
         return DIRTY_BRICK_COMPLETED;
      else
         return DIRTY_FORMING_CHANGED;
   }
   
   //--- Complete bullish brick (OVO logic)
   void CompleteUpBrick(const bool reversal,
                        const double prior_high,
                        const double prior_low,
                        const ulong volume)
   {
      double o, c;
      
      if(reversal)
      {
         // Classic Renko: reversal down from uptrend
         // With relocation: open 1 box below previous close, close 2 boxes below
         o = m_last_close - m_brick_size_price;
         c = m_last_close - 2.0 * m_brick_size_price;
      }
      else
      {
         // Continuation: open at last close, close 1 box up
         o = m_last_close;
         c = m_last_close + m_brick_size_price;
      }
      
      o = NormalizeDouble(o, m_digits);
      c = NormalizeDouble(c, m_digits);
      
      double hi = MathMax(o, c);
      double lo = MathMin(o, c);
      
      if(!m_suppress_wicks)
      {
         if(reversal)
            lo = MathMin(lo, prior_low);  // Down brick can have low wick
         else
            lo = MathMin(lo, prior_low);  // Up brick can have low wick
      }
      
      AppendCompleted(o, c, hi, lo, reversal ? -1 : +1, volume);
   }
   
   //--- Complete bearish brick (OVO logic)
   void CompleteDownBrick(const bool reversal,
                          const double prior_high,
                          const double prior_low,
                          const ulong volume)
   {
      double o, c;
      
      if(reversal)
      {
         // Classic Renko: reversal up from downtrend
         // With relocation: open 1 box above previous close, close 2 boxes above
         o = m_last_close + m_brick_size_price;
         c = m_last_close + 2.0 * m_brick_size_price;
      }
      else
      {
         // Continuation: open at last close, close 1 box down
         o = m_last_close;
         c = m_last_close - m_brick_size_price;
      }
      
      o = NormalizeDouble(o, m_digits);
      c = NormalizeDouble(c, m_digits);
      
      double hi = MathMax(o, c);
      double lo = MathMin(o, c);
      
      if(!m_suppress_wicks)
      {
         if(reversal)
            lo = MathMin(lo, prior_low);  // Up brick can have low wick
         else
            hi = MathMax(hi, prior_high);  // Down brick can have high wick
      }
      
      AppendCompleted(o, c, hi, lo, reversal ? +1 : -1, volume);
   }
   
   //--- Append completed brick to buffer
   void AppendCompleted(const double open_price,
                        const double close_price,
                        const double wick_high,
                        const double wick_low,
                        const int direction,
                        const ulong volume)
   {
      int n = m_completed_count;
      ArrayResize(m_completed_bricks, n + 1);
      
      RenkoBrick brick;
      brick.time = m_next_bar_time;
      brick.open = NormalizeDouble(open_price, m_digits);
      brick.close = NormalizeDouble(close_price, m_digits);
      brick.high = NormalizeDouble(MathMax(MathMax(brick.open, brick.close), wick_high), m_digits);
      brick.low = NormalizeDouble(MathMin(MathMin(brick.open, brick.close), wick_low), m_digits);
      brick.tick_volume = (long)MathMax((double)volume, 1.0);
      brick.spread = 0;
      brick.real_volume = 0;
      brick.is_forming = false;
      
      // OHLC integrity
      if(brick.high < MathMax(brick.open, brick.close))
         brick.high = MathMax(brick.open, brick.close);
      if(brick.low > MathMin(brick.open, brick.close))
         brick.low = MathMin(brick.open, brick.close);
      
      m_completed_bricks[n] = brick;
      m_completed_count++;
      
      // Update state
      m_next_bar_time += 60;  // 60 seconds between bricks
      m_brick_serial++;
      m_last_dir = direction;
      m_last_close = brick.close;
      m_prev_body_open = brick.open;
      m_prev_body_close = brick.close;
      
      if(m_verbose)
         Print("Completed ", (direction > 0 ? "UP" : "DOWN"), " brick: ",
               brick.open, " -> ", brick.close, " time: ", TimeToString(brick.time));
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
      RenkoBrick forming;
      forming.time = m_next_bar_time;
      forming.open = NormalizeDouble(m_last_close, m_digits);
      forming.close = NormalizeDouble(m_last_price, m_digits);
      forming.high = NormalizeDouble(MathMax(MathMax(forming.open, forming.close), m_pending_high), m_digits);
      forming.low = NormalizeDouble(MathMin(MathMin(forming.open, forming.close), m_pending_low), m_digits);
      forming.tick_volume = (long)MathMax((double)m_tick_volume, 1.0);
      forming.spread = 0;
      forming.real_volume = 0;
      forming.is_forming = true;
      
      return forming;
   }
   
   //--- Reset engine
   void Reset()
   {
      ArrayResize(m_completed_bricks, 0);
      m_completed_count = 0;
      m_seeded = false;
      m_last_close = 0;
      m_last_dir = 0;
      m_pending_high = 0;
      m_pending_low = 0;
      m_last_price = 0;
      m_tick_volume = 0;
      m_brick_serial = 0;
      m_next_bar_time = D'2000.01.01 00:00';
      m_prev_body_open = 0;
      m_prev_body_close = 0;
   }
   
   //--- Get state
   bool IsInitialized() const { return m_seeded; }
   int GetDirection() const { return m_last_dir; }
   double GetLastClose() const { return m_last_close; }
   long GetBrickSerial() const { return m_brick_serial; }
   
private:
   //--- Round anchor to brick grid (first brick only)
   double RoundAnchor(const double price)
   {
      if(m_brick_size_price <= 0.0)
         return NormalizeDouble(price, m_digits);
      
      return NormalizeDouble(MathRound(price / m_brick_size_price) * m_brick_size_price, m_digits);
   }
};

//+------------------------------------------------------------------+
