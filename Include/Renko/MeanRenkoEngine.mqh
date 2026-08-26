//+------------------------------------------------------------------+
//|                                            MeanRenkoEngine.mqh   |
//|                        Copyright 2024, Nortrading Renko Project  |
//|                                      https://github.com/vigilm   |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024, Nortrading Renko Project"
#property link      "https://github.com/vigilmvarghese/Nortrading-Renko"
#property version   "1.00"
#property strict

#include "RenkoTypes.mqh"

//+------------------------------------------------------------------+
//| Mean Renko Engine                                                |
//| OVO-calibrated body/wick behavior with Mean Renko geometry       |
//+------------------------------------------------------------------+
class CMeanRenkoEngine
{
private:
   string            m_symbol;                 // Symbol
   double            m_point;                  // Point value
   int               m_digits;                 // Price digits
   
   double            m_step_points;            // Step size in points
   double            m_step_price;             // Step size in price
   double            m_body_price;             // Body size in price (2x step)
   double            m_continuation_price;     // Continuation threshold (1x step)
   double            m_reversal_price;         // Reversal threshold (3x step)
   
   bool              m_suppress_wicks;         // Suppress wicks flag
   bool              m_verbose;                // Verbose logging
   
   RenkoBrick        m_forming_brick;          // Current forming brick
   RenkoBrick        m_completed_bricks[];     // Buffer for completed bricks
   int               m_completed_count;        // Count of completed bricks
   
   double            m_last_body_midpoint;     // Last candle body midpoint
   double            m_current_high;           // Current price high extreme
   double            m_current_low;            // Current price low extreme
   bool              m_is_bullish;             // Current trend direction
   bool              m_initialized;            // Initialization flag
   
   //--- Diagnostic file handle
   int               m_diag_handle;
   bool              m_enable_diagnostics;
   
public:
   //--- Constructor
   CMeanRenkoEngine(string symbol = "", bool verbose = false)
      : m_symbol(symbol), m_step_points(600), m_suppress_wicks(false),
        m_verbose(verbose), m_completed_count(0), m_is_bullish(true),
        m_initialized(false), m_last_body_midpoint(0), m_diag_handle(INVALID_HANDLE),
        m_enable_diagnostics(false)
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
      m_body_price = m_step_price * 2.0;              // Body = 2x step
      m_continuation_price = m_step_price;             // Continuation = 1x step
      m_reversal_price = m_step_price * 3.0;          // Reversal = 3x step
      
