//+------------------------------------------------------------------+
//|                                      CustomSymbolPublisher.mqh   |
//|                        Copyright 2024, Nortrading Renko Project  |
//|                                      https://github.com/vigilm   |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024, Nortrading Renko Project"
#property link      "https://github.com/vigilmvarghese/Nortrading-Renko"
#property version   "3.00"
#property strict

#include "RenkoTypes.mqh"

//+------------------------------------------------------------------+
//| Custom Symbol Publisher - Exact OVO Implementation              |
//| Reference: OVO CreateOrPrepareCustomSymbol, PublishRebuiltHistory|
//+------------------------------------------------------------------+
class CCustomSymbolPublisher
{
private:
   string            m_source_symbol;          // Source symbol
   string            m_custom_symbol;          // Custom symbol name
   string            m_custom_folder;          // Custom symbol folder
   bool              m_symbol_created;         // Symbol creation flag
   bool              m_verbose;                // Verbose logging
   
   double            m_point;                  // Point value
   int               m_digits;                 // Digits
   int               m_spread;                 // Spread
   
public:
   //--- Constructor
   CCustomSymbolPublisher(bool verbose = false)
      : m_source_symbol(""), m_custom_symbol(""), m_custom_folder("Renko"),
        m_symbol_created(false), m_verbose(verbose), m_point(0), m_digits(0), m_spread(0)
   {
   }
   
   //--- Destructor
   ~CCustomSymbolPublisher() {}
   
   //+------------------------------------------------------------------+
   //| EXACT OVO CreateOrPrepareCustomSymbol() - Lines 1743-1773      |
   //+------------------------------------------------------------------+
   bool CreateCustomSymbol(string source_symbol, string period_token, string folder = "Renko")
   {
      m_source_symbol = source_symbol;
      m_custom_folder = folder;
      m_custom_symbol = source_symbol + "." + period_token;
      
      // Get source symbol properties
      m_point = SymbolInfoDouble(m_source_symbol, SYMBOL_POINT);
      m_digits = (int)SymbolInfoInteger(m_source_symbol, SYMBOL_DIGITS);
      m_spread = (int)SymbolInfoInteger(m_source_symbol, SYMBOL_SPREAD);
      
      // Attempt to create custom symbol
      ResetLastError();
      if(!CustomSymbolCreate(m_custom_symbol, m_custom_folder, m_source_symbol))
      {
         int err = GetLastError();
         
         // Error 5304 means symbol already exists - this is OK, we'll reuse it
         // This is the EXACT OVO pattern
         if(err != 5304)
         {
            if(m_verbose)
               PrintFormat("ERROR: CustomSymbolCreate(%s) failed. Error=%d", m_custom_symbol, err);
            return false;
         }
         else if(m_verbose)
         {
            Print("Custom symbol already exists (reusing): ", m_custom_symbol);
         }
      }
      else if(m_verbose)
      {
         PrintFormat("SUCCESS: Created custom symbol %s in folder: %s", m_custom_symbol, m_custom_folder);
      }
      
      m_symbol_created = true;
      
      // Always ensure symbol is in Market Watch
      SymbolSelect(m_custom_symbol, true);
      
      // Set custom symbol properties to match source
      CustomSymbolSetInteger(m_custom_symbol, SYMBOL_DIGITS, m_digits);
      CustomSymbolSetInteger(m_custom_symbol, SYMBOL_SPREAD, m_spread);
      CustomSymbolSetDouble(m_custom_symbol, SYMBOL_POINT, m_point);
      
      double tick_size = SymbolInfoDouble(m_source_symbol, SYMBOL_TRADE_TICK_SIZE);
      if(tick_size > 0.0)
         CustomSymbolSetDouble(m_custom_symbol, SYMBOL_TRADE_TICK_SIZE, tick_size);
      
      double tick_value = SymbolInfoDouble(m_source_symbol, SYMBOL_TRADE_TICK_VALUE);
      if(tick_value > 0.0)
         CustomSymbolSetDouble(m_custom_symbol, SYMBOL_TRADE_TICK_VALUE, tick_value);
      
      double contract_size = SymbolInfoDouble(m_source_symbol, SYMBOL_TRADE_CONTRACT_SIZE);
      if(contract_size > 0.0)
         CustomSymbolSetDouble(m_custom_symbol, SYMBOL_TRADE_CONTRACT_SIZE, contract_size);
      
      if(m_verbose)
         PrintFormat("Custom symbol configured: %s (digits=%d, point=%.*f, spread=%d)",
                     m_custom_symbol, m_digits, m_digits, m_point, m_spread);
      
      return true;
   }
   
