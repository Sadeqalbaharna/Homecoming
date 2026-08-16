let F=[];const ck=(n,c,d='')=>{c?console.log('  PASS  '+n):(console.log('  FAIL  '+n+'  '+d),F.push(n))};
SESSION={username:'owner',role:'owner'};WHO='owner';DATA.firstRunDone=true;

// ═══ PACK SIZES ═══
const p=s=>parsePack(s);
ck('2.5KG', p('BLACK OLIVES 2.5KG TIN').total===2.5);
ck('500g becomes 0.5kg', p('BUTTER 500G').total===0.5);
ck('1L', p('OLIVE OIL 1L').total===1);
ck('750ml becomes 0.75l', p('VINEGAR 750ML').total===0.75);
// the one that matters: a multiplier pack
const mx=p('WATER 12 X 1L CASE');
ck('12 x 1L is twelve litres, not one', mx&&mx.total===12, JSON.stringify(mx));
ck('...and remembers it was 12 packs', mx.packs===12&&mx.size===1);
ck('6X500G with no spaces', p('YOGHURT 6X500G').total===3, JSON.stringify(p('YOGHURT 6X500G')));
ck('a multiplication sign works too', p('JUICE 24 × 250ML').total===6);
ck('spelled-out units', p('FLOUR 25 KILOS').total===25);
ck('gm is grams', p('SAFFRON 10 GM').total===0.01);
ck('LTR is litres', p('MILK 2 LTR').total===2);
ck('a dozen is twelve each', p('EGGS 1 DOZEN').total===12);
ck('pieces', p('CHICKEN BREAST 10 PCS').total===10);
ck('lb converts', Math.abs(p('BEEF 5LB').total-2.26796)<0.001);
ck('a description with no size returns nothing', p('MIXED HERBS')===null);
ck('a zero size is refused', p('OLIVES 0KG')===null);
ck('grams and litres are different families',
   p('X 500G').base==='kg'&&p('Y 500ML').base==='l');

// ═══ IDENTITY ═══
const c=canonicalName;
ck('pack size does not affect identity',
   c('BLACK OLIVES 2.5KG TIN')===c('BLACK OLIVES 1KG JAR'), c('BLACK OLIVES 2.5KG TIN'));
ck('an abbreviation resolves', c('BLK OLIVE 1KG')===c('BLACK OLIVES 2.5KG'), c('BLK OLIVE 1KG'));
ck('packaging words are noise', c('TOMATO PASTE 1KG TIN')===c('TOMATO PASTE 400G CAN'));
ck('word order does not matter', c('OLIVES BLACK 1KG')===c('BLACK OLIVES 1KG'));
ck('case does not matter', c('black olives 1kg')===c('BLACK OLIVES 1KG'));
ck('brackets are dropped', c('OLIVES (SPANISH) 1KG')===c('OLIVES 1KG'));

// THE ONE THAT MATTERS: things that differ must NOT merge
ck('pitted and unpitted stay apart', c('OLIVES PITTED 1KG')!==c('OLIVES 1KG'));
ck('smoked and plain stay apart', c('SALMON SMOKED 1KG')!==c('SALMON 1KG'));
ck('organic stays apart', c('MILK ORGANIC 1L')!==c('MILK 1L'));
ck('breast and thigh stay apart', c('CHICKEN BREAST 1KG')!==c('CHICKEN THIGH 1KG'));
ck('frozen and fresh stay apart', c('PEAS FROZEN 1KG')!==c('PEAS FRESH 1KG'));

