let FI=[];const ck=(n,c,d='')=>{c?console.log('  PASS  '+n):(console.log('  FAIL  '+n+'  '+d),FI.push(n))};
SESSION={username:'owner',role:'owner'};WHO='owner';SETUP_DISMISSED=true;DATA.firstRunDone=true;
CELEBRATE=null;
const menu=()=>{DATA.menu=[
  {id:'m1',name:'Espresso Martini',menuPrice:6,weeklySales:0,dept:'bar',lines:[],posCode:'E01'},
  {id:'m2',name:'Bowl of Nuts',menuPrice:3.5,weeklySales:0,dept:'kitchen',lines:[]},
  {id:'m3',name:'The BFG',menuPrice:9,weeklySales:0,dept:'kitchen',lines:[]}];
  DATA.posRejected={};rebuildIX();};

// ═══ HEADERS THE OLD READER COULD NOT COPE WITH ═══
menu();
// revenue BEFORE units, a code column first, extra columns — all fine now
STAGE={kind:'itemsales',
  headers:['Item Code','Product Name','Net Sales','Qty Sold','Department'],
  rows:[['E01','Espresso Martini','480.5','96','Bar'],
        ['N01','Bowl of Nuts','42','12','Food'],
        ['X99','Something Else','9','3','Food']],
  map:autoMap(['Item Code','Product Name','Net Sales','Qty Sold','Department'],'itemsales'),
  headerRow:0, weeks:1};
ck('the item name column is found by header', STAGE.map.name===1, JSON.stringify(STAGE.map));
ck('units are found even though revenue comes first', STAGE.map.qty===3, String(STAGE.map.qty));
ck('revenue is found', STAGE.map.total===2);
ck('the code column is found', STAGE.map.code===0);
const P=stagePreview();
ck('rows parse', P.rows.length===3, JSON.stringify(P.rows[0]));
ck('...with no "No usable rows" dead end', P.rows.length>0);

// ═══ MATCHING IS STILL STRICT ═══
global.__alerts=[];
stageApply();
ck('an exact name match applies', DATA.menu[1].weeklySales===12, String(DATA.menu[1].weeklySales));
ck('a code match applies', DATA.menu[0].weeklySales===96);
ck('an unknown item matches nothing', !DATA.menu.some(m=>m.name==='Something Else'));
ck('...and is kept for review rather than dropped',
   (DATA.posRejected.unmatched||[]).some(u=>u.name==='Something Else'));
const msg=(TOASTS.map(t=>t.msg).join(' ')+' '+(__alerts||[]).join(' '));
ck('the message counts both', /2 dish\(es\) matched/.test(msg), msg);
ck('...and says the rest were left alone', /1 line\(s\) matched nothing/.test(msg));

// the fuzzy trap that started all this
menu();
STAGE={kind:'itemsales',headers:['Item','Qty'],rows:[['Martini Espresso','96']],
  map:{name:0,qty:1},headerRow:0,weeks:1};
stageApply();
ck('a reordered name does NOT match', DATA.menu[0].weeklySales===0,
   String(DATA.menu[0].weeklySales));
ck('...it goes to review', (DATA.posRejected.unmatched||[]).length===1);

// ═══ THE PERIOD DIVIDES ═══
menu();
STAGE={kind:'itemsales',headers:['Item','Qty'],rows:[['Bowl of Nuts','130']],
  map:{name:0,qty:1},headerRow:0,weeks:13};
stageApply();
ck('a 13-week report is divided into a weekly rate', DATA.menu[1].weeklySales===10,
   String(DATA.menu[1].weeklySales));
menu();
STAGE={kind:'itemsales',headers:['Item','Qty'],rows:[['Bowl of Nuts','130']],
  map:{name:0,qty:1},headerRow:0,weeks:1};
stageApply();
ck('...and a 1-week report is not', DATA.menu[1].weeklySales===130);

// ═══ THE PERIOD IS ASKED FOR ON SCREEN, NOT IN A POP-UP ═══
menu();
STAGE={kind:'itemsales',headers:['Item','Qty'],rows:[['Bowl of Nuts','130']],
  map:{name:0,qty:1},headerRow:0,weeks:1};
view='import'; render(); const h=__store['app'].innerHTML;
ck('the screen asks how long the report covers', /How long does this report cover/.test(h));
ck('...with one-click periods', /STAGE\.weeks=13/.test(h));
ck('...warning what it affects', /scales every sales figure/.test(h));
ck('the column mapper is shown', /check the columns/.test(h));
ck('no NaN', !/NaN/.test(h));

// ═══ STEP 2 USES IT ═══
const s=SETUP_STEPS.find(x=>x.id==='sales');
ck('setup step 2 routes through the mapper', s.pick.kind==='itemsales', JSON.stringify(s.pick));
ck('...and accepts Excel', /\.xlsx/.test(s.pick.accept));
ck('...and no longer calls the old reader', !s.pick.fn);
console.log(FI.length?('\n'+FI.length+' FAILED: '+FI.join(' | ')):'\nITEM SALES: ALL PASS');
