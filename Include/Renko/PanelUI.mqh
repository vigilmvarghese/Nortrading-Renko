//+------------------------------------------------------------------+
//|                                                    PanelUI.mqh   |
//|                        Copyright 2024, Nortrading Renko Project  |
//|                                      https://github.com/vigilm   |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024, Nortrading Renko Project"
#property link      "https://github.com/vigilmvarghese/Nortrading-Renko"
#property version   "1.00"
#property strict

#include "RenkoTypes.mqh"

//+------------------------------------------------------------------+
//| Panel UI                                                         |
//| Compact 24px OVO-style control panel                            |
//+------------------------------------------------------------------+
class CPanelUI
{
private:
   long              m_chart_id;               // Chart ID
   int               m_subwindow;              // Subwindow number
   string            m_prefix;                 // Object name prefix
   
   int               m_panel_height;           // Panel height (24px)
   int               m_panel_width;            // Panel width (chart width)
   
   //--- Control positions
   int               m_brick_field_x;
   int               m_brick_field_y;
   int               m_period_button_x;
   int               m_period_button_y;
   int               m_status_x;
   int               m_status_y;
   int               m_close_button_x;
   int               m_close_button_y;
   
   //--- Current values
   string            m_brick_size_text;
   string            m_period_text;
   string            m_status_text;
   ENUM_RENKO_TYPE   m_chart_type;
   
   bool              m_visible;
   bool              m_verbose;
   
public:
   //--- Constructor
   CPanelUI(long chart_id, int subwindow, string prefix = "OVOPanel_", bool verbose = false)
      : m_chart_id(chart_id), m_subwindow(subwindow), m_prefix(prefix),
        m_panel_height(24), m_brick_size_text("600"), m_period_text("M61"),
        m_status_text("OVO C2"), m_chart_type(RENKO_MEAN), m_visible(false),
        m_verbose(verbose)
   {
      CalculatePositions();
   }
   
   //--- Destructor
   ~CPanelUI()
   {
      DeletePanel();
   }
   
   //--- Calculate control positions
   void CalculatePositions()
   {
      m_panel_width = (int)ChartGetInteger(m_chart_id, CHART_WIDTH_IN_PIXELS);
      
      // ✅ In indicator_separate_window, position at TOP of subwindow (y=0)
      // The subwindow is dedicated to this indicator, so we start from top
      
      // Left side: label and brick field
      m_brick_field_x = 80;
      m_brick_field_y = 2;
      
      // Period button next to brick field
      m_period_button_x = 150;
      m_period_button_y = 2;
      
      // Center: status
      m_status_x = m_panel_width / 2;
      m_status_y = 4;
      
      // Right side: close button
      m_close_button_x = m_panel_width - 30;
      m_close_button_y = 2;
   }
   
   //--- Create panel
   bool CreatePanel()
   {
      DeletePanel();
      
      CalculatePositions();
      
      // Background
      CreateBackground();
      
      // Chart type label
      CreateChartTypeLabel();
      
      // Brick size edit field
      CreateBrickField();
      
      // Period button
      CreatePeriodButton();
      
      // Status text
      CreateStatusLabel();
      
      // Close button
      CreateCloseButton();
      
      m_visible = true;
      
      if(m_verbose)
         Print("Panel created on chart ", m_chart_id, " subwindow ", m_subwindow);
      
      return true;
   }
   
