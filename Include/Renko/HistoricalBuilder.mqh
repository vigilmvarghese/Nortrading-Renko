//+------------------------------------------------------------------+
//|                                          HistoricalBuilder.mqh   |
//|                        Copyright 2024, Nortrading Renko Project  |
//|                                      https://github.com/vigilm   |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024, Nortrading Renko Project"
#property link      "https://github.com/vigilmvarghese/Nortrading-Renko"
#property version   "1.00"
#property strict

#include "RenkoTypes.mqh"
#include "RegularRenkoEngine.mqh"
#include "MeanRenkoEngine.mqh"

//+------------------------------------------------------------------+
//| Historical Builder                                               |
//| Asynchronous tick reconstruction with progress and cache         |
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
   
   //--- Build state
   bool              m_is_building;            // Building flag
   int               m_build_index;            // Current build index
   int               m_total_ticks;            // Total ticks to process
   int               m_budget_ms;              // Budget per pass (milliseconds)
   
   BuildProgress     m_progress;               // Progress tracking
   
   //--- Results
   RenkoBrick        m_result_bricks[];        // Result bricks
   int               m_result_count;           // Result count
   
   //--- Persistent engines for incremental build
   CRegularRenkoEngine* m_regular_engine;      // Regular Renko engine
   CMeanRenkoEngine*    m_mean_engine;         // Mean Renko engine
   
