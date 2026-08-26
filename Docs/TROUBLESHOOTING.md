# Troubleshooting Guide - OVO Renko Generator

## Error 5304: Symbol Path Not Found

### Symptoms
```
ERROR: Failed to create custom symbol US30.M61 Error: 5304
ERROR: Failed to create custom symbol
```

### Causes
1. MT5 terminal doesn't have proper permissions
2. Custom symbols folder is read-only
3. MT5 needs to be run as administrator
4. First-time custom symbol creation requires special setup

### Solutions

#### Solution 1: Run MT5 as Administrator
1. Close MT5 completely
2. Right-click MT5 icon → "Run as administrator"
3. Reattach indicator and try again

#### Solution 2: Check Folder Permissions
1. Navigate to: `C:\Users\[YourUser]\AppData\Roaming\MetaQuotes\Terminal\[Instance]\bases\Custom`
2. Right-click "Custom" folder → Properties → Security
3. Ensure your user has "Full Control"
4. If not, click Edit → Add your user → Grant Full Control

#### Solution 3: Create Custom Folder Manually
1. Open File Manager
2. Navigate to: `C:\Users\[YourUser]\AppData\Roaming\MetaQuotes\Terminal\[Instance]\bases`
3. Create folder named: `Custom`
4. Inside Custom, create folder: `Renko`
5. Restart MT5

#### Solution 4: Use Different Symbol Name
Try a simpler symbol name without special characters:
```
Change: US30.M61
To: US30_M61 (underscore instead of dot)
```

Modify in indicator input: `Custom Period ID: M61` → `M61_`

#### Solution 5: Enable AutoTrading
1. MT5: Tools → Options → Expert Advisors
2. Check: "Allow automated trading"
3. Check: "Allow DLL imports"
4. Check: "Allow WebRequest for listed URL"
5. Click OK and restart MT5

#### Solution 6: Check Terminal Directory
```
Open MT5 → File → Open Data Folder
This should open: Terminal\[UniqueID]\

If this folder doesn't exist or has permission issues:
1. Reinstall MT5
2. Choose installation directory you have full access to
```

### Verification Steps

After applying solutions, verify:

```mql5
// Add this to test custom symbol creation:
void OnStart()
{
   string test_symbol = "TEST_SYMBOL";
   
   // Try to create
   bool result = CustomSymbolCreate(test_symbol, "Custom", "EURUSD");
   
   if(result)
      Print("SUCCESS: Can create custom symbols");
   else
      Print("FAILED: Error ", GetLastError());
   
   // Clean up
   CustomSymbolDelete(test_symbol);
}
```

## Alternative Approach: Use Existing Path

If Error 5304 persists, try using an existing symbol group path:

### Check Available Paths
1. MT5: View → Symbols (Ctrl+U)
2. Look at folder structure (Forex, Futures, etc.)
3. Use one of those paths

### Modify Code
```cpp
// In CustomSymbolPublisher.mqh
// Try these paths based on your broker:

string paths[] = {
   "Forex",           // If your broker uses Forex folder
   "CFD",             // If trading CFDs
   "Futures",         // If trading futures
   "Cryptocurrencies" // If trading crypto
};
```

## Workaround: Manual Custom Symbol Creation

If automatic creation fails, create manually:

1. MT5: Tools → Options → Symbols
2. Click "+" to add custom symbol
3. Name: `US30.M61`
4. Path: Custom
5. Origin symbol: US30
6. Click Create
7. Now the indicator can use it

## Debug Information to Collect

If issue persists, collect this info:

```
1. MT5 Build Number: Help → About
2. Operating System: Windows version
3. Terminal Directory: File → Open Data Folder (copy path)
4. Broker Name: 
5. Full error log from Experts tab
6. Screenshot of folder permissions
```

## Common Error Codes

| Error | Meaning | Solution |
|-------|---------|----------|
| 5304 | Symbol path not found | Check folder permissions, run as admin |
| 4014 | Function not allowed | Enable AutoTrading in options |
| 4756 | Custom symbol name invalid | Use alphanumeric names only |
| 4023 | Not enough memory | Close other programs, restart MT5 |

## Advanced Debugging

Enable verbose logging:
```
Indicator Inputs:
Verbose Log: true
```

Check Experts tab for detailed messages about:
- Which paths were tried
- Exact error codes for each attempt
- Folder existence checks

## Still Not Working?

If none of the above works:

### Option A: Use Simple Custom Symbol Manager Script

Create a script `CreateCustomSymbols.mq5`:
```mql5
#property script_show_inputs
input string InpSourceSymbol = "US30";
input string InpPeriodToken = "M61";

void OnStart()
{
   string custom_name = InpSourceSymbol + "." + InpPeriodToken;
   
   if(CustomSymbolCreate(custom_name, "Custom", InpSourceSymbol))
   {
      Print("SUCCESS: Created ", custom_name);
      
      // Set properties
      CustomSymbolSetInteger(custom_name, SYMBOL_DIGITS, 
         (int)SymbolInfoInteger(InpSourceSymbol, SYMBOL_DIGITS));
      
      Print("Custom symbol ready for use");
   }
   else
   {
      Print("FAILED: Error ", GetLastError());
   }
}
```

Run this script FIRST, then use the indicator.

### Option B: Contact Support

If custom symbols absolutely won't create:
1. Check with your broker if custom symbols are supported
2. Some brokers disable custom symbols
3. May need broker-specific settings

### Option C: Use Different MT5 Installation

- Download fresh MT5 from MetaQuotes (not broker version)
- Install to directory with full permissions
- Connect your broker account
- Try creating custom symbols

## Prevention

To avoid this error in future:

1. ✅ Always run MT5 with proper permissions
2. ✅ Keep MT5 updated to latest build
3. ✅ Periodically check Custom folder permissions
4. ✅ Don't install MT5 to Program Files (use user folder)
5. ✅ Disable antivirus for MT5 folder temporarily during setup

## Success Indicators

You know it's working when:
```
Experts tab shows:
"SUCCESS: Created custom symbol US30.M61 in path: Custom"
"Historical build started"
"Build completed: XXX bricks"

Market Watch shows:
Custom → US30.M61 (visible in symbol list)

Chart opens:
US30.M61 chart appears automatically
```
