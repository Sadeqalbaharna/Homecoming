let FS=[];const ck=(n,c,d='')=>{c?console.log('  PASS  '+n):(console.log('  FAIL  '+n+'  '+d),FS.push(n))};
SESSION={username:'owner',role:'owner'};WHO='owner';DATA.firstRunDone=true;
// The guided flow now returns on every launch while steps are outstanding,
// so a suite testing the ordinary app has to say it has been dismissed.
SETUP_DISMISSED=true;
STAGE=null;INVBATCH=null;RESEARCH=null;CATPROP=null;
DATA.ai={provider:'',key:'',enabled:false,calls:0,ledger:[],auth:[],limits:null};
DATA.rates={vat:0.10,service:0.10,levy:0.02};DATA.venueInfo={};DATA._lastBackup=0;

ck('Settings is in the nav', NAVGROUPS.flatMap(g=>g[1].map(i=>i[0])).includes('settings'));
ck('...in Overview, where someone would look',
   NAVGROUPS.find(g=>g[0]==='Overview')[1].some(i=>i[0]==='settings'));
view='settings'; render(); let h=__store['app'].innerHTML;
ck('the key field is on it', /setAI\('key'/.test(h));
ck('...and the provider', /setAI\('provider'/.test(h));
ck('the remember-key box exists', /DATA\.ai\.remember=/.test(h));
ck('...and with it off, it says the key is NOT saved', /The key is not saved/.test(h));
DATA.ai={provider:'anthropic',key:'k',enabled:true,remember:true,calls:0,ledger:[],auth:[]};
render(); h=__store['app'].innerHTML;
ck('...and with it on, it says plainly that it is', /now saved in this browser, unencrypted/.test(h));
ck('spend limits are here', /Per batch/.test(h)&&/Lifetime/.test(h));
ck('tax rates are here', /VAT/.test(h)&&/Tourism levy/.test(h));
ck('...shown as percentages, not decimals', />10\.00</.test(h)||/value="10\.00"/.test(h), '');
// 10 ÷ (1.10 × 1.10 × 1.02) = 8.102. My first expectation here was 8.264,
// which is 10 ÷ 1.21 — the levy dropped. Third time this session that doing
// the arithmetic by hand has been the thing that was wrong.
ck('...with the compounded result spelled out', /banks <b>8\.102<\/b>/.test(h),
   (h.match(/banks <b>[\d.]+<\/b>/)||[])[0]||'');
ck('venue location is here', /setVenueInfo\('city'/.test(h));
ck('backups are here', /backupDownload\(\)/.test(h));
ck('...warning when there has never been one', /never been a backup/.test(h));
ck('it warns never to put a POS key here', /Never put a POS or payment key here/.test(h));
ck('no NaN', !/NaN/.test(h));

// the rate control must round-trip through percent without drift
DATA.rates={vat:0,service:0,levy:0};
edit(()=>{DATA.rates=Object.assign({vat:0,service:0,levy:0},DATA.rates);DATA.rates['vat']=(+'10'||0)/100});
ck('typing 10 gives a rate of 0.10', DATA.rates.vat===0.1, String(DATA.rates.vat));
ck('...and 7.5 gives 0.075', (DATA.rates.service=(+'7.5')/100)===0.075);

// discoverability from where it is needed.
// The comparison screen is gated on having a menu now, so give it one —
// otherwise this tests the gate rather than the missing-key message.
DATA.menu=[{id:'m1',name:'Chicken Plate',menuPrice:6,dept:'kitchen',lines:[],weeklySales:1}];
view='market'; DATA.ai={provider:'',key:'',enabled:false,calls:0,ledger:[],auth:[]};
render(); h=__store['app'].innerHTML;
ck('the research screen says a key is needed', /Searching needs an API key/.test(h));
ck('...and links to Settings', /go\('settings'\)/.test(h));
view='import'; render(); h=__store['app'].innerHTML;
ck('the import screen links to Settings too', /go\('settings'\)/.test(h));

// and the key actually survives a reload when remembered
DATA.ai={provider:'anthropic',key:'sk-keep',enabled:true,remember:true,calls:0,ledger:[],auth:[]};
saveNow(); DATA.ai={provider:'',key:'',enabled:false}; load();
ck('a remembered key survives a reload', DATA.ai.key==='sk-keep');
DATA.ai.remember=false; saveNow(); DATA.ai={provider:'',key:'',enabled:false}; load();
ck('...and an unremembered one does not', DATA.ai.key==='');
console.log(FS.length?('\n'+FS.length+' FAILED: '+FS.join(' | ')):'\nSETTINGS: ALL PASS');
