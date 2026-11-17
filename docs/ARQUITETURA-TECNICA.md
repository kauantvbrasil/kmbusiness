# K&M Business: limites técnicos e evolução futura

## Dependências identificadas

A aplicação é uma página no GitHub Pages. `index.html` contém estado e operações legadas. `central.js`, `business3.js`, `inventory3.js`, `visual.js` e `receipt.js` ampliam a interface, alguns decorando funções globais. Os testes executam esses módulos com jsdom. PDF e QR usam os arquivos já presentes em `vendor/`.

A persistência atual combina cache local `agenda_vendas_v1`, autenticação Firebase e coleções Firestore: products, sales, catalog, cphotos, expenses, closings, config e proofs. O catálogo público tem backend separado, com R2. Não existe uma transação compartilhada entre Firestore e R2. Nenhuma migração foi feita.

Algumas operações do módulo de estoque e edições usam `runTransaction`; o salvamento legado de outras telas usa gravações separadas. Portanto, não se pode afirmar que todo o sistema já possui atomicidade. A revisão dessas operações e das regras Firestore exige uma etapa própria; não foi feita nesta atualização.

## Módulos técnicos adicionados

- `platform/core.js`: serviços sem dependência de DOM para criar cópias, conferir estrutura e SHA-256 e acumular códigos de diagnóstico em memória.
- `platform/ui.js`: download e verificação de cópias, adaptação de leitura do novo formato ao restaurador existente, mensagens de conectividade e melhorias de teclado/rotulagem.
- `platform/technical.css`: estilos dos novos controles, alvos de toque e preferência por movimento reduzido.

Os módulos são carregados depois das dependências existentes. Eles não chamam Firebase, APIs do catálogo ou rotinas financeiras. A única ligação ao restaurador é a leitura/validação do arquivo; a confirmação e o comportamento de importação permanecem sob o fluxo legado.

Não foi criada uma nova fonte de produtos, uma nova base financeira ou uma ponte entre os sistemas. Não há automação comercial nova.

## Cópias e integridade

O arquivo JSON novo contém format, version, createdAt, algorithm, checksum e data. `data` preserva todas as propriedades serializáveis do estado carregado, inclusive campos desconhecidos e imagens embutidas. SHA-256 confere integridade do conteúdo, não autentica autor, não cifra e não garante legitimidade comercial.

A verificação do arquivo é somente leitura. O restaurador reconhece tanto o JSON legado quanto o novo envelope e solicita a confirmação já existente antes de substituir dados. Esta atualização não executa restaurações.

A cópia representa apenas o estado carregado no aparelho: aguardar a sincronização antes de exportar. Não inclui regras, índices, contas de autenticação, arquivos externos não carregados ou uma exportação independente do servidor. Backup de código e backup de dados são coisas diferentes. O arquivo pode conter dados pessoais: guardar em local privado.

## Segurança: o que esta etapa cobre

Links externos passam a receber noopener/noreferrer. Os diagnósticos novos usam apenas códigos conhecidos, contagem e horários; não registram mensagens de exceção, valores digitados, URLs, pilhas ou credenciais. Os registros ficam em memória e desaparecem quando a aba é recarregada. Não há novo envio de telemetria.

Não foram alteradas regras de autenticação nem permissões do Firestore. Configuração pública do SDK Firebase não equivale a credencial administrativa. Segurança efetiva dos dados depende das regras do servidor, que não foram auditadas nesta etapa. Não inserir chaves administrativas no GitHub Pages.

## Fronteiras para um futuro projeto com produtos permitidos

A evolução futura deve separar apresentação, autenticação/autorização, leitura pública e persistência administrativa, por meio de adaptadores. Antes de implementar qualquer integração:

1. Identificar um catálogo de produtos permitidos e confirmar o escopo desse projeto.
2. Inspecionar as regras e estruturas reais do servidor, com acesso administrativo autorizado.
3. Definir uma única fonte oficial para produtos, preços e quantidades.
4. Mapear identidades estáveis explicitamente, sem vincular apenas por nomes.
5. Isolar os dados legados e validar uma migração reversível, sem apagá-los.
6. Definir e testar contratos de leitura, tratamento de conflitos e idempotência no backend escolhido.
7. Somente nesse contexto, projetar a entrada de solicitações e a decisão administrativa, reutilizando o financeiro existente e garantindo uma operação consistente no servidor.

Este documento é um mapa de responsabilidades, não uma implementação de integração de estoque ou aprovação de pedidos. Não existe módulo de pedidos ativado, endpoint novo de vendas, reserva automática ou confirmação de pagamento.

## Rollback

Os arquivos originais não foram removidos. Para retirar a extensão técnica, remover do HTML somente a referência a platform/technical.css e os dois scripts platform/core.js e platform/ui.js. Isso não apaga nem migra dados. Guardar o ZIP de código anterior; ele não contém os registros privados carregados do Firebase.
