let FW=[];const ck=(n,c,d='')=>{c?console.log('  PASS  '+n):(console.log('  FAIL  '+n+'  '+d),FW.push(n))};
SESSION={username:'owner',role:'owner'};WHO='owner';
STAGE=null;INVBATCH=null;RESEARCH=null;CATPROP=null;
const blank=()=>{SETUP_DISMISSED=false;   // a fresh launch, not a fresh tab
  DATA.setup={name:'',at:0,done:false,skipped:{},started:false};
  DATA.firstRunDone=false;DATA.menu=[];DATA.ingredients=[];
  DATA.week={days:['a','b','c','d','e','f','g'],salesByDay:[0,0,0,0,0,0,0],guests:[0,0,0,0,0,0,0],
    employees:[],purchases:[]};rebuildIX();rebuildBX();};
const app=()=>{view='today';render();return __store['app'].innerHTML};

// ═══ IT ASKS THE NAME, AND ONLY THAT ═══
blank();
let h=app();
ck('it opens by asking your name', /What should I call you/.test(h));
ck('...and nothing else is on screen', !/Upload/.test(h), '');
ck('...with the nav hidden', (drawSide(),__store['side'].style.display==='none'));
setupName('Sadeq');
ck('the name is kept', DATA.setup.name==='Sadeq');
h=app();
ck('step one is the menu', /First — your menu/.test(h));
ck('...saying why in one line', /nothing to cost until the dishes exist/.test(h));
ck('...with one action, which opens your files', /<input type="file"/.test(h));
ck('...and a way past it', /setupSkip\('menu'\)/.test(h));
ck('progress is shown', /step 1 of 6/.test(h));

