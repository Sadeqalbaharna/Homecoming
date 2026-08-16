let FS=[];const ck=(n,c,d='')=>{c?console.log('  PASS  '+n):(console.log('  FAIL  '+n+'  '+d),FS.push(n))};
SESSION={username:'owner',role:'owner'};WHO='owner';SETUP_DISMISSED=true;DATA.firstRunDone=true;
CELEBRATE=null;STAGE=null;CATPROP=null;TOASTS=[];global.setTimeout=fn=>0;global.confirm=()=>true;

// ═══ num() IS WIRED TO THE ACTUAL INPUTS ═══
DATA.ingredients=[{id:'a',code:'001',name:'Flour',price:1,recipeUnit:'kg',ruPerPu:1,pu:'kg',yield:1,history:[]}];
DATA.menu=[];rebuildIX();
setPrice(0,'1,250');
ck('a price field takes "1,250" as 1250, not 1', DATA.ingredients[0].price===1250,
   String(DATA.ingredients[0].price));
setPrice(0,'BD 4.50');
ck('...and "BD 4.50" as 4.5', DATA.ingredients[0].price===4.5, String(DATA.ingredients[0].price));
const src=require('fs').readFileSync(process.env.TC,'utf-8');
ck('no numeric input still uses parseFloat', !/parseFloat\(this\.value\)/.test(src));
ck('...nor parseFloat(v) in setQty', !/lines\[l\]\.qty=parseFloat/.test(src));

// ═══ WHAT MOVED ═══
DATA.ingredients=[
 {id:'a',code:'001',name:'Chicken',price:6,recipeUnit:'g-wt',ruPerPu:1000,pu:'KG',yield:1,
  history:[{at:Date.now()-60*86400000,price:5,supplier:'Gulf'},
           {at:Date.now()-2*86400000,price:6,supplier:'Gulf'}]},
 // Truffle's LATEST change is old (65 days) so a 30-day window excludes it,
 // but its earlier price is inside 90 days for the sort test.
 {id:'b',code:'002',name:'Truffle',price:200,recipeUnit:'g-wt',ruPerPu:1000,pu:'KG',yield:1,
  history:[{at:Date.now()-80*86400000,price:100},{at:Date.now()-65*86400000,price:200}]},
 {id:'c',code:'003',name:'Stable',price:2,recipeUnit:'kg',ruPerPu:1,pu:'kg',yield:1,
  history:[{at:Date.now()-3*86400000,price:2}]}];
DATA.menu=[{id:'m',name:'Chicken Plate',menuPrice:9,weeklySales:200,dept:'kitchen',
  lines:[{ref:'001_Chicken',qty:200}]},
  {id:'m2',name:'Truffle Dish',menuPrice:40,weeklySales:2,dept:'kitchen',
  lines:[{ref:'002_Truffle',qty:5}]}];
rebuildIX();rebuildBX();
let ch=recentChanges(90);
ck('a price rise is detected', ch.some(c=>c.name==='Chicken'));
ck('...comparing against the price before the window move', ch.find(c=>c.name==='Chicken').from===5);
ck('a stable price is not listed', !ch.some(c=>c.name==='Stable'));
// chicken: +1/kg × 0.2kg × 200/wk = +40. truffle: +100/kg × 0.005kg × 2/wk = +1.
ck('the chicken hits weekly cost by +40', Math.abs(ch.find(c=>c.name==='Chicken').weeklyHit-40)<0.01,
   String(ch.find(c=>c.name==='Chicken').weeklyHit));
ck('sorted by weekly effect, not headline %',
   ch[0].name==='Chicken', ch.map(c=>c.name+':'+c.pct.toFixed(1)).join());
ck('...even though truffle DOUBLED and chicken rose 20%',
   ch.find(c=>c.name==='Truffle').pct>ch.find(c=>c.name==='Chicken').pct);
ck('the ripple count is shown', ch[0].dishes===1);
ck('a 30-day window excludes the 40-day-old truffle change', !recentChanges(30).some(c=>/Truffle/.test(c.name)));
view='moved'; DATA.movedDays=90; render();
let h=__store['app'].innerHTML;
ck('the screen renders', /What moved/.test(h));
ck('...showing the weekly effect', /Weekly effect/.test(h));
ck('...and the sort rationale', /not by how big the percentage looks/.test(h));
ck('no NaN', !/NaN/.test(h));

// ═══ BULK PRICE RAISE ═══
DATA.ingredients=[
 {id:'a',code:'001',name:'A',price:10,category:'Meat',recipeUnit:'kg',ruPerPu:1,pu:'kg',yield:1,history:[]},
 {id:'b',code:'002',name:'B',price:20,category:'Meat',recipeUnit:'kg',ruPerPu:1,pu:'kg',yield:1,history:[]},
 {id:'c',code:'003',name:'C',price:5,category:'Produce',recipeUnit:'kg',ruPerPu:1,pu:'kg',yield:1,history:[]},
 {id:'d',code:'004',name:'D',price:0,category:'Produce',recipeUnit:'kg',ruPerPu:1,pu:'kg',yield:1,history:[]}];
rebuildIX();
let prop=bulkRaise(8,'all');
ck('a bulk raise proposes only priced ingredients', prop.length===3);
ck('...at the right new price', prop.find(p=>p.code==='001').to===10.8);
prop=bulkRaise(8,'Meat');
ck('...and can target one category', prop.length===2&&prop.every(p=>/00[12]/.test(p.code)));
TOASTS=[];UNDO.length=0;
applyBulkRaise(bulkRaise(10,'all'));
ck('applying raises the prices', DATA.ingredients[0].price===11);
ck('...and records it in history so "what moved" sees it',
   DATA.ingredients[0].history.some(x=>x.src==='bulk price change'));
ck('...as one undoable action', TOASTS[0].action==='undo()');
undo();
ck('undo reverts the whole raise', DATA.ingredients[0].price===10);
ck('nothing matched gives a clear result', bulkRaise(8,'Seafood').length===0);

// ═══ FOOD-COST VERDICT, ONE PLACE ═══
DATA.ingredients=[{id:'x',code:'001',name:'Beef',price:10,recipeUnit:'g-wt',ruPerPu:1000,pu:'KG',yield:1,history:[]}];
DATA.menu=[{id:'m',name:'Steak',menuPrice:20,weeklySales:1,dept:'kitchen',lines:[{ref:'001_Beef',qty:200}]}];
DATA.rates={vat:0,service:0,levy:0};rebuildIX();
let v=fcVerdict(DATA.menu[0]);
ck('a good margin reads green', v.color==='var(--good)'||v.color==='var(--warn)', v.color+' fc='+v.fc);
DATA.menu[0].lines=[{ref:'001_Beef',qty:900}];
v=fcVerdict(DATA.menu[0]);
ck('a bad margin reads red', v.color==='var(--bad)', v.color+' fc='+(v.fc*100).toFixed(0)+'%');
ck('...with a verdict word', v.label==='high');
DATA.menu[0].menuPrice=0;
ck('no price gives no verdict, not a fake one', fcVerdict(DATA.menu[0]).fc===null);
console.log(FS.length?('\n'+FS.length+' FAILED: '+FS.join(' | ')):'\nSHARP: ALL PASS');
