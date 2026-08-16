let FE=[];const ck=(n,c,d='')=>{c?console.log('  PASS  '+n):(console.log('  FAIL  '+n+'  '+d),FE.push(n))};
SESSION={username:'owner',role:'owner'};WHO='owner';SETUP_DISMISSED=true;DATA.firstRunDone=true;
TOASTS=[];global.setTimeout=fn=>0;
DATA.setup={name:'Sadeq',done:true,started:true,skipped:{}};
DATA.menu=[{id:'m',name:'Chicken Plate',menuPrice:6,weeklySales:100,dept:'kitchen',lines:[{ref:'001_X',qty:1}]}];
DATA.ingredients=[{id:'x',code:'001',name:'X',price:2,recipeUnit:'kg',ruPerPu:1,pu:'kg',yield:1,history:[]}];
DATA.rates={vat:0.1,service:0.1,levy:0};
DATA.week={days:['a','b','c','d','e','f','g'],salesByDay:[100,200,150,300,400,500,250],
  guests:[10,20,15,30,40,50,25],employees:[{name:'A',rate:2,hours:[8,8,8,8,8,8,0]}],
  purchases:[{supplier:'Gulf',date:'1/7/2026',amount:300,alloc:{Meat:300}}]};
rebuildIX();rebuildBX();

// ═══ THE DOCUMENT ═══
const html=reportHTML();
ck('the report is a complete HTML document', /^<html>/.test(html)&&/<\/html>`?$/.test(html.trim()));
ck('...titled', /Where the money went/.test(html));
ck('...naming the venue owner', /Sadeq/.test(html));
ck('...with findings', /Findings/.test(html));
ck('...and the "cannot tell you" section', /What this cannot tell you yet/.test(html));
ck('no NaN in the document', !/NaN/.test(html));
ck('no undefined', !/undefined/.test(html));

// print and download share the SAME document (no drift)
let printed='';global.window.open=()=>({document:{write:s=>{printed+=s},close(){}}});
printReport();
ck('print and download produce identical output', printed===reportHTML());

// ═══ DOWNLOAD ═══
let clicked=null,dl=null,blobbed=null;
global.URL={createObjectURL:b=>{blobbed=b;return 'blob:x'}};
global.document.createElement=(t)=>({set href(v){},set download(v){dl=v},click(){clicked=true}});
global.Blob=function(parts,opts){this.parts=parts;this.type=opts&&opts.type};
TOASTS=[];
downloadReport();
ck('a file is saved', clicked===true);
ck('...as HTML', blobbed&&blobbed.type==='text/html');
ck('...containing the full report', blobbed.parts[0].includes('Where the money went'));
ck('...with a dated, named filename', /Sadeq-money-report-\d{4}-\d{2}-\d{2}\.html/.test(dl), dl);
ck('...and confirms via toast', TOASTS.some(t=>/Report saved/.test(t.msg)));

// ═══ THE BUTTONS ═══
SETUP_DISMISSED=true;view='report';render();
const h=__store['app'].innerHTML;
ck('the report screen offers Save as file', /downloadReport\(\)/.test(h));
ck('...and print', /printReport\(\)/.test(h));
console.log(FE.length?('\n'+FE.length+' FAILED: '+FE.join(' | ')):'\nEXPORT: ALL PASS');
