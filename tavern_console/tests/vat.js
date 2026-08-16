let FV=[];const ck=(n,c,d='')=>{c?console.log('  PASS  '+n):(console.log('  FAIL  '+n+'  '+d),FV.push(n))};
SESSION={username:'owner',role:'owner'};WHO='owner';SETUP_DISMISSED=true;DATA.firstRunDone=true;
TOASTS=[];global.setTimeout=fn=>0;

// ═══ THE PURE RULE ═══
DATA.settings={};
ck('with nothing set, an invoice price is untouched', invoiceToCost(11)===11);
DATA.settings={vatRegistered:true,invoicesGross:true,purchaseVat:0.10};
ck('registered + gross + rate strips the VAT', Math.abs(invoiceToCost(11)-10)<0.0001, String(invoiceToCost(11)));
ck('...a plain 10 becomes ~9.09', Math.abs(invoiceToCost(10)-9.0909)<0.001, String(invoiceToCost(10)));
DATA.settings={vatRegistered:true,invoicesGross:false,purchaseVat:0.10};
ck('registered but NET invoices: no change', invoiceToCost(10)===10);
DATA.settings={vatRegistered:false,invoicesGross:true,purchaseVat:0.10};
ck('NOT registered: VAT is real cost, no change', invoiceToCost(11)===11);
DATA.settings={vatRegistered:true,invoicesGross:true,purchaseVat:0};
ck('a zero rate does nothing even if gross', invoiceToCost(11)===11);
ck('zero and negative prices pass through', invoiceToCost(0)===0&&invoiceToCost(-5)===-5);

// ═══ IT REACHES THE CATALOGUE ═══
DATA.settings={vatRegistered:true,invoicesGross:true,purchaseVat:0.10};
DATA.ingredients=[];rebuildIX();
const prop=proposeCatalogue([
  {supplier:'Gulf',date:'1/7/2026',item:'CHICKEN 1KG',qty:10,unit:11,total:110}],
  {method:'latest',now:Date.parse('2026-07-20')});
ck('a gross invoice line is costed net in the catalogue',
   Math.abs(prop.items[0].price-10)<0.001, String(prop.items[0].price));
DATA.settings={};
const prop2=proposeCatalogue([
  {supplier:'Gulf',date:'1/7/2026',item:'CHICKEN 1KG',qty:10,unit:11,total:110}],
  {method:'latest',now:Date.parse('2026-07-20')});
ck('...and unadjusted when VAT is not configured', Math.abs(prop2.items[0].price-11)<0.001);

// ═══ IT REACHES GOODS-RECEIVED ═══
DATA.settings={vatRegistered:true,invoicesGross:true,purchaseVat:0.10};
DATA.ingredients=[{id:'a',code:'001',name:'Beef',price:0,recipeUnit:'kg',ruPerPu:1,pu:'kg',yield:1,history:[]}];
DATA.menu=[];DATA.ledger={days:{},purchases:[]};
DATA.week={days:['2026-07-01','','','','','',''],salesByDay:[0,0,0,0,0,0,0],guests:[0,0,0,0,0,0,0],
  employees:[],purchases:[]};
rebuildIX();
STAGE={kind:'purchases',headers:['Supplier','Total','Item','Unit'],
  rows:[['Gulf','55','Beef','11']],map:{supplier:0,total:1,item:2,unit:3},headerRow:0};
stageApply();
ck('goods-received prices an ingredient net of VAT',
   Math.abs(DATA.ingredients[0].price-10)<0.001, String(DATA.ingredients[0].price));
ck('...and records the true cost in history', DATA.ingredients[0].history.some(h=>Math.abs(h.price-10)<0.001));

// ═══ IT IS NEVER SILENT ═══
DATA.settings={};
DATA.ingredients=[{id:'a',code:'001',name:'X',price:5,recipeUnit:'kg',ruPerPu:1,pu:'kg',yield:1,
  history:[{at:1,price:5,src:'goods received'}]}];
ck('purchases with no VAT decision are flagged', vatUnset()===true);
DATA.settings={vatAsked:true};
ck('...and once answered, not flagged', vatUnset()===false);
DATA.settings={};DATA.ledger={days:{},purchases:[]};
DATA.ingredients=[{id:'a',name:'X',price:5,recipeUnit:'kg',ruPerPu:1,pu:'kg',yield:1,history:[]}];
ck('no purchases means nothing to flag', vatUnset()===false);

// the report surfaces it
DATA.settings={};DATA.ingredients=[{id:'a',code:'001',name:'X',price:5,recipeUnit:'kg',ruPerPu:1,pu:'kg',yield:1,
  history:[{at:1,price:5,src:'goods received'}]}];
DATA.menu=[{id:'m',name:'D',menuPrice:5,weeklySales:1,dept:'kitchen',lines:[]}];
DATA.rates={vat:0.1,service:0,levy:0};rebuildIX();
const RPT=findings();
ck('the report flags the unanswered VAT question', RPT.blocked.some(b=>/costs are right at all/.test(b.title)));

// ═══ SETTINGS UI ═══
SETUP_DISMISSED=true;view='settings';render();
const h=__store['app'].innerHTML;
ck('settings has the VAT card', /VAT on your purchases/.test(h));
ck('...the registered toggle', /vatRegistered/.test(h));
ck('...the gross toggle', /invoicesGross/.test(h));
ck('...and the rate', /purchaseVat/.test(h));
ck('no NaN', !/NaN/.test(h));
DATA.settings={vatRegistered:true,invoicesGross:true,purchaseVat:0.1,vatAsked:true};render();
ck('...and states plainly what it is doing when on', /divided by 1\.10/.test(__store['app'].innerHTML));
console.log(FV.length?('\n'+FV.length+' FAILED: '+FV.join(' | ')):'\nVAT: ALL PASS');
