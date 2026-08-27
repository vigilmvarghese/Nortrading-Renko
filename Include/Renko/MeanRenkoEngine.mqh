//+------------------------------------------------------------------+
//|                                            MeanRenkoEngine.mqh   |
//|                        Copyright 2024, Nortrading Renko Project  |
//|                                      https://github.com/vigilm   |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024, Nortrading Renko Project"
#property link      "https://github.com/vigilmvarghese/Nortrading-Renko"
#property version   "2.00"
#property strict

#include "RenkoTypes.mqh"

//+------------------------------------------------------------------+
//| Mean Renko Engine - OVO-calibrated implementation               |
//| Based on proven OVO_Style_Omnia_MT5 reference (lines 869-997)   |
//+------------------------------------------------------------------+
class CMeanRenkoEngine
{
private:
   string            m_symbol;                 // Symbol
   double            m_point;                  // Point value
   int               m_digits;                 // Price digits
   
   double            m_step_points;            // Step size in points
   double            m_step_price;             // Step size in price (g_box)
   double            m_body_price;             // Body size (2x step)
   
   bool              m_suppress_wicks;         // Suppress wicks flag
   bool              m_verbose;                // Verbose logging
   
   RenkoBrick        m_completed_bricks[];     // Buffer for completed bricks
   int               m_completed_count;        // Count of completed bricks
   
   // OVO-style state variables
   bool              m_seeded;                 // Engine seeded
   double            m_last_close;             // Last completed brick close
   int               m_last_dir;               // +1 up, -1 down, 0 none
   double            m_pending_high;           // Forming brick high extreme
   double            m_pending_low;            // Forming brick low extreme
   double            m_last_price;             // Last tick price
   ulong             m_tick_volume;            // Forming brick tick volume
   
   double            m_prev_body_open;         // Previous brick body open
   double            m_prev_body_close;        // Previous brick body close
   
   datetime          m_next_bar_time;          // Next brick timestamp
   long              m_brick_serial;           // Brick sequence counter
   
   //--- Diagnostic file handle
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
      m_digits = (int)SymbolInfoInteger(m_symbol, SYMBOL_DIGITS);
      
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
      m_step_price = m_step_points * m_point;
      m_body_price = m_step_price * 2.0;  // Body = 2x step
      
      if(m_verbose)
      {
         Print("MeanRenko Geometry:");
         Print("  Step: ", m_step_points, " points (", m_step_price, ")");
         Print("  Body: ", m_body_price, " (2x step)");
         Print("  Continuation: ", m_step_price, " (1x step)");
         Print("  Reversal: ", m_step_price * 3.0, " (3x step)");
      }
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
         Print("MeanRenko initialized at ", initial_price, " time ", TimeToString(initial_time));
      
      WriteDiagnostic("INIT", initial_time, initial_price, 0, 0, 0);
      
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
   
   //--- Process incoming tick - OVO Mean Renko logic
   ENUM_DIRTY_STATE ProcessTick(double raw_price, datetime tick_time)
   {
      if(raw_price <= 0.0 || m_step_price <= 0.0)
         return DIRTY_NONE;
      
      const double price = NormalizeDouble(raw_price, m_digits);
      
      if(!m_seeded)
      {
         Initialize(price, tick_time);
         return DIRTY_FORMING_CHANGED;
      }
      
      m_completed_count = 0;
      ArrayResize(m_completed_bricks, 0);
      
      // ✅ CRITICAL OVO PATTERN: Save extremes BEFORE this tick
      const double pre_tick_high = m_pending_high;
      const double pre_tick_low = m_pending_low;
      const ulong pre_tick_volume = m_tick_volume;
      
      const int prior_dir_before_tick = m_last_dir;
      const double prior_open_before_tick = m_prev_body_open;
      const double prior_close_before_tick = m_prev_body_close;
      
      m_last_price = price;
      m_tick_volume++;
      
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
            if(price >= m_last_close + m_step_price)
            {
               dir = +1;
               close_target = m_last_close + m_step_price;
            }
            else if(price <= m_last_close - m_step_price)
            {
               dir = -1;
               close_target = m_last_close - m_step_price;
            }
         }
         else if(m_last_dir > 0)
         {
            // Bullish - continuation or reversal
            if(price >= m_last_close + m_step_price)
            {
               dir = +1;
               close_target = m_last_close + m_step_price;
            }
            else if(price <= m_last_close - 3.0 * m_step_price)
            {
               dir = -1;
               reversal = true;
               close_target = m_last_close - 3.0 * m_step_price;
            }
         }
         else  // m_last_dir < 0
         {
            // Bearish - continuation or reversal
            if(price <= m_last_close - m_step_price)
            {
               dir = -1;
               close_target = m_last_close - m_step_price;
            }
            else if(price >= m_last_close + 3.0 * m_step_price)
            {
               dir = +1;
               reversal = true;
               close_target = m_last_close + 3.0 * m_step_price;
            }
         }
         
