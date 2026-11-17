// Keep the generated popup self-contained: no external styles or fonts are needed.
const fs=require('fs'),path=require('path');
const root=path.resolve(__dirname,'..'),filename=path.join(root,'receipt.js');
const source=fs.readFileSync(filename,'utf8'),css=fs.readFileSync(path.join(root,'receipt.css'),'utf8');
const start='/* BEGIN RECEIPT CSS */',end='/* END RECEIPT CSS */';
const a=source.indexOf(start),b=source.indexOf(end);
if(a<0||b<a)throw Error('Receipt stylesheet markers not found');
fs.writeFileSync(filename,source.slice(0,a)+start+'\nconst STYLES='+JSON.stringify(css)+';\n'+source.slice(b));
