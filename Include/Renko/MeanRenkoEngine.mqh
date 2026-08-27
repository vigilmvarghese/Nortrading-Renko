//+------------------------------------------------------------------+
//|                                            MeanRenkoEngine.mqh   |
//|                        Copyright 2024, Nortrading Renko Project  |
//|                                      https://github.com/vigilm   |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024, Nortrading Renko Project"
#property link      "https://github.com/vigilmvarghese/Nortrading-Renko"
#property version   "3.00"
#property strict

#include "RenkoTypes.mqh"

//+------------------------------------------------------------------+
//| Mean Renko Engine - Exact OVO Implementation                    |
//| Based on OVO_Style_Omnia_MT5.mq5 ProcessMeanRenko() lines 869-997|
//+------------------------------------------------------------------+
class CMeanRenkoEngine
{
private:
   string            m_symbol;                 // Symbol
   double            m_point;                  // Point value
   double            m_tick_size;              // Tick size
   int               m_digits;                 // Price digits
   
   double            m_step_points;            // Step size in points
   double            m_step;                   // Step size in price (g_box = step)
   double            m_body;                   // Body size (2x step)
   
   bool              m_suppress_wicks;         // Suppress wicks flag
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
   
   double            m_prev_body_open;         // g_prev_body_open
   double            m_prev_body_close;        // g_prev_body_close
   
   datetime          m_next_bar_time;          // g_next_bar_time
   long              m_brick_serial;           // g_brick_serial
   
   //--- Diagnostic
   int               m_diag_handle;
   bool              m_enable_diagnostics;
   
public:
   //--- Constructor
   CMeanRenkoEngine(string symbol = "", bool verbose = false)
      : m_symbol(symbol), m_step_points(600), m_suppress_wicks(false),
        m_verbose(verbose), m_completed_count(0), m_seeded(false),
        m_last_close(0), m_last_dir(0), m_pending_high(0), m_pending_low(0),
        m_last_price(0), m_tick_volume(0), m_prev_body_open(0), m_prev_body_close(0),
        m_next_bar_time(D'2000.01.01 00:00'), m_brick_serial(0),
        m_diag_handle(INVALID_HANDLE), m_enable_diagnostics(false)
   {
      if(m_symbol == "")
         m_symbol = _Symbol;
      
      m_point = SymbolInfoDouble(m_symbol, SYMBOL_POINT);
      m_tick_size = SymbolInfoDouble(m_symbol, SYMBOL_TRADE_TICK_SIZE);
      m_digits = (int)SymbolInfoInteger(m_symbol, SYMBOL_DIGITS);
      
      if(m_tick_size <= 0.0)
         m_tick_size = m_point;
      
      CalculateGeometry();
      
      ArrayResize(m_completed_bricks, 0, 1000);
   }
   
   //--- Destructor
   ~CMeanRenkoEngine()
   {
      if(m_diag_handle != INVALID_HANDLE)
      {
         FileClose(m_diag_handle);
         m_diag_handle = INVALID_HANDLE;
      }
   }
   
   //--- Calculate Mean Renko geometry from step
   void CalculateGeometry()
   {
      m_step = m_step_points * m_point;
      m_body = 2.0 * m_step;  // Body = 2x step
      
      if(m_verbose)
      {
         Print("MeanRenko Geometry:");
         Print("  Step: ", m_step_points, " points (", m_step, ")");
         Print("  Body: ", m_body, " (2x step)");
         Print("  Continuation: ", m_step, " (1x step)");
         Print("  Reversal: ", m_step * 3.0, " (3x step)");
      }
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
         Print("MeanRenko initialized at ", initial_price, " time ", TimeToString(initial_time));
      
      return true;
   }
   
   //--- Configure engine
   void Configure(double step_points, bool suppress_wicks)
   {
      m_step_points = step_points;
      m_suppress_wicks = suppress_wicks;
      
      CalculateGeometry();
      
      if(m_verbose)
         Print("MeanRenko configured: step=", step_points, " suppress_wicks=", suppress_wicks);
   }
   