         if(dir == 0)
            break;
         
         close_target = NormalizeDouble(close_target, m_digits);
         
         // Calculate open price - OVO Mean Renko midpoint logic
         double open_price;
         if(made == 0 && m_brick_serial == 0)
         {
            // Very first brick
            open_price = NormalizeDouble(close_target - dir * m_body_price, m_digits);
         }
         else
         {
            // Open at midpoint of previous brick body
            open_price = NormalizeDouble((m_prev_body_open + m_prev_body_close) / 2.0, m_digits);
         }
         
         // Verify body size integrity
         if(m_brick_serial > 0 &&
            MathAbs(MathAbs(close_target - open_price) - m_body_price) > (m_point * 1.5))
         {
            open_price = NormalizeDouble(close_target - dir * m_body_price, m_digits);
         }
         
         double hi = MathMax(open_price, close_target);
         double lo = MathMin(open_price, close_target);
         
         // ✅ OVO DIRECTIONAL WICK CLIPPING (Critical!)
         if(!m_suppress_wicks && made == 0)
         {
            // OVO Mean Renko wick rule:
            //   UP brick: high capped at body close, only LOW wick allowed
            //   DOWN brick: low capped at body close, only HIGH wick allowed
            if(dir > 0)
            {
               // UP brick: cap high, allow opposite-side low wick
               hi = close_target;
               lo = MathMin(lo, pre_tick_low);
            }
            else
            {
               // DOWN brick: cap low, allow opposite-side high wick
               lo = close_target;
               hi = MathMax(hi, pre_tick_high);
            }
         }
         
         ulong brick_volume = (made == 0 ? MathMax(pre_tick_volume + 1, (ulong)1) : (ulong)1);
         
         AppendCompleted(open_price, close_target, hi, lo, dir, brick_volume);
         
         if(m_enable_diagnostics)
         {
            string event_type = (reversal ? "REVERSAL" : "CONTINUATION");
            WriteDiagnostic(event_type, tick_time, price, made + 1, open_price, close_target);
         }
         
         made++;
         
         // Start next brick at new boundary
         m_pending_high = m_last_close;
         m_pending_low = m_last_close;
         m_tick_volume = 0;
      }
      
      // Update forming brick excursion
      if(made == 0)
      {
         // No bricks completed - update extremes
         m_pending_high = MathMax(pre_tick_high, price);
         m_pending_low = MathMin(pre_tick_low, price);
         m_tick_volume = pre_tick_volume + 1;
      }
      else
      {
         // Bricks completed - reset to boundary + current price
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
   
   //--- Append completed brick
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
   
   //--- Get forming brick
   RenkoBrick GetFormingBrick() const
   {
      RenkoBrick forming;
      
      if(m_brick_serial > 0)
      {
         // Mean Renko: open at midpoint of previous body
         forming.open = NormalizeDouble((m_prev_body_open + m_prev_body_close) / 2.0, m_digits);
      }
      else
      {
         forming.open = NormalizeDouble(m_last_close, m_digits);
      }
      
      forming.time = m_next_bar_time;
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
   
   //--- Enable diagnostics
   void EnableDiagnostics(bool enable) { m_enable_diagnostics = enable; }
   
private:
   //--- Round anchor to brick grid (first brick only)
   double RoundAnchor(const double price)
   {
      if(m_step_price <= 0.0)
         return NormalizeDouble(price, m_digits);
      
      return NormalizeDouble(MathRound(price / m_step_price) * m_step_price, m_digits);
   }
   
   //--- Diagnostic logging stub
   void WriteDiagnostic(const string event, datetime time, double price, 
                        int brick_index, double brick_open, double brick_close)
   {
      if(!m_enable_diagnostics)
         return;
      
      // Placeholder for diagnostic logging
      // Can be expanded to write to file like OVO reference
   }
};

//+------------------------------------------------------------------+
