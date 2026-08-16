let F=[];const ck=(n,c,d='')=>{c?console.log('  PASS  '+n):(console.log('  FAIL  '+n+'  '+d),F.push(n))};
SESSION={username:'owner',role:'owner'};WHO='owner';DATA.firstRunDone=true;

// ═══ 1. THE SAVE BUG: nothing durable may be silently dropped ═══
ck('every key of DATA is either persisted or explicitly transient',
   persistCheck().length===0, persistCheck().join(', '));
ck('rates are persisted — every margin divides by them', PERSIST.includes('rates'));
ck('the prime-cost week is persisted', PERSIST.includes('week'));
ck('source documents are persisted', PERSIST.includes('docs'));
ck('the API key is not in the durable list', !PERSIST.includes('ai'));

// round-trip through storage
DATA.rates={vat:0.10,service:0.10,levy:0.05};
DATA.week={days:['Mon'],salesByDay:[1234],employees:[{name:'A',hours:[8]}],purchases:[{supplier:'X',amount:50}]};
DATA.ingredients=[{id:'a',name:'Salt',price:2,ruPerPu:1}];
DATA.menu=[{id:'1',name:'Dish',menuPrice:5,lines:[],weeklySales:0,dept:'kitchen'}];
DATA.docs=[{id:'d1',name:'IMG_2201.jpg',at:1,kind:'purchases',bytes:900,where:'browser'}];
saveNow();
const wiped={rates:null,week:null,docs:null};
DATA.rates={vat:0,service:0,levy:0}; DATA.week=null; DATA.docs=[];
ck('a reload restores the tax rates', (load(),DATA.rates.vat)===0.10, JSON.stringify(DATA.rates));
ck('...the tourism levy too', DATA.rates.levy===0.05);
ck('...the whole trading week', DATA.week&&DATA.week.salesByDay[0]===1234);
ck('...the staff hours in it', DATA.week.employees[0].hours[0]===8);
ck('...and the document records', DATA.docs.length===1&&DATA.docs[0].name==='IMG_2201.jpg');

// the key: not kept unless asked for
DATA.ai={provider:'anthropic',key:'sk-secret',enabled:true,calls:3,remember:false};
saveNow(); DATA.ai={provider:'',key:'',enabled:false,calls:0}; load();
ck('the API key is NOT kept by default', DATA.ai.key==='' , DATA.ai.key);
ck('...but the provider and usage are', DATA.ai.provider==='anthropic'&&DATA.ai.calls===3);
DATA.ai={provider:'anthropic',key:'sk-secret',enabled:true,calls:3,remember:true};
saveNow(); DATA.ai={provider:'',key:'',enabled:false}; load();
ck('...and it IS kept when you opt in', DATA.ai.key==='sk-secret');
ck('a backup never contains the key', !JSON.stringify(backupPayload()).includes('sk-secret'));

// a failed write must not be silent
SAVEFAIL=null;
const realSet=localStorage.setItem.bind(localStorage);
localStorage.setItem=()=>{throw new Error('QuotaExceededError')};
// saveNow: the failure has to actually attempt the write, not sit in a timer.
saveNow(); localStorage.setItem=realSet;
ck('a storage failure is recorded, not swallowed', !!SAVEFAIL, String(SAVEFAIL));

// ═══ 2. THE GOVERNOR ═══
DATA.ai={provider:'anthropic',key:'k',enabled:true,calls:0,ledger:[],auth:[]};
ck('a first run is allowed', authorizeCalls(1).ok);
ck('a batch inside the per-run limit is allowed', authorizeCalls(30).ok);
ck('a batch over it is refused', !authorizeCalls(31).ok);
ck('...by name', authorizeCalls(31).cause==='runTooLarge');
ck('...and the refusal says the number and the limit', /31 documents.*limit of 30/.test(authorizeCalls(31).reason));

for(let i=0;i<200;i++)aiLedger().push({at:Date.now(),kind:'x'});
ck('the daily limit binds', !authorizeCalls(1).ok&&authorizeCalls(1).cause==='dailyExhausted');
ck('...and clears itself rather than needing a human', !authorizeCalls(1).needsHuman);
aiLedger().forEach(e=>e.at=Date.now()-90000000);   // yesterday
ck('yesterday does not count against today', authorizeCalls(1).ok);

DATA.ai.limits={perRun:30,perDay:200,lifetime:200,costPerCall:0.02};
ck('the lifetime limit binds', !authorizeCalls(1).ok&&authorizeCalls(1).cause==='lifetimeExhausted');
ck('...and only a human lifts it', authorizeCalls(1).needsHuman);
grantCalls(50);
ck('a grant lifts it', authorizeCalls(1).ok);
ck('...without erasing the record of what was spent', aiLedger().length===200);
ck('...and is attributed and timestamped',
   DATA.ai.auth[0].by==='owner'&&DATA.ai.auth[0].at>0);

DATA.ai.limits={perRun:50,perDay:10,lifetime:5};
ck('contradictory limits refuse rather than guess', authorizeCalls(1).cause==='misconfigured');
DATA.ai.limits=null; DATA.ai.ledger=[]; DATA.ai.auth=[];
ck('cost is presented as an estimate, not a fact', /estimate/.test((recordCall('x'),spendLine())));
ck('...and the call count is exact', /1 of 2000 lifetime/.test(spendLine()), spendLine());

