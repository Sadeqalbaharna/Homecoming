let FG=[];const ck=(n,c,d='')=>{c?console.log('  PASS  '+n):(console.log('  FAIL  '+n+'  '+d),FG.push(n))};
SESSION={username:'owner',role:'owner'};WHO='owner';SETUP_DISMISSED=true;DATA.firstRunDone=true;
CELEBRATE=null;STAGE=null;CATPROP=null;CATSHOCK=null;
global.confirm=()=>true;

// ═══ 2. UNDO COVERS EVERYTHING, AND IMPORTS SNAPSHOT ═══
DATA.menu=[];DATA.ingredients=[];UNDO.length=0;
DATA.ledger={days:{'2026-05-01':{date:'2026-05-01',sales:100}},purchases:[]};
DATA.week={days:['2026-05-01','','','','','',''],salesByDay:[100,0,0,0,0,0,0],
  guests:[0,0,0,0,0,0,0],employees:[],purchases:[]};
rebuildIX();rebuildBX();
ck('undo covers the ledger', UNDOABLE.includes('ledger'));
ck('...the week', UNDOABLE.includes('week'));
ck('...wage rates', UNDOABLE.includes('rateBook'));
ck('...and stock counts', UNDOABLE.includes('countHistory'));

// a 90-day sales import, applied wrong
const rows=[];for(let d=0;d<90;d++)rows.push([dayAdd('2026-06-01',d),String(500+d),'50']);
STAGE={kind:'daily',headers:['Date','Sales','Covers'],rows,map:{date:0,sales:1,covers:2},headerRow:0};
stageApply();
ck('the import landed', ledgerDates().length===91, String(ledgerDates().length));
ck('...and took a snapshot first', UNDO.length===1);
ck('...labelled with what it was', /90 row\(s\)/.test(undoLabel()), undoLabel());
undo();
ck('UNDOING AN IMPORT RESTORES THE LEDGER', ledgerDates().length===1,
   String(ledgerDates().length));
ck('...and the week with it', WK().salesByDay[0]===100);

// menu import too
UNDO.length=0;
STAGE={kind:'products',headers:['Item','Price'],rows:[['A','5'],['B','6']],map:{name:0,price:1},headerRow:0};
stageApply();
ck('a menu import is undoable', DATA.menu.length===2&&UNDO.length===1);
undo();
ck('...and undoing removes the dishes', DATA.menu.length===0);
// Undo no longer asks for confirmation — it is reversible via redo now, so a
// confirm dialog was pure friction. Instead it pushes the current state onto
// the redo stack so nothing is lost either way.
UNDO.length=0;REDO.length=0;
editAs2('a change',()=>{DATA.menu=[{id:'z',name:'Z',menuPrice:1,lines:[],weeklySales:0,dept:'kitchen'}]});
undo();
ck('undo is instant and reversible', REDO.length===1);
ck('...redo brings it back', (redo(), (DATA.menu||[]).some(m=>m.name==='Z')));
UNDO.length=0;REDO.length=0;

// ═══ 3. A DUPLICATE INVOICE ACROSS UPLOADS ═══
DATA.ledger.purchases=[{id:'P1',supplier:'Gulf Foods',date:'2026-07-14',amount:55}];
ck('the same invoice is recognised from a previous upload',
   !!knownInvoice('Gulf Foods','14/7/2026',55));
ck('...whatever the date format', !!knownInvoice('gulf  foods','2026-07-14',55.004));
ck('a different total is a different invoice', !knownInvoice('Gulf Foods','2026-07-14',60));
ck('a different date is a different invoice', !knownInvoice('Gulf Foods','2026-07-15',55));
ck('a different supplier is a different invoice', !knownInvoice('Delta','2026-07-14',55));
ck('an unpriced or unnamed one is never matched',
   !knownInvoice('','2026-07-14',55)&&!knownInvoice('Gulf Foods','2026-07-14',0));

// ═══ 6. YIELD ═══
DATA.ingredients=[{id:'a',code:'001',name:'Beef',price:10,recipeUnit:'g-wt',ruPerPu:1000,
  purchaseUnit:'KG',yield:0}];
rebuildIX();
let imp=impossibleValues();
ck('a yield of 0 is flagged', imp.some(x=>/yield is 0%/.test(x.why)), imp.map(x=>x.why).join(' | '));
ck('...explaining what it silently did', imp.some(x=>/as if there were no waste at all/.test(x.why)));
DATA.ingredients[0].yield=1.4; rebuildIX();
ck('a yield above 100% is flagged', impossibleValues().some(x=>/more comes out than went in/.test(x.why)));
DATA.ingredients[0].yield=0.85; rebuildIX();
ck('a sensible yield is not flagged', !impossibleValues().some(x=>/yield/.test(x.why)));

