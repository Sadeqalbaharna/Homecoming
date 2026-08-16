let FF=[];const ck=(n,c,d='')=>{c?console.log('  PASS  '+n):(console.log('  FAIL  '+n+'  '+d),FF.push(n))};
SESSION={username:'owner',role:'owner'};WHO='owner';DATA.firstRunDone=true;SETUP_DISMISSED=true;
(async()=>{
// fill the book with something of everything
const fill=()=>{
  DATA.menu=[{id:'m',name:'Dish',menuPrice:5,weeklySales:9,dept:'kitchen',lines:[{ref:'001_X',qty:1}]}];
  DATA.ingredients=[{id:'i',code:'001',name:'X',price:2,recipeUnit:'kg',ruPerPu:1,pu:'kg',yield:1,history:[{at:1,price:2}]}];
  DATA.ledger={days:{'2026-05-01':{date:'2026-05-01',sales:100,src:['f.csv']}},purchases:[{id:'P',supplier:'S',date:'2026-05-01',amount:5}]};
  DATA.rateBook={Ana:3}; DATA.market=[{id:'k',name:'Cafe',items:[{name:'a',price:1}]}];
  DATA.docs=[{id:'d',name:'inv.jpg',where:'browser',bytes:10}];
  DATA.rates={vat:0.1,service:0.1,levy:0.02};
  DATA.venueInfo={city:'Adliya',country:'BH'};
  DATA.setup={name:'Sadeq',done:true,started:true,skipped:{hours:true}};
  DATA.ai={provider:'anthropic',key:'sk-secret',enabled:true,remember:true,calls:5,ledger:[{at:1}],auth:[]};
  DATA.week={days:['2026-05-01','','','','','',''],salesByDay:[100,0,0,0,0,0,0],guests:[9,0,0,0,0,0,0],
    employees:[{name:'Ana',rate:3,hours:[8,0,0,0,0,0,0]}],purchases:[]};
  DATA.countHistory=[{at:1}]; DATA.audit=[{at:1,what:'x'}];
  UNDO.push('x'); STAGE={kind:'products'}; FILEFAIL={file:'x'};
  rebuildIX();rebuildBX();save();
};

// ═══ IT CANNOT GO OFF BY ACCIDENT ═══
fill(); global.__alerts=[];
let ok=await formatEverything('yes');
ck('a wrong word does nothing', ok===false&&(DATA.menu||[]).length===1);
ck('...and says so', /Type FORMAT to confirm/.test((__alerts||[]).join()));
ok=await formatEverything('');
ck('an empty answer does nothing', ok===false&&(DATA.menu||[]).length===1);
ok=await formatEverything('format');
ck('lower case is accepted — it is deliberate either way', ok===true);

// ═══ IT CLEARS EVERYTHING ═══
fill();
let offered=false; global.confirm=()=>{offered=true;return false};
await formatEverything('FORMAT');
ck('a backup is offered before anything is deleted', offered);
ck('the menu is gone', (DATA.menu||[]).length===0);
ck('the ingredients are gone', (DATA.ingredients||[]).length===0);
ck('the day ledger is gone', ledgerDates().length===0);
ck('...and its purchases', (DATA.ledger.purchases||[]).length===0);
ck('wage rates are gone', Object.keys(DATA.rateBook||{}).length===0);
ck('competitor menus are gone', (DATA.market||[]).length===0);
ck('document records are gone', (DATA.docs||[]).length===0);
ck('tax rates are back to zero', DATA.rates.vat===0&&DATA.rates.levy===0);
ck('the venue location is gone', !(DATA.venueInfo||{}).city);
ck('the week is empty', (DATA.week.salesByDay||[]).every(v=>!v));
ck('...and its staff', (DATA.week.employees||[]).length===0);
ck('stock counts are gone', (DATA.countHistory||[]).length===0);
// The key is kept by default — a testing convenience, stated everywhere.
ck('the API key is KEPT by default', (DATA.ai||{}).key==='sk-secret', (DATA.ai||{}).key);
ck('...along with the provider', (DATA.ai||{}).provider==='anthropic');
ck('...but the usage history is not data worth keeping', ((DATA.ai||{}).ledger||[]).length===0);
ck('...nor the call count', (DATA.ai||{}).calls===0);
ck('the undo stack is gone', UNDO.length===0);
ck('any staged import is gone', STAGE===null);
ck('any file error is gone', FILEFAIL===null);
ck('the ingredient index rebuilt empty', Object.keys(IX||{}).length===0);
ck('browser storage was cleared', !localStorage.getItem(KEY)||!JSON.parse(localStorage.getItem(KEY)).menu.length);

// ═══ IT RETURNS YOU TO THE START ═══
ck('setup is reset', DATA.setup.started===false&&DATA.setup.done===false);
ck('...with no name remembered', DATA.setup.name==='');
ck('...no skipped steps carried over', Object.keys(DATA.setup.skipped||{}).length===0);
ck('the flow is live again', inSetup()===true);
ck('...and the view is the welcome screen', view==='today');
render();
ck('...which asks the name', /What should I call you/.test(__store['app'].innerHTML));
// and the explicit wipe really does take it
fill();
await formatEverything('FORMAT',{keepKey:false});
ck('formatting WITH the key removes it', (DATA.ai||{}).key==='');
ck('...and the provider', (DATA.ai||{}).provider==='');
ck('...and the remember flag', !(DATA.ai||{}).remember);
ck('...while still clearing everything else', (DATA.menu||[]).length===0&&ledgerDates().length===0);
ck('no NaN', !/NaN/.test(__store['app'].innerHTML));

// ═══ IT SURVIVES A RELOAD ═══
DATA.menu=[{id:'z',name:'ghost',menuPrice:1,lines:[],weeklySales:0,dept:'kitchen'}];
load();
ck('reloading after a format does not resurrect anything', (DATA.menu||[]).length===0,
   JSON.stringify((DATA.menu||[]).map(m=>m.name)));

// ═══ THE BUTTONS ═══
// A book WITH data never shows the welcome screen — an existing book is not
// hijacked into onboarding — so the reachable case is a clean book.
await formatEverything('FORMAT');
DATA.setup={name:'',done:false,started:false,skipped:{}}; SETUP_DISMISSED=false;
view='today'; render(); let h=__store['app'].innerHTML;
ck('the welcome screen is showing', /What should I call you/.test(h));
ck('...and offers format for repeat testing', /formatPrompt\(true\)/.test(h));
ck('...saying the key is the exception', /except your API key/.test(h));
SETUP_DISMISSED=true; view='settings'; render(); h=__store['app'].innerHTML;
ck('settings offers both', /formatPrompt\(true\)/.test(h)&&/formatPrompt\(false\)/.test(h));
ck('...listing what goes', /every day of history/.test(h));
ck('...and that it offers a backup first', /download a backup first/.test(h));
DATA.ai={provider:'anthropic',key:'sk-x',enabled:true,calls:0,ledger:[],auth:[]};
render(); h=__store['app'].innerHTML;
ck('...and warns that a formatted console is not an empty one when a key is saved',
   /a formatted console is not an empty one/.test(h));
DATA.ai={provider:'',key:'',enabled:false,calls:0,ledger:[],auth:[]};
render(); h=__store['app'].innerHTML;
ck('...and says so plainly when there is no key', /both buttons do the same thing/.test(h));
console.log(FF.length?('\n'+FF.length+' FAILED: '+FF.join(' | ')):'\nFORMAT: ALL PASS');
})();
