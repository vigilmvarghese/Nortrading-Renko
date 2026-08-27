//+------------------------------------------------------------------+
//|                                          RegularRenkoEngine.mqh  |
//|                        Copyright 2024, Nortrading Renko Project  |
//|                                      https://github.com/vigilm   |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024, Nortrading Renko Project"
#property link      "https://github.com/vigilmvarghese/Nortrading-Renko"
#property version   "3.00"
#property strict

#include "RenkoTypes.mqh"

//+------------------------------------------------------------------+
//| Regular Renko Engine - Exact OVO Implementation                 |
//| Based on OVO_Style_Omnia_MT5.mq5 ProcessPrice() logic           |
//+------------------------------------------------------------------+
class CRegularRenkoEngine
{
private:
   string            m_symbol;                 // Symbol
   double            m_point;                  // Point value
   double            m_tick_size;              // Tick size
   int               m_digits;                 // Price digits
   
   double            m_brick_size_points;      // Brick size in points
   double            m_box;                    // Brick size in price (g_box)
   bool              m_suppress_wicks;         // Suppress wicks flag
   bool              m_relocate_open;          // Relocate reversal open
   bool              m_verbose;                // Verbose logging
   
   RenkoBrick        m_completed_bricks[];     // Buffer for completed bricks
   int               m_completed_count;        // Count of completed bricks
   
   // OVO-style state variables (exact match to reference)
   bool              m_seeded;                 // g_seeded
   double            m_last_close;             // g_last_close
   int               m_last_dir;               // g_last_dir: +1 up, -1 down, 0 none
   double            m_pending_high;           // g_pending_high
   double            m_pending_low;            // g_pending_low
   double            m_last_price;             // g_last_price
   ulong             m_tick_volume;            // g_tick_volume
   
   datetime          m_next_bar_time;          // g_next_bar_time
   long              m_brick_serial;           // g_brick_serial
   
   double            m_prev_body_open;         // g_prev_body_open
   double            m_prev_body_close;        // g_prev_body_close
   
public:
   //--- Constructor
   CRegularRenkoEngine(string symbol = "", bool verbose = false)
      : m_symbol(symbol), m_brick_size_points(600), m_suppress_wicks(false),
        m_relocate_open(true), m_verbose(verbose), m_completed_count(0),
        m_seeded(false), m_last_close(0), m_last_dir(0), 
        m_pending_high(0), m_pending_low(0), m_last_price(0), m_tick_volume(0),
        m_brick_serial(0), m_next_bar_time(D'2000.01.01 00:00'),
        m_prev_body_open(0), m_prev_body_close(0)
   {
      if(m_symbol == "")
         m_symbol = _Symbol;
      
      m_point = SymbolInfoDouble(m_symbol, SYMBOL_POINT);
      m_tick_size = SymbolInfoDouble(m_symbol, SYMBOL_TRADE_TICK_SIZE);
      m_digits = (int)SymbolInfoInteger(m_symbol, SYMBOL_DIGITS);
      
      if(m_tick_size <= 0.0)
         m_tick_size = m_point;
      
      m_box = m_brick_size_points * m_point;
      
      ArrayResize(m_completed_bricks, 0, 1000);
   }
   
   //--- Destructor
   ~CRegularRenkoEngine() {}
   
   //--- Configure engine
   void Configure(double brick_size_points, bool suppress_wicks, bool relocate_open = true)
   {
      m_brick_size_points = brick_size_points;
      m_box = NormalizeToTick(brick_size_points * m_point);
      m_suppress_wicks = suppress_wicks;
      m_relocate_open = relocate_open;
      
      if(m_verbose)
         Print("RegularRenko configured: brick=", brick_size_points, 
               " suppress_wicks=", suppress_wicks,
               " relocate_open=", relocate_open);
   }
   
   //--- Initialize with first price (OVO SeedEngine)
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
   