   //--- Create background (BLACK as requested)
   void CreateBackground()
   {
      string name = m_prefix + "BG";
      
      if(m_verbose)
         Print("Creating background: chart=", m_chart_id, " subwindow=", m_subwindow, " name=", name);
      
      ObjectCreate(m_chart_id, name, OBJ_RECTANGLE_LABEL, m_subwindow, 0, 0);
      ObjectSetInteger(m_chart_id, name, OBJPROP_XDISTANCE, 0);
      ObjectSetInteger(m_chart_id, name, OBJPROP_YDISTANCE, 0);  // ✅ Top of subwindow
      ObjectSetInteger(m_chart_id, name, OBJPROP_XSIZE, m_panel_width);
      ObjectSetInteger(m_chart_id, name, OBJPROP_YSIZE, m_panel_height);
      ObjectSetInteger(m_chart_id, name, OBJPROP_BGCOLOR, clrBlack);  // ✅ BLACK background
      ObjectSetInteger(m_chart_id, name, OBJPROP_BORDER_TYPE, BORDER_FLAT);
      ObjectSetInteger(m_chart_id, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
      ObjectSetInteger(m_chart_id, name, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(m_chart_id, name, OBJPROP_BACK, true);
      
      if(m_verbose)
         Print("Background created: ", (ObjectFind(m_chart_id, name) >= 0 ? "SUCCESS" : "FAILED"));
   }
   
   //--- Create chart type label (WHITE text on black background)
   void CreateChartTypeLabel()
   {
      string name = m_prefix + "TypeLabel";
      string text = (m_chart_type == RENKO_REGULAR) ? "Renko:" : "Mean Renko:";
      
      ObjectCreate(m_chart_id, name, OBJ_LABEL, m_subwindow, 0, 0);
      ObjectSetInteger(m_chart_id, name, OBJPROP_XDISTANCE, 5);
      ObjectSetInteger(m_chart_id, name, OBJPROP_YDISTANCE, 4);  // ✅ Top of subwindow
      ObjectSetInteger(m_chart_id, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
      ObjectSetInteger(m_chart_id, name, OBJPROP_ANCHOR, ANCHOR_LEFT_UPPER);
      ObjectSetString(m_chart_id, name, OBJPROP_TEXT, text);
      ObjectSetString(m_chart_id, name, OBJPROP_FONT, "Arial");
      ObjectSetInteger(m_chart_id, name, OBJPROP_FONTSIZE, 9);
      ObjectSetInteger(m_chart_id, name, OBJPROP_COLOR, clrWhite);  // ✅ WHITE text
      ObjectSetInteger(m_chart_id, name, OBJPROP_SELECTABLE, false);
   }
   
   //--- Create brick size field (WHITE input field)
   void CreateBrickField()
   {
      string name = m_prefix + "BrickField";
      
      ObjectCreate(m_chart_id, name, OBJ_EDIT, m_subwindow, 0, 0);
      ObjectSetInteger(m_chart_id, name, OBJPROP_XDISTANCE, m_brick_field_x);
      ObjectSetInteger(m_chart_id, name, OBJPROP_YDISTANCE, m_brick_field_y);
      ObjectSetInteger(m_chart_id, name, OBJPROP_XSIZE, 60);
      ObjectSetInteger(m_chart_id, name, OBJPROP_YSIZE, 18);
      ObjectSetInteger(m_chart_id, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
      ObjectSetInteger(m_chart_id, name, OBJPROP_ANCHOR, ANCHOR_LEFT_UPPER);
      ObjectSetString(m_chart_id, name, OBJPROP_TEXT, m_brick_size_text);
      ObjectSetString(m_chart_id, name, OBJPROP_FONT, "Arial");
      ObjectSetInteger(m_chart_id, name, OBJPROP_FONTSIZE, 9);
      ObjectSetInteger(m_chart_id, name, OBJPROP_COLOR, clrBlack);     // Black text in field
      ObjectSetInteger(m_chart_id, name, OBJPROP_BGCOLOR, clrWhite);   // ✅ WHITE background (only input)
      ObjectSetInteger(m_chart_id, name, OBJPROP_BORDER_COLOR, clrGray);
      ObjectSetInteger(m_chart_id, name, OBJPROP_ALIGN, ALIGN_CENTER);
      ObjectSetInteger(m_chart_id, name, OBJPROP_READONLY, false);
      ObjectSetInteger(m_chart_id, name, OBJPROP_SELECTABLE, false);
   }
   
   //--- Create period button
   void CreatePeriodButton()
   {
      string name = m_prefix + "PeriodButton";
      
      ObjectCreate(m_chart_id, name, OBJ_BUTTON, m_subwindow, 0, 0);
      ObjectSetInteger(m_chart_id, name, OBJPROP_XDISTANCE, m_period_button_x);
      ObjectSetInteger(m_chart_id, name, OBJPROP_YDISTANCE, m_period_button_y);
      ObjectSetInteger(m_chart_id, name, OBJPROP_XSIZE, 50);
      ObjectSetInteger(m_chart_id, name, OBJPROP_YSIZE, 18);
      ObjectSetInteger(m_chart_id, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
      ObjectSetString(m_chart_id, name, OBJPROP_TEXT, m_period_text);
      ObjectSetString(m_chart_id, name, OBJPROP_FONT, "Arial Bold");
      ObjectSetInteger(m_chart_id, name, OBJPROP_FONTSIZE, 9);
      ObjectSetInteger(m_chart_id, name, OBJPROP_COLOR, clrWhite);
      ObjectSetInteger(m_chart_id, name, OBJPROP_BGCOLOR, clrDodgerBlue);
      ObjectSetInteger(m_chart_id, name, OBJPROP_BORDER_COLOR, clrBlue);
      ObjectSetInteger(m_chart_id, name, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(m_chart_id, name, OBJPROP_STATE, false);
   }
   
   //--- Create status label (WHITE text on black background)
   void CreateStatusLabel()
   {
      string name = m_prefix + "Status";
      
      ObjectCreate(m_chart_id, name, OBJ_LABEL, m_subwindow, 0, 0);
      ObjectSetInteger(m_chart_id, name, OBJPROP_XDISTANCE, m_status_x);
      ObjectSetInteger(m_chart_id, name, OBJPROP_YDISTANCE, m_status_y);
      ObjectSetInteger(m_chart_id, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
      ObjectSetInteger(m_chart_id, name, OBJPROP_ANCHOR, ANCHOR_CENTER);
      ObjectSetString(m_chart_id, name, OBJPROP_TEXT, m_status_text);
      ObjectSetString(m_chart_id, name, OBJPROP_FONT, "Arial");
      ObjectSetInteger(m_chart_id, name, OBJPROP_FONTSIZE, 9);
      ObjectSetInteger(m_chart_id, name, OBJPROP_COLOR, clrLimeGreen);  // ✅ Lime green status text
      ObjectSetInteger(m_chart_id, name, OBJPROP_SELECTABLE, false);
   }
   
   //--- Create close button
   void CreateCloseButton()
   {
      string name = m_prefix + "CloseButton";
      
      ObjectCreate(m_chart_id, name, OBJ_BUTTON, m_subwindow, 0, 0);
      ObjectSetInteger(m_chart_id, name, OBJPROP_XDISTANCE, m_close_button_x);
      ObjectSetInteger(m_chart_id, name, OBJPROP_YDISTANCE, m_close_button_y);
      ObjectSetInteger(m_chart_id, name, OBJPROP_XSIZE, 20);
      ObjectSetInteger(m_chart_id, name, OBJPROP_YSIZE, 18);
      ObjectSetInteger(m_chart_id, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
      ObjectSetString(m_chart_id, name, OBJPROP_TEXT, "X");
      ObjectSetString(m_chart_id, name, OBJPROP_FONT, "Arial Bold");
      ObjectSetInteger(m_chart_id, name, OBJPROP_FONTSIZE, 10);
      ObjectSetInteger(m_chart_id, name, OBJPROP_COLOR, clrWhite);
      ObjectSetInteger(m_chart_id, name, OBJPROP_BGCOLOR, clrCrimson);
      ObjectSetInteger(m_chart_id, name, OBJPROP_BORDER_COLOR, clrDarkRed);
      ObjectSetInteger(m_chart_id, name, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(m_chart_id, name, OBJPROP_STATE, false);
   }
   
   //--- Delete panel
   void DeletePanel()
   {
      ObjectDelete(m_chart_id, m_prefix + "BG");
      ObjectDelete(m_chart_id, m_prefix + "TypeLabel");
      ObjectDelete(m_chart_id, m_prefix + "BrickField");
      ObjectDelete(m_chart_id, m_prefix + "PeriodButton");
      ObjectDelete(m_chart_id, m_prefix + "Status");
      ObjectDelete(m_chart_id, m_prefix + "CloseButton");
      
      m_visible = false;
   }
   
   //--- Update panel position (handles chart resize)
   void UpdateWidth()
   {
      int new_width = (int)ChartGetInteger(m_chart_id, CHART_WIDTH_IN_PIXELS);
      
      if(new_width != m_panel_width)
      {
         m_panel_width = new_width;
         CalculatePositions();
         
         // Update background
         ObjectSetInteger(m_chart_id, m_prefix + "BG", OBJPROP_XSIZE, m_panel_width);
         
         // Update horizontal positions only (Y stays at top)
         ObjectSetInteger(m_chart_id, m_prefix + "Status", OBJPROP_XDISTANCE, m_status_x);
         ObjectSetInteger(m_chart_id, m_prefix + "CloseButton", OBJPROP_XDISTANCE, m_close_button_x);
      }
   }
   
   //--- Set brick size
   void SetBrickSize(string size_text)
   {
      m_brick_size_text = size_text;
      ObjectSetString(m_chart_id, m_prefix + "BrickField", OBJPROP_TEXT, size_text);
   }
   
   //--- Get brick size
   string GetBrickSize() const
   {
      return ObjectGetString(m_chart_id, m_prefix + "BrickField", OBJPROP_TEXT);
   }
   
   //--- Set period text
   void SetPeriodText(string period_text)
   {
      m_period_text = period_text;
      ObjectSetString(m_chart_id, m_prefix + "PeriodButton", OBJPROP_TEXT, period_text);
   }
   
   //--- Get period text
   string GetPeriodText() const
   {
      return m_period_text;
   }
   
   //--- Set status text
   void SetStatusText(string status)
   {
      m_status_text = status;
      ObjectSetString(m_chart_id, m_prefix + "Status", OBJPROP_TEXT, status);
   }
   
   //--- Set chart type
   void SetChartType(ENUM_RENKO_TYPE type)
   {
      m_chart_type = type;
      string text = (type == RENKO_REGULAR) ? "Renko:" : "Mean Renko:";
      ObjectSetString(m_chart_id, m_prefix + "TypeLabel", OBJPROP_TEXT, text);
   }
   
   //--- Check button click
   bool IsPeriodButtonClicked()
   {
      if(ObjectGetInteger(m_chart_id, m_prefix + "PeriodButton", OBJPROP_STATE))
      {
         ObjectSetInteger(m_chart_id, m_prefix + "PeriodButton", OBJPROP_STATE, false);
         return true;
      }
      return false;
   }
   
   //--- Check close button click
   bool IsCloseButtonClicked()
   {
      if(ObjectGetInteger(m_chart_id, m_prefix + "CloseButton", OBJPROP_STATE))
      {
         ObjectSetInteger(m_chart_id, m_prefix + "CloseButton", OBJPROP_STATE, false);
         return true;
      }
      return false;
   }
   
   //--- Check if visible
   bool IsVisible() const
   {
      return m_visible;
   }
};

//+------------------------------------------------------------------+
