//+------------------------------------------------------------------+
//|                                      CustomSymbolPublisher.mqh   |
//|                        Copyright 2024, Nortrading Renko Project  |
//|                                      https://github.com/vigilm   |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024, Nortrading Renko Project"
#property link      "https://github.com/vigilmvarghese/Nortrading-Renko"
#property version   "1.00"
#property strict

#include "RenkoTypes.mqh"

//+------------------------------------------------------------------+
//| Custom Symbol Publisher                                          |
//| Handles CustomRatesUpdate/Replace with optimization              |
//+------------------------------------------------------------------+
class CCustomSymbolPublisher
{
private:
   string            m_source_symbol;          // Source symbol
   string            m_custom_symbol;          // Custom symbol name
   bool              m_symbol_created;         // Symbol creation flag
   bool              m_verbose;                // Verbose logging
   
   MqlRates          m_history_buffer[];       // Historical rates buffer
   int               m_history_count;          // Count of historical rates
   
   datetime          m_last_published_time;    // Last published bar time
   
public:
   //--- Constructor
   CCustomSymbolPublisher(bool verbose = false)
      : m_source_symbol(""), m_custom_symbol(""), m_symbol_created(false),
        m_verbose(verbose), m_history_count(0), m_last_published_time(0)
   {
      ArrayResize(m_history_buffer, 0, 10000);
   }
   
   //--- Destructor
   ~CCustomSymbolPublisher() {}
   
   //--- Create custom symbol
   bool CreateCustomSymbol(string source_symbol, string period_token)
   {
      m_source_symbol = source_symbol;
      m_custom_symbol = source_symbol + "." + period_token;
      
      // Check if symbol already exists
      bool symbol_exists = false;
      if(SymbolSelect(m_custom_symbol, false))
      {
         symbol_exists = true;
      }
      
      if(symbol_exists)
      {
         if(m_verbose)
            Print("Custom symbol already exists: ", m_custom_symbol);
         
         m_symbol_created = true;
         return true;
      }
      
      // Try multiple path variations for custom symbol creation
      string paths[] = {
         "Custom",                    // Root custom folder
         "Custom\\Renko",             // Custom\Renko subfolder
         "Forex",                     // Use existing Forex path
         "Currencies"                 // Use existing Currencies path
      };
      
      bool created = false;
      string used_path = "";
      
      for(int i = 0; i < ArraySize(paths); i++)
      {
         ResetLastError();
         if(CustomSymbolCreate(m_custom_symbol, paths[i], m_source_symbol))
         {
            created = true;
            used_path = paths[i];
            Print("SUCCESS: Created custom symbol ", m_custom_symbol, " in path: ", used_path);
            break;
         }
         else
         {
            int error = GetLastError();
            if(m_verbose)
               Print("Attempt ", i+1, " failed with path '", paths[i], "' Error: ", error);
         }
      }
      
      if(!created)
      {
         int error = GetLastError();
         Print("ERROR: Failed to create custom symbol ", m_custom_symbol, " after trying all paths. Last error: ", error);
         Print("Please check: Tools → Options → Expert Advisors → Allow DLL imports");
         Print("And ensure terminal has write permissions to Custom symbols folder");
         return false;
      }
      
      // Set custom symbol properties
      CustomSymbolSetInteger(m_custom_symbol, SYMBOL_DIGITS, 
                             (int)SymbolInfoInteger(m_source_symbol, SYMBOL_DIGITS));
      CustomSymbolSetInteger(m_custom_symbol, SYMBOL_SPREAD, 
                             (int)SymbolInfoInteger(m_source_symbol, SYMBOL_SPREAD));
      CustomSymbolSetDouble(m_custom_symbol, SYMBOL_POINT, 
                            SymbolInfoDouble(m_source_symbol, SYMBOL_POINT));
      CustomSymbolSetDouble(m_custom_symbol, SYMBOL_TRADE_TICK_SIZE, 
                            SymbolInfoDouble(m_source_symbol, SYMBOL_TRADE_TICK_SIZE));
      CustomSymbolSetDouble(m_custom_symbol, SYMBOL_TRADE_TICK_VALUE, 
                            SymbolInfoDouble(m_source_symbol, SYMBOL_TRADE_TICK_VALUE));
      CustomSymbolSetDouble(m_custom_symbol, SYMBOL_TRADE_CONTRACT_SIZE, 
                            SymbolInfoDouble(m_source_symbol, SYMBOL_TRADE_CONTRACT_SIZE));
      
      m_symbol_created = true;
      
      return true;
   }
   
