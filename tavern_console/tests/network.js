let FN=[];const ck=(n,c,d='')=>{c?console.log('  PASS  '+n):(console.log('  FAIL  '+n+'  '+d),FN.push(n))};
SESSION={username:'owner',role:'owner'};WHO='owner';SETUP_DISMISSED=true;DATA.firstRunDone=true;
DATA.ai={provider:'anthropic',key:'sk-x',enabled:true,calls:0,ledger:[],auth:[],limits:null};

// ═══ RECOGNISING THE FAILURE ═══
ck('a TypeError is a network failure', isNetFail(new TypeError('Failed to fetch')));
ck('...whatever the browser calls it', isNetFail(new Error('Load failed'))&&isNetFail(new Error('NetworkError when attempting to fetch resource')));
ck('an HTTP error is NOT a network failure', !isNetFail(new Error('Claude returned 401.')));
ck('...nor a parsing problem', !isNetFail(new Error('The model did not return usable JSON.')));

// ═══ THE DIAGNOSIS DEPENDS ON WHERE THE PAGE IS ═══
global.location={protocol:'file:'};
// Node 22 ships a read-only `navigator`, so a plain assignment does nothing
// at all — it has to be redefined. Worth knowing: the same silent no-op would
// make any test that stubs navigator pass for the wrong reason.
const setOnline=v=>Object.defineProperty(globalThis,'navigator',
  {value:{onLine:v},configurable:true,writable:true});
setOnline(true);
global.window.self=global.window; global.window.top=global.window;
let d=netDiagnosis();
ck('a file:// page is identified as the cause', /opened straight from a file on disk/.test(d));
ck('...and named as the reason the key is irrelevant', /before it looks at your key/.test(d));
ck('...with the actual fix', /serve\.bat/.test(d));

global.location={protocol:'https:'};
global.window.top={};                        // embedded
d=netDiagnosis();
ck('a preview pane is identified', /inside a preview pane/.test(d));
ck('...and told to open a real tab', /normal browser tab/.test(d));
global.window.top=global.window;

setOnline(false);
ck('being offline is said plainly', /reports that it is offline/.test(netDiagnosis()));
setOnline(true);
d=netDiagnosis();
ck('otherwise it says the request never arrived', /did not reach the API at all/.test(d));
ck('...and that it is not the key', /rather than a problem with your key/.test(d));

(async()=>{
// ═══ EVERY API CALL GOES THROUGH IT ═══
globalThis.fetch=async()=>{throw new TypeError('Failed to fetch')};
global.location={protocol:'file:'};
let err=null;
try{ await netFetch('https://api.anthropic.com/x',{},'This menu'); }catch(e){ err=e.message; }
ck('the raw browser message is never shown alone', !/^Failed to fetch$/.test(err||''));
ck('...it says what was being attempted', /^This menu never reached the server/.test(err||''), String(err).slice(0,60));
ck('...and diagnoses it', /file on disk/.test(err||''));

// a real HTTP error must pass through untouched
globalThis.fetch=async()=>({ok:false,status:401,text:async()=>''});
err=null;
try{ await aiResearch('s','p',1); }catch(e){ err=e.message; }
ck('a rejected key still says the key was rejected', /key was rejected/.test(err||''), String(err));

// and a network failure during research is diagnosed too
globalThis.fetch=async()=>{throw new TypeError('Failed to fetch')};
err=null;
try{ await aiResearch('s','p',1); }catch(e){ err=e.message; }
ck('research diagnoses a network failure', /never reached the server/.test(err||''), String(err).slice(0,50));

// ═══ IT IS SHOWN ON THE PAGE, NOT IN AN ALERT ═══
FILEFAIL={file:'menu.pdf',short:'That menu could not be read.',
  why:'This menu never reached the server.\n\n'+netDiagnosis(),reason:'network',canVision:false};
DATA.setup={name:'x',done:false,started:true,skipped:{}};SETUP_DISMISSED=false;CELEBRATE=null;
DATA.menu=[];STAGE=null;view='import';render();
let h=__store['app'].innerHTML;
ck('the failure is a panel on the page', /That file could not be read/.test(h));
ck('...carrying the diagnosis', /file on disk/.test(h));
ck('...and a way onward', /back to setup/.test(h));
ck('no NaN', !/NaN/.test(h));
console.log(FN.length?('\n'+FN.length+' FAILED: '+FN.join(' | ')):'\nNETWORK ERRORS: ALL PASS');
})();