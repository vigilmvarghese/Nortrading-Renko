//+------------------------------------------------------------------+
//|                                              ChartManager.mqh    |
//|                        Copyright 2024, Nortrading Renko Project  |
//|                                      https://github.com/vigilm   |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024, Nortrading Renko Project"
#property link      "https://github.com/vigilmvarghese/Nortrading-Renko"
#property version   "1.00"
#property strict

//+------------------------------------------------------------------+
//| Chart Manager                                                    |
//| Handle chart creation, restoration, M1 enforcement               |
//+------------------------------------------------------------------+
class CChartManager
{
private:
   string            m_custom_symbol;          // Custom symbol name
   long              m_chart_id;               // Chart ID
   bool              m_chart_exists;           // Chart exists flag
   bool              m_verbose;                // Verbose logging
   
   string            m_template_name;          // Template name for backup
   datetime          m_last_template_save;     // Last template save time
   int               m_template_save_interval; // Template save interval (seconds)
   
public:
   //--- Constructor
   CChartManager(bool verbose = false)
      : m_custom_symbol(""), m_chart_id(0), m_chart_exists(false),
        m_verbose(verbose), m_template_name(""), m_last_template_save(0),
        m_template_save_interval(60)
   {
   }
   
   //--- Destructor
   ~CChartManager() {}
   
   //--- Find existing chart
   long FindChart(string custom_symbol)
   {
      m_custom_symbol = custom_symbol;
      
      // Search through all charts
      long chart_id = ChartFirst();
      
      while(chart_id >= 0)
      {
         string chart_symbol = ChartSymbol(chart_id);
         
         if(chart_symbol == custom_symbol)
         {
            m_chart_id = chart_id;
            m_chart_exists = true;
            
            if(m_verbose)
               Print("Found existing chart: ", custom_symbol, " ID: ", m_chart_id);
            
            return m_chart_id;
         }
         
         chart_id = ChartNext(chart_id);
      }
      
      m_chart_id = 0;
      m_chart_exists = false;
      return 0;
   }
   
   //--- Open or switch to chart
   long OpenChart(string custom_symbol, bool switch_to_chart = true)
   {
      m_custom_symbol = custom_symbol;
      
      // Check if chart already exists
      long existing = FindChart(custom_symbol);
      if(existing > 0)
      {
         if(switch_to_chart)
         {
            ChartSetInteger(existing, CHART_BRING_TO_TOP, true);
         }
         
         return existing;
      }
      
      // Create new chart
      m_chart_id = ChartOpen(custom_symbol, PERIOD_M1);
      
      if(m_chart_id == 0)
      {
         Print("ERROR: Failed to create chart for ", custom_symbol, 
               ". Error: ", GetLastError());
         return 0;
      }
      
      m_chart_exists = true;
      
      // Configure chart
      ConfigureChart();
      
      // Apply template if exists
      if(m_template_name != "")
         ApplyTemplate();
      
      if(m_verbose)
         Print("Created new chart: ", custom_symbol, " ID: ", m_chart_id);
      
      if(switch_to_chart)
      {
         ChartSetInteger(m_chart_id, CHART_BRING_TO_TOP, true);
      }
      
      return m_chart_id;
   }
   
   //--- Configure chart settings
   void ConfigureChart()
   {
      if(m_chart_id == 0)
         return;
      
      // Set to M1 permanently
      ChartSetSymbolPeriod(m_chart_id, m_custom_symbol, PERIOD_M1);
      
      // Chart appearance
      ChartSetInteger(m_chart_id, CHART_SHOW_GRID, true);
      ChartSetInteger(m_chart_id, CHART_SHOW_PERIOD_SEP, false);
      ChartSetInteger(m_chart_id, CHART_AUTOSCROLL, true);
      ChartSetInteger(m_chart_id, CHART_SHIFT, true);
      
      if(m_verbose)
         Print("Configured chart: ", m_custom_symbol);
   }
   
   //--- Enforce M1 timeframe
   void EnforceM1()
   {
      if(m_chart_id == 0 || !m_chart_exists)
         return;
      
      ENUM_TIMEFRAMES current_period = (ENUM_TIMEFRAMES)ChartPeriod(m_chart_id);
      
      if(current_period != PERIOD_M1)
      {
         ChartSetSymbolPeriod(m_chart_id, m_custom_symbol, PERIOD_M1);
         
         if(m_verbose)
            Print("Enforced M1 on chart ", m_chart_id);
      }
   }
   
   //--- Save chart template
   bool SaveTemplate(string template_name)
   {
      if(m_chart_id == 0 || !m_chart_exists)
         return false;
      
      m_template_name = template_name;
      
      if(!ChartSaveTemplate(m_chart_id, template_name))
      {
         if(m_verbose)
            Print("Failed to save template: ", template_name);
         return false;
      }
      
      m_last_template_save = TimeCurrent();
      
      if(m_verbose)
         Print("Saved chart template: ", template_name);
      
      return true;
   }
   
   //--- Apply template
   bool ApplyTemplate()
   {
      if(m_chart_id == 0 || !m_chart_exists || m_template_name == "")
         return false;
      
      if(!ChartApplyTemplate(m_chart_id, m_template_name))
      {
         if(m_verbose)
            Print("Failed to apply template: ", m_template_name);
         return false;
      }
      
      if(m_verbose)
         Print("Applied chart template: ", m_template_name);
      
      return true;
   }
   
   //--- Periodic template backup
   void PeriodicTemplateSave()
   {
      if(m_chart_id == 0 || !m_chart_exists || m_template_name == "")
         return;
      
      datetime now = TimeCurrent();
      
      if(now - m_last_template_save >= m_template_save_interval)
      {
         SaveTemplate(m_template_name);
      }
   }
   
   //--- Redraw chart
   void Redraw()
   {
      if(m_chart_id == 0 || !m_chart_exists)
         return;
      
      ChartRedraw(m_chart_id);
   }
   
   //--- Close chart
   void CloseChart()
   {
      if(m_chart_id == 0 || !m_chart_exists)
         return;
      
      if(!ChartClose(m_chart_id))
      {
         if(m_verbose)
            Print("Failed to close chart ", m_chart_id);
      }
      
      m_chart_id = 0;
      m_chart_exists = false;
   }
   
   //--- Get chart ID
   long GetChartId() const
   {
      return m_chart_id;
   }
   
   //--- Check if chart exists
   bool ChartExists() const
   {
      return m_chart_exists && ChartSymbol(m_chart_id) == m_custom_symbol;
   }
   
   //--- Set template save interval
   void SetTemplateSaveInterval(int seconds)
   {
      m_template_save_interval = seconds;
   }
   
   //--- Get custom symbol
   string GetCustomSymbol() const
   {
      return m_custom_symbol;
   }
};

//+------------------------------------------------------------------+