public:
   //--- Constructor
   CHistoricalBuilder(string symbol = "", bool verbose = false)
      : m_symbol(symbol), m_verbose(verbose), m_cache_size(0), 
        m_cache_enabled(true), m_is_building(false), m_build_index(0),
        m_total_ticks(0), m_budget_ms(8), m_result_count(0),
        m_regular_engine(NULL), m_mean_engine(NULL)
   {
      if(m_symbol == "")
         m_symbol = _Symbol;
      
      ArrayResize(m_tick_cache, 0, 100000);
      ArrayResize(m_result_bricks, 0, 10000);
   }
   
   //--- Destructor
   ~CHistoricalBuilder()
   {
      if(m_regular_engine != NULL)
      {
         delete m_regular_engine;
         m_regular_engine = NULL;
      }
      if(m_mean_engine != NULL)
      {
         delete m_mean_engine;
         m_mean_engine = NULL;
      }
   }
   
   //--- Load ticks into cache
   bool LoadTickCache(int history_days)
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
      
      // Copy ticks for the entire period
      int copied = CopyTicks(m_symbol, m_tick_cache, COPY_TICKS_ALL, 
                             (ulong)(from * 1000), 0);
      
      if(copied <= 0)
      {
         Print("ERROR: Failed to load tick cache. Error: ", GetLastError());
         return false;
      }
      
      m_cache_size = copied;
      m_cache_start_time = from;
      m_cache_end_time = now;
      
      uint elapsed_ms = GetTickCount() - start_ms;
      
      if(m_verbose)
         Print("Loaded ", m_cache_size, " ticks into cache in ", elapsed_ms, " ms");
      
      return true;
   }
   
   //--- Append new ticks to cache
   bool AppendToCache()
   {
      if(!m_cache_enabled || m_cache_size == 0)
         return false;
      
      datetime now = TimeCurrent();
      
      if(m_cache_end_time >= now)
         return true;  // Already up to date
      
      // Get ticks since last cache update
      MqlTick new_ticks[];
      int copied = CopyTicks(m_symbol, new_ticks, COPY_TICKS_ALL,
                             (ulong)(m_cache_end_time * 1000), 0);
      
      if(copied <= 0)
         return true;  // No new ticks
      
      // Append to cache
      int old_size = m_cache_size;
      ArrayResize(m_tick_cache, old_size + copied);
      ArrayCopy(m_tick_cache, new_ticks, old_size);
      
      m_cache_size = old_size + copied;
      m_cache_end_time = now;
      
      if(m_verbose)
         Print("Appended ", copied, " new ticks to cache. Total: ", m_cache_size);
      
      return true;
   }
   
   //--- Start asynchronous build
   bool StartBuild(ENUM_RENKO_TYPE type, double brick_size_points, 
                   bool suppress_wicks, int history_days)
   {
      if(m_is_building)
         return false;
      
      // Clean up old engines
      if(m_regular_engine != NULL)
      {
         delete m_regular_engine;
         m_regular_engine = NULL;
      }
      if(m_mean_engine != NULL)
      {
         delete m_mean_engine;
         m_mean_engine = NULL;
      }
      
      // Create persistent engine for this build
      if(type == RENKO_REGULAR)
      {
         m_regular_engine = new CRegularRenkoEngine(m_symbol, m_verbose);
         m_regular_engine.Configure(brick_size_points, suppress_wicks);
      }
      else if(type == RENKO_MEAN)
      {
         m_mean_engine = new CMeanRenkoEngine(m_symbol, m_verbose);
         m_mean_engine.Configure(brick_size_points, suppress_wicks);
      }
      
      // Load tick cache if enabled
      if(m_cache_enabled)
      {
         if(!LoadTickCache(history_days))
            return false;
      }
      else
      {
         // Load ticks directly without caching
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
      
      // Initialize build state
      m_is_building = true;
      m_build_index = 0;
      m_total_ticks = m_cache_size;
      m_result_count = 0;
      
      ArrayResize(m_result_bricks, 0);
      m_progress.Start(m_total_ticks);
      
      if(m_verbose)
         Print("Started asynchronous build with ", m_total_ticks, " ticks");
      
      return true;
   }
   
   //--- Process one build pass (SYNCHRONOUS - all ticks at once)
   bool ProcessBuildPass(ENUM_RENKO_TYPE type, double brick_size_points,
                         bool suppress_wicks)
   {
      if(!m_is_building)
         return false;
      
      uint start_time = GetTickCount();
      
      if(m_verbose)
         Print("Processing ", m_total_ticks, " ticks synchronously...");
      
      // ✅ SYNCHRONOUS BUILD: Process ALL ticks in one pass
      // No time budget - complete immediately
      while(m_build_index < m_total_ticks)
      {
         MqlTick tick = m_tick_cache[m_build_index];
         double price = tick.bid > 0 ? tick.bid : tick.last;
         
         if(price > 0)
         {
            ENUM_DIRTY_STATE dirty = DIRTY_NONE;
            
            if(type == RENKO_REGULAR && m_regular_engine != NULL)
               dirty = m_regular_engine.ProcessTick(price, tick.time);
            else if(type == RENKO_MEAN && m_mean_engine != NULL)
               dirty = m_mean_engine.ProcessTick(price, tick.time);
            
            // Collect completed bricks
            if(dirty == DIRTY_BRICK_COMPLETED || dirty == DIRTY_MULTI_BRICK_COMPLETED)
            {
               RenkoBrick completed[];
               int count = 0;
               
               if(type == RENKO_REGULAR && m_regular_engine != NULL)
                  count = m_regular_engine.GetCompletedBricks(completed);
               else if(type == RENKO_MEAN && m_mean_engine != NULL)
                  count = m_mean_engine.GetCompletedBricks(completed);
               
               // Add to results
               if(count > 0)
               {
                  int old_size = m_result_count;
                  ArrayResize(m_result_bricks, old_size + count);
                  
                  for(int i = 0; i < count; i++)
                     m_result_bricks[old_size + i] = completed[i];
                  
                  m_result_count += count;
                  m_progress.total_bricks = m_result_count;
               }
            }
         }
         
         m_build_index++;
         m_progress.processed_ticks = m_build_index;
      }
      
      // Build finished - mark complete
      uint elapsed_ms = GetTickCount() - start_time;
      m_is_building = false;
      m_progress.Complete();
      
      if(m_verbose)
         Print("Build completed: ", m_result_count, " bricks from ", 
               m_total_ticks, " ticks in ", elapsed_ms, " ms");
      
      return false;  // Build finished (single pass)
   }
   
   //--- Get build results
   int GetResults(RenkoBrick &bricks[])
   {
      if(m_is_building)
         return 0;
      
      ArrayResize(bricks, m_result_count);
      for(int i = 0; i < m_result_count; i++)
         bricks[i] = m_result_bricks[i];
      
      return m_result_count;
   }
   
   //--- Get progress
   BuildProgress GetProgress() const
   {
      return m_progress;
   }
   
   //--- Check if building
   bool IsBuilding() const
   {
      return m_is_building;
   }
   
   //--- Cancel build
   void CancelBuild()
   {
      m_is_building = false;
      m_build_index = 0;
      m_progress.Reset();
   }
   
   //--- Set budget
   void SetBudgetMs(int budget_ms)
   {
      m_budget_ms = budget_ms;
   }
   
   //--- Enable/disable cache
   void EnableCache(bool enable)
   {
      m_cache_enabled = enable;
   }
   
   //--- Clear cache
   void ClearCache()
   {
      ArrayResize(m_tick_cache, 0);
      m_cache_size = 0;
      m_cache_start_time = 0;
      m_cache_end_time = 0;
   }
   
   //--- Get cache info
   int GetCacheSize() const { return m_cache_size; }
   datetime GetCacheStartTime() const { return m_cache_start_time; }
   datetime GetCacheEndTime() const { return m_cache_end_time; }
};

//+------------------------------------------------------------------+
