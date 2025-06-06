//+------------------------------------------------------------------+
//|                                          PicosValesRobot.mq5     |
//|                        Copyright 2024, Seu Nome                  |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024, Seu Nome"
#property link      "https://www.mql5.com"
#property version   "1.00"

//--- Parâmetros de entrada
input double PercentualVale = 22.0;           // % abaixo da MA200 para definir o vale
input double PercentualPico = 20.0;           // % acima da MA200 para definir o pico
input double LoteSize = 0.1;                  // Tamanho do lote
input int MagicNumber = 123456;               // Número mágico
input string Comentario = "PicosVales";       // Comentário das ordens

//--- Variáveis globais
int handleMA200;
double ma200[];
bool posicaoAberta = false;
ulong ticketPosicao = 0;

//+------------------------------------------------------------------+
//| Função de inicialização do expert                                |
//+------------------------------------------------------------------+
int OnInit()
{
    // Criar handle para MA200 no timeframe diário
    handleMA200 = iMA(_Symbol, PERIOD_D1, 200, 0, MODE_SMA, PRICE_CLOSE);
    
    if(handleMA200 == INVALID_HANDLE)
    {
        Print("Erro ao criar handle da MA200");
        return INIT_FAILED;
    }
    
    // Configurar arrays
    ArraySetAsSeries(ma200, true);
    
    Print("Robô Picos e Vales inicializado com sucesso!");
    Print("Vale: ", PercentualVale, "% abaixo da MA200");
    Print("Pico: ", PercentualPico, "% acima da MA200");
    Print("Compra quando preço atingir o vale");
    Print("Venda quando preço atingir o pico");
    
    return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Função de desinicialização do expert                             |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
    if(handleMA200 != INVALID_HANDLE)
        IndicatorRelease(handleMA200);
}

//+------------------------------------------------------------------+
//| Função principal do expert                                        |
//+------------------------------------------------------------------+
void OnTick()
{
    // Obter dados da MA200 - pegar mais dados para garantir disponibilidade
    if(CopyBuffer(handleMA200, 0, 0, 205, ma200) < 200)
    {
        Print("Aguardando dados suficientes da MA200...");
        return;
    }
    
    // Verificar se temos dados válidos da MA200
    if(ma200[0] <= 0)
    {
        Print("MA200 inválida: ", ma200[0]);
        return;
    }
    
    // Calcular pico e vale baseados na MA200 atual
    double ma200Atual = ma200[0];
    double precoVale = ma200Atual * (1.0 - PercentualVale / 100.0);
    double precoPico = ma200Atual * (1.0 + PercentualPico / 100.0);
    
    // Obter preços atuais
    double precoAtualBid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
    double precoAtualAsk = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
    
    // Verificar status da posição atual
    VerificarPosicao();
    
    // Debug detalhado
    static int debugCount = 0;
    debugCount++;
    if(debugCount % 100 == 0) // A cada 100 ticks
    {
        Print("=== DEBUG ROBÔ ===");
        Print("MA200: ", ma200Atual);
        Print("Vale (", PercentualVale, "%): ", precoVale);
        Print("Pico (", PercentualPico, "%): ", precoPico);
        Print("Preço Bid: ", precoAtualBid);
        Print("Preço Ask: ", precoAtualAsk);
        Print("Posição Aberta: ", posicaoAberta);
        Print("Condição Compra (Bid <= Vale): ", (precoAtualBid <= precoVale));
        Print("Condição Venda (Bid >= Pico): ", (precoAtualBid >= precoPico));
        Print("==================");
    }
    
    // Lógica de trading
    if(!posicaoAberta)
    {
        // Verificar condição de compra (preço atingiu o vale)
        if(precoAtualBid <= precoVale)
        {
            Print("*** TENTANDO COMPRA ***");
            Print("Preço Bid: ", precoAtualBid, " <= Vale: ", precoVale);
            
            if(AbrirPosicaoCompra())
            {
                Print("COMPRA EXECUTADA COM SUCESSO!");
                Print("Preço: ", precoAtualBid, " | Vale: ", precoVale, " | MA200: ", ma200Atual);
            }
        }
    }
    else
    {
        // Verificar condição de venda (preço atingiu o pico)
        if(precoAtualBid >= precoPico)
        {
            Print("*** TENTANDO VENDA ***");
            Print("Preço Bid: ", precoAtualBid, " >= Pico: ", precoPico);
            
            if(FecharPosicao())
            {
                Print("VENDA EXECUTADA COM SUCESSO!");
                Print("Preço: ", precoAtualBid, " | Pico: ", precoPico, " | MA200: ", ma200Atual);
            }
        }
    }
    
    // Informações de debug no gráfico
    Comment("MA200: ", DoubleToString(ma200Atual, _Digits),
            "\nVale (", PercentualVale, "%): ", DoubleToString(precoVale, _Digits),
            "\nPico (", PercentualPico, "%): ", DoubleToString(precoPico, _Digits),
            "\nPreço Bid: ", DoubleToString(precoAtualBid, _Digits),
            "\nPreço Ask: ", DoubleToString(precoAtualAsk, _Digits),
            "\nPosição: ", (posicaoAberta ? "ABERTA" : "FECHADA"),
            "\nCondição Compra: ", (precoAtualBid <= precoVale ? "SIM" : "NÃO"),
            "\nCondição Venda: ", (precoAtualBid >= precoPico ? "SIM" : "NÃO"));
}

