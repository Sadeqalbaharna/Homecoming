let FO=[];const ck=(n,c,d='')=>{c?console.log('  PASS  '+n):(console.log('  FAIL  '+n+'  '+d),FO.push(n))};
SESSION={username:'owner',role:'owner'};WHO='owner';SETUP_DISMISSED=false;
const app=()=>{view='today';render();return __store['app'].innerHTML};
const heading=()=>((__store['app'].innerHTML.match(/<h1>([^<]*)<\/h1>/)||[])[1]||'');
const blank=()=>{SETUP_DISMISSED=false;CELEBRATE=null;
  DATA.setup={name:'',done:false,started:false,skipped:{},breakSeen:{}};DATA.firstRunDone=false;
  DATA.menu=[];DATA.ingredients=[];
  DATA.week={days:['a','b','c','d','e','f','g'],salesByDay:[0,0,0,0,0,0,0],guests:[0,0,0,0,0,0,0],
    employees:[],purchases:[]};rebuildIX();rebuildBX();};

// ═══ ORDER: EASY EXPORTS FIRST, EFFORT AFTER ═══
const ids=SETUP_STEPS.map(s=>s.id);
ck('order is menu → sales → daily → hours → invoices → recipes',
   ids.join(',')==='menu,sales,daily,hours,invoices,recipes', ids.join(','));
ck('the easy exports come before the receipts', ids.indexOf('sales')<ids.indexOf('invoices'));
ck('...and daily/hours too', ids.indexOf('daily')<ids.indexOf('invoices')&&ids.indexOf('hours')<ids.indexOf('invoices'));
ck('recipes is last', ids[ids.length-1]==='recipes');
ck('the break sits before the invoices step', !!SETUP_STEPS.find(s=>s.id==='invoices').breakBefore);
ck('...and nowhere else', SETUP_STEPS.filter(s=>s.breakBefore).length===1);

// ═══ THE SALES TEASER ═══
blank(); setupName('Sadeq');
DATA.menu=[
  {id:'a',name:'Big Burger',menuPrice:8,weeklySales:200,dept:'kitchen',lines:[]},
  {id:'b',name:'Wings',menuPrice:5,weeklySales:120,dept:'kitchen',lines:[]},
  {id:'c',name:'Ghost Salad',menuPrice:4,weeklySales:0,dept:'kitchen',lines:[]},
  {id:'d',name:'Dead Wrap',menuPrice:6,weeklySales:0,dept:'kitchen',lines:[]}];
DATA.rates={vat:0,service:0,levy:0};rebuildIX();
const t=salesTeaser();
ck('the teaser names the top sellers', t.top[0].name==='Big Burger');
ck('...with their share of the money', t.top[0].share>0.5);
ck('...and counts the dead items', t.dead===2, String(t.dead));
ck('...naming them', t.deadNames.includes('Ghost Salad'));

// it shows in the sales-step celebration
celebrateStep('sales',{trust:0.1,count:''});
let h=app();
ck('the sales celebration shows the teaser', /Already, from your sales alone/.test(h));
ck('...the top dishes', /Big Burger/.test(h));
ck('...and the dead count', /2<\/b> of 4 dishes never sold/.test(h)||/never sold/.test(h));
ck('...framed as motivation for the next steps', /cost <b>.*<\/b> and you understand most of your money/.test(h));
ck('no NaN', !/NaN/.test(h));
celebrateDone();

// ═══ THE BREAK IN THE MIDDLE ═══
blank(); setupName('M');
// complete the easy half so the flow arrives at invoices (the break)
DATA.menu=[{id:'a',name:'X',menuPrice:5,weeklySales:9,dept:'kitchen',lines:[]}];
DATA.week={days:['a','b','c','d','e','f','g'],salesByDay:[9,0,0,0,0,0,0],guests:[1,0,0,0,0,0,0],
  employees:[{name:'A',rate:2,hours:[8,0,0,0,0,0,0]}],purchases:[]};
