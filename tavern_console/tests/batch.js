let F=[];const ck=(n,c,d='')=>{c?console.log('  PASS  '+n):(console.log('  FAIL  '+n+'  '+d),F.push(n))};
SESSION={username:'owner',role:'owner'};DATA.firstRunDone=true;
DATA.ai={provider:'anthropic',key:'sk-test',on:true};

// ── the crash I nearly shipped: visionBody reads .dataUrl ──
const shot={dataUrl:'data:image/jpeg;base64,AAA',data:'AAA',w:1200,h:1600,page:1};
let body=null,threw=null;
try{ body=visionBody('anthropic','m','sys','prompt',[shot]); }catch(e){ threw=e.message; }
ck('visionBody accepts what shrinkImage returns', !threw, String(threw));
ck('...and finds the base64', body&&body.messages[0].content[0].source.data==='AAA');
ck('...with the prompt after the image', body&&body.messages[0].content[1].type==='text');
ck('an object with only .data would still crash — so both are returned',
   (()=>{try{visionBody('anthropic','m','s','p',[{data:'AAA'}]);return false}catch(e){return true}})());

// ── a fake API: one invoice per call, each with its own supplier ──
const INV={
 'gulf.jpg':  {items:[{supplier:'Gulf Foods',date:'2026-07-01',item:'Chicken',qty:10,unit:2.4,total:24}]},
 'delta.jpg': {items:[{supplier:'Delta Trading',date:'2026-07-02',item:'Rice',qty:20,unit:1.1,total:22}]},
 'boom.jpg':  '__500__',
 'empty.jpg': {items:[]},
 'gulf2.jpg': {items:[{supplier:'Gulf Foods',date:'2026-07-01',item:'Chicken',qty:10,unit:2.4,total:24}]}
};
let CALLS=[];
const mkfile=n=>({name:n,type:'image/jpeg',arrayBuffer:async()=>new ArrayBuffer(8)});
globalThis.fetch=async(url,opt)=>{
  const body=JSON.parse(opt.body);
  const which=CALLS.length; CALLS.push(body);
  const name=globalThis.__ORDER[which];
  const r=INV[name];
  if(r==='__500__')return{ok:false,status:500,text:async()=>'boom'};
  return {ok:true,status:200,json:async()=>({content:[{type:'text',text:JSON.stringify(r)}]})};
};
// shrinkImage needs a canvas; the queue only needs its output shape.
shrinkImage=async()=>({dataUrl:'data:image/jpeg;base64,AAA',data:'AAA',w:800,h:1000,page:1});

async function runBatch(names){
  CALLS=[]; globalThis.__ORDER=names; STAGE=null;
  INVBATCH={kind:'purchases',items:names.map(n=>({name:n,file:mkfile(n),status:'waiting',rows:[],error:''})),
            i:0,stop:false,calls:0,done:false};
  await batchRun();
  return INVBATCH;
}

