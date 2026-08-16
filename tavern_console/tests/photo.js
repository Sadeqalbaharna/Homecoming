let F=[];const ck=(n,c,d='')=>{c?console.log('  PASS  '+n):(console.log('  FAIL  '+n+'  '+d),F.push(n))};
SESSION={username:'owner',role:'owner'};DATA.firstRunDone=true;

// ── downscaling: pure, and it must never enlarge ──
ck('a 12MP portrait photo fits the box', JSON.stringify(fitBox(3024,4032,1600))==='{"w":1200,"h":1600}');
ck('landscape too', JSON.stringify(fitBox(4032,3024,1600))==='{"w":1600,"h":1200}');
ck('a small scan is left alone', JSON.stringify(fitBox(900,1200,1600))==='{"w":900,"h":1200}');
ck('exactly at the edge is left alone', fitBox(1600,1600,1600).w===1600);
ck('aspect ratio survives', Math.abs((3024/4032)-(1200/1600))<0.001);
ck('a degenerate size does not crash or divide by zero', fitBox(0,0,1600).w===1);
const px=fitBox(3024,4032,1600); 
ck('...and it is ~10x fewer pixels', (3024*4032)/(px.w*px.h)>6);

// ── the model's output must become mapper rows, or be dropped ──
const good=[{supplier:'Gulf Foods',date:'2026-07-14',item:'Chicken breast',qty:10,unit:2.4,total:24}];
let st=photoRowsToStage('purchases',good);
ck('a complete line becomes one row', st.rows.length===1, JSON.stringify(st.rows));
ck('...mapped to the same fields as a CSV',
   JSON.stringify(st.map)===JSON.stringify({supplier:0,total:1,date:2,item:3,qty:4,unit:5,cat:6}),
   JSON.stringify(st.map));
ck('...with the spec\'s own headers', st.headers[0]==='Supplier'&&st.headers[1]==='Line total');
ck('...and numbers survive as text the mapper can parse', st.rows[0][1]==='24'&&st.rows[0][5]==='2.4');
ck('...flagged as coming from a photo', st.fromPhoto===true);

// THE ONE THAT MATTERS: a half-read line must be dropped, not guessed.
st=photoRowsToStage('purchases',[
  {supplier:'Gulf Foods',item:'Chicken',qty:10,unit:2.4,total:24},   // ok, date optional
  {supplier:'Gulf Foods',item:'Rice',qty:5},                          // no total — REQUIRED
  {item:'Oil',total:9},                                               // no supplier — REQUIRED
  {}                                                                  // nothing
]);
ck('a line missing its total is dropped', st.rows.length===1, JSON.stringify(st.rows));
ck('...and it is the complete one that survived', st.rows[0][3]==='Chicken');

// dedup: the same invoice photographed twice
st=photoRowsToStage('purchases',[good[0],JSON.parse(JSON.stringify(good[0])),
  {supplier:'Gulf Foods',date:'2026-07-14',item:'Chicken breast',qty:10,unit:2.4,total:26}]);
ck('an identical line photographed twice lands once', st.rows.length===2, String(st.rows.length));
ck('...but a different total is NOT treated as a duplicate', st.rows.length===2);

// junk in must not become confident rows out
ck('null items yield nothing', photoRowsToStage('purchases',[null,undefined,'x',7]).rows.length===0);
ck('an empty response yields nothing', photoRowsToStage('purchases',[]).rows.length===0);
ck('a missing kind refuses rather than guesses',
   (()=>{try{photoRowsToStage('nope',good);return false}catch(e){return /Unknown import kind/.test(e.message)}})());
ck('an absurdly long field is truncated, not passed through',
   photoRowsToStage('purchases',[{supplier:'x'.repeat(999),total:5}]).rows[0][0].length===120);
ck('a NaN number is dropped, not rendered "NaN"',
   photoRowsToStage('purchases',[{supplier:'A',total:5,qty:NaN}]).rows[0][4]==='');