      if(m_verbose)
      {
         Print("MeanRenko Geometry:");
         Print("  Step: ", m_step_points, " points (", m_step_price, ")");
         Print("  Body: ", m_body_price);
         Print("  Continuation: ", m_continuation_price);
         Print("  Reversal: ", m_reversal_price);
      }
   }
   
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
      
      m_last_body_midpoint = m_forming_brick.open;
      m_current_high = m_forming_brick.open;
      m_current_low = m_forming_brick.open;
      m_is_bullish = true;
      m_initialized = true;
      m_completed_count = 0;
      
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
      
      // Update current extremes
      if(price > m_current_high)
         m_current_high = price;
      if(price < m_current_low)
         m_current_low = price;
      
      // Check for brick completion - MULTI-BRICK LOOP
      bool completed_any = false;
      int safety_counter = 0;
      const int MAX_BRICKS_PER_TICK = 100;
      
      while(safety_counter < MAX_BRICKS_PER_TICK)
      {
         bool completed_this_pass = false;
         
         if(m_is_bullish)
         {
            // Check for bullish continuation (moved 1x step from midpoint)
            double continuation_threshold = m_last_body_midpoint + m_continuation_price;
            if(price >= continuation_threshold)
            {
               CompleteBullishBrick(tick_time);
               completed_this_pass = true;
               completed_any = true;
            }
            // Check for bearish reversal (moved 3x step below midpoint)
            else
            {
               double reversal_threshold = m_last_body_midpoint - m_reversal_price;
               if(price <= reversal_threshold)
               {
                  CompleteBearishBrick(tick_time);
                  completed_this_pass = true;
                  completed_any = true;
               }
            }
         }
         else
         {
            // Check for bearish continuation (moved 1x step from midpoint)
            double continuation_threshold = m_last_body_midpoint - m_continuation_price;
            if(price <= continuation_threshold)
            {
               CompleteBearishBrick(tick_time);
               completed_this_pass = true;
               completed_any = true;
            }
            // Check for bullish reversal (moved 3x step above midpoint)
            else
            {
               double reversal_threshold = m_last_body_midpoint + m_reversal_price;
               if(price >= reversal_threshold)
               {
                  CompleteBullishBrick(tick_time);
                  completed_this_pass = true;
                  completed_any = true;
               }
            }
         }
         
         if(!completed_this_pass)
            break;
         
         safety_counter++;
      }
      
      if(safety_counter >= MAX_BRICKS_PER_TICK && m_verbose)
         Print("WARNING: Hit max bricks per tick limit");
      
      WriteDiagnostic("TICK", tick_time, price, m_completed_count, 
                      m_forming_brick.open, m_forming_brick.close);
      
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
      
      // Calculate new brick open around previous body midpoint
      double new_open = NormalizeDouble(m_last_body_midpoint - m_step_price, m_digits);
      double new_close = NormalizeDouble(new_open + m_body_price, m_digits);
      
      completed.open = new_open;
      completed.close = new_close;
      completed.high = new_close;  // Bullish: high capped at body close
      
      // Wick behavior: opposite-side lower excursion can form wick
      if(m_suppress_wicks)
         completed.low = completed.open;
      else
      {
         double wick_low = NormalizeDouble(MathMin(m_current_low, completed.open), m_digits);
         completed.low = wick_low;
      }
      
      // Store completed brick
      int idx = ArraySize(m_completed_bricks);
      ArrayResize(m_completed_bricks, idx + 1);
      m_completed_bricks[idx] = completed;
      m_completed_count++;
      
      // Update state for next brick
      m_last_body_midpoint = (completed.open + completed.close) / 2.0;
      m_current_high = completed.close;
      m_current_low = completed.close;
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
      {
         Print("Completed Mean bullish brick: ", completed.open, " -> ", completed.close,
               " (midpoint=", m_last_body_midpoint, ")");
      }
      
      WriteDiagnostic("BULL_COMPLETE", tick_time, completed.close, 1, 
                      completed.open, completed.close);
   }
   
   //--- Complete bearish brick
   void CompleteBearishBrick(datetime tick_time)
   {
      RenkoBrick completed = m_forming_brick;
      completed.is_forming = false;
      
      // Calculate new brick open around previous body midpoint
      double new_open = NormalizeDouble(m_last_body_midpoint + m_step_price, m_digits);
      double new_close = NormalizeDouble(new_open - m_body_price, m_digits);
      
      completed.open = new_open;
      completed.close = new_close;
      completed.low = new_close;  // Bearish: low capped at body close
      
      // Wick behavior: opposite-side upper excursion can form wick
      if(m_suppress_wicks)
         completed.high = completed.open;
      else
      {
         double wick_high = NormalizeDouble(MathMax(m_current_high, completed.open), m_digits);
         completed.high = wick_high;
      }
      
      // Store completed brick
      int idx = ArraySize(m_completed_bricks);
      ArrayResize(m_completed_bricks, idx + 1);
      m_completed_bricks[idx] = completed;
      m_completed_count++;
      
      // Update state for next brick
      m_last_body_midpoint = (completed.open + completed.close) / 2.0;
      m_current_high = completed.close;
      m_current_low = completed.close;
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
      {
         Print("Completed Mean bearish brick: ", completed.open, " -> ", completed.close,
               " (midpoint=", m_last_body_midpoint, ")");
      }
      
      WriteDiagnostic("BEAR_COMPLETE", tick_time, completed.close, 1,
                      completed.open, completed.close);
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
      m_last_body_midpoint = 0;
      m_current_high = 0;
      m_current_low = 0;
      m_is_bullish = true;
      m_initialized = false;
   }
   
   //--- Get state
   bool IsInitialized() const { return m_initialized; }
   bool IsBullish() const { return m_is_bullish; }
   double GetLastBodyMidpoint() const { return m_last_body_midpoint; }
   
   //--- Enable diagnostics
   void EnableDiagnostics(bool enable)
   {
      m_enable_diagnostics = enable;
      
      if(enable && m_diag_handle == INVALID_HANDLE)
      {
         string filename = "MeanRenko_Diagnostic_" + m_symbol + ".csv";
         m_diag_handle = FileOpen(filename, FILE_WRITE|FILE_CSV|FILE_ANSI);
         
         if(m_diag_handle != INVALID_HANDLE)
         {
            FileWrite(m_diag_handle, "Event", "Time", "Price", "BricksCompleted", 
                      "FormingOpen", "FormingClose");
         }
      }
      else if(!enable && m_diag_handle != INVALID_HANDLE)
      {
         FileClose(m_diag_handle);
         m_diag_handle = INVALID_HANDLE;
      }
   }
   
   //--- Write diagnostic entry
   void WriteDiagnostic(string event, datetime time, double price, int bricks_completed,
                        double forming_open, double forming_close)
   {
      if(!m_enable_diagnostics || m_diag_handle == INVALID_HANDLE)
         return;
      
      FileWrite(m_diag_handle, event, TimeToString(time, TIME_DATE|TIME_SECONDS),
                DoubleToString(price, m_digits), IntegerToString(bricks_completed),
                DoubleToString(forming_open, m_digits), 
                DoubleToString(forming_close, m_digits));
   }
};

//+------------------------------------------------------------------+
