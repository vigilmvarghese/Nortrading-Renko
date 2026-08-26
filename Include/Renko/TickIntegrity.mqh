//+------------------------------------------------------------------+
//|                                                TickIntegrity.mqh |
//|                        Copyright 2024, Nortrading Renko Project  |
//|                                      https://github.com/vigilm   |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024, Nortrading Renko Project"
#property link      "https://github.com/vigilmvarghese/Nortrading-Renko"
#property version   "1.00"
#property strict

#include "RenkoTypes.mqh"

//+------------------------------------------------------------------+
//| Tick Integrity Layer                                             |
//| Handles same-millisecond ticks, duplicate protection             |
//+------------------------------------------------------------------+
class CTickIntegrityLayer
{
private:
   string            m_symbol;                 // Symbol
   TickSignature     m_last_processed;         // Last processed tick signature
   MqlTick           m_latest_tick;            // Latest tick from SymbolInfoTick
   int               m_ticks_processed;        // Total ticks processed
   bool              m_verbose;                // Verbose logging
   
public:
   //--- Constructor
   CTickIntegrityLayer(string symbol = "", bool verbose = false)
      : m_symbol(symbol), m_ticks_processed(0), m_verbose(verbose)
   {
      if(m_symbol == "")
         m_symbol = _Symbol;
      
      m_last_processed.Reset();
      ZeroMemory(m_latest_tick);
   }
   
   //--- Destructor
   ~CTickIntegrityLayer() {}
   
   //--- Initialize
   bool Initialize(string symbol)
   {
      m_symbol = symbol;
      m_last_processed.Reset();
      m_ticks_processed = 0;
      
      // Get initial tick
      if(!SymbolInfoTick(m_symbol, m_latest_tick))
      {
         Print("ERROR: Failed to get initial tick for ", m_symbol);
         return false;
      }
      
      m_last_processed.Set(m_latest_tick);
      
      if(m_verbose)
         Print("TickIntegrity initialized for ", m_symbol);
      
      return true;
   }
   
   //--- Check if new tick exists (fast path)
   bool HasNewTick()
   {
      // Get latest tick
      if(!SymbolInfoTick(m_symbol, m_latest_tick))
         return false;
      
      // Compare with last processed
      TickSignature current;
      current.Set(m_latest_tick);
      
      return (current != m_last_processed);
   }
   
   //--- Get new ticks since last processed
   int GetNewTicks(MqlTick &ticks[])
   {
      ArrayResize(ticks, 0);
      
      // Check if there's a new tick at all
      if(!HasNewTick())
         return 0;
      
      // Get tick range from last processed time to now
      long from_msc = m_last_processed.time_msc;
      long to_msc = m_latest_tick.time_msc;
      
      // Include the previous millisecond to catch same-ms ticks
      if(from_msc > 0)
         from_msc = from_msc - 1;
      
      // Copy tick range
      MqlTick temp_ticks[];
      int copied = CopyTicksRange(m_symbol, temp_ticks, COPY_TICKS_ALL, from_msc, to_msc);
      
      if(copied <= 0)
      {
         // Fallback: use latest tick directly
         if(m_verbose)
            Print("CopyTicksRange returned 0, using fallback");
         
         ArrayResize(ticks, 1);
         ticks[0] = m_latest_tick;
         return 1;
      }
      
      // Find where we left off and collect new ticks
      bool found_last = false;
      int new_count = 0;
      
      for(int i = 0; i < copied; i++)
      {
         TickSignature sig;
         sig.Set(temp_ticks[i]);
         
         // Skip until we find the last processed tick
         if(!found_last)
         {
            if(sig == m_last_processed)
            {
               found_last = true;
               continue;
            }
         }
         else
         {
            // Add new tick
            ArrayResize(ticks, new_count + 1);
            ticks[new_count] = temp_ticks[i];
            new_count++;
         }
      }
      
      // If we never found the last processed tick, it means all ticks are new
      if(!found_last && copied > 0)
      {
         if(m_verbose)
            Print("Last processed tick not found in range, processing all ", copied, " ticks");
         
         ArrayResize(ticks, copied);
         ArrayCopy(ticks, temp_ticks);
         new_count = copied;
      }
      
      if(m_verbose && new_count > 0)
      {
         Print("Retrieved ", new_count, " new ticks");
         if(new_count > 1)
            Print("  First: ", TimeToString(ticks[0].time, TIME_DATE|TIME_SECONDS), 
                  ".", ticks[0].time_msc % 1000, " Bid=", ticks[0].bid);
      }
      
      return new_count;
   }
   
   //--- Mark tick as processed
   void MarkProcessed(const MqlTick &tick)
   {
      m_last_processed.Set(tick);
      m_ticks_processed++;
   }
   
   //--- Get statistics
   int GetTotalProcessed() const
   {
      return m_ticks_processed;
   }
   
   //--- Get last processed signature
   TickSignature GetLastProcessed() const
   {
      return m_last_processed;
   }
   
   //--- Reset
   void Reset()
   {
      m_last_processed.Reset();
      m_ticks_processed = 0;
      ZeroMemory(m_latest_tick);
   }
   
   //--- Get latest tick info
   MqlTick GetLatestTick() const
   {
      return m_latest_tick;
   }
   
   //--- Check for same-millisecond ticks in array
   int CountSameMillisecondTicks(const MqlTick &ticks[])
   {
      int count = 0;
      int size = ArraySize(ticks);
      
      for(int i = 1; i < size; i++)
      {
         if(ticks[i].time_msc == ticks[i-1].time_msc)
            count++;
      }
      
      return count;
   }
   
   //--- Set verbose mode
   void SetVerbose(bool verbose)
   {
      m_verbose = verbose;
   }
};

//+------------------------------------------------------------------+
