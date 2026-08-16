let FS=[];const ck=(n,c,d='')=>{c?console.log('  PASS  '+n):(console.log('  FAIL  '+n+'  '+d),FS.push(n))};
SESSION={username:'owner',role:'owner'};WHO='owner';SETUP_DISMISSED=true;DATA.firstRunDone=true;
TOASTS=[];

// ═══ DEBOUNCE: A BURST OF EDITS IS ONE WRITE ═══
let writes=0;
const realSet=localStorage.setItem.bind(localStorage);
localStorage.setItem=(k,v)=>{writes++;return realSet(k,v)};
let timers=[];global.setTimeout=(fn,ms)=>{const id=timers.length;timers.push(fn);return id};
global.clearTimeout=(id)=>{if(id!=null)timers[id]=null};

DATA.ingredients=[{id:'a',code:'001',name:'X',price:1,recipeUnit:'kg',ruPerPu:1,pu:'kg',yield:1,history:[]}];
writes=0;
for(let i=0;i<20;i++)save();
ck('twenty rapid saves do not each write', writes===0, 'writes so far: '+writes);
ck('...they schedule instead', timers.filter(Boolean).length>=1);
// fire the pending timer
timers.filter(Boolean).forEach(fn=>fn());
ck('...and settle into a single write', writes===1, String(writes));

// ═══ saveNow WRITES IMMEDIATELY ═══
writes=0; saveNow();
ck('saveNow writes at once', writes===1);
ck('...recording the size', STORE_BYTES>0);

// ═══ SIZE WARNING WHILE THERE IS STILL ROOM ═══
TOASTS=[];DATA._storeWarned=false;
const bigHist=[];for(let i=0;i<200000;i++)bigHist.push({at:i,price:i%9});
DATA.ingredients[0].history=bigHist;
saveNow();
ck('a large book crosses the soft ceiling', STORE_BYTES>STORE_SOFT, (STORE_BYTES/1048576).toFixed(1)+'MB');
ck('...and warns with room to act', TOASTS.some(t=>/near the browser's limit/i.test(t.msg)));
ck('...pointing at backups', TOASTS.some(t=>/settings/.test(t.action||'')));
ck('...only once per session', (TOASTS=[],saveNow(),!TOASTS.some(t=>/near the browser/i.test(t.msg))));
DATA.ingredients[0].history=[];

// ═══ A REAL QUOTA FAILURE IS LOUD ═══
TOASTS=[];SAVEFAIL=null;
localStorage.setItem=(k,v)=>{const e=new Error('QuotaExceededError');throw e};
saveNow();
ck('a failed save is recorded', !!SAVEFAIL);
ck('...and shouted, not glanced past', TOASTS.some(t=>/SAVE FAILED/.test(t.msg)&&t.kind==='bad'));
ck('...with a way to rescue the data', TOASTS.some(t=>/backupDownload/.test(t.action||'')));
ck('...that stays on screen', TOASTS.some(t=>t.ms>=30000));
localStorage.setItem=realSet;

// ═══ CRITICAL PATHS STILL WRITE SYNCHRONOUSLY ═══
const html=require('fs').readFileSync(process.env.TC,'utf-8');
ck('format writes immediately, not debounced', /rebuildIX\(\); rebuildBX\(\); saveNow\(\);\n  view='today'/.test(html));
ck('restore writes immediately', /rebuildIX\(\); rebuildBX\(\); saveNow\(\);\n  return \{ok:true/.test(html));
ck('a debounced write is flushed when the tab hides', /visibilitychange/.test(html)&&/beforeunload/.test(html));

// ═══ SETTINGS SHOWS THE SIZE ═══
STORE_BYTES=1234567;SETUP_DISMISSED=true;view='settings';render();
const h=__store['app'].innerHTML;
ck('settings shows how big the book is', /1\.18 MB/.test(h)||/Storage/.test(h));
ck('...and that photos are separate', /photos are kept separately/.test(h));
ck('no NaN', !/NaN/.test(h));
console.log(FS.length?('\n'+FS.length+' FAILED: '+FS.join(' | ')):'\nSTORAGE: ALL PASS');