// ═══ 7. CIRCULAR BATCH ═══
// A batch reference is 'B' + the batch id, not its code — BX is keyed that
// way. Using the code silently resolves to nothing, which is its own quiet
// failure: a dangling reference costs zero.
DATA.batch=[{id:'b1',code:'B1',name:'Sauce A',yieldQty:1000,yieldUnit:'ml',
  lines:[{ref:'Bb2',qty:100}]},
  {id:'b2',code:'B2',name:'Sauce B',yieldQty:1000,yieldUnit:'ml',
  lines:[{ref:'Bb1',qty:100}]}];
rebuildBX();
ck('a circular batch is detected', batchInCycle(DATA.batch[0])===true);
ck('...and costs NULL, not zero', batchCost(DATA.batch[0])===null,
   String(batchCost(DATA.batch[0])));
ck('...so it is never treated as free', batchCost(DATA.batch[0])!==0);
ck('the cycle is reported', impossibleValues().some(x=>/contains itself/.test(x.why)));
ck('...saying dishes become uncosted rather than cheap',
   impossibleValues().some(x=>/uncosted rather than cheap/.test(x.why)));
DATA.menu=[{id:'m',name:'Dish',menuPrice:9,weeklySales:1,dept:'kitchen',
  lines:[{ref:'Bb1',qty:50}]}];
ck('a dish using it is uncostable, not cheap', itemCost(DATA.menu[0])===null,
   String(itemCost(DATA.menu[0])));
// a normal nested batch still works
DATA.batch=[{id:'b1',code:'B1',name:'Stock',yieldQty:1000,yieldUnit:'ml',
  lines:[{ref:'001_Beef',qty:500}]},
  {id:'b2',code:'B2',name:'Sauce',yieldQty:500,yieldUnit:'ml',
  lines:[{ref:'Bb1',qty:200}]}];
DATA.ingredients=[{id:'a',code:'001',name:'Beef',price:10,recipeUnit:'g-wt',ruPerPu:1000,
  purchaseUnit:'KG',yield:1}];
rebuildIX();rebuildBX();
ck('a normal nested batch still costs', batchCost(DATA.batch[1])>0, String(batchCost(DATA.batch[1])));
ck('...at the right number', Math.abs(batchCost(DATA.batch[1])-1)<0.001, String(batchCost(DATA.batch[1])));

// ═══ 4. A PRICE THAT CANNOT BE RIGHT ═══
const ing={name:'Onion',price:0.45,history:[{at:1,price:0.45},{at:2,price:0.5}]};
ck('a decimal-point slip is caught', !!priceShock(ing,4.5));
ck('...saying what it looks like', /misread decimal point/.test(priceShock(ing,4.5).why));
ck('...with what you had paid', Math.abs(priceShock(ing,4.5).was-0.475)<0.001);
ck('a real 30% rise is NOT queried', !priceShock(ing,0.62));
ck('...nor a doubling, which is a real finding', !priceShock(ing,0.95));
ck('a collapse to a tenth is queried', !!priceShock(ing,0.04));
ck('an ingredient with no history is never queried', !priceShock({name:'New'},99));
ck('a zero or missing price is never queried', !priceShock(ing,0)&&!priceShock(ing,null));

// end to end: the sane ones apply, the mad one is held
DATA.ingredients=[{id:'o',code:'001',name:'Onion',price:0.45,recipeUnit:'kg',ruPerPu:1,pu:'kg',
  yield:1,history:[{at:1,price:0.45}]},
  {id:'c',code:'002',name:'Cashews',price:8,recipeUnit:'kg',ruPerPu:1,pu:'kg',yield:1,
  history:[{at:1,price:8}]}];
rebuildIX();
CATPROP=proposeCatalogue([
  {supplier:'S',date:'1/7/2026',item:'ONION 1KG',qty:10,unit:4.5,total:45},
  {supplier:'S',date:'1/7/2026',item:'CASHEWS 1KG',qty:5,unit:8.5,total:42.5}],
  {method:'latest',now:Date.parse('2026-07-20')});
const res=applyCatalogue(CATPROP);
ck('the plausible price is applied', DATA.ingredients.find(i=>/Cashew/i.test(i.name)).price===8.5,
   String(DATA.ingredients.find(i=>/Cashew/i.test(i.name)).price));
ck('the implausible one is HELD, not applied',
   DATA.ingredients.find(i=>/Onion/i.test(i.name)).price===0.45,
   String(DATA.ingredients.find(i=>/Onion/i.test(i.name)).price));
ck('...and reported', res.shocks.length===1&&/Onion/.test(res.shocks[0].name));
view='catalogue'; CATSHOCK=res.shocks; render();
const h=__store['app'].innerHTML;
ck('the held price is shown on screen', /look wrong/.test(h)&&/Onion/.test(h));
ck('...with both numbers', /0\.450/.test(h)&&/4\.500/.test(h));
ck('...and a way to say the invoice is right', /shockAccept\(\)/.test(h));
ck('no NaN', !/NaN/.test(h));
console.log(FG.length?('\n'+FG.length+' FAILED: '+FG.join(' | ')):'\nGUARDS: ALL PASS');
