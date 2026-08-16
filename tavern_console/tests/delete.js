let FD=[];const ck=(n,c,d='')=>{c?console.log('  PASS  '+n):(console.log('  FAIL  '+n+'  '+d),FD.push(n))};
SESSION={username:'owner',role:'owner'};WHO='owner';
// The guided flow now returns on every launch while steps are outstanding,
// so a suite testing the ordinary app has to say it has been dismissed.
SETUP_DISMISSED=true;
DATA.setup={name:'x',done:true,started:true,skipped:{}};DATA.firstRunDone=true;
STAGE=null;INVBATCH=null;RESEARCH=null;CATPROP=null;
const ing=(code,name,price)=>({id:'i'+code,code,name,price,recipeUnit:'g-wt',ruPerPu:1000,
  purchaseUnit:'KG',yield:1,category:'Seafood'});
const reset=()=>{DATA.ingredients=[ing('1852','Salmon Fillet',0),ing('1853','Seabass Fillet',0),
  ing('1854','Octopus',12)];
  DATA.menu=[{id:'m1',name:'Salmon Plate',menuPrice:9,weeklySales:5,dept:'kitchen',
    lines:[{ref:'1852_Salmon Fillet',qty:180}]}];
  DATA.batch=[];rebuildIX();rebuildBX();};

// ═══ WHAT USES IT ═══
reset();
ck('an ingredient in a recipe reports its dish', ingUsedBy('1852').includes('Salmon Plate'));
ck('an unused one reports nothing', ingUsedBy('1853').length===0);
DATA.batch=[{id:'b1',code:'B1',name:'Fish Stock',lines:[{ref:'1853_Seabass Fillet',qty:100}],
  yieldQty:1000,yieldUnit:'ml'}];
rebuildBX();
ck('batch recipes count too', ingUsedBy('1853').some(s=>/Fish Stock/.test(s)));
DATA.batch=[];rebuildBX();

// ═══ DELETE REFUSES WHEN IT WOULD BREAK A RECIPE ═══
reset();
global.__alerts=[];global.confirm=()=>true;
const before=DATA.ingredients.length;
delIng(0);                                   // Salmon Fillet — used
ck('deleting a used ingredient is refused', DATA.ingredients.length===before);
ck('...and says which recipes use it', /Salmon Plate/.test((__alerts||[]).join()));
ck('...and why it matters', /costing less than they do/.test((__alerts||[]).join()));

// ═══ DELETE WORKS WHEN IT IS SAFE ═══
delIng(1);                                   // Seabass — unused
ck('an unused ingredient deletes', DATA.ingredients.length===before-1);
ck('...and the right one went', !DATA.ingredients.some(x=>x.name==='Seabass Fillet'));
ck('...and the index rebuilt', !IX['1853']);
ck('...and it is undoable', (undo(),DATA.ingredients.length===before));

// declining the confirm does nothing
reset(); global.confirm=()=>false;
delIng(1);
ck('saying no leaves it alone', DATA.ingredients.length===3);
global.confirm=()=>true;

// ═══ BULK TIDY — the "I clicked + Seafood by mistake" case ═══
reset();
delUnusedUnpriced();
ck('unpriced and unused ingredients are removed together', DATA.ingredients.length===2,
   DATA.ingredients.map(x=>x.name).join());
ck('...the used one survives even though it has no price',
   DATA.ingredients.some(x=>x.name==='Salmon Fillet'));
ck('...and the priced one survives even though nothing uses it',
   DATA.ingredients.some(x=>x.name==='Octopus'));
ck('...and that is undoable too', (undo(),DATA.ingredients.length===3));
reset();
DATA.ingredients=[ing('1','A',5)];rebuildIX();
global.__alerts=[];
delUnusedUnpriced();
ck('with nothing to remove it says so rather than doing nothing silently',
   /Nothing to remove/.test((__alerts||[]).join()));

// ═══ THE BUTTONS ARE THERE ═══
reset(); view='ing'; render();
const h=__store['app'].innerHTML;
ck('every row has a delete', (h.match(/delIng\(/g)||[]).length===DATA.ingredients.length);
ck('the bulk tidy is offered', /delUnusedUnpriced\(\)/.test(h));
ck('no NaN', !/NaN/.test(h));

// ═══ AND THE FLOW DOES NOT DUMP YOU OUT ═══
DATA.setup={name:'x',done:false,started:true,skipped:{}};
SETUP_DISMISSED=false;                       // as if the app was just opened
DATA.menu=[];DATA.ingredients=[];rebuildIX();
STAGE={kind:'products',headers:['Item','Price'],rows:[['Burger','5']],
  map:{name:0,price:1},headerRow:0};
stageApply();
ck('applying an import during setup returns to the flow', view==='today', view);
ck('...and the menu actually landed', (DATA.menu||[]).length===1);
// Completing a step opens the celebration, which deliberately holds the flow
// until it is dismissed — so dismiss it before testing the post-setup route.
ck('...via the celebration screen', !!CELEBRATE);
celebrateDone(); CELEBRATE=null;
DATA.setup.done=true; SETUP_DISMISSED=true;  // flow closed for this session
STAGE={kind:'products',headers:['Item','Price'],rows:[['Wrap','6']],
  map:{name:0,price:1},headerRow:0};
stageApply();
ck('after setup it goes to the screen the data landed on', view==='menu', view);
console.log(FD.length?('\n'+FD.length+' FAILED: '+FD.join(' | ')):'\nDELETE + FLOW: ALL PASS');
