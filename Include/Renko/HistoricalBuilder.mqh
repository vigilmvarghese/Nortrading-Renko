//+------------------------------------------------------------------+
//|                                          HistoricalBuilder.mqh   |
//|                        Copyright 2024, Nortrading Renko Project  |
//|                                      https://github.com/vigilm   |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024, Nortrading Renko Project"
#property link      "https://github.com/vigilmvarghese/Nortrading-Renko"
#property version   "3.00"
#property strict

#include "RenkoTypes.mqh"
#include "RegularRenkoEngine.mqh"
#include "MeanRenkoEngine.mqh"

//+------------------------------------------------------------------+
//| Historical Builder - Synchronous (OVO pattern)                  |
//| Reference: OVO BuildHistoricalModel() - instant completion      |
//+------------------------------------------------------------------+
class CHistoricalBuilder
{
private:
   string            m_symbol;                 // Symbol
   bool              m_verbose;                // Verbose logging
   
   //--- Tick cache
   MqlTick           m_tick_cache[];           // Cached ticks
   int               m_cache_size;             // Cache size
   bool              m_cache_enabled;          // Cache enabled flag
   datetime          m_cache_start_time;       // Cache start time
   datetime          m_cache_end_time;         // Cache end time
   
   //--- Results
   RenkoBrick        m_result_bricks[];        // Result bricks
   int               m_result_count;           // Result count
   
public:
   //--- Constructor
   CHistoricalBuilder(string symbol = "", bool verbose = false)
      : m_symbol(symbol), m_verbose(verbose), m_cache_size(0), 
        m_cache_enabled(true), m_result_count(0)
   {
      if(m_symbol == "")
         m_symbol = _Symbol;
      
      ArrayResize(m_tick_cache, 0, 100000);
      ArrayResize(m_result_bricks, 0, 10000);
   }
   
   //--- Destructor
   ~CHistoricalBuilder() {}
   
   //+------------------------------------------------------------------+
   //| Load ticks into cache (OVO EnsureTickCache pattern)            |
   //+------------------------------------------------------------------+
   bool LoadTickCache(int history_days, int chunk_minutes = 180)
   {
      if(!m_cache_enabled)
         return false;
      
      datetime now = TimeCurrent();
      datetime from = now - (history_days * 86400);
      
      // Check if cache is already loaded and covers the range
      if(m_cache_size > 0 && m_cache_start_time <= from && m_cache_end_time >= now)
      {
         if(m_verbose)
            Print("Tick cache already loaded and valid");
         return true;
      }
      
      if(m_verbose)
         Print("Loading tick cache for ", history_days, " days...");
      
      uint start_ms = GetTickCount();
      
      ArrayResize(m_tick_cache, 0);
      m_cache_size = 0;
      
      ulong from_msc = (ulong)from * 1000;
      ulong to_msc = (ulong)now * 1000;
      ulong chunk_ms = (ulong)MathMax(chunk_minutes, 1) * 60 * 1000;
      
      // Load ticks in chunks to avoid single-call limits
      for(ulong cursor = from_msc; cursor <= to_msc; )
      {
         ulong chunk_end = cursor + chunk_ms - 1;
         if(chunk_end > to_msc)
            chunk_end = to_msc;
         
         MqlTick ticks[];
         ResetLastError();
         int copied = CopyTicksRange(m_symbol, ticks, COPY_TICKS_ALL, cursor, chunk_end);
         
         if(copied > 0)
         {
            int old_size = m_cache_size;
            ArrayResize(m_tick_cache, old_size + copied, 65536);
            
            for(int i = 0; i < copied; i++)
               m_tick_cache[old_size + i] = ticks[i];
            
            m_cache_size += copied;
         }
         
         if(chunk_end == to_msc)
            break;
         
         cursor = chunk_end + 1;
      }
      
      m_cache_start_time = from;
      m_cache_end_time = now;
      
      uint elapsed_ms = GetTickCount() - start_ms;
      
      if(m_verbose)
         PrintFormat("Loaded %d ticks into cache in %d ms", m_cache_size, elapsed_ms);
      
      return (m_cache_size > 0);
   }
   
