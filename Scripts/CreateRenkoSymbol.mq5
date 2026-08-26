//+------------------------------------------------------------------+
//|                                          CreateRenkoSymbol.mq5   |
//|                        Copyright 2024, Nortrading Renko Project  |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024, Nortrading Renko Project"
#property link      "https://github.com/vigilmvarghese/Nortrading-Renko"
#property version   "1.00"
#property description "Manual custom symbol creator for OVO Renko Generator"
#property description "Run this script BEFORE using the indicator"
#property script_show_inputs

//--- Inputs
input string InpSourceSymbol = "US30";        // Source Symbol (e.g., US30, EURUSD)
input string InpPeriodToken = "M61";          // Period Token (e.g., M61, M62, M2)

//+------------------------------------------------------------------+
//| Script program start function                                    |
//+------------------------------------------------------------------+
void OnStart()
{
   Print("===========================================");
   Print("OVO Renko - Manual Custom Symbol Creator");
   Print("===========================================");
   
   // Construct custom symbol name
   string custom_symbol = InpSourceSymbol + "." + InpPeriodToken;
   
   Print("Source Symbol: ", InpSourceSymbol);
   Print("Custom Symbol: ", custom_symbol);
   Print("");
   
   // Check if source symbol exists
   if(!SymbolSelect(InpSourceSymbol, true))
   {
      Print("ERROR: Source symbol '", InpSourceSymbol, "' not found!");
      Print("Please check symbol name and try again.");
      return;
   }
   
   Print("✓ Source symbol exists");
   
   // Check if custom symbol already exists
   if(SymbolSelect(custom_symbol, false))
   {
      Print("⚠ Custom symbol already exists: ", custom_symbol);
      
      // Ask to recreate
      int answer = MessageBox(
         "Custom symbol " + custom_symbol + " already exists.\n\n" +
         "Do you want to delete and recreate it?",
         "Symbol Exists",
         MB_YESNO | MB_ICONQUESTION
      );
      
      if(answer == IDYES)
      {
         Print("Deleting existing symbol...");
         if(!CustomSymbolDelete(custom_symbol))
         {
            Print("ERROR: Failed to delete existing symbol. Error: ", GetLastError());
            return;
         }
         Print("✓ Existing symbol deleted");
      }
      else
      {
         Print("Operation cancelled by user.");
         return;
      }
   }
   
   // Try to create custom symbol using proven OVO approach
   Print("");
   Print("Attempting to create custom symbol...");
   Print("");
   
   string custom_folder = "Renko";
   bool created = false;
   
   ResetLastError();
   Print("Creating with folder: '", custom_folder, "'...");
   
   if(CustomSymbolCreate(custom_symbol, custom_folder, InpSourceSymbol))
   {
      created = true;
      Print("✓✓✓ SUCCESS! Created in folder: ", custom_folder);
   }
   else
   {
      int error = GetLastError();
      
      if(error == 5304)
      {
         // Symbol already exists - this is OK
         created = true;
         Print("✓ Symbol already exists (will reuse): ", custom_symbol);
      }
      else
      {
         Print("✗ Failed with error: ", error, " (", GetErrorDescription(error), ")");
      }
   }
   
   if(!created)
   {
      Print("");
      Print("========================================");
      Print("ERROR: Could not create custom symbol!");
      Print("========================================");
      Print("");
      Print("SOLUTION 1: Run MT5 as Administrator");
      Print("  1. Close MT5 completely");
      Print("  2. Right-click MT5 icon");
      Print("  3. Select 'Run as administrator'");
      Print("  4. Run this script again");
      Print("");
      Print("SOLUTION 2: Create 'Custom' folder manually");
      Print("  1. MT5: File → Open Data Folder");
      Print("  2. Navigate to: bases folder");
      Print("  3. Create folder named: Custom");
      Print("  4. Restart MT5");
      Print("  5. Run this script again");
      Print("");
      Print("SOLUTION 3: Check folder permissions");
      Print("  1. Find MT5 data folder (File → Open Data Folder)");
      Print("  2. Right-click 'bases' folder → Properties");
      Print("  3. Security tab → Ensure your user has Full Control");
      Print("  4. Apply and restart MT5");
      
      return;
   }
   
   // Set custom symbol properties
   Print("");
   Print("Setting symbol properties...");
   
   CustomSymbolSetInteger(custom_symbol, SYMBOL_DIGITS, 
      (int)SymbolInfoInteger(InpSourceSymbol, SYMBOL_DIGITS));
   CustomSymbolSetInteger(custom_symbol, SYMBOL_SPREAD, 
      (int)SymbolInfoInteger(InpSourceSymbol, SYMBOL_SPREAD));
   CustomSymbolSetDouble(custom_symbol, SYMBOL_POINT, 
      SymbolInfoDouble(InpSourceSymbol, SYMBOL_POINT));
   CustomSymbolSetDouble(custom_symbol, SYMBOL_TRADE_TICK_SIZE, 
      SymbolInfoDouble(InpSourceSymbol, SYMBOL_TRADE_TICK_SIZE));
   CustomSymbolSetDouble(custom_symbol, SYMBOL_TRADE_TICK_VALUE, 
      SymbolInfoDouble(InpSourceSymbol, SYMBOL_TRADE_TICK_VALUE));
   CustomSymbolSetDouble(custom_symbol, SYMBOL_TRADE_CONTRACT_SIZE, 
      SymbolInfoDouble(InpSourceSymbol, SYMBOL_TRADE_CONTRACT_SIZE));
   
   Print("✓ Properties set");
   
   // Select symbol in Market Watch
   SymbolSelect(custom_symbol, true);
   
   Print("");
   Print("========================================");
   Print("SUCCESS! Custom symbol ready!");
   Print("========================================");
   Print("");
   Print("Symbol Name: ", custom_symbol);
   Print("Created in: ", custom_folder);
   Print("Digits: ", SymbolInfoInteger(custom_symbol, SYMBOL_DIGITS));
   Print("Point: ", SymbolInfoDouble(custom_symbol, SYMBOL_POINT));
   Print("");
   Print("NEXT STEPS:");
   Print("1. Check Market Watch → Symbols → ", custom_folder);
   Print("2. You should see: ", custom_symbol);
   Print("3. Now attach OVO_Renko_Generator indicator");
   Print("4. Use Period Token: ", InpPeriodToken);
   Print("");
   Print("✓ Ready to use!");
   
   // Show success message
   MessageBox(
      "Custom symbol ready!\n\n" +
      "Symbol: " + custom_symbol + "\n" +
      "Folder: " + custom_folder + "\n\n" +
      "You can now use the OVO Renko Generator indicator.",
      "Success!",
      MB_OK | MB_ICONINFORMATION
   );
}

//+------------------------------------------------------------------+
//| Get error description                                            |
//+------------------------------------------------------------------+
string GetErrorDescription(int error)
{
   switch(error)
   {
      case 5304: return "Symbol path not found";
      case 4014: return "Function not allowed";
      case 4756: return "Custom symbol name invalid";
      case 4023: return "Not enough memory";
      default:   return "Unknown error";
   }
}
//+------------------------------------------------------------------+