// ═══ 3. BACKUPS ═══
DATA._lastBackup=0;
ck('a book that has never been backed up is stale', backupStale());
DATA._lastBackup=Date.now();
ck('...and is not, once it has', !backupStale());
DATA._lastBackup=Date.now()-8*86400000;
ck('...and goes stale again after a week', backupStale());
ck('the backup filename is dated and sortable', /^costing-console-\d{4}-\d{2}-\d{2}-\d{4}\.json$/.test(backupName()), backupName());

const pay=JSON.stringify(backupPayload());
let r=restoreBackup(pay);
ck('a backup restores', r.ok, r.why);
ck('...reporting what it restored', r.items>=1);
r=restoreBackup('{"menu":[],"ingredients":[]}');
ck('a foreign JSON file is refused', !r.ok);
ck('...saying why, rather than half-loading it', /half-overwrite/.test(r.why));
r=restoreBackup('not json at all');
ck('junk is refused', !r.ok&&/readable JSON/.test(r.why));
const bad=JSON.parse(pay); delete bad.ingredients;
ck('an incomplete backup is refused', !restoreBackup(JSON.stringify(bad)).ok);

// ═══ 4. PROVENANCE ═══
ck('a document id is unique', docId()!==docId());
const rec={id:'dabc',name:'IMG 2201 (1).jpg',at:Date.parse('2026-07-21T10:05:00Z'),bytes:9};
ck('the stored filename is dated and safe',
   /^2026-\d{2}-\d{2}_dabc_IMG_2201_\(?1?\)?\.?jpg$/.test(docFileName(rec).replace(/[()]/g,''))||
   /^2026-\d{2}-\d{2}_dabc_/.test(docFileName(rec)), docFileName(rec));
ck('...with no characters that break a filesystem', !/[\/\\:*?"<>|]/.test(docFileName(rec)));
DATA.docs=[{id:'a',where:'folder',bytes:1048576},{id:'b',where:'browser',bytes:1048576},
           {id:'c',where:'failed',bytes:0}];
const s=docStats();
ck('the console can say where the paper actually is',
   s.n===3&&s.folder===1&&s.browser===1&&s.failed===1);
ck('...and how much of it there is', Math.round(s.mb)===2);
ck('documents are not kept in localStorage', !/bytes.*base64|data:image/.test(JSON.stringify(backupPayload())));
console.log(F.length?('\n'+F.length+' FAILED: '+F.join(' | ')):'\nDURABILITY: ALL PASS');
// ═══ UI ═══
(function(){
 let G=[];const ck2=(n,c,d='')=>{c?console.log('  PASS  '+n):(console.log('  FAIL  '+n+'  '+d),G.push(n))};
 DATA.ai={provider:'anthropic',key:'k',enabled:true,calls:0,ledger:[],auth:[],limits:null};
 DATA._lastBackup=0; DATA.docs=[]; STAGE=null; INVBATCH=null; view='import'; render();
 let h=__store['app'].innerHTML;
 ck2('a book with no backup says so loudly', /has never been a backup/.test(h));
 ck2('...and offers one click to fix it', /backupDownload\(\)/.test(h));
 ck2('...and a restore path', /restoreBackup/.test(h));
 ck2('the spend panel shows the limits', /Per batch/.test(h)&&/Lifetime/.test(h));
 ck2('...and labels money as an estimate', /is an <b>estimate<\/b>/.test(h));
 DATA._lastBackup=Date.now(); render(); h=__store['app'].innerHTML;
 ck2('a fresh backup stops the warning', !/has never been a backup/.test(h));
 // Daily exhaustion clears itself, so it must NOT offer a grant button.
 // perDay must not sit below perRun or the governor calls it incoherent —
 // which it is, and which this test proved by getting it wrong.
 DATA.ai.limits={perRun:1,perDay:1,lifetime:1000}; DATA.ai.ledger=[{at:Date.now()}]; render();
 h=__store['app'].innerHTML;
 ck2('a held state is shown with its reason', /<b>Held\.<\/b>/.test(h));
 ck2('a daily halt offers no grant — it clears itself', !/grantCalls\(200\)/.test(h));
 // A lifetime halt is a decision about money, so it needs a human.
 // lifetime must not sit below perDay either. Twice now my scenario has been
 // the incoherent one and the governor has been right — which is the guard
 // doing its job on the person most likely to misconfigure it.
 DATA.ai.limits={perRun:5,perDay:10,lifetime:10};
 DATA.ai.ledger=Array.from({length:10},()=>({at:Date.now()-90000000})); render();
 h=__store['app'].innerHTML;
 ck2('a lifetime halt offers a human the choice', /grantCalls\(200\)/.test(h));
 ck2('...and says the decision is theirs', /yours rather than mine/.test(h));
 DATA.docs=[{id:'d1',name:'a.jpg',at:Date.now(),bytes:2097152,where:'browser'}];
 DATA.ai.limits=null; render(); h=__store['app'].innerHTML;
 ck2('kept documents are counted', /1 source document\(s\) kept/.test(h));
 ck2('...with an honest warning about browser storage', /disappears with the same/.test(h));
 ck2('no NaN anywhere', !/NaN/.test(h));
 console.log(G.length?('\n'+G.length+' UI FAILED: '+G.join(' | ')):'DURABILITY UI: ALL PASS');
})();