   //+------------------------------------------------------------------+
   //| FIXED: Clear and Replace History - Proper cleanup               |
   //| OVO Pattern + Explicit Delete for clean regeneration           |
   //+------------------------------------------------------------------+
   bool ReplaceHistory(const RenkoBrick &bricks[], int count)
   {
      if(!m_symbol_created || count <= 0)
         return false;
      
      if(m_verbose)
         PrintFormat("🔄 Replacing history: %d bricks", count);
      
      // ✅ CRITICAL FIX: Delete ALL existing bars first
      datetime delete_from = D'1970.01.01 00:00';
      datetime delete_to = D'2099.12.31 23:59';
      
      if(m_verbose)
         Print("   Step 1: Deleting ALL existing bars...");
      
      ResetLastError();
      int delete_result = CustomRatesDelete(m_custom_symbol, delete_from, delete_to);
      int delete_error = GetLastError();
      
      if(m_verbose)
      {
         if(delete_result > 0)
            PrintFormat("   ✅ Deleted %d old bars", delete_result);
         else if(delete_error == 0 || delete_error == 4400)
            Print("   ✅ No old bars to delete (clean slate)");
         else
            PrintFormat("   ⚠️ Delete returned %d, error %d", delete_result, delete_error);
      }
      
      // ⚡ CRITICAL: Give MT5 time to process deletion
      Sleep(250);
      
      // Convert bricks to MqlRates
      if(m_verbose)
         Print("   Step 2: Converting bricks to rates...");
      
      MqlRates rates[];
      ArrayResize(rates, count);
      
      for(int i = 0; i < count; i++)
      {
         rates[i].time = bricks[i].time;
         rates[i].open = bricks[i].open;
         rates[i].high = bricks[i].high;
         rates[i].low = bricks[i].low;
         rates[i].close = bricks[i].close;
         rates[i].tick_volume = bricks[i].tick_volume;
         rates[i].spread = bricks[i].spread;
         rates[i].real_volume = bricks[i].real_volume;
      }
      
      // Get time range from actual data with buffer
      datetime first_time = rates[0].time;
      datetime last_time = rates[count - 1].time + 86400;
      
      if(m_verbose)
      {
         Print("   Step 3: Writing new bars to custom symbol...");
         PrintFormat("   Time range: %s to %s", TimeToString(first_time), TimeToString(last_time));
      }
      
      // ✅ Write new bars into clean slate
      ResetLastError();
      int written = CustomRatesReplace(m_custom_symbol,
                                       first_time,
                                       last_time,
                                       rates);
      
      int replace_error = GetLastError();
      
      if(written < 0)
      {
         PrintFormat("❌ ERROR: CustomRatesReplace failed. Written=%d, Error=%d", written, replace_error);
         return false;
      }
      
      if(m_verbose)
         PrintFormat("   ✅ Wrote %d new bars", written);
      
      // ⚡ Force symbol refresh in MT5
      SymbolSelect(m_custom_symbol, true);
      Sleep(100);
      
      if(m_verbose)
         Print("✅ Clean regeneration complete - old bars cleared, new bars published");
      
      return true;
   }
   