   //+------------------------------------------------------------------+
   //| EXACT OVO ProcessPrice() - Multi-brick processing               |
   //| Reference: OVO_Style_Omnia_MT5.mq5 lines 1520-1603             |
   //+------------------------------------------------------------------+
   ENUM_DIRTY_STATE ProcessTick(double raw_price, datetime tick_time)
   {
      if(raw_price <= 0.0 || m_box <= 0.0)
         return DIRTY_NONE;
      
      const double price = NormalizeToTick(raw_price);
      
      if(!m_seeded)
      {
         Initialize(price, tick_time);
         return DIRTY_FORMING_CHANGED;
      }
      
      // Save excursion that existed BEFORE the present tick
      const double prior_high = m_pending_high;
      const double prior_low = m_pending_low;
      const ulong prior_vol = MathMax(m_tick_volume, (ulong)1);
      
      m_last_price = price;
      m_tick_volume++;
      
      m_completed_count = 0;
      ArrayResize(m_completed_bricks, 0);
      
      int made = 0;
      bool first_emitted = true;
      
      // Guard against malformed quotes / accidental infinite loops
      for(int guard = 0; guard < 10000; guard++)
      {
         bool emitted = false;
         
         if(m_last_dir == 0)
         {
            // No direction yet - check both ways
            if(price >= m_last_close + m_box)
            {
               CompleteUpBrick(false,
                              first_emitted ? prior_high : m_last_close,
                              first_emitted ? prior_low : m_last_close,
                              prior_vol);
               emitted = true;
            }
            else if(price <= m_last_close - m_box)
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
            if(price >= m_last_close + m_box)
            {
               CompleteUpBrick(false,
                              first_emitted ? prior_high : m_last_close,
                              first_emitted ? prior_low : m_last_close,
                              prior_vol);
               emitted = true;
            }
            else if(price <= m_last_close - 2.0 * m_box)
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
            if(price <= m_last_close - m_box)
            {
               CompleteDownBrick(false,
                                first_emitted ? prior_high : m_last_close,
                                first_emitted ? prior_low : m_last_close,
                                prior_vol);
               emitted = true;
            }
            else if(price >= m_last_close + 2.0 * m_box)
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
      
      // Excursion state belongs to the CURRENT unfinished Renko decision
      if(made > 0)
      {
         m_pending_high = MathMax(m_last_close, price);
         m_pending_low = MathMin(m_last_close, price);
         m_tick_volume = 1;
      }
      else
      {
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
   
   //+------------------------------------------------------------------+
   //| EXACT OVO CompleteUpBrick() - Reference lines 337-377          |
   //+------------------------------------------------------------------+
   void CompleteUpBrick(const bool reversal,
                        const double prior_high,
                        const double prior_low,
                        const ulong volume)
   {
      double o, c;
      
      if(reversal)
      {
         // Classic Renko reversal with relocation
         if(m_relocate_open)
         {
            o = m_last_close - m_box;
            c = m_last_close - 2.0 * m_box;
         }
         else
         {
            // No-gap visual form
            o = m_last_close;
            c = m_last_close - 2.0 * m_box;
         }
         
         double hi = MathMax(o, c);
         double lo = MathMin(o, c);
         
         if(!m_suppress_wicks)
            hi = MathMax(hi, prior_high);
         
         AppendCompleted(o, c, hi, lo, -1, volume);
         return;
      }
      
      // Continuation
      o = m_last_close;
      c = m_last_close + m_box;
      
      double hi = MathMax(o, c);
      double lo = MathMin(o, c);
      
      if(!m_suppress_wicks)
         lo = MathMin(lo, prior_low);
      
      AppendCompleted(o, c, hi, lo, +1, volume);
   }
   
   //+------------------------------------------------------------------+
   //| EXACT OVO CompleteDownBrick() - Reference lines 379-419        |
   //+------------------------------------------------------------------+
   void CompleteDownBrick(const bool reversal,
                          const double prior_high,
                          const double prior_low,
                          const ulong volume)
   {
      double o, c;
      
      if(reversal)
      {
         // Classic Renko reversal with relocation
         if(m_relocate_open)
         {
            o = m_last_close + m_box;
            c = m_last_close + 2.0 * m_box;
         }
         else
         {
            // No-gap visual form
            o = m_last_close;
            c = m_last_close + 2.0 * m_box;
         }
         
         double hi = MathMax(o, c);
         double lo = MathMin(o, c);
         
         if(!m_suppress_wicks)
            lo = MathMin(lo, prior_low);
         
         AppendCompleted(o, c, hi, lo, +1, volume);
         return;
      }
      
      // Continuation
      o = m_last_close;
      c = m_last_close - m_box;
      
      double hi = MathMax(o, c);
      double lo = MathMin(o, c);
      
      if(!m_suppress_wicks)
         hi = MathMax(hi, prior_high);
      
      AppendCompleted(o, c, hi, lo, -1, volume);
   }
   
   //+------------------------------------------------------------------+
   //| EXACT OVO AppendCompleted() - Reference lines 259-295          |
   //+------------------------------------------------------------------+
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
      brick.open = NormalizeToTick(open_price);
      brick.close = NormalizeToTick(close_price);
      brick.high = NormalizeToTick(MathMax(MathMax(brick.open, brick.close), wick_high));
      brick.low = NormalizeToTick(MathMin(MathMin(brick.open, brick.close), wick_low));
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
      {
         Print("=== Completed ", (direction > 0 ? "UP" : "DOWN"), " brick ===");
         Print("  Time: ", TimeToString(brick.time));
         Print("  Open: ", brick.open);
         Print("  High: ", brick.high);
         Print("  Low: ", brick.low);
         Print("  Close: ", brick.close);
         Print("  Body: ", MathAbs(brick.close - brick.open));
         Print("  Volume: ", brick.tick_volume);
      }
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
      forming.open = NormalizeToTick(m_last_close);
      forming.close = NormalizeToTick(m_last_price);
      forming.high = NormalizeToTick(MathMax(MathMax(forming.open, forming.close), m_pending_high));
      forming.low = NormalizeToTick(MathMin(MathMin(forming.open, forming.close), m_pending_low));
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
   //--- Normalize to tick size (OVO NormalizeToTick)
   double NormalizeToTick(const double price) const
   {
      if(m_tick_size <= 0.0)
         return NormalizeDouble(price, m_digits);
      
      double v = MathRound(price / m_tick_size) * m_tick_size;
      return NormalizeDouble(v, m_digits);
   }
   
   //--- Round anchor to brick grid (OVO RoundAnchor)
   double RoundAnchor(const double price)
   {
      if(m_box <= 0.0)
         return NormalizeToTick(price);
      
      return NormalizeToTick(MathRound(price / m_box) * m_box);
   }
};

//+------------------------------------------------------------------+
