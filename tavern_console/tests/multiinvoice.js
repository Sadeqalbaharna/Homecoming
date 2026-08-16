let FM=[];const ck=(n,c,d='')=>{c?console.log('  PASS  '+n):(console.log('  FAIL  '+n+'  '+d),FM.push(n))};
SESSION={username:'owner',role:'owner'};WHO='owner';SETUP_DISMISSED=true;DATA.firstRunDone=true;
CELEBRATE=null;STAGE=null;
DATA.ai={provider:'anthropic',key:'k',enabled:true,calls:0,ledger:[],auth:[],limits:null};

// ═══ ONE FILE, MANY INVOICES ═══
const twoInvoices=[
 {supplier:'Gulf Foods',date:'2026-05-10',invoiceNo:'A1',pages:'1',
  items:[{item:'BLACK OLIVES 2.5KG TIN',qty:4,unit:12.5,total:50}]},
 {supplier:'Delta Trading',date:'2026-07-12',invoiceNo:'B7',pages:'2-3',
  items:[{item:'BLACK OLIVES 1KG JAR',qty:10,unit:5.5,total:55},
         {item:'WATER 12 X 1L CASE',qty:20,unit:2.4,total:48}]}];
let inv=normaliseInvoices(twoInvoices);
ck('two invoices in one file stay two', inv.length===2);
ck('...each with its own supplier', inv[0].supplier==='Gulf Foods'&&inv[1].supplier==='Delta Trading');
ck('...its own date', inv[1].date==='2026-07-12');
ck('...and its page range', inv[1].pages==='2-3');

// the old flat shape still works
inv=normaliseInvoices([
 {supplier:'Gulf Foods',date:'2026-05-10',item:'A',qty:1,unit:2,total:2},
 {supplier:'Gulf Foods',date:'2026-05-10',item:'B',qty:1,unit:3,total:3},
 {supplier:'Delta Trading',date:'2026-07-12',item:'C',qty:1,unit:4,total:4}]);
ck('a flat answer is grouped by supplier and date', inv.length===2, String(inv.length));
ck('...keeping both lines of the first', inv[0].items.length===2);
ck('rubbish yields nothing', normaliseInvoices([null,'x',7]).length===0);
ck('empty yields nothing', normaliseInvoices([]).length===0&&normaliseInvoices(null).length===0);