   //--- Replace entire history
   bool ReplaceHistory(const RenkoBrick &bricks[], int count)
   {
      if(!m_symbol_created || count <= 0)
         return false;
      
      // Convert bricks to MqlRates
      ArrayResize(m_history_buffer, count);
      for(int i = 0; i < count; i++)
      {
         bricks[i].ToMqlRates(m_history_buffer[i]);
      }
      
      m_history_count = count;
      
      // Clear existing history
      datetime from = m_history_buffer[0].time;
      datetime to = m_history_buffer[count - 1].time + PeriodSeconds(PERIOD_D1);
      
      if(!CustomRatesDelete(m_custom_symbol, from, to))
      {
         if(m_verbose)
            Print("Warning: CustomRatesDelete returned false");
      }
      
      // Replace history
      int replace_result = CustomRatesReplace(m_custom_symbol, from, to, m_history_buffer);
      if(replace_result <= 0)
      {
         Print("ERROR: CustomRatesReplace failed. Error: ", GetLastError());
         return false;
      }
      
      if(count > 0)
         m_last_published_time = m_history_buffer[count - 1].time;
      
      if(m_verbose)
         Print("Replaced history: ", count, " bars from ", 
               TimeToString(from), " to ", TimeToString(to));
      
      return true;
   }
   
   //--- Update with completed bricks and forming brick
   bool UpdateRates(const RenkoBrick &completed_bricks[], int completed_count,
                    const RenkoBrick &forming_brick, ENUM_DIRTY_STATE dirty_state)
   {
      if(!m_symbol_created)
         return false;
      
      if(dirty_state == DIRTY_NONE)
         return true;
      
      // Build update buffer
      MqlRates update_rates[];
      int update_count = completed_count + 1;  // completed + forming
      ArrayResize(update_rates, update_count);
      
      // Add completed bricks
      for(int i = 0; i < completed_count; i++)
      {
         completed_bricks[i].ToMqlRates(update_rates[i]);
      }
      
      // Add forming brick
      forming_brick.ToMqlRates(update_rates[completed_count]);
      
      // Update custom symbol
      int update_result = CustomRatesUpdate(m_custom_symbol, update_rates);
      if(update_result <= 0)
      {
         int error = GetLastError();
         if(m_verbose)
            Print("CustomRatesUpdate failed. Error: ", error);
         
         // Fallback: try replace
         if(update_count > 0)
         {
            datetime from = update_rates[0].time;
            datetime to = update_rates[update_count - 1].time + 60;
            int replace_result = CustomRatesReplace(m_custom_symbol, from, to, update_rates);
            return (replace_result > 0);
         }
         
         return false;
      }
      
      // Update last published time
      if(update_count > 0)
         m_last_published_time = update_rates[update_count - 1].time;
      
      if(m_verbose && completed_count > 0)
         Print("Updated rates: ", completed_count, " completed + 1 forming");
      
      return true;
   }
   
   //--- Update only forming brick (no new completed bricks)
   bool UpdateFormingOnly(const RenkoBrick &forming_brick)
   {
      if(!m_symbol_created)
         return false;
      
      MqlRates rate;
      forming_brick.ToMqlRates(rate);
      
      MqlRates update_rates[1];
      update_rates[0] = rate;
      
      int update_result = CustomRatesUpdate(m_custom_symbol, update_rates);
      if(update_result <= 0)
      {
         if(m_verbose)
            Print("UpdateFormingOnly failed. Error: ", GetLastError());
         return false;
      }
      
      return true;
   }
   
   //--- Delete custom symbol
   bool DeleteCustomSymbol()
   {
      if(!m_symbol_created)
         return true;
      
      if(!CustomSymbolDelete(m_custom_symbol))
      {
         int error = GetLastError();
         if(error != 0)
         {
            Print("WARNING: Failed to delete custom symbol ", m_custom_symbol, 
                  " Error: ", error);
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
   
   //--- Get history count
   int GetHistoryCount() const
   {
      return m_history_count;
   }
   
   //--- Reset
   void Reset()
   {
      m_source_symbol = "";
      m_custom_symbol = "";
      m_symbol_created = false;
      m_history_count = 0;
      m_last_published_time = 0;
      ArrayResize(m_history_buffer, 0);
   }
};

//+------------------------------------------------------------------+
