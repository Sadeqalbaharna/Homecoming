let FAILS=[];const ck=(n,c,d='')=>{c?console.log('  PASS  '+n):(console.log('  FAIL  '+n+'  '+d),FAILS.push(n))};
SESSION={username:'owner',role:'owner'};WHO='owner';DATA.firstRunDone=true;
// The guided flow now returns on every launch while steps are outstanding,
// so a suite testing the ordinary app has to say it has been dismissed.
SETUP_DISMISSED=true;

// ═══ AN EMPTY BOOK MUST NOT INVENT FINDINGS ═══
DATA.ingredients=[];DATA.menu=[];DATA.market=[];
DATA.week={days:['Mon','Tue','Wed','Thu','Fri','Sat','Sun'],salesByDay:[0,0,0,0,0,0,0],
  guests:[0,0,0,0,0,0,0],employees:[],purchases:[]};
DATA.rates={vat:0,service:0,levy:0};
rebuildIX();rebuildBX();
let RPT=findings();
ck('an empty book produces no findings', RPT.findings.length===0, RPT.findings.map(f=>f.id).join());
ck('...and names no money', RPT.money===0);
ck('...but says what it cannot tell you', RPT.blocked.length>0);
ck('...including the stock count', RPT.blocked.some(b=>/variance/i.test(b.title)));
ck('...and that the rates are unset', RPT.blocked.some(b=>/percentage/i.test(b.title)));

// ═══ A REAL WEEK ═══
DATA.rates={vat:0.10,service:0.10,levy:0.02};
DATA.ingredients=[
 {id:'a',code:'001',name:'Chicken Breast',price:5,recipeUnit:'kg',ruPerPu:1,pu:'kg',yield:1,
  history:[{at:Date.parse('2026-05-01'),price:5.00,supplier:'Fine Foods',qty:100},
           {at:Date.parse('2026-06-01'),price:3.60,supplier:'Hasan Habib',qty:200},
           {at:Date.parse('2026-07-01'),price:6.00,supplier:'Fine Foods',qty:100}]},
 {id:'b',code:'002',name:'Salt',price:1,recipeUnit:'kg',ruPerPu:1,pu:'kg',yield:1,history:[]}];
DATA.menu=[
 {id:'m1',name:'Chicken Plate',menuPrice:6,weeklySales:100,dept:'kitchen',lines:[{ref:'001_Chicken Breast',qty:0.2}]},
 {id:'m2',name:'Never Sold',menuPrice:9,weeklySales:0,dept:'kitchen',lines:[]},
 {id:'m3',name:'Big Seller',menuPrice:12,weeklySales:200,dept:'kitchen',lines:[]}];
DATA.week={days:['Mon','Tue','Wed','Thu','Fri','Sat','Sun'],
  salesByDay:[500,500,0,800,1200,1500,900],guests:[40,40,0,60,90,110,70],
  employees:[{name:'A',rate:2,hours:[8,8,10,8,8,8,8]},{name:'B',rate:2,hours:[8,8,10,8,8,8,8]}],
  purchases:[{supplier:'Fine Foods',date:'2026-07-01',amount:900,alloc:{Meat:900}},
             {supplier:'Corner',date:'2026-07-02',amount:120,alloc:{}}]};
rebuildIX();rebuildBX();
RPT=findings();
const by=id=>RPT.findings.find(f=>f.id===id||String(f.id).startsWith(id));

ck('findings appear', RPT.findings.length>0);
ck('every finding shows its working', RPT.findings.every(f=>f.working&&f.working.length>10),
   RPT.findings.filter(f=>!f.working).map(f=>f.id).join());
ck('every finding cites evidence', RPT.findings.every(f=>Array.isArray(f.evidence)&&f.evidence.length));
ck('every finding says what to do', RPT.findings.every(f=>f.action));
ck('they are ordered by severity', SEV[RPT.findings[0].severity]>=SEV[RPT.findings[RPT.findings.length-1].severity]);