// ═══ THE PROPOSAL ═══
const D=(y,m,d)=>`${d}/${m}/${y}`;
const lines=[
  // same substance, two suppliers, two pack sizes, three months
  {supplier:'Gulf Foods',   date:D(2026,5,10), item:'BLACK OLIVES 2.5KG TIN', qty:4, unit:12.5,total:50},
  {supplier:'Delta Trading',date:D(2026,6,12), item:'BLK OLIVE 1KG JAR',      qty:10,unit:5.5, total:55},
  {supplier:'Gulf Foods',   date:D(2026,7,14), item:'BLACK OLIVES 2.5KG TIN', qty:4, unit:13.75,total:55},
  // a genuinely different product
  {supplier:'Gulf Foods',   date:D(2026,7,14), item:'OLIVES PITTED 1KG JAR',  qty:6, unit:6,   total:36},
  // multiplier pack
  {supplier:'Delta Trading',date:D(2026,7,15), item:'WATER 12 X 1L CASE',     qty:20,unit:2.4, total:48},
  // unparseable
  {supplier:'Corner Shop',  date:D(2026,7,16), item:'MISC KITCHEN',           qty:1, unit:9,   total:9},
  // no price
  {supplier:'Gulf Foods',   date:D(2026,7,16), item:'SALT 1KG',               qty:2, unit:0,   total:0},
];
let r=proposeCatalogue(lines,{method:'wavg',now:Date.parse('2026-07-20')});

ck('suppliers are collected', r.suppliers.length===3, r.suppliers.join());
ck('...deduplicated', r.suppliers.filter(s=>s==='Gulf Foods').length===1);
const olive=r.items.find(i=>/black/i.test(i.name));
ck('two suppliers and two pack sizes become ONE ingredient', !!olive&&olive.variants.length===3,
   olive&&olive.variants.length);
ck('...with both suppliers recorded', olive.suppliers.length===2, olive.suppliers.join());
ck('...and both pack sizes recorded', olive.packs.length===2, olive.packs.join());
ck('...costed per kilo', olive.unit==='kg');
ck('pitted olives stay a SEPARATE ingredient', r.items.some(i=>/pitted/i.test(i.name)));
ck('...so nothing merged that should not have', r.items.filter(i=>/olive/i.test(i.name)).length===2);

// the arithmetic, by hand:
//  Gulf 10/5: 4 tins x 2.5kg = 10kg at 12.5/tin = 5.00/kg
//  Delta 12/6: 10 jars x 1kg = 10kg at 5.5/jar  = 5.50/kg
//  Gulf 14/7: 4 tins x 2.5kg = 10kg at 13.75    = 5.50/kg
//  weighted:  (10*5 + 10*5.5 + 10*5.5)/30       = 5.3333/kg
ck('weighted average is weighted by QUANTITY, not by line',
   Math.abs(olive.price-5.3333)<0.001, String(olive.price));
const latest=proposeCatalogue(lines,{method:'latest',now:Date.parse('2026-07-20')})
  .items.find(i=>/black/i.test(i.name));
ck('latest takes the most recent price', Math.abs(latest.price-5.5)<0.001, String(latest.price));
ck('...and says when and from whom', /2026-07-14/.test(latest.basis)&&/Gulf/.test(latest.basis), latest.basis);
const fifo=proposeCatalogue(lines,{method:'fifo',now:Date.parse('2026-07-20')})
  .items.find(i=>/black/i.test(i.name));
ck('FIFO takes the oldest layer', Math.abs(fifo.price-5)<0.001, String(fifo.price));
ck('...and admits it is an assumption, not a measurement', fifo.assumed===true);
ck('...saying why in plain words', /policy rather than a measurement/.test(fifo.basis));

const water=r.items.find(i=>/water/i.test(i.name));
ck('a 12x1L case is costed per litre, not per case',
   Math.abs(water.price-0.2)<0.0001, String(water.price));

ck('a line with no pack size is skipped, not guessed',
   r.skipped.some(s=>/MISC KITCHEN/.test(s.desc||'')));
ck('...and says why', /no pack size/.test(r.skipped.find(s=>/MISC/.test(s.desc||'')).why));
ck('a line with no price is skipped', r.skipped.some(s=>/SALT/.test(s.desc||'')));
// Rescue: the same no-pack line, given a pack size, is placed instead of skipped.
// (In the app the pack rides in on unitDesc from STAGE.fix; here we supply it directly.)
const rescued=proposeCatalogue([
  {item:'MISC KITCHEN',unitDesc:'5kg',qty:1,unit:9,total:9},
  {item:'LOOSE TOMATOES',unitDesc:'1 ea',qty:1,unit:0,total:4.5}],{now:Date.parse('2026-07-20')});