//+------------------------------------------------------------------+
//| Verificar se há posição aberta                                   |
//+------------------------------------------------------------------+
void VerificarPosicao()
{
    posicaoAberta = false;
    ticketPosicao = 0;
    
    for(int i = 0; i < PositionsTotal(); i++)
    {
        if(PositionGetTicket(i) > 0)
        {
            if(PositionGetString(POSITION_SYMBOL) == _Symbol && 
               PositionGetInteger(POSITION_MAGIC) == MagicNumber)
            {
                posicaoAberta = true;
                ticketPosicao = PositionGetTicket(i);
                break;
            }
        }
    }
}

//+------------------------------------------------------------------+
//| Abrir posição de compra                                          |
//+------------------------------------------------------------------+
bool AbrirPosicaoCompra()
{
    // Verificar se o mercado permite trading
    if(!SymbolInfoInteger(_Symbol, SYMBOL_TRADE_MODE))
    {
        Print("Trading não permitido para ", _Symbol);
        return false;
    }
    
    // Normalizar o volume
    double volumeMin = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
    double volumeMax = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
    double volumeStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
    
    double volumeNormalizado = MathMax(volumeMin, MathMin(volumeMax, LoteSize));
    volumeNormalizado = NormalizeDouble(volumeNormalizado / volumeStep, 0) * volumeStep;
    
    MqlTradeRequest request = {};
    MqlTradeResult result = {};
    
    request.action = TRADE_ACTION_DEAL;
    request.symbol = _Symbol;
    request.volume = volumeNormalizado;
    request.type = ORDER_TYPE_BUY;
    request.price = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
    request.deviation = 10;
    request.magic = MagicNumber;
    request.comment = Comentario + " - Compra";
    request.type_filling = ORDER_FILLING_FOK;
    
    // Tentar ORDER_FILLING_IOC se FOK falhar
    bool sucesso = OrderSend(request, result);
    if(!sucesso && result.retcode == TRADE_RETCODE_INVALID_FILL)
    {
        request.type_filling = ORDER_FILLING_IOC;
        sucesso = OrderSend(request, result);
    }
    
    // Tentar sem especificar filling mode
    if(!sucesso && result.retcode == TRADE_RETCODE_INVALID_FILL)
    {
        request.type_filling = 0;
        sucesso = OrderSend(request, result);
    }
    
    if(sucesso)
    {
        Print("*** POSIÇÃO DE COMPRA ABERTA ***");
        Print("Ticket: ", result.order);
        Print("Volume: ", volumeNormalizado);
        Print("Preço: ", request.price);
        posicaoAberta = true;
        ticketPosicao = result.order;
    }
    else
    {
        Print("*** ERRO AO ABRIR COMPRA ***");
        Print("Código: ", result.retcode);
        Print("Descrição: ", result.comment);
        Print("Volume solicitado: ", LoteSize);
        Print("Volume normalizado: ", volumeNormalizado);
        Print("Volume mín: ", volumeMin, " | máx: ", volumeMax, " | step: ", volumeStep);
    }
    
    return sucesso;
}

//+------------------------------------------------------------------+
//| Fechar posição                                                    |
//+------------------------------------------------------------------+
bool FecharPosicao()
{
    if(!posicaoAberta || ticketPosicao == 0)
    {
        Print("Nenhuma posição para fechar");
        return false;
    }
    
    // Selecionar a posição
    if(!PositionSelectByTicket(ticketPosicao))
    {
        Print("Erro ao selecionar posição: ", ticketPosicao);
        // Tentar revalidar posições
        VerificarPosicao();
        return false;
    }
    
    double volume = PositionGetDouble(POSITION_VOLUME);
    ENUM_POSITION_TYPE tipo = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
    
    MqlTradeRequest request = {};
    MqlTradeResult result = {};
    
    request.action = TRADE_ACTION_DEAL;
    request.symbol = _Symbol;
    request.volume = volume;
    request.type = (tipo == POSITION_TYPE_BUY) ? ORDER_TYPE_SELL : ORDER_TYPE_BUY;
    request.position = ticketPosicao;
    request.price = (tipo == POSITION_TYPE_BUY) ? 
                    SymbolInfoDouble(_Symbol, SYMBOL_BID) : 
                    SymbolInfoDouble(_Symbol, SYMBOL_ASK);
    request.deviation = 10;
    request.magic = MagicNumber;
    request.comment = Comentario + " - Venda";
    request.type_filling = ORDER_FILLING_FOK;
    
    // Tentar diferentes modos de preenchimento
    bool sucesso = OrderSend(request, result);
    if(!sucesso && result.retcode == TRADE_RETCODE_INVALID_FILL)
    {
        request.type_filling = ORDER_FILLING_IOC;
        sucesso = OrderSend(request, result);
    }
    
    if(!sucesso && result.retcode == TRADE_RETCODE_INVALID_FILL)
    {
        request.type_filling = 0;
        sucesso = OrderSend(request, result);
    }
    
    if(sucesso)
    {
        Print("*** POSIÇÃO FECHADA ***");
        Print("Ticket: ", result.order);
        Print("Volume: ", volume);
        Print("Preço: ", request.price);
        posicaoAberta = false;
        ticketPosicao = 0;
    }
    else
    {
        Print("*** ERRO AO FECHAR POSIÇÃO ***");
        Print("Código: ", result.retcode);
        Print("Descrição: ", result.comment);
        Print("Ticket posição: ", ticketPosicao);
    }
    
    return sucesso;
}

//+------------------------------------------------------------------+