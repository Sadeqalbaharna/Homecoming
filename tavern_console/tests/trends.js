let FT=[];const ck=(n,c,d='')=>{c?console.log('  PASS  '+n):(console.log('  FAIL  '+n+'  '+d),FT.push(n))};
SESSION={username:'owner',role:'owner'};WHO='owner';SETUP_DISMISSED=true;DATA.firstRunDone=true;
CELEBRATE=null;STAGE=null;CATPROP=null;CATSHOCK=null;
const fill=(month,days,sales,guests,hours,rate)=>{
  for(let d=1;d<=days;d++){
    const iso=`${month}-${String(d).padStart(2,'0')}`;
    ledgerPut(iso,{sales,guests,hours:{Ana:hours},cost:{Ana:hours*rate}},'t');
  }
};
const reset=()=>{DATA.ledger={days:{},purchases:[]};DATA.rateBook={Ana:2};
  DATA.menu=[];DATA.ingredients=[];DATA.settings={};
  DATA.week={days:[],salesByDay:[],guests:[],employees:[],purchases:[]};
  rebuildIX();rebuildBX();};

// ═══ #10 · THE FLOOR COMES FROM YOUR WAGES ═══
reset();
DATA.week={days:['2026-05-01','','','','','',''],salesByDay:[500,0,0,0,0,0,0],
  guests:[50,0,0,0,0,0,0],employees:[{name:'Ana',rate:1.5,hours:[10,0,0,0,0,0,0]}],purchases:[]};
ck('the floor derives from the wage bill', Math.abs(splhFloor()-9)<0.05, String(splhFloor()));
DATA.week.employees[0].rate=4;
ck('...and rises with the wage', splhFloor()>20, String(splhFloor()));
DATA.settings={splhFloor:18};
ck('an explicit setting wins', splhFloor()===18);
DATA.settings={};
DATA.week.employees=[];
ck('with no wage data at all it falls back', splhFloor()===25, String(splhFloor()));

// ═══ #5 · REVENUE COVERAGE, NOT ROW COUNT ═══
reset();
DATA.ingredients=[{id:'i',code:'001',name:'X',price:1,recipeUnit:'kg',ruPerPu:1,pu:'kg',yield:1}];
DATA.menu=[
  {id:'big',name:'Best Seller',menuPrice:10,weeklySales:100,dept:'kitchen',lines:[]},
  ...Array.from({length:19},(_,i)=>({id:'s'+i,name:'Slow '+i,menuPrice:5,weeklySales:1,
    dept:'kitchen',lines:[{ref:'001_X',qty:1}]}))];
DATA.rates={vat:0,service:0,levy:0};
rebuildIX();
let RC=revenueCoverage();
ck('19 of 20 dishes costed is 95% by row count', Math.abs(RC.itemPct-0.95)<0.001);
ck('...but only 49% of the money', RC.pct<0.5, (RC.pct*100).toFixed(1)+'%');
ck('...and it names the dish to fix first', RC.top[0].name==='Best Seller');
ck('...with its share', RC.top[0].share>0.5, (RC.top[0].share*100).toFixed(0)+'%');
DATA.menu[0].lines=[{ref:'001_X',qty:1}];
ck('costing the big seller moves it to 100%', revenueCoverage().pct===1);
ck('an uncostable dish does not count as costed',
   (DATA.menu[0].lines=[{ref:'Bnope',qty:1}], DATA.batch=[{id:'nope',code:'N',name:'N',
     yieldQty:1,lines:[{ref:'Bnope',qty:1}]}], rebuildBX(), revenueCoverage().pct<1));