ck('a no-pack line is rescued once a pack size is supplied',
   rescued.items.some(i=>/misc kitchen/i.test(i.name)) && !rescued.skipped.some(s=>/MISC/.test(s.desc||'')));
ck('...costed per kilo from the supplied pack', (()=>{const it=rescued.items.find(i=>/misc/i.test(i.name));return it&&it.unit==='kg';})());
ck('...and "count as each" places a unit-priced line', (()=>{const it=rescued.items.find(i=>/tomato/i.test(i.name));return !!it&&it.unit==='ea';})());
// The reference build has a real book in it, so "empty" is the wrong test —
// what matters is that PROPOSING changed nothing.
const ingsBefore=(DATA.ingredients||[]).length;
proposeCatalogue(lines,{now:Date.parse('2026-07-20')});
ck('proposing writes nothing to the book', (DATA.ingredients||[]).length===ingsBefore);

// a suspicious merge gets flagged rather than silently averaged
const odd=proposeCatalogue([
  {supplier:'A',date:D(2026,7,1),item:'SAFFRON 10G',qty:1,unit:2,total:2},
  {supplier:'B',date:D(2026,7,2),item:'SAFFRON 10G',qty:1,unit:40,total:40},
],{now:Date.parse('2026-07-20')});
ck('a wild price spread is flagged for a human', !!odd.items[0].flag, odd.items[0].flag);

// window behaviour
const old=proposeCatalogue(lines,{method:'wavg',windowDays:5,now:Date.parse('2026-12-01')});
const oi=old.items.find(i=>/black/i.test(i.name));
ck('an empty window falls back to everything rather than returning zero', oi.price>0);
ck('...and says so', /none inside the window/.test(oi.basis), oi.basis);

// ═══ APPLYING ═══
DATA.ingredients=[]; DATA.suppliers=[];
const res=applyCatalogue(r);
ck('applying writes the ingredients', DATA.ingredients.length===res.added&&res.added>0, JSON.stringify(res));
ck('...and the suppliers', DATA.suppliers.length===3);
ck('...with price history for drift detection',
   DATA.ingredients.find(i=>/black/i.test(i.name)).history.length===3);
ck('...and the recipe unit set', DATA.ingredients.every(i=>i.ru&&i.ruPerPu>0));
ck('...and every one priced', DATA.ingredients.every(i=>i.price>0));
const before=DATA.ingredients.length;
applyCatalogue(r);
ck('applying twice updates rather than duplicating', DATA.ingredients.length===before);
r.items.forEach(i=>i.accept=false);
DATA.ingredients=[]; applyCatalogue(r);
ck('unticked items are not written', DATA.ingredients.length===0);
console.log(F.length?('\n'+F.length+' FAILED: '+F.join(' | ')):'\nCATALOGUE: ALL PASS');

// ═══ DATE AMBIGUITY — the bug that made a June invoice the newest ═══
(function(){
 let G=[];const ck2=(n,c,d='')=>{c?console.log('  PASS  '+n):(console.log('  FAIL  '+n+'  '+d),G.push(n))};
 const iso=t=>new Date(t).toISOString().slice(0,10);
 ck2('12/6/2026 is 12 June, not 6 December', iso(parseDate('12/6/2026'))==='2026-06-12', iso(parseDate('12/6/2026')));
 ck2('01/02/2026 is 1 February', iso(parseDate('01/02/2026'))==='2026-02-01');
 ck2('14/7/2026 is 14 July', iso(parseDate('14/7/2026'))==='2026-07-14');
 ck2('dashes work the same way', iso(parseDate('12-6-2026'))==='2026-06-12');
 ck2('dots too', iso(parseDate('12.6.2026'))==='2026-06-12');
 ck2('a two-digit year', iso(parseDate('12/6/26'))==='2026-06-12');
 ck2('ISO is respected as ISO', iso(parseDate('2026-06-12'))==='2026-06-12');
 ck2('an American export where the day cannot be a month still reads right',
     iso(parseDate('7/14/2026'))==='2026-07-14', iso(parseDate('7/14/2026')));
 ck2('a textual date works', iso(parseDate('14 Jul 2026'))==='2026-07-14');
 ck2('an impossible date returns nothing rather than a wrong one', parseDate('45/13/2026')===0);
 ck2('empty is nothing', parseDate('')===0&&parseDate(null)===0);
 console.log(G.length?('\n'+G.length+' DATE FAILED: '+G.join(' | ')):'DATES: ALL PASS');
})();
(function(){
 const iso=t=>new Date(t).toISOString().slice(0,10);
 const all=['12/6/2026','2026-06-12','14 Jul 2026','7/14/2026'].map(parseDate);
 const ok=all.every(t=>t%86400000===0);
 console.log(ok?'  PASS  every date path returns UTC midnight, so none can drift a day'
               :'  FAIL  mixed date anchoring: '+all.map(iso).join(', '));
})();

