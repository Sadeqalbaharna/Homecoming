let F=[];const ck=(n,c,d='')=>{c?console.log('  PASS  '+n):(console.log('  FAIL  '+n+'  '+d),F.push(n))};
SESSION={username:'owner',role:'owner'};DATA.firstRunDone=true;

// ── what a JPEG looks like when you decode it as text ──
const jpegAsText='\xFF\xD8\xFF\xE0\x00\x10JFIF\x00\x01\x01\x00'+
  '\x00qq8\x00q\x009)Ɛt\x000\x005Hi\x00`&0C@0bba@1P\x00`'.repeat(40);
ck('a JPEG read as text is not text', !looksLikeText(jpegAsText));
ck('a real CSV is text',
   looksLikeText('supplier,item,qty,cost\nGulf Foods,Chicken,10,2.4\nDelta,Rice,20,1.1\n'));
ck('a semicolon export is text',
   looksLikeText('Supplier;Item;Qty;Cost\nGulf;Chicken;10;2,4\nDelta;Rice;20;1,1\n'));
ck('an Arabic export is text',
   looksLikeText('المورد,الصنف,الكمية\nالخليج,دجاج,10\nدلتا,أرز,20\nGulf,Chicken,10\n'));
ck('a PNG header is not text', !looksLikeText('\x89PNG\r\n\x1a\n'+'\x00\x01\x02\x03'.repeat(200)));
ck('a zip/xlsx header is not text', !looksLikeText('PK\x03\x04'+'\x00\x14\x00\x08'.repeat(200)));

// ── the file router ──
ck('a .jpg is an image', isImageFile({name:'IMG_2201.jpg',type:'image/jpeg'}));
ck('an Android camera file with no extension is still an image',
   isImageFile({name:'capture',type:'image/jpeg'}));
ck('an iPhone .HEIC is an image', isImageFile({name:'IMG_0001.HEIC',type:''}));
ck('a .csv is not an image', !isImageFile({name:'sales.csv',type:'text/csv'}));
ck('a .pdf is not an image', !isImageFile({name:'menu.pdf',type:'application/pdf'}));

// ── the actual bug: a photo into the CSV importer ──
let routed=null;
const realAdd=addShots; addShots=(o,k)=>{routed={kind:k,n:o.files.length}};
STAGE=null; FILEFAIL=null;
stageFile({files:[{name:'invoice.jpg',type:'image/jpeg'}],value:''},'purchases');
ck('a photo on Purchases goes to the camera path, not the parser',
   routed&&routed.kind==='purchases', JSON.stringify(routed));
ck('...and never reaches the column mapper', STAGE===null);

routed=null; STAGE=null; FILEFAIL=null;
stageFile({files:[{name:'shift.jpg',type:'image/jpeg'}],value:''},'punches');
ck('a photo on attendance is refused, not parsed', FILEFAIL&&FILEFAIL.reason==='image');
ck('...with no mojibake columns offered', STAGE===null);
ck('...and says why photographing it is the wrong route',
   /worse route to a file you can already download/.test(FILEFAIL.why));
addShots=realAdd;

// ── the second net: binary wearing a .csv name ──
STAGE=null; FILEFAIL=null;
let onload=null;
globalThis.FileReader=function(){ this.readAsText=()=>onload({target:{result:jpegAsText}});
  Object.defineProperty(this,'onload',{set:f=>onload=f}); };
stageFile({files:[{name:'export.csv',type:'text/csv'}],value:''},'purchases');
ck('binary named .csv is refused', FILEFAIL&&FILEFAIL.reason==='binary');
ck('...and nothing is staged', STAGE===null);
ck('...and it names the likely causes', /xlsx|compressed/i.test(FILEFAIL.why));

STAGE=null; FILEFAIL=null;
onload=null;
globalThis.FileReader=function(){ this.readAsText=()=>onload({target:{result:'only one line, no newline'}});
  Object.defineProperty(this,'onload',{set:f=>onload=f}); };
stageFile({files:[{name:'x.csv',type:'text/csv'}],value:''},'purchases');
ck('a one-line file is explained on the page, not in an alert', FILEFAIL&&FILEFAIL.reason==='norows');

// a good file still works
STAGE=null; FILEFAIL=null; onload=null;
globalThis.FileReader=function(){ this.readAsText=()=>onload({target:{result:
  'Supplier,Line total,Item\nGulf Foods,24,Chicken\nDelta,22,Rice\n'}});
  Object.defineProperty(this,'onload',{set:f=>onload=f}); };
stageFile({files:[{name:'goods.csv',type:'text/csv'}],value:''},'purchases');
ck('a genuine CSV still reaches the mapper', STAGE&&STAGE.rows.length===2, JSON.stringify(STAGE&&STAGE.rows));
ck('...and was not flagged', !FILEFAIL);
console.log(F.length?('\n'+F.length+' FAILED: '+F.join(' | ')):'\nBINARY GUARD: ALL PASS');