// ═══ #1 · THE REPORT READS THE LEDGER ═══
reset();
// June: sales down AND hours up, so labour % moves by more than the 2-point
// threshold. The first attempt moved it by 0.4 points, which the finding
// correctly ignored as noise.
// Realistic proportions: labour around 28% of sales. The first attempt had
// labour at 1.6% of sales, where a real swing in hours moved the percentage
// by less than the 2-point threshold — the finding was right to ignore it.
fill('2026-05',31,1000,100,140,2);
fill('2026-06',30,900,100,155,2);
let C=comparableMonths();
ck('two complete months are comparable', !!C.pair, JSON.stringify(C));
ck('...and they are the latest two', C.pair[1].month==='2026-06');
let A=periodTotals('2026-05-01','2026-05-31');
ck('a period totals its sales', A.sales===31000, String(A.sales));
ck('...its labour from the ledger', A.labour===31*280, String(A.labour));
ck('...and spend per head', Math.abs(A.spend-10)<0.001);
let TF=trendFindings();
const f=id=>TF.out.find(x=>x.id===id);
ck('a sales fall is reported', !!f('trend-sales'), TF.out.map(x=>x.id).join());
ck('...with the real percentage',
   /12\.9%|12\.90%/.test(f('trend-sales').title), f('trend-sales').title);
ck('...showing the arithmetic', /÷/.test(f('trend-sales').working));
ck('...and the money', f('trend-sales').money>0);
ck('guests held, so it says spend per head', /spend per head/.test(f('trend-sales').action));
ck('labour creeping up is reported', !!f('trend-labour'), TF.out.map(x=>x.id).join());
ck('...in points of sales', /points of sales/.test(f('trend-labour').title));
ck('...and blames the rota when hours rose', /rota rather than wages/.test(f('trend-labour').action));

// a month with holes is NOT compared
reset();
fill('2026-05',31,1000,100,8,2);
fill('2026-06',12,900,100,9,2);
C=comparableMonths();
ck('an incomplete month is not compared', !C.pair);
TF=trendFindings();
ck('...and nothing is claimed about it', TF.out.length===0);
ck('...but it says why', TF.blocked.some(b=>/Month-on-month/.test(b.title)));
ck('...naming how many are complete', /1 of 2 month/.test(TF.blocked[0].what), TF.blocked[0].what);

// the week being analysed is declared incomplete
reset();
fill('2026-05',31,1000,100,8,2);
ledgerPut('2026-06-01',{sales:100},'t');
DATA.week={days:['2026-06-01','2026-06-02','2026-06-03','2026-06-04','2026-06-05','2026-06-06','2026-06-07'],
  salesByDay:[100,0,0,0,0,0,0],guests:[0,0,0,0,0,0,0],employees:[],purchases:[]};
let R2=findings();
ck('an incomplete week is declared', R2.blocked.some(b=>/week being analysed is incomplete/.test(b.title)));
ck('...listing the missing days', /06-02/.test((R2.blocked.find(b=>/incomplete/.test(b.title))||{}).what||''));

// ═══ #9 · THE PRINTED REPORT ═══
let printed='';
global.window.open=()=>({document:{write:s=>{printed+=s},close(){}}});
DATA.menu=[{id:'m',name:'Big One',menuPrice:10,weeklySales:100,dept:'kitchen',lines:[]}];
DATA.rates={vat:0.1,service:0.1,levy:0};rebuildIX();
printReport();
ck('the report prints as its own document', /<h1>Where the money went/.test(printed));
ck('...stating the period analysed', /week analysed/.test(printed));
ck('...and how much history exists', /history on record/.test(printed));
ck('...and revenue costed', /revenue costed/.test(printed));
ck('...with a section for what it CANNOT tell you', /What this cannot tell you yet/.test(printed));
ck('...saying why that is not a caveat', /not shown at all/.test(printed));
ck('...and the quickest way to improve it', /quickest way to improve/.test(printed));
ck('...naming the dish', /Big One/.test(printed));
ck('...and it closes with the no-forecasts promise', /Nothing here is a forecast/.test(printed));
ck('no NaN in the printed report', !/NaN/.test(printed));
ck('no undefined either', !/undefined/.test(printed));
console.log(FT.length?('\n'+FT.length+' FAILED: '+FT.join(' | ')):'\nTRENDS: ALL PASS');