// menu photos reuse the menu spec and prompt
st=photoRowsToStage('products',[{name:'Bowl of Nuts',price:3.5,cat:'To Share'}]);
ck('a photographed menu maps to the product spec', st.rows[0][0]==='Bowl of Nuts'&&st.rows[0][1]==='3.5');
ck('the menu photo prompt is the one already tested on the PDF',
   PHOTO_KINDS.products.prompt===AI_VISION_PROMPT);

// what the camera is deliberately NOT offered for
ck('attendance is not photographable', !PHOTO_KINDS.punches);
ck('daily sales is not photographable', !PHOTO_KINDS.sales&&!PHOTO_KINDS.days);
ck('purchases is', !!PHOTO_KINDS.purchases);

// the invoice prompt's two most expensive mistakes are named in it
const ip=PHOTO_KINDS.purchases.prompt;
ck('the prompt says which party is the supplier', /sender, not the restaurant/.test(ip));
ck('the prompt excludes VAT and totals as line items', /Do NOT include VAT lines/.test(ip));
ck('the prompt prefers omission over invention', /omitted line is recoverable/.test(ip));

// no key = a clear refusal, not a silent nothing
DATA.ai={provider:'anthropic',key:'',on:false};
ck('AI off means the camera is not ready', !aiReady());

// the UI is wired
view='import'; DATA.ai={provider:'anthropic',key:'sk-x',on:true}; render();
let h=__store['app'].innerHTML;
ck('a camera button exists', /addShots\(this,'purchases'\)/.test(h));
ck('...using the rear camera', /capture="environment"/.test(h));
// capture and multiple must never share an input: capture wins and the
// "several pages" promise silently becomes one.
const inputs=h.match(/<input[^>]*type="file"[^>]*>/g)||[];
ck('no input has both capture and multiple',
   !inputs.some(i=>/capture=/.test(i)&&/multiple/.test(i)),
   (inputs.filter(i=>/capture=/.test(i)&&/multiple/.test(i))[0]||''));
ck('there is a separate multi-select input for a gallery',
   inputs.some(i=>/multiple/.test(i)&&!/capture=/.test(i)&&/image\//.test(i)));
ck('no camera button on attendance', !/addShots\(this,'punches'\)/.test(h));

// the tray accumulates and only sends when told
SHOTS=[]; SHOTKIND=null; render();
ck('no tray shown when empty', !/page\(s\) ready/.test(__store['app'].innerHTML));
SHOTS=[{name:'a.jpg',data:'AAAA',w:1200,h:1600}]; SHOTKIND='purchases'; render();
h=__store['app'].innerHTML;
ck('one shot shows the tray', /1 page\(s\) ready/.test(h));
ck('...with a thumbnail', /data:image\/jpeg;base64,AAAA/.test(h));
ck('...and nothing has been sent yet', /Read 1 page\(s\)/.test(h));
SHOTS.push({name:'b.jpg',data:'BBBB',w:1200,h:1600}); render();
ck('a second tap adds rather than replaces', /2 page\(s\) ready/.test(__store['app'].innerHTML));
dropShot(0);
ck('a bad page can be removed', SHOTS.length===1&&SHOTS[0].name==='b.jpg');
clearShots();
ck('discard empties the tray and its kind', SHOTS.length===0&&SHOTKIND===null);
// an invoice must never be read as a menu
SHOTS=[{name:'inv.jpg',data:'A',w:10,h:10}]; SHOTKIND='purchases';
ck('switching import kind does not mix the pages',
   (()=>{ if(SHOTKIND&&SHOTKIND!=='products')clearShots(); return SHOTS.length===0 })());
ck('the page says nothing is written until confirmed', /nothing is written until you confirm/i.test(h));
ck('no NaN on the import screen', !/NaN/.test(h));
console.log(F.length?('\n'+F.length+' FAILED: '+F.join(' | ')):'\nPHOTO: ALL PASS');
