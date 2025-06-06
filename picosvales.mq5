//+------------------------------------------------------------------+
//|                                            PicosValesIndicator.mq5 |
//|                                  Copyright 2024, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024, MetaQuotes Ltd."
#property link      "https://www.mql5.com"
#property version   "1.00"
#property indicator_chart_window
#property indicator_buffers 1
#property indicator_plots   1

//--- plot MovingAverage
#property indicator_label1  "MA200"
#property indicator_type1   DRAW_LINE
#property indicator_color1  clrBlue
#property indicator_style1  STYLE_SOLID
#property indicator_width1  2

//--- Parâmetros de entrada
input int MA_Period = 200;              // Período da Média Móvel
input ENUM_MA_METHOD MA_Method = MODE_SMA; // Método da Média Móvel
input int MinDaysBetweenPeaks = 7;      // Mínimo de dias entre picos
input color PeakTitleColor = clrLime;   // Cor do título dos picos
input color PeakTextColor = clrYellow;  // Cor do texto dos picos
input color ValleyTitleColor = clrRed;  // Cor do título dos vales
input color ValleyTextColor = clrOrange; // Cor do texto dos vales

//--- Buffers do indicador
double MovingAverageBuffer[];

//--- Estrutura para armazenar picos e vales
struct PeakValley
{
    datetime time;
    double price;
    double ma_value;
    double percentage;
};

//--- Arrays globais para armazenar picos e vales
PeakValley peaks[100];
PeakValley valleys[100];
int peaks_count = 0;
int valleys_count = 0;

//--- Handle da média móvel
int ma_handle;