// the net-revenue gap
const ng=by('netgap');
ck('the tax gap is reported', !!ng);
ck('...computed by compounding, not adding', /×/.test(ng.working));
// 1 − 1 ÷ (1.10 × 1.10 × 1.02) = 0.1898. My first guess at this by hand was
// 18.7%, which is what happens when you add the rates instead of compounding
// them — the exact error the finding exists to warn about.
ck('...at the right number', /19\.0%/.test(ng.title), ng.title);

// prime cost — the bug that would have shown NaN
const pc=by('prime');
ck('prime cost is reported', !!pc);
ck('...with no NaN', !/NaN/.test(pc.title+pc.what+pc.working), pc.title+' | '+pc.what);
ck('...and shows the division', /÷/.test(pc.working));

// dead hours
const dh=by('deadhours');
ck('a day staffed with no sales is caught', !!dh, RPT.findings.map(f=>f.id).join());
ck('...and names the money', dh&&dh.money>0);
// The caveat no longer apologises for a borrowed benchmark, because the
// floor is now worked out from this venue's own wage bill.
ck('...saying the floor came from your own wages', /your own wage bill/.test(dh.caveat||''),
   dh.caveat||'');

// THE SUPPLIER FINDING — provable money
const sp=RPT.findings.find(f=>String(f.id).startsWith('supplier-'));
ck('the supplier price gap is found', !!sp, RPT.findings.map(f=>f.id).join());
// 100kg@5 + 200@3.60 + 100@6 = 500+720+600 = 1820 over 400kg. All at 3.60 = 1440.
ck('...with the saving computed from real quantities', sp&&Math.abs(sp.money-380)<0.5, sp&&String(sp.money));
ck('...naming each supplier and its price', /Fine Foods/.test(sp.evidence.join())&&/Hasan Habib/.test(sp.evidence.join()));
ck('...and warns a gap can be a quality gap', /quality gap/.test(sp.action));

// drift
const dr=RPT.findings.find(f=>String(f.id).startsWith('drift-'));
ck('price drift is found', !!dr);
ck('...from the earliest price on record', dr&&/5\.000/.test(dr.evidence.join()));

// dead items + effort
const deadItemsF=RPT.findings.find(f=>f.id==='dead');
ck('items that never sold are listed', !!deadItemsF);
ck('...dead finding cites the report window, not a raw count', /sell in /.test(deadItemsF.title));
ck('sales concentration is surfaced', !!by('concentration'));
ck('...naming how few dishes carry the money', /bring in \d+% of sales/.test(by('concentration').title));
ck('uncosted top sellers are called out', !!by('effort'));
ck('...pointing at the recipe sheets', by('effort').go==='sheets');
ck('unassigned spend is found', !!by('unalloc'));

// ═══ SUPPRESSION ═══
ck('theoretical food cost is SUPPRESSED at low coverage',
   RPT.blocked.some(b=>/Theoretical/.test(b.title)), RPT.blocked.map(b=>b.title).join(' | '));
ck('...saying exactly why', /only \d+% of the menu is costed/.test(
   (RPT.blocked.find(b=>/Theoretical/.test(b.title))||{}).what||''));
DATA.menu.forEach(m=>m.lines=[{ref:'001_Chicken Breast',qty:0.1}]);
ck('...and appears once coverage is enough', !findings().blocked.some(b=>/Theoretical/.test(b.title)));

// ═══ NO FORECASTS ═══
const txt=JSON.stringify(RPT.findings).toLowerCase();
ck('no finding claims a future saving from a price change',
   !/could earn|would earn|additional monthly|projected/.test(txt));

// ═══ MARKET ═══
ck('similar dishes match', dishSimilarity('Grilled Chicken Plate','Chicken Plate Grilled')>=0.6);
ck('unrelated dishes do not', dishSimilarity('Grilled Chicken','Chocolate Cake')===0);
ck('filler words are ignored', dishSimilarity('Chicken with Rice','Chicken and Rice')>=0.6);
DATA.market=[];
addMarketSet('Cafe A','Adliya',[{name:'Chicken Plate',price:7},{name:'Cake',price:3}]);
addMarketSet('Cafe B','Adliya',[{name:'Chicken Plate Grilled',price:8}]);
ck('a set is stored', DATA.market.length===2);
ck('...dropping unpriced items', DATA.market[0].items.length===2);
let CMP=marketCompare();
ck('a dish with two matches is compared', CMP.rows.length===1, JSON.stringify(CMP.rows.map(r=>r.dish)));
ck('...with the median', CMP.rows[0].median===7.5, String(CMP.rows[0].median));
ck('...and your distance from it', Math.abs(CMP.rows[0].delta-(6-7.5)/7.5)<0.001);
ck('...and the band', CMP.rows[0].min===7&&CMP.rows[0].max===8);
ck('it reports position, never a recommended price',
   !JSON.stringify(CMP.rows).match(/recommend|should charge|set price/i));