// ═══ THE REVIEW SCREEN ═══
(function(){
 let G=[];const ck2=(n,c,d='')=>{c?console.log('  PASS  '+n):(console.log('  FAIL  '+n+'  '+d),G.push(n))};
 SESSION={username:'owner',role:'owner'};WHO='owner';DATA.firstRunDone=true;
 DATA.ingredients=[];DATA.suppliers=[];DATA.costMethod='wavg';
 // stage invoice rows exactly as the batch importer leaves them
 const spec=IMPORT_KINDS.purchases, keys=spec.fields.map(f=>f.k);
 const row=o=>keys.map(k=>o[k]!==undefined?String(o[k]):'');
 STAGE={kind:'purchases',headers:spec.fields.map(f=>f.label),
   map:Object.fromEntries(keys.map((k,i)=>[k,i])),
   rows:[row({supplier:'Gulf Foods',date:'10/5/2026',item:'BLACK OLIVES 2.5KG TIN',qty:4,unit:12.5,total:50}),
         row({supplier:'Delta Trading',date:'12/6/2026',item:'BLK OLIVE 1KG JAR',qty:10,unit:5.5,total:55}),
         row({supplier:'Delta Trading',date:'15/7/2026',item:'WATER 12 X 1L CASE',qty:20,unit:2.4,total:48}),
         row({supplier:'Corner Shop',date:'16/7/2026',item:'MISC KITCHEN',qty:1,unit:9,total:9})]};
 buildCatalogue();
 ck2('the button opens the proposal', view==='catalogue'&&!!CATPROP);
 render(); let h=__store['app'].innerHTML;
 ck2('it says nothing has been written', /Nothing has been written yet/.test(h));
 ck2('olives from two suppliers show as one ingredient', /Black Olives/i.test(h));
 ck2('...listing both suppliers', /Gulf Foods/.test(h)&&/Delta Trading/.test(h));
 ck2('...and both pack sizes', /2\.5kg/.test(h)&&/1kg/.test(h));
 ck2('a per-unit cost is shown', /per kg/.test(h));
 ck2('the pricing method can be changed', /catMethod\('fifo'\)/.test(h));
 ck2('...and FIFO is described as an assumption', /not a measurement/.test(h));
 ck2('the skipped line is shown with its reason', /MISC KITCHEN/.test(h)&&/no pack size/.test(h));
 ck2('every purchase behind a price can be opened', /catExpand\(0\)/.test(h));
 catExpand(0); render(); h=__store['app'].innerHTML;
 ck2('...showing the individual invoice lines', /BLACK OLIVES 2\.5KG TIN/.test(h));
 ck2('...with the date read day-first', /2026-05-10/.test(h), (h.match(/2026-\d\d-\d\d/g)||[]).join());
 ck2('...and the per-unit maths for each', /5\.000/.test(h));
 ck2('no NaN', !/NaN/.test(h));
 ck2('nothing written until Add is pressed', DATA.ingredients.length===0);
 const n=CATPROP.items.length; catToggle(0);
 ck2('an item can be untick    ed', CATPROP.items[0].accept===false);
 catToggle(0); catApply();
 ck2('applying writes them', DATA.ingredients.length===n, DATA.ingredients.length+' of '+n);
 ck2('...and the suppliers', DATA.suppliers.length===3);
 ck2('...and returns you to the ingredients screen', view==='ing');
 console.log(G.length?('\n'+G.length+' UI FAILED: '+G.join(' | ')):'CATALOGUE UI: ALL PASS');
})();
// Every view the code can navigate to must be registered as BUILT, or the
// "not built yet" guard swallows it — which is what happened to this screen.
(function(){
 const views=[...new Set((function(){
   const out=[];const re=/view='([a-z]+)'/g;let m;
   const src=require('fs').readFileSync(process.env.TC,'utf-8');
   while((m=re.exec(src)))out.push(m[1]);return out})())];
 const missing=views.filter(v=>!BUILT.has(v));
 console.log(missing.length?('  FAIL  unregistered views: '+missing.join(', '))
   :'  PASS  every view the code navigates to is registered as built');
})();