// ═══ STEPS COMPLETE THEMSELVES FROM DATA ═══
DATA.menu=[{id:'m1',name:'A',menuPrice:6,weeklySales:0,dept:'kitchen',lines:[]}];
h=app();
ck('importing a menu completes step one without clicking anything', /what has been selling/.test(h));
ck('...and says what landed', /1 dishes priced/.test(h));
DATA.menu[0].weeklySales=10;
ck('sales completes → daily is next', /Daily sales and covers/.test(app()), app().match(/<h1>[^<]*/)||'');
DATA.week.salesByDay=[100,0,0,0,0,0,0];
ck('daily completes → hours is next', /Staff hours/.test(app()));
DATA.week.employees=[{name:'A',rate:2,hours:[8,0,0,0,0,0,0]}];
// hours done → the flow reaches invoices, which shows the BREAK first
ck('hours completes → the break appears', /You've done the quick part/.test(app()));
edit(()=>{DATA.setup.breakSeen={invoices:true}});
ck('...after the break, invoices', /real work/.test(app())||/Choose your invoices/.test(app()));
DATA.ingredients=[{id:'i',name:'X',price:2,recipeUnit:'kg',ruPerPu:1,pu:'kg',yield:1}];
ck('invoices completes → recipes is last', /downloadAllRecipeSheets\(\)/.test(app()));

// ═══ IT ENDS ═══
DATA.menu[0].lines=[{ref:'X',qty:1}];
h=app();
ck('costing the menu finishes the flow', /That's it, Sadeq/.test(h), h.slice(0,120));
ck('...and hands you the report', /setupFinish\(\)/.test(h));
setupFinish();
ck('finishing lands on the unlocked screen', view==='unlocked');
ck('...and marks setup done', DATA.setup.done===true);
ck('...and does not come back', !inSetup());
view='today';render();
ck('...the normal screen is back', !/What should I call you/.test(__store['app'].innerHTML));
ck('...and so is the nav', (drawSide(),__store['side'].style.display!=='none'));

// ═══ SKIPPING NEVER BLOCKS ═══
blank(); setupName('Manager');
setupSkip('menu'); setupSkip('sales'); setupSkip('invoices');
h=app();
ck('skipped steps are passed over', /Daily sales and covers/.test(h), (h.match(/<h1>[^<]*/)||[])[0]||'');
ck('...and marked distinctly in the progress bar', /wpip skip/.test(h));
setupSkip('hours');setupSkip('daily');setupSkip('recipes');
h=app();
ck('skipping everything still reaches the end', /That's it/.test(h));
ck('...and lists what was skipped', /Skipped:/.test(h));
ck('...offering them back', /setupUnskip\(/.test(h));
setupUnskip('menu');
ck('un-skipping brings a step back', /First — your menu/.test(app()));

// ═══ IT RESUMES ═══
blank(); setupName('X'); DATA.menu=[{id:'m',name:'A',menuPrice:5,weeklySales:0,dept:'kitchen',lines:[]}];
saveNow();
DATA.setup={name:'',done:false,skipped:{},started:false};DATA.menu=[];
load();
ck('the name survives a reload', DATA.setup.name==='X');
ck('...and it resumes at the right step', /what has been selling/.test(app()));

// ═══ AN ESCAPE HATCH ═══
blank(); setupName('Y');
ck('there is a way out of the whole thing', /Skip for now and look around/.test(app()));
ck('no NaN anywhere in the flow', !/NaN/.test(app()));
console.log(FW.length?('\n'+FW.length+' FAILED: '+FW.join(' | ')):'\nGUIDED SETUP: ALL PASS');

// ═══ EVERY STEP SAYS WHAT IT UNLOCKS ═══
(function(){
 let G=[];const ck2=(n,c,d='')=>{c?console.log('  PASS  '+n):(console.log('  FAIL  '+n+'  '+d),G.push(n))};
 ck2('every step has an unlocks line', SETUP_STEPS.every(s=>s.unlocks&&s.unlocks.length>10),
     SETUP_STEPS.filter(s=>!s.unlocks).map(s=>s.id).join());
 ck2('...and they are all different', new Set(SETUP_STEPS.map(s=>s.unlocks)).size===SETUP_STEPS.length);
 blank(); setupName('Z');
 let h=app();
 ck2('unlocks render as pills', /class="unlocks">Unlocks <span class="unlockpill"/.test(h));
 ck2('...naming what step one turns on', /food cost per dish/.test(h));
 DATA.menu=[{id:'m',name:'A',menuPrice:5,weeklySales:0,dept:'kitchen',lines:[]}];
 ck2('...and changes with the step', /which twenty dishes make your money/.test(app()));
 DATA.menu[0].weeklySales=5;
 // daily and hours now precede invoices; drive to invoices past the break
 DATA.week.salesByDay=[100,0,0,0,0,0,0];
 DATA.week.employees=[{name:'A',rate:2,hours:[8,0,0,0,0,0,0]}];
 edit(()=>{DATA.setup.breakSeen={invoices:true}});
 ck2('...for invoices too', /price-drift warnings/.test(app()));

 // A promise here has to be one the app keeps.
 const promised=SETUP_STEPS.map(s=>s.unlocks).join(' ').toLowerCase();
 ck2('prime cost is promised and exists', /prime cost/.test(promised)&&typeof primeCost==='function');
 ck2('sales per labour hour is promised and exists', /sales per labour hour/.test(promised)&&typeof splh==='function');
 ck2('supplier comparison is promised and exists',
     /supplier price comparison/.test(promised)&&typeof supplierSpread==='function');
 ck2('price drift is promised and exists', /price-drift/.test(promised)&&typeof priceDrift==='function');
 ck2('price comparison is promised and exists', /price comparison/.test(promised)&&typeof marketCompare==='function');
 ck2('menu engineering is promised and is a real screen', /menu engineering/.test(promised)&&BUILT.has('eng'));
 ck2('theoretical vs actual is promised and is a real screen',
     /theoretical vs actual/.test(promised)&&BUILT.has('tva'));
 ck2('over-pour is promised and is a real screen', /over-pour/.test(promised)&&BUILT.has('pour'));
 console.log(G.length?('\n'+G.length+' UNLOCK FAILED: '+G.join(' | ')):'UNLOCKS: ALL PASS');
})();

// ═══ THE FLOW MUST NOT HAND YOU OFF ═══
(function(){
 let G=[];const ck2=(n,c,d='')=>{c?console.log('  PASS  '+n):(console.log('  FAIL  '+n+'  '+d),G.push(n))};
 blank(); setupName('M');
 let h=app();
 ck2('step one opens a file picker, not the dashboard', /<input type="file"/.test(h));
 ck2('...and does NOT navigate away', !/onclick="go\('import'\)"/.test(h));
 ck2('...accepting a PDF, a photo, a CSV or Excel',
     /accept="\.csv,\.txt,\.tsv,\.pdf,\.xlsx,image\/\*"/.test(h));
 ck2('...with a line saying what to pick', /A menu PDF, a photo of the menu/.test(h));

 // every step that takes a file must offer one inline
 const withPick=SETUP_STEPS.filter(s=>s.pick);
 ck2('five of the six steps take a file directly', withPick.length===5, String(withPick.length));
 // A top-level `function foo(){}` is not on globalThis under CommonJS, so
 // resolve by name the way the browser will — through the scope chain.
 const fnExists=n=>{try{return typeof eval(n)==='function'}catch(e){return false}};
 ck2('...and each names a real handler',
     withPick.every(s=>s.pick.fn?fnExists(s.pick.fn):!!IMPORT_KINDS[s.pick.kind]),
     withPick.filter(s=>!(s.pick.fn?fnExists(s.pick.fn):!!IMPORT_KINDS[s.pick.kind]))
       .map(s=>s.id+':'+(s.pick.kind||s.pick.fn)).join());
 ck2('...including the item-sales reader', fnExists('importSales'));
 ck2('...and every file kind is one the importer knows',
     withPick.filter(s=>s.pick.kind).every(s=>!!IMPORT_KINDS[s.pick.kind]));
 ck2('the recipes step downloads sheets in place, not navigating away',
     SETUP_STEPS.find(s=>s.id==='recipes').act==='downloadAllRecipeSheets()'
     && !SETUP_STEPS.find(s=>s.id==='recipes').go);
 ck2('invoices take several files at once', SETUP_STEPS.find(s=>s.id==='invoices').pick.multiple===true);

 // the nav stays hidden once you land on the mapper
 DATA.menu=[]; view='import'; STAGE=null; render(); drawSide();
 ck2('the sidebar stays hidden on the import screen during setup',
     __store['side'].style.display==='none');
 h=__store['app'].innerHTML;
 // With no file staged this is now the MINIMAL step screen, which shows the
 // pips rather than the banner card. The banner belongs to the column mapper.
 ck2('...and it says which step you are on', /step 1 of 6/.test(h));
 ck2('...with a way back into the flow', /back to setup/.test(h));
 STAGE={kind:'products',headers:['Item','Price'],rows:[['A','1']],map:{name:0,price:1},headerRow:0};
 render(); h=__store['app'].innerHTML;
 ck2('the column mapper carries the setup banner', /Setup · step 1 of 6/.test(h));
 ck2('...and its own way back', /back to setup/.test(h));
 STAGE=null;

 // and once setup is finished, none of that applies
 DATA.setup.done=true; SETUP_DISMISSED=true; render(); drawSide();
 ck2('after setup the sidebar returns', __store['side'].style.display!=='none');
 ck2('...and the banner is gone', !/back to setup/.test(__store['app'].innerHTML));
 console.log(G.length?('\n'+G.length+' HANDOFF FAILED: '+G.join(' | ')):'NO HANDOFF: ALL PASS');
})();

// ═══ OPENING THE APP RESUMES WHAT YOU MISSED ═══
(function(){
 let G=[];const ck2=(n,c,d='')=>{c?console.log('  PASS  '+n):(console.log('  FAIL  '+n+'  '+d),G.push(n))};
 const relaunch=()=>{ SETUP_DISMISSED=false; };   // what a page load does

 // Monday: menu in, then leaves.
 blank(); setupName('Sadeq');
 DATA.menu=[{id:'m',name:'A',menuPrice:5,weeklySales:0,dept:'kitchen',lines:[]}];
 setupDismiss();
 ck2('dismissing gets you into the app', !inSetup()&&view==='dash');
 ck2('...without claiming setup was finished', DATA.setup.done!==true);
 ck2('...and it does not nag again this session', !inSetup());

 // Tuesday.
 relaunch();
 ck2('opening the app again resumes the flow', inSetup());
 let h=app();
 ck2('...at the step that was missed, not from the top', /what has been selling/.test(h));
 ck2('...and does not re-ask the name', !/What should I call you/.test(h));

 // A SKIPPED step is a decision and must not come back.
 setupSkip('sales'); setupSkip('invoices'); setupSkip('daily'); setupSkip('recipes');
 relaunch();
 h=app();
 // Check the HEADING, not the whole page: every step's title also appears as
 // a tooltip on its progress pip, which is correct and would defeat a naive
 // substring match.
 const heading=()=>((__store['app'].innerHTML.match(/<h1>([^<]*)<\/h1>/)||[])[1]||'');
 ck2('a skipped step is not raised again', !/what has been selling/.test(heading()), heading());
 ck2('...the flow moves to the next outstanding one', /Staff hours/.test(heading()), heading());
 setupSkip('hours'); relaunch();
 ck2('with everything skipped or done, nothing is outstanding', setupOutstanding().length===0);
 h=app();
 ck2('...it shows the closing screen once', /That's it/.test(h));
 ck2('...saying skipped steps stay skipped', /stay skipped/.test(h));
 setupFinish();
 relaunch();
 ck2('after finishing with nothing outstanding it stops appearing', !inSetup());

 // Un-skipping brings it back on the next launch.
 setupUnskip('invoices');
 ck2('un-skipping makes it outstanding again', setupOutstanding().some(s=>s.id==='invoices'));
 relaunch();
 ck2('...and the flow returns on next open', inSetup());
 // invoices sits behind the break; acknowledge it, then it shows
 edit(()=>{DATA.setup.breakSeen={invoices:true}});
 ck2('...at that step', /real work/.test(app())||/Choose your invoices/.test(app()));

 // Doing the work quietly, outside the flow, also settles it.
 DATA.ingredients=[{id:'i',name:'X',price:2,recipeUnit:'kg',ruPerPu:1,pu:'kg',yield:1}];
 relaunch();
 ck2('data added anywhere counts — no need to do it through the flow',
     !setupOutstanding().some(s=>s.id==='invoices'));

 // The wording tells the truth about which button does what.
 blank(); setupName('Z'); h=app();
 ck2('the exit says it will come back', /comes back next time you open the app/.test(h));
 ck2('...and points at the button that settles a step', /to settle a step for good/.test(h));

 // An established book that never used the flow is not hijacked.
 blank(); DATA.setup={name:'',done:false,started:false,skipped:{}};
 DATA.menu=[{id:'m',name:'A',menuPrice:5,weeklySales:9,dept:'kitchen',lines:[{ref:'x',qty:1}]}];
 DATA.ingredients=[{id:'i',name:'X',price:2,recipeUnit:'kg',ruPerPu:1,pu:'kg',yield:1}];
 DATA.week={days:['a','b','c','d','e','f','g'],salesByDay:[9,0,0,0,0,0,0],guests:[1,0,0,0,0,0,0],
   employees:[{name:'A',rate:2,hours:[8,0,0,0,0,0,0]}],purchases:[]};
 relaunch();
 ck2('an existing book that never started the flow is left alone', !inSetup());
 console.log(G.length?('\n'+G.length+' RESUME FAILED: '+G.join(' | ')):'RESUME: ALL PASS');
})();

// ═══ THE MOMENT AFTER A FILE LANDS ═══
(function(){
 let G=[];const ck2=(n,c,d='')=>{c?console.log('  PASS  '+n):(console.log('  FAIL  '+n+'  '+d),G.push(n))};
 blank(); setupName('Sadeq'); CELEBRATE=null;
 DATA.rates={vat:0,service:0,levy:0};
 // upload a menu through the real path
 STAGE={kind:'products',headers:['Item','Price'],rows:[['Burger','5'],['Wrap','4'],['Salad','3']],
   map:{name:0,price:1},headerRow:0};
 global.__alerts=[];
 stageApply();
 ck2('finishing a step opens the celebration, not a dashboard', !!CELEBRATE);
 ck2('...and no alert box interrupts it', (__alerts||[]).length===0, (__alerts||[]).join());
 view='today'; render(); let h=__store['app'].innerHTML;
 ck2('it says what it says', /Unlocking hidden money/.test(h));
 ck2('...names the step that landed', /your menu<\/b> is in/.test(h)||/menu<\/b> is in/.test(h));
 ck2('...counts what actually arrived', /3 dishes priced/.test(h), (h.match(/\d+ dishes priced/)||[])[0]||'');
 ck2('there is a progress bar', /class="meter"/.test(h)&&/class="fill"/.test(h));
 ck2('...whose width is the REAL trust score',
     new RegExp('width:'+Math.max(2,Math.round(trustScore()*100))+'%').test(h),
     (h.match(/width:\d+%/)||[])[0]||'');
 ck2('...and it says where the book moved from and to',
     /complete/.test(h)&&/<b>\d+%<\/b> to <b>\d+%<\/b>/.test(h),
     (h.match(/from <b>[^<]*<\/b> to <b>[^<]*<\/b>[^<]*/)||[])[0]||'');
 ck2('the step\'s unlocks are shown', /Now switched on · food cost per dish/.test(h));
 ck2('the button names the NEXT step', /Next — what has been selling/.test(h),
     (h.match(/Next — [^<]*/)||[])[0]||'');
 ck2('...with a line about it', /item sales report/.test(h));
 ck2('no NaN', !/NaN/.test(h));

 // it holds you until you press on
 SETUP_DISMISSED=true;
 ck2('nothing can navigate away mid-celebration', inSetup()===true);
 SETUP_DISMISSED=false;
 celebrateDone();
 ck2('pressing on clears it', CELEBRATE===null);
 ck2('...and lands on the next step', /what has been selling/.test(app()));

 // a file that does NOT finish a step should not celebrate
 CELEBRATE=null;
 STAGE={kind:'products',headers:['Item','Price'],rows:[['Another','6']],map:{name:0,price:1},headerRow:0};
 global.__alerts=[]; TOASTS=[];
 stageApply();
 ck2('an import that completes nothing new does not celebrate', CELEBRATE===null);
 // A non-milestone import now reports with a toast rather than an alert.
 ck2('...and reports normally instead', TOASTS.length>0||(__alerts||[]).length>0);

 // the last step ends differently
 blank(); setupName('Z');
 DATA.menu=[{id:'m',name:'A',menuPrice:5,weeklySales:1,dept:'kitchen',lines:[]}];
 DATA.ingredients=[{id:'i',name:'X',price:1,recipeUnit:'kg',ruPerPu:1,pu:'kg',yield:1}];
 DATA.week={days:['a','b','c','d','e','f','g'],salesByDay:[9,0,0,0,0,0,0],guests:[1,0,0,0,0,0,0],
   employees:[{name:'A',rate:1,hours:[8,0,0,0,0,0,0]}],purchases:[]};
 SETUP_STEPS.forEach(s=>{if(s.id!=='recipes'&&!setupDone(s))setupSkip(s.id)});
 DATA.menu[0].lines=[{ref:'X',qty:1}];
 celebrateStep('recipes',{trust:0.5,count:''});
 render(); h=__store['app'].innerHTML;
 ck2('the final step points at the unlocked report', /See what you unlocked/.test(h));
 console.log(G.length?('\n'+G.length+' CELEBRATE FAILED: '+G.join(' | ')):'CELEBRATION: ALL PASS');
})();

// ═══ A FAILED FILE MUST NOT DUMP THE WHOLE CONSOLE ON YOU ═══
(function(){
 let G=[];const ck2=(n,c,d='')=>{c?console.log('  PASS  '+n):(console.log('  FAIL  '+n+'  '+d),G.push(n))};
 blank(); setupName('Sadeq'); CELEBRATE=null; STAGE=null;
 DATA.ai={provider:'',key:'',enabled:false,calls:0,ledger:[],auth:[]};
 // the exact failure: an outlines-only menu PDF
 FILEFAIL={file:'The Menu.pdf',short:'The text was converted to outlines when this menu was exported.',
   why:'The letters are drawings of letter shapes, not letters.',reason:'outlines',canVision:true};
 view='import'; render(); let h=__store['app'].innerHTML;

 ck2('the failure is the headline', /That file could not be read/.test(h));
 ck2('...with the explanation', /converted to outlines/.test(h));
 // none of the administrative furniture
 ck2('the four intake routes are NOT shown', !/How your numbers get in/.test(h));
 ck2('the POS chooser is not shown', !/Which POS do you run/.test(h));
 ck2('the eight upload kinds are not shown', !/Purchases \/ goods received/.test(h));
 ck2('backups are not shown', !/Download a backup/.test(h));
 ck2('spend limits are not shown', !/Per batch/.test(h));
 ck2('the long AI essay is not shown', !/It never calculates/.test(h));

 // exactly the three things you can do
 ck2('you can add a key right here', /setAI\('key'/.test(h));
 ck2('...explained in one line', /looks at the pages the way you do/.test(h));
 ck2('you can pick another file', /<input type="file"/.test(h));
 ck2('you can go back', /back to setup/.test(h));
 ck2('you can skip the step', /setupSkip\('menu'\)/.test(h));
 ck2('progress is still visible', /wpip/.test(h)&&/step 1 of 6/.test(h));
 ck2('no NaN', !/NaN/.test(h));

 // with a key already set, it says to retry rather than offering the field again
 DATA.ai={provider:'anthropic',key:'k',enabled:true,calls:0,ledger:[],auth:[]};
 render(); h=__store['app'].innerHTML;
 ck2('with a key set it tells you to retry the same file', /Try that file again/.test(h));
 ck2('...and does not ask for a key again', !/setAI\('key'/.test(h));

 // no failure: the step itself, still minimal
 FILEFAIL=null; render(); h=__store['app'].innerHTML;
 ck2('with no failure it shows the step, minimally', /First — your menu/.test(h));
 ck2('...still without the four routes', !/How your numbers get in/.test(h));
 ck2('...and its unlocks', /food cost per dish/.test(h));

 // outside setup the full screen is unchanged
 DATA.setup.done=true; SETUP_DISMISSED=true; render(); h=__store['app'].innerHTML;
 ck2('outside setup the full import screen is intact', /How your numbers get in/.test(h));
 ck2('...with every upload kind', /Purchases \/ goods received/.test(h));
 console.log(G.length?('\n'+G.length+' FOCUS FAILED: '+G.join(' | ')):'FOCUSED IMPORT: ALL PASS');
})();

// ═══ THE LAST STEP STAYS IN THE FLOW ═══
(function(){
 let G=[];const ck2=(n,c,d='')=>{c?console.log('  PASS  '+n):(console.log('  FAIL  '+n+'  '+d),G.push(n))};
 blank(); setupName('Sadeq'); CELEBRATE=null;
 // complete every step except recipes so recipes is the current one
 DATA.menu=[{id:'m1',name:'Big Seller',menuPrice:9,weeklySales:200,dept:'kitchen',lines:[]},
            {id:'m2',name:'Quiet',menuPrice:5,weeklySales:1,dept:'kitchen',lines:[]}];
 DATA.ingredients=[{id:'i',code:'001',name:'X',price:2,recipeUnit:'kg',ruPerPu:1,pu:'kg',yield:1,
   history:[{at:Date.parse('2026-05-01'),price:2,supplier:'S'},{at:Date.parse('2026-07-01'),price:2,supplier:'S'}]}];
 DATA.week={days:['a','b','c','d','e','f','g'],salesByDay:[100,0,0,0,0,0,0],guests:[9,0,0,0,0,0,0],
   employees:[{name:'A',rate:2,hours:[8,0,0,0,0,0,0]}],purchases:[]};
 rebuildIX();rebuildBX();
 const idx=setupIndex();
 ck2('the flow is on the last step (recipes)', SETUP_STEPS[idx].id==='recipes', SETUP_STEPS[idx]&&SETUP_STEPS[idx].id);

 let h=app();
 ck2('its action downloads one file, not go(sheets)', /onclick="downloadAllRecipeSheets\(\)"/.test(h)&&!/go\('sheets'\)/.test(h));
 ck2('...and the secondary button finishes to the report', /Finish → see the report/.test(h));
 ck2('...with a plain-language finish link too', /Finish setup and show me where the money went/.test(h));
 ck2('...explaining recipes carry on after setup', /carries on after setup|carry on after setup|works on everything else/.test(h));

 // downloading does NOT leave the flow
 let dl=null,clicked=false;
 global.URL={createObjectURL:()=>'blob:x'};
 global.Blob=function(p,o){this.parts=p;this.type=o&&o.type};
 global.document.createElement=(t)=>({set href(v){},set download(v){dl=v},click(){clicked=true}});
 TOASTS=[];
 downloadAllRecipeSheets();
 ck2('it saves one file', clicked===true);
 ck2('...named as recipe sheets', /recipe-sheets-\d{4}-\d{2}-\d{2}\.html/.test(dl), dl);
 ck2('...and does NOT change the view', view==='today', view);
 ck2('...still in setup', inSetup()===true);
 ck2('...covering the whole menu in one file', TOASTS.some(t=>/one file with 2 recipe sheet/.test(t.msg)), TOASTS.map(x=>x.msg).join('|'));

 // finishing from the last step reaches the report
 setupSkip('recipes'); setupFinish();
 ck2('finishing the last step lands on the unlocked report', view==='unlocked', view);
 ck2('...and setup is done', DATA.setup.done===true);
 console.log(G.length?('\n'+G.length+' LAST-STEP FAILED: '+G.join(' | ')):'LAST STEP IN FLOW: ALL PASS');
})();