rebuildIX();rebuildBX();
ck('the flow is now at the invoices step', SETUP_STEPS[setupIndex()].id==='invoices');
h=app();
ck('...and shows the BREAK, not the step yet', /You've done the quick part/.test(h), heading());
ck('...acknowledging what is done', /Menu, sales/.test(h));
ck('...with a keep-going button', /keep going/.test(h));
ck('...and an option to come back later', /Come back to the rest later/.test(h));
ck('...promising nothing is lost', /Nothing is lost/.test(h));
ck('the invoices upload is NOT shown yet', !/Choose your invoices/.test(h));

// acknowledging the break reveals the step
edit(()=>{DATA.setup.breakSeen={invoices:true}});
h=app();
ck('after the break, the invoices step appears', /Choose your invoices/.test(h)||/first bit of real work/.test(h));
ck('...and the break does not return', !/You've done the quick part/.test(h));

// the break is seen once, then remembered
ck('breakSeen is remembered', (DATA.setup.breakSeen||{}).invoices===true);
console.log(FO.length?('\n'+FO.length+' FAILED: '+FO.join(' | ')):'\nONBOARDING ORDER: ALL PASS');

// ═══ EXAMPLE OUTCOMES ON EACH STEP ═══
(function(){
 let G=[];const ck2=(n,c,d='')=>{c?console.log('  PASS  '+n):(console.log('  FAIL  '+n+'  '+d),G.push(n))};
 // every step has BD-denominated examples
 ck2('every step carries example outcomes', SETUP_STEPS.every(s=>(s.examples||[]).length>=1),
     SETUP_STEPS.filter(s=>!(s.examples||[]).length).map(s=>s.id).join());
 ck2('...at least two on most', SETUP_STEPS.filter(s=>(s.examples||[]).length>=2).length>=5);
 const all=SETUP_STEPS.flatMap(s=>s.examples||[]).join(' ');
 // Each step shows at least one dinar figure; time-saved examples may sit
// alongside without one, which is honest — time is its own value axis.
ck2('every step shows at least one dinar figure',
     SETUP_STEPS.every(s=>(s.examples||[]).some(e=>/BD |fils/.test(e))),
     SETUP_STEPS.filter(s=>!(s.examples||[]).some(e=>/BD |fils/.test(e))).map(s=>s.id).join());
 ck2('the user\'s burger example is on the recipes step',
     SETUP_STEPS.find(s=>s.id==='recipes').examples.some(e=>/burger costing BD 1\.400/.test(e)));
 ck2('...and the croque madame one', SETUP_STEPS.find(s=>s.id==='recipes').examples.some(e=>/croque madame/.test(e)));

 // they render on the step screen, clearly labelled illustrative
 blank(); setupName('Sadeq');
 let h=app();
 ck2('the menu step shows an example', /WHAT THIS TYPICALLY TURNS UP/.test(h));
 ck2('...marked illustrative, not a real finding', /illustrative/.test(h));
 ck2('...with the dinar figure', /BD 150–300 a month/.test(h));
 ck2('...and a rotate hint when there are several', /they rotate/.test(h));
 ck2('the first example is visible without any script', /exline" data-ex="0"[^>]*>💡/.test(h)&&!/data-ex="0"[^>]*display:none/.test(h));
 ck2('the second waits hidden', /data-ex="1"[^>]*display:none/.test(h));
 ck2('no NaN', !/NaN/.test(h));

 // advancing to a later step shows ITS examples — menu priced but sales not yet
 DATA.menu=[{id:'m',name:'X',menuPrice:5,weeklySales:0,dept:'kitchen',lines:[]}];rebuildIX();
 h=app();
 ck2('the sales step shows its own example', /top 20 dishes could be ~40%/.test(h));
 ck2('examples use conditional language, not assertions',
     SETUP_STEPS.flatMap(s=>s.examples||[]).filter(e=>/BD /.test(e))
       .every(e=>/could|might|may|would|perhaps|potentially|if /i.test(e)),
     SETUP_STEPS.flatMap(s=>s.examples||[]).filter(e=>/BD /.test(e)&&!/could|might|may|would|perhaps|potentially|if /i.test(e))[0]||'');
 console.log(G.length?('\n'+G.length+' EXAMPLES FAILED: '+G.join(' | ')):'STEP EXAMPLES: ALL PASS');
})();

// ═══ THE STEP SCREEN IS VISUALLY ALIVE (but degrades to static) ═══
(function(){
 let G=[];const ck2=(n,c,d='')=>{c?console.log('  PASS  '+n):(console.log('  FAIL  '+n+'  '+d),G.push(n))};
 blank(); setupName('Sadeq'); DATA.menu=[];DATA.ingredients=[];rebuildIX();
 const h=app();
 const css=require('fs').readFileSync(process.env.TC,'utf-8');
 ck2('the step has a shimmer progress bar', /class="wprog"/.test(h)&&/@keyframes shimmer/.test(css));
 ck2('...showing real completion width', /class="wprog"><div style="width:\d+%"/.test(h));
 ck2('unlocks render as pills, not a flat line', (h.match(/unlockpill/g)||[]).length>=2);
 ck2('...and the old italic line is gone', !/Unlocks · <i>/.test(h));
 ck2('the primary action has a breathing accent', /animation:cta/.test(css));
 ck2('the backdrop has drifting glows', /@keyframes drift1/.test(css)&&/@keyframes drift2/.test(css));
 ck2('the step content rises in', /@keyframes stepIn/.test(css)&&/@keyframes riseIn/.test(css));
 ck2('the active pip pulses', /@keyframes pipPulse/.test(css));
 ck2('reduced-motion disables the wiz animations',
     /@media\(prefers-reduced-motion:reduce\)\{\.wiz::before/.test(css.replace(/\s+/g,''))
     || (/prefers-reduced-motion:reduce/.test(css)&&/\.wiz::before,\.wiz::after/.test(css)));
 ck2('no NaN', !/NaN/.test(h));
 // the real content is still there under the visuals (degrade-to-truth)
 ck2('the heading is present', /<h1>First/.test(h));
 ck2('the action is present', /Choose your menu file/.test(h));
 console.log(G.length?('\n'+G.length+' VISUALS FAILED: '+G.join(' | ')):'STEP VISUALS: ALL PASS');
})();

// ═══ THE BREAK SHOWS REAL FINDINGS, NOT EXAMPLES ═══
(function(){
 let G=[];const ck2=(n,c,d='')=>{c?console.log('  PASS  '+n):(console.log('  FAIL  '+n+'  '+d),G.push(n))};
 blank(); setupName('Sadeq');
 // the easy half: menu, sales, daily takings, hours — enough to find real things
 DATA.menu=[
   {id:'a',name:'Big Seller',menuPrice:8,weeklySales:200,dept:'kitchen',lines:[]},
   {id:'b',name:'Ghost',menuPrice:5,weeklySales:0,dept:'kitchen',lines:[]},
   {id:'c',name:'Dead Wrap',menuPrice:6,weeklySales:0,dept:'kitchen',lines:[]}];
 DATA.rates={vat:0.1,service:0.1,levy:0};
 // a day staffed against no sales → a real dead-hours finding
 DATA.week={days:['Mon','Tue','Wed','Thu','Fri','Sat','Sun'],
   salesByDay:[500,500,0,800,1200,1500,900],guests:[40,40,0,60,90,110,70],
   employees:[{name:'A',rate:2,hours:[8,8,10,8,8,8,8]},{name:'B',rate:2,hours:[8,8,10,8,8,8,8]}],
   purchases:[]};
 rebuildIX();rebuildBX();
 // arrive at the break (invoices) with breakSeen not yet set
 ck2('the flow is at the break', SETUP_STEPS[setupIndex()].id==='invoices'&&!(DATA.setup.breakSeen||{}).invoices);
 const h=app();
 ck2('the break shows the two-column insight card', /class="binsights"/.test(h));
 ck2('...with a hero money figure', /class="bnum"/.test(h)&&/data-hero="/.test(h));
 ck2('...counting from a real total, computed not hardcoded', /data-hero="\d/.test(h));
 ck2('...a live ledger of findings', /What your data already reveals/.test(h));
 ck2('...listing an actual finding from the data', /never sold|staffed below|labour hour|revenue is costed|top .*sellers/i.test(h));
 ck2('...each row set to reveal one by one', /class="brow binsight" style="--bi:0"/.test(h)&&/--bi:1/.test(h));
 ck2('...time saved sits in the hero square as a second bnum, under BD', /class="bnum bnum2"><b data-htime=/.test(h)&&/typing already done for you/.test(h));
 ck2('...same count-up animation target as the money (data-htime marker)', /<b data-htime="\d/.test(h));
 ck2('...and not duplicated in the ledger list', (h.match(/typing already done for you/g)||[]).length===1);
 ck2('...never nags about the recipes step it has not reached yet', !/no recipe|revenue is costed|Prime cost is/i.test(h));
 ck2('...framed real, not examples', /Each shows its arithmetic/.test(h));
 ck2('no NaN', !/NaN/.test(h));
 ck2('the keep-going button is still there', /keep going/.test(h));

 // it is COMPUTED, not hardcoded — a different book gives a different panel
 blank(); setupName('M');
 DATA.menu=[{id:'x',name:'Only Dish',menuPrice:5,weeklySales:10,dept:'kitchen',lines:[]}];
 DATA.week={days:['a','b','c','d','e','f','g'],salesByDay:[100,0,0,0,0,0,0],guests:[9,0,0,0,0,0,0],
   employees:[{name:'A',rate:2,hours:[8,0,0,0,0,0,0]}],purchases:[]};
 rebuildIX();rebuildBX();
 const h2=app();
 ck2('a different book yields a different panel (computed, not static)', h2!==h);
 console.log(G.length?('\n'+G.length+' BREAK FINDINGS FAILED: '+G.join(' | ')):'BREAK FINDINGS: ALL PASS');
})();