// A single match is now SHOWN, but never dressed as a band.
DATA.market=[DATA.market[0]];
const one=marketCompare().rows;
ck('a single match is shown rather than hidden', one.length===1);
ck('...marked as an anecdote', one[0].conf.label==='anecdote', one[0].conf.label);
ck('...flagged single so the view does not call it a median', one[0].single===true);
ck('...and excluded from the above/below counts', marketCompare().solid===0);
console.log(FAILS.length?('\n'+FAILS.length+' FAILED: '+FAILS.join(' | ')):'\nFINDINGS: ALL PASS');

// ═══ LABOUR COST MUST NOT VANISH WHEN ONLY HOURS AND A RATE EXIST ═══
(function(){
 let G=[];const ck2=(n,c,d='')=>{c?console.log('  PASS  '+n):(console.log('  FAIL  '+n+'  '+d),G.push(n))};
 DATA.week={days:['Mon','Tue','Wed','Thu','Fri','Sat','Sun'],
   salesByDay:[100,100,100,100,100,100,100],guests:[10,10,10,10,10,10,10],purchases:[],
   employees:[{name:'From the punch importer',rate:2,hours:[8,8,8,8,8,0,0]}]};
 let L=weekLabour();
 ck2('hours + rate with no cost array still costs money', L.total>0, String(L.total));
 ck2('...at rate x hours', Math.abs(L.paid-80)<0.001, String(L.paid));
 ck2('...spread across the right days', L.byDay[0]===16&&L.byDay[5]===0, JSON.stringify(L.byDay));
 ck2('...and flagged as estimated', L.rows[0].costEstimated===true);
 ck2('prime cost now includes it', primeCost().labour>0);

 // a recorded cost still wins — it carries overtime the rate cannot know
 DATA.week.employees=[{name:'With overtime',rate:2,hours:[8,8,8,8,8,0,0],
                       cost:[16,16,16,16,40,0,0]}];
 L=weekLabour();
 ck2('a recorded cost is used where it exists', Math.abs(L.paid-104)<0.001, String(L.paid));
 ck2('...and the premium is visible', Math.abs(L.rows[0].premium-24)<0.001);
 ck2('...and it is not marked estimated', L.rows[0].costEstimated===false);

 // a partially filled cost array: recorded days recorded, blank days derived
 DATA.week.employees=[{name:'Half recorded',rate:2,hours:[8,8,8,8,8,0,0],cost:[16,16]}];
 L=weekLabour();
 ck2('a half-filled cost array fills the gaps rather than zeroing them',
     Math.abs(L.paid-80)<0.001, String(L.paid));
 console.log(G.length?('\n'+G.length+' LABOUR FAILED: '+G.join(' | ')):'LABOUR COST: ALL PASS');
})();
(function(){
 let G=[];const ck2=(n,c,d='')=>{c?console.log('  PASS  '+n):(console.log('  FAIL  '+n+'  '+d),G.push(n))};
 SESSION={username:'owner',role:'owner'};WHO='owner';DATA.firstRunDone=true;STAGE=null;INVBATCH=null;
 const nav=NAVGROUPS.flatMap(g=>g[1].map(i=>i[0]));
 ck2('the report is in the nav', nav.includes('report'));
 ck2('the comparison is in the nav', nav.includes('market'));
 view='report'; render(); let h=__store['app'].innerHTML;
 ck2('the report renders', /Where the money went/.test(h));
 ck2('...showing every finding its working', /WORKING/.test(h)||/Nothing to report/.test(h));
 ck2('...and what it will not tell you', /cannot tell you yet/.test(h)||/Nothing to report/.test(h));
 ck2('no NaN on the report', !/NaN/.test(h));
 view='market'; render(); h=__store['app'].innerHTML;
 ck2('the comparison renders', /How your prices sit/.test(h));
 ck2('...and states plainly that it recommends no price', /does not recommend a price/i.test(h));
 ck2('...and that it is menu price to menu price', /menu price to menu price/.test(h));
 ck2('no NaN on the comparison', !/NaN/.test(h));
 console.log(G.length?('\n'+G.length+' NAV FAILED: '+G.join(' | ')):'REPORT NAV: ALL PASS');
})();

