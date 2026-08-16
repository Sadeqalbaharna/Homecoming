let F=[];const ck=(n,c,d='')=>{c?console.log('  PASS  '+n):(console.log('  FAIL  '+n+'  '+d),F.push(n))};
SESSION={username:'owner',role:'owner'};WHO='owner';DATA.firstRunDone=true;

// ── A fake cloud: one blob per (org,venue), in memory. Stands in for Firebase
//    Storage so the sync ORCHESTRATION is tested without a network. ──
function fakeCloud(){
  const blobs={};                    // key `${org}/${venue}` -> {json,updated}
  return {
    _blobs:blobs, calls:{get:0,put:0},
    async getBlob(org,venue){ this.calls.get++; return blobs[org+'/'+venue]||null; },
    async putBlob(org,venue,json,updated){ this.calls.put++; blobs[org+'/'+venue]={json,updated}; },
  };
}
const seed=(sav)=>{ DATA.ingredients=[{code:'001',name:'MEAT',price:5}]; DATA.menu=[];
  DATA._lastSaved=sav; };

// ═══ OFFLINE-FIRST: with no adapter, nothing cloud-related fires ═══
CLOUD=null;
ck('cloudOn() is false with no adapter', cloudOn()===false);
seed(1000); saveNow();                       // must not throw, must not need cloud
ck('saveNow works offline (no adapter)', /"code":"001"/.test(localStorage.getItem(KEY)));

// ═══ RENDER GATE: platform mode gates the app behind sign-in ═══
SETUP_DISMISSED=true; DATA.setup={done:true,started:true};
CLOUD_CONFIG.apiKey='demo'; CLOUDSTATE.user=null; CLOUD=null;
render();
ck('platform mode shows the cloud login when signed out',
   /synced to every device/.test(__store['app'].innerHTML));
CLOUDSTATE.user={uid:'u1',email:'a@b.com'}; SESSION={username:'a@b.com',role:'owner'};
render();
ck('once signed in, the app renders (no cloud login)',
   !/synced to every device/.test(__store['app'].innerHTML));
CLOUD_CONFIG.apiKey=''; CLOUDSTATE.user=null;   // back to offline for the rest
render();
ck('the offline build never shows the cloud login',
   !/synced to every device/.test(__store['app'].innerHTML));

// ═══ SEED: opening a venue with an empty cloud pushes local up ═══
const C=fakeCloud(); cloudUse(C);
ck('cloudOn() true once wired', cloudOn()===true);
seed(2000);
(async()=>{
  await cloudOpenVenue('org1','venueA');
  ck('first open of an empty venue seeds the cloud from local', C.calls.put===1 && !!C._blobs['org1/venueA']);
  const up=JSON.parse(C._blobs['org1/venueA'].json);
  ck('...the pushed blob carries the local data', up.ingredients[0].name==='MEAT');
  ck('...tagged with the real edit time, not now', up.saved===2000);

  // ═══ PULL newer: a second device catches up ═══
  // Simulate the other device having written a fresher blob directly.
  C._blobs['org1/venueA']={json:JSON.stringify({saved:5000,ingredients:[{code:'001',name:'FISH',price:9}],menu:[]}),updated:5000};
  DATA._lastSaved=2000;                       // this device is behind
  const pulled=await cloudPull();
  ck('a newer cloud blob is pulled and applied', pulled===true && DATA.ingredients[0].name==='FISH');
  ck('...and mirrored into localStorage', /FISH/.test(localStorage.getItem(KEY)));

  // ═══ STALE never clobbers fresher local ═══
  C._blobs['org1/venueA']={json:JSON.stringify({saved:1,ingredients:[{code:'001',name:'STALE',price:0}],menu:[]}),updated:1};
  DATA._lastSaved=9999;                        // local is much newer
  const pulled2=await cloudPull();
  ck('a stale cloud blob is NOT applied over fresher local', pulled2===false && DATA.ingredients[0].name==='FISH');

  // ═══ PUSH after a local change carries everything up ═══
  DATA.ingredients=[{code:'001',name:'LAMB',price:7}]; DATA._lastSaved=12000;
  await cloudPush();
  ck('a local change pushes up', JSON.parse(C._blobs['org1/venueA'].json).ingredients[0].name==='LAMB');

  // ═══ VENUE ISOLATION: a different venue is a different blob ═══
  await cloudOpenVenue('org1','venueB');
  ck('opening a second venue does not overwrite the first',
     JSON.parse(C._blobs['org1/venueA'].json).ingredients[0].name==='LAMB');
  ck('...and the two venues are separate slots',
     C._blobs['org1/venueB'] && C._blobs['org1/venueA']!==C._blobs['org1/venueB']);

  // ═══ VENUE SWITCH: force-loads the target even when its blob is "older" ═══
  cloudUse(C);
  // venueA currently holds LAMB (saved 12000). Make venueB hold an OLDER blob.
  C._blobs['org1/venueB']={json:JSON.stringify({saved:3000,ingredients:[{code:'009',name:'RICE',price:1}],menu:[]}),updated:3000};
  CLOUDSTATE.org='org1'; CLOUDSTATE.venue='venueA'; DATA._lastSaved=12000;
  DATA.ingredients=[{code:'001',name:'LAMB',price:7}];
  CLOUDSTATE.venues=[{id:'venueA',name:'A'},{id:'venueB',name:'B'}];
  await venueSwitch('venueB');
  ck('switching loads the target venue even though its save time is older',
     DATA.ingredients[0].name==='RICE' && CLOUDSTATE.venue==='venueB');
  ck('...and the venue we left was saved up first',
     JSON.parse(C._blobs['org1/venueA'].json).ingredients[0].name==='LAMB');

  // Switch to a venue that has NO blob yet: opens empty, does not copy the old.
  CLOUDSTATE.venues.push({id:'venueC',name:'C'});
  await venueSwitch('venueC');
  ck('a brand-new venue opens empty, not a copy of the last one',
     DATA.ingredients.length===0 && CLOUDSTATE.venue==='venueC');

  // ═══ A push failure is remembered, not lost ═══
  const bad=fakeCloud(); bad.putBlob=async()=>{throw new Error('offline')}; cloudUse(bad);
  CLOUDSTATE.org='o'; CLOUDSTATE.venue='v';
  const ok=await cloudPush();
  ck('a failed push reports false and records the reason',
     ok===false && /offline|paused|retry/i.test(CLOUDSTATE.pushErr||''));

  console.log(F.length?('CLOUD: '+F.length+' FAILED'):'CLOUD: ALL PASS');
})();
