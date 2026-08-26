//+------------------------------------------------------------------+
//|                                              TradeOverlay.mqh    |
//|                        Copyright 2024, Nortrading Renko Project  |
//|                                      https://github.com/vigilm   |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024, Nortrading Renko Project"
#property link      "https://github.com/vigilmvarghese/Nortrading-Renko"
#property version   "1.00"
#property strict

//+------------------------------------------------------------------+
//| Trade Overlay                                                    |
//| Display positions, SL/TP, and source Bid/Ask on Renko chart     |
//+------------------------------------------------------------------+
class CTradeOverlay
{
private:
   string            m_source_symbol;          // Source symbol
   long              m_chart_id;               // Renko chart ID
   string            m_prefix;                 // Object name prefix
   bool              m_verbose;                // Verbose logging
   
   //--- Display settings
   bool              m_show_bid_ask;
   bool              m_show_positions;
   bool              m_show_monetary;
   
   //--- Last update time
   datetime          m_last_update;
   int               m_update_interval;        // Update interval (seconds)
   
public:
   //--- Constructor
   CTradeOverlay(string source_symbol, long chart_id, string prefix = "OVOTrade_", bool verbose = false)
      : m_source_symbol(source_symbol), m_chart_id(chart_id), m_prefix(prefix),
        m_verbose(verbose), m_show_bid_ask(true), m_show_positions(true),
        m_show_monetary(true), m_last_update(0), m_update_interval(1)
   {
   }
   
   //--- Destructor
   ~CTradeOverlay()
   {
      ClearAll();
   }
   
   //--- Configure display
   void Configure(bool show_bid_ask, bool show_positions, bool show_monetary)
   {
      m_show_bid_ask = show_bid_ask;
      m_show_positions = show_positions;
      m_show_monetary = show_monetary;
   }
   
   //--- Update overlay
   void Update()
   {
      datetime now = TimeCurrent();
      if(now - m_last_update < m_update_interval)
         return;
      
      m_last_update = now;
      
      // Clear old objects
      ClearAll();
      
      // Draw Bid/Ask lines
      if(m_show_bid_ask)
         DrawBidAskLines();
      
      // Draw positions
      if(m_show_positions)
         DrawPositions();
   }
   
   //--- Draw Bid/Ask lines
   void DrawBidAskLines()
   {
      double bid = SymbolInfoDouble(m_source_symbol, SYMBOL_BID);
      double ask = SymbolInfoDouble(m_source_symbol, SYMBOL_ASK);
      
      if(bid <= 0 || ask <= 0)
         return;
      
      // Bid line
      string bid_name = m_prefix + "Bid";
      ObjectCreate(m_chart_id, bid_name, OBJ_HLINE, 0, 0, bid);
      ObjectSetInteger(m_chart_id, bid_name, OBJPROP_COLOR, clrRed);
      ObjectSetInteger(m_chart_id, bid_name, OBJPROP_STYLE, STYLE_DOT);
      ObjectSetInteger(m_chart_id, bid_name, OBJPROP_WIDTH, 1);
      ObjectSetInteger(m_chart_id, bid_name, OBJPROP_BACK, true);
      ObjectSetInteger(m_chart_id, bid_name, OBJPROP_SELECTABLE, false);
      ObjectSetString(m_chart_id, bid_name, OBJPROP_TEXT, "Bid");
      
      // Ask line
      string ask_name = m_prefix + "Ask";
      ObjectCreate(m_chart_id, ask_name, OBJ_HLINE, 0, 0, ask);
      ObjectSetInteger(m_chart_id, ask_name, OBJPROP_COLOR, clrBlue);
      ObjectSetInteger(m_chart_id, ask_name, OBJPROP_STYLE, STYLE_DOT);
      ObjectSetInteger(m_chart_id, ask_name, OBJPROP_WIDTH, 1);
      ObjectSetInteger(m_chart_id, ask_name, OBJPROP_BACK, true);
      ObjectSetInteger(m_chart_id, ask_name, OBJPROP_SELECTABLE, false);
      ObjectSetString(m_chart_id, ask_name, OBJPROP_TEXT, "Ask");
   }
   