// ═══ COMPARABILITY ═══
(function(){
 let G=[];const ck2=(n,c,d='')=>{c?console.log('  PASS  '+n):(console.log('  FAIL  '+n+'  '+d),G.push(n))};
 const mk=(sets,sims,prices)=>({matches:sets.map((s,i)=>({x:{set:s,price:prices[i]},s:sims[i]})),
                                prices:prices.slice().sort((a,b)=>a-b)});
 const C=o=>comparability(o.matches,o.prices);

 // the ideal: many dishes, many venues, close names, tight prices
 let g=C(mk(['A','B','C','D','E'],[.95,.92,.9,.88,.9],[6,6.2,6.1,6.3,6.05]));
 ck2('five close matches across five venues is strong', g.label==='strong', g.label+' '+g.score.toFixed(2));

 // THE ONE THAT MATTERS: five matches, all from one menu
 let one=C(mk(['A','A','A','A','A'],[.95,.92,.9,.88,.9],[6,6.2,6.1,6.3,6.05]));
 ck2('five matches from ONE venue is not strong', one.label!=='strong', one.label+' '+one.score.toFixed(2));
 ck2('...and says so in words', one.why.some(w=>/one opinion rather than a market/.test(w)));
 ck2('...scoring below the same five across five venues', one.score<g.score);

 // wild spread means the matcher grouped different dishes
 let wild=C(mk(['A','B','C'],[.9,.9,.9],[3,7,14]));
 ck2('a wild price spread drops confidence', wild.score<0.45, wild.label+' '+wild.score.toFixed(2));
 ck2('...and says they are probably not the same dish',
     wild.why.some(w=>/probably not the same dish/.test(w)));

 // loose names
 let loose=C(mk(['A','B','C'],[.6,.6,.62],[6,6.1,6.2]));
 ck2('loosely matched names drop confidence', loose.score<g.score);
 ck2('...and warn to check them', loose.why.some(w=>/only loosely match/.test(w)));

 // a single match
 let solo=C(mk(['A'],[.95],[6]));
 ck2('one match is an anecdote', solo.label==='anecdote', solo.label);

 // any one bad factor pulls it down — the product shape
 let manyButLoose=C(mk(['A','B','C','D','E'],[.55,.55,.55,.55,.55],[6,6.1,6.05,6.2,6.15]));
 ck2('quantity does not rescue a bad name match', manyButLoose.score<0.45,
     manyButLoose.label+' '+manyButLoose.score.toFixed(2));
 ck2('scores stay inside 0..1', [g,one,wild,loose,solo].every(x=>x.score>=0&&x.score<=1));

 // ordering: trustworthy before dramatic
 DATA.menu=[{id:'x',name:'Chicken Plate',menuPrice:6,dept:'kitchen',lines:[],weeklySales:1},
            {id:'y',name:'Beef Burger',menuPrice:20,dept:'kitchen',lines:[],weeklySales:1}];
 DATA.market=[];
 addMarketSet('A','',[{name:'Chicken Plate',price:6.5},{name:'Beef Burger',price:5}]);
 addMarketSet('B','',[{name:'Chicken Plate',price:6.4}]);
 addMarketSet('C','',[{name:'Chicken Plate',price:6.6}]);
 const rows=marketCompare().rows;
 ck2('the well-supported dish is listed first, not the dramatic one',
     rows[0].dish==='Chicken Plate', rows.map(r=>r.dish+':'+r.conf.label).join(' | '));
 ck2('...even though the other has a far bigger gap', Math.abs(rows[1].delta)>Math.abs(rows[0].delta));

 SESSION={username:'owner',role:'owner'};view='market';STAGE=null;INVBATCH=null;render();
 const h=__store['app'].innerHTML;
 ck2('the view shows a confidence label', /pill (g|w|b)">(strong|fair|weak|anecdote)/.test(h));
 ck2('...and the reasons behind it', /venue/.test(h));
 ck2('...and still refuses to recommend a price', /does not recommend a price/i.test(h));
 ck2('a single price is not called a median', !/one price seen:<\/span>\s*<div class="mini">band/.test(h));
 ck2('no NaN', !/NaN/.test(h));
 console.log(G.length?('\n'+G.length+' CONF FAILED: '+G.join(' | ')):'COMPARABILITY: ALL PASS');
})();

// ═══ COMPARISON IS GATED ON HAVING A MENU ═══
(function(){
 let G=[];const ck2=(n,c,d='')=>{c?console.log('  PASS  '+n):(console.log('  FAIL  '+n+'  '+d),G.push(n))};
 SESSION={username:'owner',role:'owner'};WHO='owner';DATA.firstRunDone=true;
 STAGE=null;INVBATCH=null;RESEARCH=null;CATPROP=null;
 // The sidebar renders into #sidegroups, and only the OPEN group's items are
// in the DOM at all — so searching the nav (which expands every group) is the
// only honest way to ask whether an item is offered.
const navHas=()=>{
  __store['navq']=__store['navq']||{value:''};
  __store['navq'].value='compare';
  drawSide();
  const h=(__store['sidegroups']||{innerHTML:''}).innerHTML;
  __store['navq'].value='';
  return /go\('market'\)/.test(h);
};

 DATA.menu=[];
 ck2('with no menu, comparison is gated', !!viewGate('market'));
 ck2('...and hidden from the nav', !navHas());
 view='market'; render(); let h=__store['app'].innerHTML;
 ck2('...and reaching it directly explains rather than showing an empty screen',
     /Nothing to compare yet/.test(h));
 ck2('...saying the menu is what gets searched', /dish names are what gets searched/.test(h));
 ck2('...with a way to fix it', /go\('import'\)/.test(h));
 ck2('...and no button that would spend money on nothing', !/researchMenus\(\)/.test(h));

 DATA.menu=[{id:'m1',name:'Chicken Plate',menuPrice:0,dept:'kitchen',lines:[],weeklySales:0}];
 ck2('an unpriced menu is still not enough', !!viewGate('market'));
 DATA.menu[0].menuPrice=6;
 ck2('one priced dish opens it', !viewGate('market'));
 ck2('...and it returns to the nav', navHas());
 render(); h=__store['app'].innerHTML;
 ck2('...and the real screen appears', /How your prices sit/.test(h));
 ck2('...with the search button', /researchMenus\(\)/.test(h));
 ck2('no NaN', !/NaN/.test(h));

 // the menu genuinely seeds the search
 DATA.menu=[{id:'a',name:'Wagyu Slider',menuPrice:9,weeklySales:200,dept:'kitchen',lines:[]},
            {id:'b',name:'Rarely Sold Soup',menuPrice:4,weeklySales:1,dept:'kitchen',lines:[]}];
 DATA.ai={provider:'anthropic',key:'k',enabled:true,calls:0,ledger:[],auth:[],limits:null};
 DATA.venueInfo={city:'Adliya',country:'BH'};
 let sent=null;
 globalThis.fetch=async(u,o)=>{sent=JSON.parse(o.body);return {ok:true,status:200,json:async()=>({
   stop_reason:'end_turn',usage:{},content:[{type:'text',text:'{"venues":[]}'}]})}};
 researchMenus().then(()=>{
   const p=sent.messages[0].content;
   ck2('the search is seeded with your dish names', /Wagyu Slider/.test(p));
   ck2('...best sellers first', p.indexOf('Wagyu Slider')<p.indexOf('Rarely Sold Soup'));
   console.log(G.length?('\n'+G.length+' GATE FAILED: '+G.join(' | ')):'MENU GATE: ALL PASS');
 });
})();