   //+------------------------------------------------------------------+
   //| SYNCHRONOUS Build - Instant completion (OVO pattern)           |
   //| Reference: OVO BuildHistoricalModel() - no async passes        |
   //+------------------------------------------------------------------+
   bool BuildHistory(ENUM_RENKO_TYPE type, double brick_size_points, 
                     bool suppress_wicks, int history_days,
                     bool relocate_open = true)
   {
      if(brick_size_points <= 0)
         return false;
      
      uint build_start_ms = GetTickCount();
      
      // Load tick cache if enabled
      if(m_cache_enabled)
      {
         if(!LoadTickCache(history_days))
         {
            Print("ERROR: Failed to load tick cache");
            return false;
         }
      }
      else
      {
         // Load ticks directly without caching (fallback)
         datetime now = TimeCurrent();
         datetime from = now - (history_days * 86400);
         
         int copied = CopyTicks(m_symbol, m_tick_cache, COPY_TICKS_ALL,
                                (ulong)(from * 1000), 0);
         
         if(copied <= 0)
         {
            Print("ERROR: Failed to load ticks. Error: ", GetLastError());
            return false;
         }
         
         m_cache_size = copied;
      }
      
      if(m_cache_size <= 0)
      {
         Print("ERROR: No ticks available for historical build");
         return false;
      }
      
      // Create engine instance
      CRegularRenkoEngine* regular_engine = NULL;
      CMeanRenkoEngine* mean_engine = NULL;
      
      if(type == RENKO_REGULAR)
      {
         regular_engine = new CRegularRenkoEngine(m_symbol, m_verbose);
         regular_engine.Configure(brick_size_points, suppress_wicks, relocate_open);
      }
      else if(type == RENKO_MEAN)
      {
         mean_engine = new CMeanRenkoEngine(m_symbol, m_verbose);
         mean_engine.Configure(brick_size_points, suppress_wicks);
      }
      else
      {
         Print("ERROR: Unsupported Renko type");
         return false;
      }
      
      if(m_verbose)
         PrintFormat("Processing %d ticks synchronously...", m_cache_size);
      
      // ✅ SYNCHRONOUS BUILD: Process ALL ticks in one go
      int total_bricks = 0;
      
      for(int i = 0; i < m_cache_size; i++)
      {
         MqlTick tick = m_tick_cache[i];
         double price = tick.bid > 0 ? tick.bid : tick.last;
         
         if(price <= 0)
            continue;
         
         ENUM_DIRTY_STATE dirty = DIRTY_NONE;
         
         if(type == RENKO_REGULAR && regular_engine != NULL)
            dirty = regular_engine.ProcessTick(price, tick.time);
         else if(type == RENKO_MEAN && mean_engine != NULL)
            dirty = mean_engine.ProcessTick(price, tick.time);
         
         // Collect completed bricks
         if(dirty == DIRTY_BRICK_COMPLETED || dirty == DIRTY_MULTI_BRICK_COMPLETED)
         {
            RenkoBrick completed[];
            int count = 0;
            
            if(type == RENKO_REGULAR && regular_engine != NULL)
               count = regular_engine.GetCompletedBricks(completed);
            else if(type == RENKO_MEAN && mean_engine != NULL)
               count = mean_engine.GetCompletedBricks(completed);
            
            // Add to results
            if(count > 0)
            {
               int old_size = m_result_count;
               ArrayResize(m_result_bricks, old_size + count);
               
               for(int j = 0; j < count; j++)
                  m_result_bricks[old_size + j] = completed[j];
               
               m_result_count += count;
               total_bricks += count;
            }
         }
      }
      
      // Add forming brick to results
      RenkoBrick forming;
      if(type == RENKO_REGULAR && regular_engine != NULL)
         forming = regular_engine.GetFormingBrick();
      else if(type == RENKO_MEAN && mean_engine != NULL)
         forming = mean_engine.GetFormingBrick();
      
      if(forming.time > 0)
      {
         ArrayResize(m_result_bricks, m_result_count + 1);
         m_result_bricks[m_result_count] = forming;
         m_result_count++;
      }
      
      // Cleanup engines
      if(regular_engine != NULL)
         delete regular_engine;
      if(mean_engine != NULL)
         delete mean_engine;
      
      uint elapsed_ms = GetTickCount() - build_start_ms;
      
      if(m_verbose)
         PrintFormat("Build completed: %d bricks from %d ticks in %d ms",
                     m_result_count, m_cache_size, elapsed_ms);
      
      return true;
   }
   
   //--- Get build results
   int GetResults(RenkoBrick &bricks[])
   {
      ArrayResize(bricks, m_result_count);
      for(int i = 0; i < m_result_count; i++)
         bricks[i] = m_result_bricks[i];
      
      return m_result_count;
   }
   
   //--- Get result count
   int GetResultCount() const { return m_result_count; }
   
   //--- Enable/disable cache
   void EnableCache(bool enable) { m_cache_enabled = enable; }
   
   //--- Clear cache
   void ClearCache()
   {
      ArrayResize(m_tick_cache, 0);
      m_cache_size = 0;
      m_cache_start_time = 0;
      m_cache_end_time = 0;
   }
   
   //--- Clear results
   void ClearResults()
   {
      ArrayResize(m_result_bricks, 0);
      m_result_count = 0;
   }
   
   //--- Get cache info
   int GetCacheSize() const { return m_cache_size; }
   datetime GetCacheStartTime() const { return m_cache_start_time; }
   datetime GetCacheEndTime() const { return m_cache_end_time; }
};

//+------------------------------------------------------------------+