// ═══ THE NAME MUST NOT NAME ONE OF SEVERAL PACKS ═══
(function(){
 let G=[];const ck2=(n,c,d='')=>{c?console.log('  PASS  '+n):(console.log('  FAIL  '+n+'  '+d),G.push(n))};
 const dn=displayName;
 ck2('the pack size is stripped', dn(['BLACK OLIVES 2.5KG TIN'])==='Black Olives', dn(['BLACK OLIVES 2.5KG TIN']));
 ck2('a mixed group is named for the substance',
     dn(['BLACK OLIVES 1KG JAR','BLACK OLIVES 2.5KG TIN'])==='Black Olives',
     dn(['BLACK OLIVES 1KG JAR','BLACK OLIVES 2.5KG TIN']));
 ck2('a multiplier pack is stripped', dn(['WATER 12 X 1L CASE'])==='Water', dn(['WATER 12 X 1L CASE']));
 ck2('QUALIFIERS SURVIVE — they are why it stayed separate',
     dn(['OLIVES PITTED 1KG JAR'])==='Olives Pitted', dn(['OLIVES PITTED 1KG JAR']));
 ck2('...and the longest description wins, so none are lost',
     dn(['SALMON 1KG','SALMON SMOKED SLICED 1KG'])==='Salmon Smoked Sliced');
 ck2('packaging words go', !/tin|jar|case/i.test(dn(['TOMATO PASTE 400G TIN'])));
 ck2('a name with no pack survives untouched', dn(['MIXED HERBS'])==='Mixed Herbs');
 ck2('an unnameable line still gets something', dn(['500G'])!=='');
 ck2('apostrophes and hyphens survive', dn(["CHEF'S SELECTION HALF-FAT 1KG"])==="Chef's Selection Half-Fat");

 // and the price is still per kg
 const r=proposeCatalogue([
   {supplier:'Fine Foods', date:'10/6/2026',item:'BLACK OLIVES 1KG JAR',  qty:6,unit:5,total:30},
   {supplier:'Hasan Habib',date:'12/7/2026',item:'BLACK OLIVES 2.5KG TIN',qty:4,unit:9,total:36},
 ],{method:'wavg',now:Date.parse('2026-07-20')});
 ck2('the merged name is clean', r.items[0].name==='Black Olives', r.items[0].name);
 ck2('the price is still per kg', r.items[0].unit==='kg');
 ck2('...and unchanged by the rename', Math.abs(r.items[0].price-4.125)<0.001, String(r.items[0].price));
 ck2('...with both packs still listed against it', r.items[0].packs.length===2, r.items[0].packs.join());
 console.log(G.length?('\n'+G.length+' NAME FAILED: '+G.join(' | ')):'NAMES: ALL PASS');
})();

