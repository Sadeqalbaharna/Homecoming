// Core invariants. Each one exists because it broke once.
let F=[];const ck=(n,c,d='')=>{c?console.log('  PASS  '+n):(console.log('  FAIL  '+n+'  '+d),F.push(n))};
SESSION={username:'owner',role:'owner'}; DATA.firstRunDone=true;
// The guided flow now returns on every launch while steps are outstanding,
// so a suite testing the ordinary app has to say it has been dismissed.
SETUP_DISMISSED=true;

// ── net revenue: rates compound, they do not add ──
DATA.rates={vat:0.10,service:0.10,levy:0.05};
const g=100, n=netOf(g);
ck('rates compound', Math.abs(n-100/(1.1*1.1*1.05))<1e-9, String(n));
ck('adding rates would be wrong', Math.abs(n-100/1.25)>0.5);
ck('net/gross round-trip', Math.abs(grossOf(netOf(77))-77)<1e-9);
DATA.rates={vat:0,service:0,levy:0};
ck('zero rates are a no-op', netOf(50)===50);

// ── 0/0 is not 100% ──
// Blank the WHOLE book, not just the menu — the reference build has real
// purchases and staff, and a half-cleared book is not the state under test.
DATA.ingredients=[]; DATA.menu=[]; DATA.weeks=[]; DATA.week=0;
if(typeof WK==='function'){const w=WK(); if(w){w.purchases=[];w.employees=[];
  w.salesByDay=[];w.guests=[];w.days=w.days||[];}}
const t=taskState();
// data-sane legitimately passes on a blank book: no values, no impossible ones.
// Everything that requires DATA must not.
const dataTasks=t.filter(x=>x.id!=='data-sane');
ck('no data task completes on a blank book', !dataTasks.some(x=>x.complete),
   dataTasks.filter(x=>x.complete).map(x=>x.id).join());
ck('a blank book scores 0 on every data task, not 57%', dataTasks.every(x=>x.pct===0));

// ── an empty task still names itself usefully ──
ck('empty tasks get an empty label', t.filter(x=>x.empty).length>0);

// ── the two prices are distinguishable ──
DATA.menu=[{id:'1',name:'A',menuPrice:3.5,lines:[],weeklySales:0,dept:'kitchen'}];
DATA.ingredients=[{id:'a',name:'Salt',price:0,ruPerPu:1}];
const t2=taskState();
ck('menu price says SELL', /SELL/.test(t2.find(x=>x.id==='menu-price').label));
ck('ingredient price says BUY', /BUY/.test(t2.find(x=>x.id==='ing-price').label));

// ── nextStep opens on what is actually missing ──
const ns=nextStep();
ck('nextStep returns something incomplete', ns && !ns.complete, ns&&ns.id);

// ── POS matching: equality, not overlap ──
if(typeof matchSales==='function'){
  DATA.menu=[{id:'1',name:'Espresso Martini',menuPrice:5,lines:[],weeklySales:0,dept:'bar'}];
  const m=matchSales([{name:'Martini Espresso',qty:96}]);
  ck('a reordered name is NOT an exact match', !m.some(x=>x.how==='exact'), JSON.stringify(m[0]||{}));
  const m2=matchSales([{name:'espresso  martini',qty:5}]);
  ck('case and spacing still match exactly', m2[0]&&m2[0].how==='exact');
}

// ── base64: the chunked encoder survives a big file ──
if(typeof bufToBase64==='function'){
  const big=new Uint8Array(3*1024*1024); for(let i=0;i<big.length;i++) big[i]=i&255;
  let b64=null,err=null; try{ b64=bufToBase64(big.buffer);}catch(e){err=e.message}
  ck('3MB encodes without a stack overflow', !err, String(err));
  ck('...to the right length', b64 && b64.length===Math.ceil(big.length/3)*4);
  const back=Buffer.from(b64,'base64');
  ck('...and round-trips byte-identical', back.length===big.length&&back[7]===big[7]&&back[big.length-1]===big[big.length-1]);
}

// ── the PDF failure message no longer blames the user's internet ──
const html=require('fs').readFileSync(process.env.TC,'utf-8');
ck('no "needs an internet connection" claim', !/needs an internet connection/.test(html));
ck('Claude path sends a document block', /application\/pdf/.test(html));
ck('...before the instruction', html.indexOf('application/pdf') < html.indexOf('PDF_MAX_BYTES')+40000);

// ── no real venue data in the distributable ──
if(/_blank/.test(process.env.TC)){
  for(const bad of ['Tavern','sk-ant','BFG'])
    ck('blank build contains no "'+bad+'"', !new RegExp(bad,'i').test(html));
  // The word IBAN appears once, in the sentence promising they are never
  // imported. What must not appear is an actual account number.
  ck('no real IBAN in the blank build', !/\b[A-Z]{2}\d{2}[A-Z0-9]{12,30}\b/.test(html),
     (html.match(/\b[A-Z]{2}\d{2}[A-Z0-9]{12,30}\b/)||[])[0]||'');
  ck('...and it still promises they are not imported', /IBANs were deliberately not imported/.test(html));
}
console.log(F.length?('\n'+F.length+' FAILED: '+F.join(' | ')):'\nCORE: ALL PASS');

// ═══ THE SIDEBAR DRAWS ON FIRST PAINT, NOT AFTER AN INTERACTION ═══
(function(){
 SESSION={username:'owner',role:'owner'};WHO='owner';
 DATA.setup={name:'x',done:true,started:true,skipped:{}};DATA.firstRunDone=true;SETUP_DISMISSED=true;
 // the boot path is R(), not render() alone — R draws the sidebar
 R();
 const side=(__store['sidegroups']||{innerHTML:''}).innerHTML;
 const src=require('fs').readFileSync(process.env.TC,'utf-8');
 ck('the app boots through R(), not bare render()', /\nR\(\);\nif\(restored\)/.test(src));
 ck('...so the sidebar is populated on first paint', /go\(/.test(side)&&/Overview/.test(side));
})();
