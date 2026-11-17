# Recibos K&M Imports

Os botões de recibo existentes agora usam `receipt.js`. O documento é gerado a partir de uma cópia da venda no momento da abertura: cliente, contato, produto, total, valores recebidos e em aberto, forma de pagamento, datas completas, observações e identificação original da venda.

- A paleta é fundo preto com detalhes em azul escuro neon. O PDF A4 preserva a mesma paleta escura, com textos claros e a marca K&M.
- Um pagamento parcial recebe indicação explícita. Venda sem recebimento gera “Resumo da compra”, sem sugerir quitação. Diferenças entre parcelas e total são sinalizadas para conferência.
- Datas de recebimento ausentes não são inventadas. Custos internos, taxas, margem e e-mail do responsável não são incluídos no documento do cliente.
- O QR code contém exclusivamente o endereço do atendimento da K&M no WhatsApp. Não é assinatura digital nem verificação de autenticidade.
- “Compartilhar PDF” envia exclusivamente um arquivo `application/pdf` pela folha de compartilhamento do navegador. Quando o compartilhamento de arquivos não está disponível, o PDF é baixado para anexar manualmente. Não há resumo em texto nem cópia de texto como alternativa. “Baixar PDF” salva diretamente o arquivo; a impressão continua disponível em um botão separado.
- A emissão não grava documentos no banco, não altera pagamentos e não gera um link público com dados da compra.

## Manutenção

`receipt.css` é a fonte dos estilos. Após alterá-la, rode `npm run build:receipt` para atualizar o estilo incorporado em `receipt.js`. O recibo tem estilo, marca vetorial e QR code incorporados, sem dependência de fonte ou folha de estilo externa; a foto de produto, quando cadastrada, usa a imagem existente.

A biblioteca local `vendor/qrcode-2.0.4.js` é qrcode-generator 2.0.4 (MIT). A licença acompanha o arquivo.

Execute `npm test` para testar os fluxos existentes e os recibos. A conferência visual em navegador incluiu 320, 360, 393, 768 e 1100 px, exportação A4, leitura de valores e casos de pagamento quitado/parcial/em aberto e dados divergentes. Os dados de conferência são fictícios e não são publicados no sistema.

## Geração e compartilhamento de PDF

`receipt-pdf.js` usa html2canvas 1.4.1 e jsPDF 4.2.1, distribuídos localmente em `vendor/` com suas licenças MIT. Os geradores são carregados apenas quando um recibo é aberto. Os dados são processados no navegador, sem envio a um serviço externo.

O PDF é preparado a partir do mesmo retrato da venda mostrado na tela. O compartilhamento só é habilitado quando o arquivo está pronto; o clique chama `navigator.share({files: [file]})` diretamente para preservar a autorização de toque no celular. Cancelar o envio não baixa outro arquivo. Uma falha de geração mantém o recibo visível e permite tentar novamente.

O documento preserva a paleta preta/azul escuro neon e a composição A4. Recibos longos são paginados sem cortar linhas de pagamentos, com cabeçalho repetido e número de página. Os links de atendimento continuam clicáveis no PDF. Os dados visuais são incorporados como imagem de alta resolução; o texto do corpo não é selecionável como no HTML.
