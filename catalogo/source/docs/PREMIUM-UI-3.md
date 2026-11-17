# PREMIUM UI EXPERIENCE 3.0 — auditoria e preservação

## Estado anterior à edição

Sites: `b3a67be159a89f0f472627076ca61af905988504` (versão 21).
GitHub kmimportsz/kmbusiness: `de89ccea4c21ad518e967632e89e24c8a921020a`.
Tag em ambos os repositórios: `catalogo-before-premium-ui-3`.
Bundle local do histórico original criado e validado por `git bundle verify` antes da edição.

## Arquitetura auditada

- `worker/index.js`: rotas, autenticação do administrador, catálogo, upload/fotos, backups/versionamento, cálculo de entrega e documento HTML embutido.
- `worker/observability.js`: estatísticas opcionais e diagnósticos privados.
- `public/catalogo.html`: documento público do GitHub Pages, pesquisa, filtros, coleções, detalhes do produto, sacola, quantidades, totais, entrega/retirada, WhatsApp e privacidade.
- `public/catalogoadm.html`: encaminhamento para a administração protegida do Sites.
- `scripts/build.mjs`: empacota o Worker; scripts/test*.mjs e check-public.mjs verificam os fluxos existentes.
- Integrações: armazenamento R2 `BUCKET`, identidade do Sites e `ADMIN_EMAIL`, Geoapify, dados de limites GeoSampa, WhatsApp e Instagram. Variáveis, permissões e contratos preservados.
- Navegação: catálogo → coleções/marca/pesquisa/filtros → foto/detalhes → sacola → identificação e entrega/retirada → revisão → WhatsApp. Menu, ajuda, privacidade e administração continuam disponíveis.

## Arquivos e escopo registrados antes das alterações

Modificar apenas a apresentação de `public/catalogo.html` e do HTML embutido em `worker/index.js`. Adicionar `visual/premium.css`, `visual/premium.js`, `visual/banner.html`, `scripts/apply-premium.mjs`, esta auditoria e verificação de preservação. No GitHub, sincronizar `catalogo/index.html` e a cópia completa `catalogo/source/`.

A nova camada observa o estado visual de carregamento de `#grid`. Não intercepta fetch, não refaz requisições e não modifica a inicialização funcional. A mesma identidade passa do centro da tela à posição no banner por transformação visual. Movimento reduzido, pausa, aba em segundo plano e saída antecipada da apresentação são tratados pela camada visual.

## Restauração

A tag identifica a árvore anterior completa. Para reverter apenas a apresentação, recupere `public/catalogo.html` e `worker/index.js` dessa tag; no GitHub, recupere `catalogo/index.html` e `catalogo/source/`. Publique o commit de reversão pelo fluxo habitual, preservando dados e configuração. Restaurar arquivos não restaura nem altera produtos, históricos ou fotos do armazenamento.

## Limites

Nenhuma melhoria que exija alterar lógica comercial, APIs, autenticação, armazenamento ou integrações está incluída. O servidor continua hospedado no Sites; GitHub Pages continua servindo a página pública.

## Validação executada

- Suíte existente `npm test`: aprovada (administração/backup, entrega, sacola, quantidades, filtros, detalhes/compartilhamento, privacidade/diagnósticos e página pública).
- `node scripts/test-premium.mjs`: comparação byte a byte com a tag original, removendo somente as adições visuais; lógica funcional, configuração e integrações intactas. Scripts dos dois documentos compilados.
- QA DOM isolado: sucesso e erro na requisição existente, mesma identidade DOM durante a transição FLIP, abreviação em carregamento rápido, saída antecipada sem nova requisição, pausa/retomada, movimento reduzido inicial e dinâmico e navegação por teclado. CSS analisado com parser.
- Build do Worker gerado e sintaxe verificada.
- Prévia local: o relay de porta do ambiente expirou; não foi possível realizar inspeção visual por essa rota. Verificação em navegador na publicação será registrada separadamente. Testes DOM não comprovam layout ou compatibilidade real com Safari iOS/Chrome Android.
