# K&M • Catálogo

- **Abrir catálogo:** https://kmimportsz.github.io/kmbusiness/catalogo/
- **Administração protegida:** https://kmimportsz.github.io/kmbusiness/catalogoadm/
- **Hospedagem do servidor e dos dados:** https://km-camisetas-catalogo.inventivetoucan16.chatgpt.site

`index.html` é a página publicada pelo GitHub Pages. A pasta `source/` contém o código completo do catálogo, incluindo o servidor, as páginas, os testes e a camada visual PREMIUM UI EXPERIENCE 3.0. A auditoria e as instruções de restauração estão em `source/docs/PREMIUM-UI-3.md`. O estado anterior está identificado pela tag `catalogo-before-premium-ui-3`.

O GitHub Pages serve a página; produtos, fotos, administração e APIs continuam usando o servidor do Sites e seu armazenamento. Esta cópia do código não inclui dados do armazenamento nem variáveis secretas. Alterações em `source/` não publicam automaticamente o servidor.

Para executar os testes do código recuperado:

```sh
cd catalogo/source
mkdir -p work
npm test
```