   //+------------------------------------------------------------------+
   //| EXACT OVO ProcessMeanRenko() - Reference lines 869-997         |
   //| CSV-calibrated directional wick clipping                        |
   //+------------------------------------------------------------------+
   ENUM_DIRTY_STATE ProcessTick(double raw_price, datetime tick_time)
   {
      if(raw_price <= 0.0 || m_step <= 0.0)
         return DIRTY_NONE;
      
      const double price = NormalizeToTick(raw_price);
      
      if(!m_seeded)
      {
         Initialize(price, tick_time);
         return DIRTY_FORMING_CHANGED;
      }
      
      // CRITICAL: Keep the excursion that existed BEFORE this incoming tick
      // separate from the incoming tick itself
      const double pre_tick_high = m_pending_high;
      const double pre_tick_low = m_pending_low;
      const ulong pre_tick_volume = m_tick_volume;
      
      const int prior_dir_before_tick = m_last_dir;
      const double prior_open_before_tick = m_prev_body_open;
      const double prior_close_before_tick = m_prev_body_close;
      
      m_last_price = price;
      m_tick_volume++;
      
      m_completed_count = 0;
      ArrayResize(m_completed_bricks, 0);
      
      int made = 0;
      
      // Multi-brick loop
      for(int guard = 0; guard < 10000; guard++)
      {
         int dir = 0;
         bool reversal = false;
         double close_target = 0.0;
         
         if(m_last_dir == 0)
         {
            // No direction yet
            if(price >= m_last_close + m_step)
            {
               dir = +1;
               close_target = m_last_close + m_step;
            }
            else if(price <= m_last_close - m_step)
            {
               dir = -1;
               close_target = m_last_close - m_step;
            }
         }
         else if(m_last_dir > 0)
         {
            // Bullish - continuation or reversal
            if(price >= m_last_close + m_step)
            {
               dir = +1;
               close_target = m_last_close + m_step;
            }
            else if(price <= m_last_close - 3.0 * m_step)
            {
               dir = -1;
               reversal = true;
               close_target = m_last_close - 3.0 * m_step;
            }
         }
         else  // m_last_dir < 0
         {
            // Bearish - continuation or reversal
            if(price <= m_last_close - m_step)
            {
               dir = -1;
               close_target = m_last_close - m_step;
            }
            else if(price >= m_last_close + 3.0 * m_step)
            {
               dir = +1;
               reversal = true;
               close_target = m_last_close + 3.0 * m_step;
            }
         }
         
         if(dir == 0)
            break;
         
         close_target = NormalizeToTick(close_target);
         
         // Calculate open price - OVO Mean Renko midpoint logic
         double open_price;
         if(made == 0 && m_brick_serial == 0)
         {
            // Very first brick
            open_price = NormalizeToTick(close_target - dir * m_body);
         }
         else
         {
            // Open at midpoint of previous brick body
            open_price = NormalizeToTick((m_prev_body_open + m_prev_body_close) / 2.0);
         }
         
         // Verify body size integrity
         if(m_brick_serial > 0 &&
            MathAbs(MathAbs(close_target - open_price) - m_body) > (m_tick_size * 1.5))
         {
            open_price = NormalizeToTick(close_target - dir * m_body);
         }
         
         double hi = MathMax(open_price, close_target);
         double lo = MathMin(open_price, close_target);
         
         // ✅ CSV-CALIBRATED OVO MEAN RENKO WICK RULE (Critical!)
         // Reference: OVO lines 933-950
         //
         // UP completed candle   -> high is capped at body close;
         //                          only the LOWER/opposite-side excursion
         //                          may form a wick.
         //
         // DOWN completed candle -> low is capped at body close;
         //                          only the UPPER/opposite-side excursion
         //                          may form a wick.
         //
         // The threshold-crossing raw tick is NOT written beyond the close
         // of the completed candle.
         if(!m_suppress_wicks && made == 0)
         {
            if(dir > 0)
            {
               // UP brick: cap high at close, allow low wick
               hi = close_target;
               lo = MathMin(lo, pre_tick_low);
            }
            else
            {
               // DOWN brick: cap low at close, allow high wick
               lo = close_target;
               hi = MathMax(hi, pre_tick_high);
            }
         }
         
         ulong brick_volume = (made == 0 ? MathMax(pre_tick_volume + 1, (ulong)1) : (ulong)1);
         
         AppendCompleted(open_price, close_target, hi, lo, dir, brick_volume);
         
         made++;
         
         // Start the next synthetic brick at the newly completed boundary
         m_pending_high = m_last_close;
         m_pending_low = m_last_close;
         m_tick_volume = 0;
      }
      
      // If the tick did not complete a brick, it remains part of the active
      // candle's excursion. If it completed bricks, only the residual movement
      // after the final synthetic boundary belongs to the new forming candle.
      if(made == 0)
      {
         m_pending_high = MathMax(pre_tick_high, price);
         m_pending_low = MathMin(pre_tick_low, price);
         m_tick_volume = pre_tick_volume + 1;
      }
      else
      {
         m_pending_high = MathMax(m_last_close, price);
         m_pending_low = MathMin(m_last_close, price);
         m_tick_volume = 1;
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
         Print("Completed Mean ", (direction > 0 ? "UP" : "DOWN"), " brick: ",
               brick.open, " -> ", brick.close,
               " (midpoint=", (brick.open + brick.close) / 2.0, ")",
               " time: ", TimeToString(brick.time));
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
   
   //--- Get forming brick (OVO BuildFormingRate for Mean Renko)
   RenkoBrick GetFormingBrick() const
   {
      RenkoBrick forming;
      
      if(m_brick_serial > 0)
      {
         // OVO Mean Renko relocates the candle open to the mean/midpoint
         // of the previous completed body
         forming.open = NormalizeToTick((m_prev_body_open + m_prev_body_close) / 2.0);
      }
      else
      {
         forming.open = NormalizeToTick(m_last_close);
      }
      
      forming.time = m_next_bar_time;
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
   
   //--- Enable diagnostics
   void EnableDiagnostics(bool enable) { m_enable_diagnostics = enable; }
   
private:
   //--- Normalize to tick size (OVO NormalizeToTick)
   double NormalizeToTick(const double price) const
   {
      if(m_tick_size <= 0.0)
         return NormalizeDouble(price, m_digits);
      
      double v = MathRound(price / m_tick_size) * m_tick_size;
      return NormalizeDouble(v, m_digits);
   }
   
   //--- Round anchor to step grid (OVO RoundAnchor for Mean Renko)
   double RoundAnchor(const double price)
   {
      if(m_step <= 0.0)
         return NormalizeToTick(price);
      
      return NormalizeToTick(MathRound(price / m_step) * m_step);
   }
};

//+------------------------------------------------------------------+
