import fs from 'node:fs';
const css=fs.readFileSync('visual/premium.css','utf8').trim();
const motion=fs.readFileSync('visual/motion.js','utf8').trim();
const banner=fs.readFileSync('visual/banner.html','utf8').trim();
for(const path of ['public/catalogo.html','worker/index.js']){
 let source=fs.readFileSync(path,'utf8');
 source=source.replace(/<!-- km-premium-style:start -->[\s\S]*?<!-- km-premium-style:end -->/g,'').replace(/<!-- km-premium-script:start -->[\s\S]*?<!-- km-premium-script:end -->/g,'');
 source=source.replace(/<!-- km-premium-banner:start -->[\s\S]*?<!-- km-premium-banner:end -->/g,'<div class="art" aria-hidden="true"><div class="orbit"></div><div class="monogram">K<span>&</span>M</div><div class="art-label">CURADORIA K&M / SELEÇÃO ESPECIAL</div></div>');
 const old='<div class="art" aria-hidden="true"><div class="orbit"></div><div class="monogram">K<span>&</span>M</div><div class="art-label">CURADORIA K&M / SELEÇÃO ESPECIAL</div></div>';
 if(!source.includes(old))throw Error('Original banner missing: '+path);
 source=source.replace(old,'<!-- km-premium-banner:start -->'+banner+'<!-- km-premium-banner:end -->');
 source=source.replace('</head>','<!-- km-premium-style:start --><style>\n'+css+'\n</style><!-- km-premium-style:end --></head>');
 source=source.replace('</body>','<!-- km-premium-script:start --><script>\n'+motion+'\n</script><!-- km-premium-script:end --></body>');
 fs.writeFileSync(path,source);
}