// ═══ RECEIPTS AUTO-CATEGORISE ═══
(function(){
 let G=[];const ck2=(n,c,d='')=>{c?console.log('  PASS  '+n):(console.log('  FAIL  '+n+'  '+d),G.push(n))};
 SESSION={username:'owner',role:'owner'};WHO='owner';SETUP_DISMISSED=true;DATA.firstRunDone=true;
 DATA.ingredients=[];DATA.suppliers=[];rebuildIX();
 // an invoice with NO category column — should infer from the starter catalogue
 let prop=proposeCatalogue([
   {supplier:'Gulf',date:'1/7/2026',item:'CHICKEN BREAST 2KG',qty:5,unit:8,total:40},
   {supplier:'Gulf',date:'1/7/2026',item:'POTATO 10KG',qty:2,unit:4,total:8},
   {supplier:'Gulf',date:'1/7/2026',item:'ZORBLAX WIDGET 1KG',qty:1,unit:9,total:9}],
   {method:'latest',now:Date.parse('2026-07-20')});
 const cat=n=>prop.items.find(i=>new RegExp(n,'i').test(i.name));
 ck2('chicken is inferred as Meat', cat('chicken').category==='Meat', cat('chicken').category);
 ck2('potato is inferred as Produce', cat('potato').category==='Produce', cat('potato').category);
 ck2('an unknown item is left blank, not mis-filed', cat('zorblax').category==='',
     cat('zorblax').category);
 // an invoice WITH a category column — trust it over the guess
 prop=proposeCatalogue([
   {supplier:'Gulf',date:'1/7/2026',item:'CHICKEN BREAST 2KG',qty:5,unit:8,total:40,cat:'Poultry'}],
   {method:'latest',now:Date.parse('2026-07-20')});
 ck2('the invoice category wins over the guess', prop.items[0].category==='Poultry',
     prop.items[0].category);
 // token overlap: a cut not in the catalogue borrows its category
 prop=proposeCatalogue([
   {supplier:'Gulf',date:'1/7/2026',item:'CHICKEN THIGH BONELESS 2KG',qty:5,unit:7,total:35}],
   {method:'latest',now:Date.parse('2026-07-20')});
 ck2('chicken thigh borrows chicken\'s category', prop.items[0].category==='Meat',
     prop.items[0].category);

 // applying writes the category onto the ingredient
 DATA.ingredients=[];rebuildIX();
 prop=proposeCatalogue([
   {supplier:'Gulf',date:'1/7/2026',item:'POTATO 10KG',qty:2,unit:4,total:8}],
   {method:'latest',now:Date.parse('2026-07-20')});
 applyCatalogue(prop);
 ck2('the saved ingredient carries its category', DATA.ingredients[0].category==='Produce',
     DATA.ingredients[0].category);
 // a human override before applying is respected
 DATA.ingredients=[];rebuildIX();
 prop=proposeCatalogue([{supplier:'Gulf',date:'1/7/2026',item:'POTATO 10KG',qty:2,unit:4,total:8}],
   {method:'latest',now:Date.parse('2026-07-20')});
 prop.items[0].category='Root Veg';
 applyCatalogue(prop);
 ck2('a corrected category is what gets saved', DATA.ingredients[0].category==='Root Veg');

 // the review screen shows and lets you edit it
 DATA.ingredients=[];rebuildIX();
 CATPROP=proposeCatalogue([{supplier:'Gulf',date:'1/7/2026',item:'CHICKEN BREAST 2KG',qty:5,unit:8,total:40}],
   {method:'latest',now:Date.parse('2026-07-20')});
 view='catalogue';render();
 const h=__store['app'].innerHTML;
 ck2('the review has a Category column', /<th>Category<\/th>/.test(h));
 ck2('...pre-filled with the guess', /value="Meat"/.test(h));
 ck2('...editable', /CATPROP\.items\[0\]\.category=this\.value/.test(h));
 ck2('...with a picklist of known categories', /id="catlist"/.test(h)&&/Produce/.test(h));
 ck2('no NaN', !/NaN/.test(h));
 console.log(G.length?('\n'+G.length+' CAT FAILED: '+G.join(' | ')):'AUTO-CATEGORISE: ALL PASS');
})();