//+------------------------------------------------------------------+
//| Função de inicialização do indicador                              |
//+------------------------------------------------------------------+
int OnInit()
{
    //--- Verificar se estamos no timeframe diário
    if(Period() != PERIOD_D1)
    {
        Alert("Este indicador deve ser usado apenas no gráfico diário!");
        return(INIT_FAILED);
    }
    
    //--- Configurar buffers
    SetIndexBuffer(0, MovingAverageBuffer, INDICATOR_DATA);
    PlotIndexSetInteger(0, PLOT_DRAW_BEGIN, MA_Period);
    
    //--- Criar handle da média móvel
    ma_handle = iMA(_Symbol, PERIOD_D1, MA_Period, 0, MA_Method, PRICE_CLOSE);
    if(ma_handle == INVALID_HANDLE)
    {
        Print("Erro ao criar handle da média móvel");
        return(INIT_FAILED);
    }
    
    //--- Inicializar arrays
    peaks_count = 0;
    valleys_count = 0;
    
    return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Função principal de cálculo                                       |
//+------------------------------------------------------------------+
int OnCalculate(const int rates_total,
                const int prev_calculated,
                const datetime &time[],
                const double &open[],
                const double &high[],
                const double &low[],
                const double &close[],
                const long &tick_volume[],
                const long &volume[],
                const int &spread[])
{
    //--- Verificar se temos dados suficientes
    if(rates_total < MA_Period)
        return(0);
    
    //--- Copiar dados da média móvel
    if(CopyBuffer(ma_handle, 0, 0, rates_total, MovingAverageBuffer) <= 0)
        return(0);
    
    //--- Buscar picos e vales apenas se estivermos no último cálculo
    if(prev_calculated == 0 || rates_total - prev_calculated > 1)
    {
        FindPeaksAndValleys(rates_total, time, high, low, close);
        DisplayResults();
    }
    
    return(rates_total);
}

//+------------------------------------------------------------------+
//| Encontrar picos e vales                                          |
//+------------------------------------------------------------------+
void FindPeaksAndValleys(int total_bars, const datetime &time[], 
                        const double &high[], const double &low[], 
                        const double &close[])
{
    peaks_count = 0;
    valleys_count = 0;
    
    //--- Começar a partir do período da MA + 1
    for(int i = MA_Period + 1; i < total_bars - 1; i++)
    {
        if(MovingAverageBuffer[i] == 0) continue;
        
        //--- Verificar se é um pico local (máxima local)
        bool is_peak = (high[i] > high[i-1] && high[i] > high[i+1]);
        
        //--- Verificar se é um vale local (mínima local)
        bool is_valley = (low[i] < low[i-1] && low[i] < low[i+1]);
        
        if(is_peak)
        {
            double percentage = ((high[i] - MovingAverageBuffer[i]) / MovingAverageBuffer[i]) * 100.0;
            
            //--- Verificar distância mínima de outros picos
            if(IsValidPeak(time[i], peaks, peaks_count))
            {
                //--- Adicionar pico se temos espaço ou se é maior que o menor pico atual
                if(peaks_count < 5)
                {
                    peaks[peaks_count].time = time[i];
                    peaks[peaks_count].price = high[i];
                    peaks[peaks_count].ma_value = MovingAverageBuffer[i];
                    peaks[peaks_count].percentage = percentage;
                    peaks_count++;
                }
                else
                {
                    //--- Encontrar o menor pico e substituir se necessário
                    int min_idx = FindMinPeakIndex();
                    if(percentage > peaks[min_idx].percentage)
                    {
                        peaks[min_idx].time = time[i];
                        peaks[min_idx].price = high[i];
                        peaks[min_idx].ma_value = MovingAverageBuffer[i];
                        peaks[min_idx].percentage = percentage;
                    }
                }
            }
        }
        
        if(is_valley)
        {
            double percentage = ((MovingAverageBuffer[i] - low[i]) / MovingAverageBuffer[i]) * 100.0;
            
            //--- Verificar distância mínima de outros vales
            if(IsValidValley(time[i], valleys, valleys_count))
            {
                //--- Adicionar vale se temos espaço ou se é maior que o menor vale atual
                if(valleys_count < 5)
                {
                    valleys[valleys_count].time = time[i];
                    valleys[valleys_count].price = low[i];
                    valleys[valleys_count].ma_value = MovingAverageBuffer[i];
                    valleys[valleys_count].percentage = percentage;
                    valleys_count++;
                }
                else
                {
                    //--- Encontrar o menor vale e substituir se necessário
                    int min_idx = FindMinValleyIndex();
                    if(percentage > valleys[min_idx].percentage)
                    {
                        valleys[min_idx].time = time[i];
                        valleys[min_idx].price = low[i];
                        valleys[min_idx].ma_value = MovingAverageBuffer[i];
                        valleys[min_idx].percentage = percentage;
                    }
                }
            }
        }
    }
    
    //--- Ordenar arrays por percentual (maior para menor)
    SortPeaksByPercentage();
    SortValleysByPercentage();
}

//+------------------------------------------------------------------+
//| Verificar se o pico é válido (distância mínima de outros picos)   |
//+------------------------------------------------------------------+
bool IsValidPeak(datetime peak_time, PeakValley &existing_peaks[], int count)
{
    for(int i = 0; i < count; i++)
    {
        int days_diff = (int)((peak_time - existing_peaks[i].time) / (24 * 3600));
        if(MathAbs(days_diff) < MinDaysBetweenPeaks)
            return false;
    }
    return true;
}

//+------------------------------------------------------------------+
//| Verificar se o vale é válido (distância mínima de outros vales)   |
//+------------------------------------------------------------------+
bool IsValidValley(datetime valley_time, PeakValley &existing_valleys[], int count)
{
    for(int i = 0; i < count; i++)
    {
        int days_diff = (int)((valley_time - existing_valleys[i].time) / (24 * 3600));
        if(MathAbs(days_diff) < MinDaysBetweenPeaks)
            return false;
    }
    return true;
}

//+------------------------------------------------------------------+
//| Encontrar índice do menor pico                                    |
//+------------------------------------------------------------------+
int FindMinPeakIndex()
{
    int min_idx = 0;
    for(int i = 1; i < 5; i++)
    {
        if(peaks[i].percentage < peaks[min_idx].percentage)
            min_idx = i;
    }
    return min_idx;
}

//+------------------------------------------------------------------+
//| Encontrar índice do menor vale                                    |
//+------------------------------------------------------------------+
int FindMinValleyIndex()
{
    int min_idx = 0;
    for(int i = 1; i < 5; i++)
    {
        if(valleys[i].percentage < valleys[min_idx].percentage)
            min_idx = i;
    }
    return min_idx;
}

//+------------------------------------------------------------------+
//| Ordenar picos por percentual                                      |
//+------------------------------------------------------------------+
void SortPeaksByPercentage()
{
    for(int i = 0; i < peaks_count - 1; i++)
    {
        for(int j = i + 1; j < peaks_count; j++)
        {
            if(peaks[j].percentage > peaks[i].percentage)
            {
                PeakValley temp = peaks[i];
                peaks[i] = peaks[j];
                peaks[j] = temp;
            }
        }
    }
}

//+------------------------------------------------------------------+
//| Ordenar vales por percentual                                      |
//+------------------------------------------------------------------+
void SortValleysByPercentage()
{
    for(int i = 0; i < valleys_count - 1; i++)
    {
        for(int j = i + 1; j < valleys_count; j++)
        {
            if(valleys[j].percentage > valleys[i].percentage)
            {
                PeakValley temp = valleys[i];
                valleys[i] = valleys[j];
                valleys[j] = temp;
            }
        }
    }
}

//+------------------------------------------------------------------+
//| Exibir resultados na tela                                        |
//+------------------------------------------------------------------+
void DisplayResults()
{
    //--- Remover objetos de texto anteriores
    for(int i = 0; i < 15; i++)
    {
        ObjectDelete(0, "PeakText" + IntegerToString(i));
        ObjectDelete(0, "ValleyText" + IntegerToString(i));
    }
    
    int y_offset = 30;
    
    //--- Exibir título dos picos
    CreateTextObject("PeakTitle", "=== MAIORES PICOS (% acima da MA200) ===", 
                     10, y_offset, PeakTitleColor, 9, "Arial Bold");
    y_offset += 20;
    
    //--- Exibir picos
    for(int i = 0; i < peaks_count; i++)
    {
        string peak_text = StringFormat("%d. %s - %.2f%% (Preço: %.5f)", 
                                       i + 1, 
                                       TimeToString(peaks[i].time, TIME_DATE),
                                       peaks[i].percentage,
                                       peaks[i].price);
        
        CreateTextObject("PeakText" + IntegerToString(i), peak_text, 
                        10, y_offset, PeakTextColor, 8, "Arial");
        y_offset += 15;
    }
    
    y_offset += 10;
    
    //--- Exibir título dos vales
    CreateTextObject("ValleyTitle", "=== MAIORES VALES (% abaixo da MA200) ===", 
                     10, y_offset, ValleyTitleColor, 9, "Arial Bold");
    y_offset += 20;
    
    //--- Exibir vales
    for(int i = 0; i < valleys_count; i++)
    {
        string valley_text = StringFormat("%d. %s - %.2f%% (Preço: %.5f)", 
                                         i + 1, 
                                         TimeToString(valleys[i].time, TIME_DATE),
                                         valleys[i].percentage,
                                         valleys[i].price);
        
        CreateTextObject("ValleyText" + IntegerToString(i), valley_text, 
                        10, y_offset, ValleyTextColor, 8, "Arial");
        y_offset += 15;
    }
}

//+------------------------------------------------------------------+
//| Criar objeto de texto                                             |
//+------------------------------------------------------------------+
void CreateTextObject(string name, string text, int x, int y, color clr, int size, string font)
{
    ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0);
    ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
    ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
    ObjectSetString(0, name, OBJPROP_TEXT, text);
    ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
    ObjectSetInteger(0, name, OBJPROP_FONTSIZE, size);
    ObjectSetString(0, name, OBJPROP_FONT, font);
    ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
    ObjectSetInteger(0, name, OBJPROP_ANCHOR, ANCHOR_LEFT_UPPER);
}

//+------------------------------------------------------------------+
//| Função de desinicialização                                        |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
    //--- Remover todos os objetos de texto
    for(int i = 0; i < 15; i++)
    {
        ObjectDelete(0, "PeakText" + IntegerToString(i));
        ObjectDelete(0, "ValleyText" + IntegerToString(i));
    }
    ObjectDelete(0, "PeakTitle");
    ObjectDelete(0, "ValleyTitle");
    
    //--- Liberar handle da média móvel
    if(ma_handle != INVALID_HANDLE)
        IndicatorRelease(ma_handle);
}