   //--- Draw positions
   void DrawPositions()
   {
      int total = PositionsTotal();
      
      for(int i = 0; i < total; i++)
      {
         ulong ticket = PositionGetTicket(i);
         if(ticket == 0)
            continue;
         
         string pos_symbol = PositionGetString(POSITION_SYMBOL);
         if(pos_symbol != m_source_symbol)
            continue;
         
         // Get position info
         ENUM_POSITION_TYPE type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
         double volume = PositionGetDouble(POSITION_VOLUME);
         double price_open = PositionGetDouble(POSITION_PRICE_OPEN);
         double sl = PositionGetDouble(POSITION_SL);
         double tp = PositionGetDouble(POSITION_TP);
         double profit = PositionGetDouble(POSITION_PROFIT);
         
         // Draw entry line
         DrawEntryLine(ticket, type, price_open, volume);
         
         // Draw SL/TP
         if(sl > 0)
            DrawSLLine(ticket, type, sl, price_open);
         
         if(tp > 0)
            DrawTPLine(ticket, type, tp, price_open);
      }
   }
   
   //--- Draw entry line
   void DrawEntryLine(ulong ticket, ENUM_POSITION_TYPE type, double price, double volume)
   {
      string name = m_prefix + "Entry_" + IntegerToString(ticket);
      color line_color = (type == POSITION_TYPE_BUY) ? clrDodgerBlue : clrOrangeRed;
      
      ObjectCreate(m_chart_id, name, OBJ_HLINE, 0, 0, price);
      ObjectSetInteger(m_chart_id, name, OBJPROP_COLOR, line_color);
      ObjectSetInteger(m_chart_id, name, OBJPROP_STYLE, STYLE_SOLID);
      ObjectSetInteger(m_chart_id, name, OBJPROP_WIDTH, 2);
      ObjectSetInteger(m_chart_id, name, OBJPROP_BACK, false);
      ObjectSetInteger(m_chart_id, name, OBJPROP_SELECTABLE, false);
      
      // Label
      string label_name = m_prefix + "EntryLabel_" + IntegerToString(ticket);
      string label_text = (type == POSITION_TYPE_BUY ? "BUY " : "SELL ") + 
                          DoubleToString(volume, 2);
      
      ObjectCreate(m_chart_id, label_name, OBJ_TEXT, 0, TimeCurrent(), price);
      ObjectSetString(m_chart_id, label_name, OBJPROP_TEXT, label_text);
      ObjectSetInteger(m_chart_id, label_name, OBJPROP_COLOR, line_color);
      ObjectSetString(m_chart_id, label_name, OBJPROP_FONT, "Arial");
      ObjectSetInteger(m_chart_id, label_name, OBJPROP_FONTSIZE, 8);
      ObjectSetInteger(m_chart_id, label_name, OBJPROP_ANCHOR, ANCHOR_LEFT);
      ObjectSetInteger(m_chart_id, label_name, OBJPROP_SELECTABLE, false);
   }
   
   //--- Draw SL line
   void DrawSLLine(ulong ticket, ENUM_POSITION_TYPE type, double sl_price, double entry_price)
   {
      string name = m_prefix + "SL_" + IntegerToString(ticket);
      
      ObjectCreate(m_chart_id, name, OBJ_HLINE, 0, 0, sl_price);
      ObjectSetInteger(m_chart_id, name, OBJPROP_COLOR, clrRed);
      ObjectSetInteger(m_chart_id, name, OBJPROP_STYLE, STYLE_DASH);
      ObjectSetInteger(m_chart_id, name, OBJPROP_WIDTH, 1);
      ObjectSetInteger(m_chart_id, name, OBJPROP_BACK, false);
      ObjectSetInteger(m_chart_id, name, OBJPROP_SELECTABLE, true);
      
      // Calculate monetary value if enabled
      if(m_show_monetary)
      {
         string label_name = m_prefix + "SLLabel_" + IntegerToString(ticket);
         string label_text = "SL";
         
         // Calculate profit at SL
         double volume = PositionGetDouble(POSITION_VOLUME);
         double profit = 0;
         
         if(OrderCalcProfit(ORDER_TYPE_BUY, m_source_symbol, volume, entry_price, sl_price, profit))
         {
            if(type == POSITION_TYPE_SELL)
               profit = -profit;
            
            string currency = AccountInfoString(ACCOUNT_CURRENCY);
            label_text = "SL: " + (profit < 0 ? "- " : "+ ") + currency + 
                        DoubleToString(MathAbs(profit), 2);
         }
         
         ObjectCreate(m_chart_id, label_name, OBJ_TEXT, 0, TimeCurrent(), sl_price);
         ObjectSetString(m_chart_id, label_name, OBJPROP_TEXT, label_text);
         ObjectSetInteger(m_chart_id, label_name, OBJPROP_COLOR, clrRed);
         ObjectSetString(m_chart_id, label_name, OBJPROP_FONT, "Arial");
         ObjectSetInteger(m_chart_id, label_name, OBJPROP_FONTSIZE, 7);
         ObjectSetInteger(m_chart_id, label_name, OBJPROP_ANCHOR, ANCHOR_LEFT);
         ObjectSetInteger(m_chart_id, label_name, OBJPROP_SELECTABLE, false);
      }
   }
   