(async()=>{
const b=await runBatch(['gulf.jpg','delta.jpg','boom.jpg','empty.jpg','gulf2.jpg']);

ck('one API call per invoice, never one big call', CALLS.length===5, String(CALLS.length));
ck('...each carrying a single document', CALLS.every(c=>c.messages[0].content.filter(x=>x.type==='image').length===1));

const st=n=>b.items.find(x=>x.name===n).status;
ck('a good invoice reads', st('gulf.jpg')==='ok');
ck('a second good invoice also reads', st('delta.jpg')==='ok');
ck('a 500 fails ALONE — it does not kill the run', st('boom.jpg')==='failed');
ck('...and the error is kept against that file',
   /returned 500/.test(b.items.find(x=>x.name==='boom.jpg').error));
ck('...and invoices AFTER the failure still ran', st('empty.jpg')==='empty'||st('empty.jpg')==='duplicate');
ck('an invoice with no readable lines is "empty", not "ok"', st('empty.jpg')==='empty');
ck('the same invoice twice is flagged as a duplicate', st('gulf2.jpg')==='duplicate');
ck('...naming which file it duplicates', b.items.find(x=>x.name==='gulf2.jpg').dupOf==='gulf.jpg');

ck('everything readable merges into ONE review table', STAGE&&STAGE.rows.length===2, STAGE&&STAGE.rows.length);
ck('...and the duplicate is NOT counted twice', STAGE.rows.filter(r=>/Gulf/.test(r[0])).length===1);
ck('...marked as a batch', STAGE.fromBatch===true);
ck('nothing was written to the book', (DATA.weeks?WK().purchases||[]:[]).length===0);

// THE ONE THAT MATTERS: suppliers cannot bleed between documents
const sup=STAGE.rows.map(r=>r[STAGE.map.supplier]).sort();
ck('each row keeps the supplier from its OWN invoice',
   JSON.stringify(sup)===JSON.stringify(['Delta Trading','Gulf Foods']), JSON.stringify(sup));
const dates=STAGE.rows.map(r=>r[STAGE.map.date]).sort();
ck('...and its own date', JSON.stringify(dates)===JSON.stringify(['2026-07-01','2026-07-02']));

// 4, not 3: empty.jpg was a real request that came back with nothing. You are
// billed for the reading, not for the result, and a counter that hid that
// would understate the cost of a bad batch.
ck('paid calls count every request that got a reply', b.calls===4, String(b.calls));
ck('...and exclude the one that errored', b.calls===CALLS.length-1);

// ── stop works mid-run, and keeps what was already read ──
CALLS=[]; globalThis.__ORDER=['gulf.jpg','delta.jpg','gulf.jpg','delta.jpg'];
INVBATCH={kind:'purchases',items:globalThis.__ORDER.map(n=>({name:n,file:mkfile(n),status:'waiting',rows:[],error:''})),
          i:0,stop:false,calls:0,done:false};
const p=batchRun();
INVBATCH.stop=true;            // pressed after the first is in flight
await p;
ck('stop halts the queue', INVBATCH.items.some(x=>x.status==='stopped'));
ck('...without spending on the rest', CALLS.length<4, String(CALLS.length));
ck('...and keeps whatever was already read', INVBATCH.items.some(x=>x.status==='ok'));

// ── the fingerprint ──
const m={supplier:0,total:1,date:2};
ck('same supplier, date and total = same paper',
   invoiceKey([['A','10','2026-01-01']],m)===invoiceKey([['a  ','10','2026-01-01']],m));
ck('a different total is a different invoice',
   invoiceKey([['A','10','2026-01-01']],m)!==invoiceKey([['A','11','2026-01-01']],m));
ck('a different date is a different invoice',
   invoiceKey([['A','10','2026-01-01']],m)!==invoiceKey([['A','10','2026-01-02']],m));
ck('multi-line totals are summed for the fingerprint',
   invoiceKey([['A','10','d'],['A','5','d']],m)==='a|d|15.00', invoiceKey([['A','10','d'],['A','5','d']],m));
ck('an empty invoice has no fingerprint', invoiceKey([],m)==='');

// ── UI ──
// The import screen shows the review table when one is staged, so clear it to
// see the upload list. (Test-only: this is what a fresh screen looks like.)
STAGE=null; view='import'; render(); const h=__store['app'].innerHTML;
ck('the batch button exists on purchases', /stageBatch\(this,'purchases'\)/.test(h));
ck('...accepting PDFs as well as photos', /accept="image\/\*,\.pdf"/.test(h));
ck('no batch button on the menu import', !/stageBatch\(this,'products'\)/.test(h));
ck('the panel reports paid calls', /paid call/.test(h));
ck('the panel reassures the import is reversible (auto-flow is one-click undoable)',
   /one-click undoable|Review first/i.test(h));
ck('no NaN', !/NaN/.test(h));
ck('batch recipes still work — BATCH() was not clobbered', typeof BATCH==='function');
console.log(F.length?('\n'+F.length+' FAILED: '+F.join(' | ')):'\nBATCH: ALL PASS');
})();
