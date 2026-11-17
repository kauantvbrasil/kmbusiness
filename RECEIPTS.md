# Recibos K&M Imports

Os botões de recibo existentes agora usam `receipt.js`. O documento é gerado a partir de uma cópia da venda no momento da abertura: cliente, contato, produto, total, valores recebidos e em aberto, forma de pagamento, datas completas, observações e identificação original da venda.

- A paleta é fundo preto com detalhes em azul escuro neon. O PDF A4 preserva a mesma paleta escura, com textos claros e a marca K&M.
- Um pagamento parcial recebe indicação explícita. Venda sem recebimento gera “Resumo da compra”, sem sugerir quitação. Diferenças entre parcelas e total são sinalizadas para conferência.
- Datas de recebimento ausentes não são inventadas. Custos internos, taxas, margem e e-mail do responsável não são incluídos no documento do cliente.
- O QR code contém exclusivamente o endereço do atendimento da K&M no WhatsApp. Não é assinatura digital nem verificação de autenticidade.
- “Compartilhar resumo” compartilha texto pelo navegador ou copia o resumo quando o recurso não está disponível. “Imprimir / salvar PDF” abre a impressão do navegador, onde se pode escolher o destino PDF.
- A emissão não grava documentos no banco, não altera pagamentos e não gera um link público com dados da compra.

## Manutenção

`receipt.css` é a fonte dos estilos. Após alterá-la, rode `npm run build:receipt` para atualizar o estilo incorporado em `receipt.js`. O recibo tem estilo, marca vetorial e QR code incorporados, sem dependência de fonte ou folha de estilo externa; a foto de produto, quando cadastrada, usa a imagem existente.

A biblioteca local `vendor/qrcode-2.0.4.js` é qrcode-generator 2.0.4 (MIT). A licença acompanha o arquivo.

Execute `npm test` para testar os fluxos existentes e os recibos. A conferência visual em navegador incluiu 320, 360, 393, 768 e 1100 px, exportação A4, leitura de valores e casos de pagamento quitado/parcial/em aberto e dados divergentes. Os dados de conferência são fictícios e não são publicados no sistema.