   //+------------------------------------------------------------------+
   //| Update with completed bricks and forming brick (live updates)  |
   //| Reference: OVO PublishTail() - Lines 1913-1948                 |
   //+------------------------------------------------------------------+
   bool UpdateRates(const RenkoBrick &completed_bricks[], int completed_count,
                    const RenkoBrick &forming_brick)
   {
      if(!m_symbol_created)
         return false;
      
      // Build update buffer: completed + forming
      int total = completed_count + 1;
      MqlRates rates[];
      ArrayResize(rates, total);
      
      // Add completed bricks
      for(int i = 0; i < completed_count; i++)
      {
         rates[i].time = completed_bricks[i].time;
         rates[i].open = completed_bricks[i].open;
         rates[i].high = completed_bricks[i].high;
         rates[i].low = completed_bricks[i].low;
         rates[i].close = completed_bricks[i].close;
         rates[i].tick_volume = completed_bricks[i].tick_volume;
         rates[i].spread = completed_bricks[i].spread;
         rates[i].real_volume = completed_bricks[i].real_volume;
      }
      
      // Add forming brick
      rates[completed_count].time = forming_brick.time;
      rates[completed_count].open = forming_brick.open;
      rates[completed_count].high = forming_brick.high;
      rates[completed_count].low = forming_brick.low;
      rates[completed_count].close = forming_brick.close;
      rates[completed_count].tick_volume = forming_brick.tick_volume;
      rates[completed_count].spread = forming_brick.spread;
      rates[completed_count].real_volume = forming_brick.real_volume;
      
      // Update custom symbol
      ResetLastError();
      int written = CustomRatesUpdate(m_custom_symbol, rates, WHOLE_ARRAY);
      
      if(written < 0)
      {
         if(m_verbose)
            PrintFormat("CustomRatesUpdate failed. Error=%d", GetLastError());
         return false;
      }
      
      if(m_verbose && completed_count > 0)
         PrintFormat("Updated rates: %d completed + 1 forming", completed_count);
      
      return true;
   }
   
   //+------------------------------------------------------------------+
   //| Update only forming brick (no new completed bricks)            |
   //| Reference: OVO PublishAll() pattern                             |
   //+------------------------------------------------------------------+
   bool UpdateFormingOnly(const RenkoBrick &forming_brick)
   {
      if(!m_symbol_created)
         return false;
      
      MqlRates rate;
      rate.time = forming_brick.time;
      rate.open = forming_brick.open;
      rate.high = forming_brick.high;
      rate.low = forming_brick.low;
      rate.close = forming_brick.close;
      rate.tick_volume = forming_brick.tick_volume;
      rate.spread = forming_brick.spread;
      rate.real_volume = forming_brick.real_volume;
      
      MqlRates rates[1];
      rates[0] = rate;
      
      ResetLastError();
      int written = CustomRatesUpdate(m_custom_symbol, rates, WHOLE_ARRAY);
      
      if(written < 0)
      {
         if(m_verbose)
            PrintFormat("UpdateFormingOnly failed. Error=%d", GetLastError());
         return false;
      }
      
      return true;
   }
   
   //--- Delete custom symbol
   bool DeleteCustomSymbol()
   {
      if(!m_symbol_created)
         return true;
      
      ResetLastError();
      if(!CustomSymbolDelete(m_custom_symbol))
      {
         int error = GetLastError();
         if(error != 0)
         {
            if(m_verbose)
               PrintFormat("WARNING: Failed to delete custom symbol %s. Error=%d",
                           m_custom_symbol, error);
            return false;
         }
      }
      
      m_symbol_created = false;
      
      if(m_verbose)
         Print("Deleted custom symbol: ", m_custom_symbol);
      
      return true;
   }
   
   //--- Get custom symbol name
   string GetCustomSymbolName() const
   {
      return m_custom_symbol;
   }
   
   //--- Check if created
   bool IsCreated() const
   {
      return m_symbol_created;
   }
   
   //--- Reset
   void Reset()
   {
      m_source_symbol = "";
      m_custom_symbol = "";
      m_symbol_created = false;
   }
};

//+------------------------------------------------------------------+