   //--- Draw TP line
   void DrawTPLine(ulong ticket, ENUM_POSITION_TYPE type, double tp_price, double entry_price)
   {
      string name = m_prefix + "TP_" + IntegerToString(ticket);
      
      ObjectCreate(m_chart_id, name, OBJ_HLINE, 0, 0, tp_price);
      ObjectSetInteger(m_chart_id, name, OBJPROP_COLOR, clrGreen);
      ObjectSetInteger(m_chart_id, name, OBJPROP_STYLE, STYLE_DASH);
      ObjectSetInteger(m_chart_id, name, OBJPROP_WIDTH, 1);
      ObjectSetInteger(m_chart_id, name, OBJPROP_BACK, false);
      ObjectSetInteger(m_chart_id, name, OBJPROP_SELECTABLE, true);
      
      // Calculate monetary value if enabled
      if(m_show_monetary)
      {
         string label_name = m_prefix + "TPLabel_" + IntegerToString(ticket);
         string label_text = "TP";
         
         // Calculate profit at TP
         double volume = PositionGetDouble(POSITION_VOLUME);
         double profit = 0;
         
         if(OrderCalcProfit(ORDER_TYPE_BUY, m_source_symbol, volume, entry_price, tp_price, profit))
         {
            if(type == POSITION_TYPE_SELL)
               profit = -profit;
            
            string currency = AccountInfoString(ACCOUNT_CURRENCY);
            label_text = "TP: " + (profit < 0 ? "- " : "+ ") + currency + 
                        DoubleToString(MathAbs(profit), 2);
         }
         
         ObjectCreate(m_chart_id, label_name, OBJ_TEXT, 0, TimeCurrent(), tp_price);
         ObjectSetString(m_chart_id, label_name, OBJPROP_TEXT, label_text);
         ObjectSetInteger(m_chart_id, label_name, OBJPROP_COLOR, clrGreen);
         ObjectSetString(m_chart_id, label_name, OBJPROP_FONT, "Arial");
         ObjectSetInteger(m_chart_id, label_name, OBJPROP_FONTSIZE, 7);
         ObjectSetInteger(m_chart_id, label_name, OBJPROP_ANCHOR, ANCHOR_LEFT);
         ObjectSetInteger(m_chart_id, label_name, OBJPROP_SELECTABLE, false);
      }
   }
   
   //--- Clear all objects
   void ClearAll()
   {
      int total = ObjectsTotal(m_chart_id, 0, OBJ_HLINE);
      for(int i = total - 1; i >= 0; i--)
      {
         string name = ObjectName(m_chart_id, i, 0, OBJ_HLINE);
         if(StringFind(name, m_prefix) == 0)
            ObjectDelete(m_chart_id, name);
      }
      
      total = ObjectsTotal(m_chart_id, 0, OBJ_TEXT);
      for(int i = total - 1; i >= 0; i--)
      {
         string name = ObjectName(m_chart_id, i, 0, OBJ_TEXT);
         if(StringFind(name, m_prefix) == 0)
            ObjectDelete(m_chart_id, name);
      }
   }
   
   //--- Set update interval
   void SetUpdateInterval(int seconds)
   {
      m_update_interval = seconds;
   }
};

//+------------------------------------------------------------------+