(async()=>{
// ═══ THROUGH THE BATCH, END TO END ═══
DATA.ingredients=[];DATA.suppliers=[];DATA.ledger={days:{},purchases:[]};
const mkfile=n=>({name:n,type:'application/pdf',size:1000,
  arrayBuffer:async()=>new ArrayBuffer(8)});
shrinkImage=async()=>({dataUrl:'data:image/jpeg;base64,AAA',data:'AAA',w:800,h:1000,page:1});
keepDoc=async(f,k)=>({id:'d1',name:f.name,where:'browser'});
globalThis.fetch=async()=>({ok:true,status:200,json:async()=>({
  stop_reason:'end_turn',usage:{},
  content:[{type:'text',text:JSON.stringify({invoices:twoInvoices})}]})});
INVBATCH={kind:'purchases',items:[{name:'scan.pdf',file:mkfile('scan.pdf'),status:'waiting',rows:[],error:''}],
  i:0,stop:false,calls:0,done:false};
await batchRun();
const it=INVBATCH.items[0];
ck('one upload produced two invoices', (it.invoices||[]).length===2, String((it.invoices||[]).length));
ck('...and three line rows', it.rows.length===3, String(it.rows.length));
ck('...on ONE paid call', INVBATCH.calls===1);
ck('...noted on screen', /2 separate invoices/.test(it.note||''), it.note||'');

// THE FAILURE THAT MATTERS: supplier must not bleed across invoices
const sup=it.rows.map(r=>r[it.map.supplier]);
ck('each row keeps its OWN supplier', sup.filter(s=>s==='Gulf Foods').length===1
   && sup.filter(s=>s==='Delta Trading').length===2, JSON.stringify(sup));
const dts=it.rows.map(r=>r[it.map.date]);
ck('...and its own date', dts.filter(d=>d==='2026-05-10').length===1, JSON.stringify(dts));
ck('the prompt forbids carrying a supplier across',
   /NEVER carry a supplier name or a date from one invoice onto another/.test(PHOTO_KINDS.purchases.prompt));
ck('...and tells it to start a new invoice when unsure',
   /start a new one/.test(PHOTO_KINDS.purchases.prompt));

// and it still builds a catalogue from the lot
STAGE=null; batchCollect();
ck('all three lines land in one review table', STAGE&&STAGE.rows.length===3);
const prop=proposeCatalogue(STAGE.rows.map(r=>({supplier:r[STAGE.map.supplier],date:r[STAGE.map.date],
  item:r[STAGE.map.item],qty:+r[STAGE.map.qty],unit:+r[STAGE.map.unit],total:+r[STAGE.map.total]})),
  {method:'wavg',now:Date.parse('2026-07-20')});
ck('olives from both invoices merge into one ingredient',
   prop.items.filter(i=>/olive/i.test(i.name)).length===1);
ck('...priced across both suppliers', prop.items.find(i=>/olive/i.test(i.name)).suppliers.length===2);

// ═══ COVERAGE — WHAT IS STILL WORTH PHOTOGRAPHING ═══
DATA.ledger={days:{},purchases:[]};
DATA.ingredients=[{id:'a',name:'X',price:5,recipeUnit:'kg',ruPerPu:1,pu:'kg',yield:1,
  history:[{at:Date.parse('2026-07-01'),price:5,supplier:'Gulf Foods'}]}];
let C=invoiceCoverage();
ck('one invoice from a supplier is "thin"', C.suppliers[0].state==='thin');
ck('...and it says what is missing', /older invoice/.test(C.suppliers[0].need));
DATA.ingredients[0].history.push({at:Date.parse('2026-04-01'),price:4,supplier:'Gulf Foods'});
C=invoiceCoverage();
ck('two invoices two months apart is enough', C.suppliers[0].state==='good', C.suppliers[0].state);
ck('...and nothing more is asked for', C.suppliers[0].need==='');
ck('...counted as covered', C.good===1&&C.thin===0);
DATA.ingredients[0].history.push({at:Date.parse('2026-07-02'),price:5,supplier:'Fine Foods'});
C=invoiceCoverage();
ck('a second supplier is tracked separately', C.suppliers.length===2);
ck('...and the one needing work is listed first', C.suppliers[0].state==='thin');
// two invoices a day apart give a price but no drift
DATA.ingredients[0].history=[{at:Date.parse('2026-07-01'),price:5,supplier:'A'},
                             {at:Date.parse('2026-07-02'),price:5,supplier:'A'}];
C=invoiceCoverage();
ck('two invoices from the same week are still thin', C.suppliers[0].state==='thin',
   C.suppliers[0].state+' span '+C.suppliers[0].spanDays);

// ═══ THE STEP SAYS THE RIGHT THING ═══
const s=SETUP_STEPS.find(x=>x.id==='invoices');
ck('the step no longer demands three months of everything',
   !/last three months/.test(s.line), s.line);
ck('...it asks for two per supplier', /Two invoices per supplier/.test(s.line));
ck('...and explains why that is enough', /Twelve documents does almost everything/.test(s.why));
ck('...and mentions the scanned-folder route', /finds where each invoice starts/.test(s.longer));
// Put the flow ON the invoices step: menu and sales done, daily and hours
// skipped (they now sit between sales and invoices in the flow), prices not yet.
DATA.setup={name:'x',done:false,started:true,skipped:{daily:1,hours:1},breakSeen:{invoices:1}};SETUP_DISMISSED=false;
DATA.menu=[{id:'m',name:'A',menuPrice:5,weeklySales:1,dept:'kitchen',lines:[]}];
DATA.ingredients=[{id:'a',name:'X',price:0,recipeUnit:'kg',ruPerPu:1,pu:'kg',yield:1,
  history:[{at:Date.parse('2026-07-01'),price:5,supplier:'Gulf Foods'}]}];
rebuildIX();
view='today';render();
const h=__store['app'].innerHTML;
ck('the flow is on the invoices step', /The invoices/.test(h), (h.match(/<h1>[^<]*/)||[])[0]||'');
ck('...showing supplier coverage', /Where you are/.test(h));
ck('...naming the supplier', /Gulf Foods/.test(h));
ck('...and what it still needs', /needs one older invoice/.test(h));
ck('no NaN', !/NaN/.test(h));
console.log(FM.length?('\n'+FM.length+' FAILED: '+FM.join(' | ')):'\nMULTI-INVOICE: ALL PASS');
})();