let FL=[];const ck=(n,c,d='')=>{c?console.log('  PASS  '+n):(console.log('  FAIL  '+n+'  '+d),FL.push(n))};
SESSION={username:'owner',role:'owner'};WHO='owner';SETUP_DISMISSED=true;DATA.firstRunDone=true;
STAGE=null;INVBATCH=null;
const fresh=()=>{DATA.ledger={days:{},purchases:[]};DATA.rateBook={};
  DATA.week={days:['2026-07-13','2026-07-14','2026-07-15','2026-07-16','2026-07-17','2026-07-18','2026-07-19'],
    salesByDay:[0,0,0,0,0,0,0],guests:[0,0,0,0,0,0,0],employees:[],purchases:[]};
  DATA.menu=[];DATA.ingredients=[];rebuildIX();rebuildBX();};

// ═══ DATE HELPERS ═══
ck('day arithmetic crosses a month', dayAdd('2026-07-30',3)==='2026-08-02');
ck('...and a year', dayAdd('2026-12-31',1)==='2027-01-01');
ck('...backwards', dayAdd('2026-01-01',-1)==='2025-12-31');
ck('...and a leap day', dayAdd('2024-02-28',1)==='2024-02-29');
ck('day difference is inclusive-safe', dayDiff('2026-07-01','2026-07-31')===30);
ck('a day-first date becomes ISO', isoDate('13/7/2026')==='2026-07-13');
ck('an ISO date stays put', isoDate('2026-07-13')==='2026-07-13');

// ═══ THE BUG THAT STARTED THIS: 90 DAYS IN, 90 DAYS KEPT ═══
fresh();
const rows=[];
for(let d=0;d<90;d++){const iso=dayAdd('2026-04-22',d);rows.push([iso,String(500+d),String(50+d)]);}
STAGE={kind:'daily',headers:['Date','Sales','Covers'],rows,map:{date:0,sales:1,covers:2},headerRow:0,
  fileName:'daily.csv'};
global.__alerts=[];
stageApply();
ck('ninety days uploaded means ninety days kept', ledgerDates().length===90, String(ledgerDates().length));
ck('...spanning the real range',
   ledgerSpan().from==='2026-04-22'&&ledgerSpan().to===dayAdd('2026-04-22',89),
   ledgerSpan().from+' → '+ledgerSpan().to);
ck('...with values intact', DATA.ledger.days['2026-04-22'].sales===500);
ck('...and guests', DATA.ledger.days['2026-04-22'].guests===50);
ck('...and the source file recorded', DATA.ledger.days['2026-04-22'].src.includes('daily.csv'));
// The message now arrives as a toast rather than a blocking alert.
const msg0=(TOASTS[0]||{}).msg||(__alerts[0]||'');
ck('the message reports the whole span, not "7 matched"',
   /history now runs 2026-04-22 to/.test(msg0), msg0);
ck('...and explains the window', /window you are looking through/.test(msg0));

// ═══ THE WINDOW IS A VIEW, NOT THE TRUTH ═══
ck('the window jumped to the latest data', DATA.period.end===ledgerSpan().to, JSON.stringify(DATA.period));
ck('...showing seven days', (WK().days||[]).length===7);
ck('...with the right numbers', WK().salesByDay[6]===589, JSON.stringify(WK().salesByDay));
const before=ledgerDates().length;
loadWindow('2026-05-01');
ck('moving the window loses nothing', ledgerDates().length===before);
ck('...and shows the older week', WK().days[0]==='2026-05-01'&&WK().salesByDay[0]===509);
shiftWindow(-1);
ck('stepping back a week works', DATA.period.start==='2026-04-24');
shiftWindow(1);
ck('...and forward again', DATA.period.start==='2026-05-01');

// ═══ MANUAL EDITS SURVIVE A WINDOW MOVE ═══
DATA.week.salesByDay[0]=9999;
loadWindow('2026-06-01');
loadWindow('2026-05-01');
ck('a typed correction is flushed to the ledger before the window moves',
   WK().salesByDay[0]===9999, String(WK().salesByDay[0]));
ck('...and is in the ledger itself', DATA.ledger.days['2026-05-01'].sales===9999);

// ═══ ATTENDANCE ACROSS MONTHS ═══
fresh();
const punch=[];
for(let d=0;d<40;d++){const iso=dayAdd('2026-05-01',d);
  punch.push([iso+' 09:00','Ana','IN'],[iso+' 17:00','Ana','OUT']);}
// The punch spec's keys are emp / stamp / dir — not the column headings.
STAGE={kind:'punches',headers:['Time','Name','Dir'],rows:punch,
  map:{stamp:0,emp:1,dir:2},headerRow:0,fileName:'zk.csv'};
global.__alerts=[];
stageApply();
ck('forty days of shifts are all kept',
   ledgerDates().filter(d=>hasHours(DATA.ledger.days[d])).length===40,
   String(ledgerDates().filter(d=>hasHours(DATA.ledger.days[d])).length));
ck('...each with the right hours', Math.abs(DATA.ledger.days['2026-05-01'].hours['Ana']-8)<0.01,
   String(DATA.ledger.days['2026-05-01'].hours['Ana']));
ck('...and the window shows a week of them', (WK().employees||[]).length===1);

// wage rates are remembered across windows
DATA.week.employees[0].rate=2.5; rememberRates();
loadWindow('2026-05-01');
ck('a wage rate survives moving the window', WK().employees[0].rate===2.5);

// ═══ COVERAGE — AND REFUSING TO ANALYSE ═══
fresh();
for(const d of ['2026-06-01','2026-06-02','2026-06-05'])ledgerPut(d,{sales:100},'t');
let c=coverage('2026-06-01','2026-06-05','sales');
ck('coverage counts the days present', c.have===3&&c.days===5);
ck('...and names the ones missing', c.missing.join()==='2026-06-03,2026-06-04', c.missing.join());
ck('...as a fraction', Math.abs(c.pct-0.6)<0.001);
c=coverage('2026-06-01','2026-06-02','sales');
ck('a fully covered period reports 100%', c.pct===1&&!c.missing.length);
c=coverage('2026-06-01','2026-06-05','hours');
ck('coverage can be asked about labour separately', c.have===0&&c.missing.length===5);

// ═══ MIGRATION ═══
DATA.ledger={days:{},purchases:[]};
DATA.week={days:['2026-07-13','2026-07-14','2026-07-15','2026-07-16','2026-07-17','2026-07-18','2026-07-19'],
  salesByDay:[100,200,0,0,0,0,0],guests:[10,20,0,0,0,0,0],
  employees:[{name:'Bo',rate:3,hours:[8,8,0,0,0,0,0],cost:[24,24,0,0,0,0,0]}],
  purchases:[{id:'P1',supplier:'S',date:'2026-07-13',amount:50,alloc:{}}]};
ck('an old book migrates', migrateToLedger()===true);
ck('...keeping its sales', DATA.ledger.days['2026-07-13'].sales===100);
ck('...its hours', DATA.ledger.days['2026-07-13'].hours['Bo']===8);
ck('...its purchases', (DATA.ledger.purchases||[]).length===1);
ck('...and the wage rate', DATA.rateBook['Bo']===3);
ck('migrating twice does nothing', migrateToLedger()===false);

// ═══ MONTHS + THE SCREEN ═══
fresh();
for(let d=0;d<31;d++)ledgerPut(dayAdd('2026-05-01',d),{sales:100+d,guests:10},'t');
for(let d=0;d<12;d++)ledgerPut(dayAdd('2026-06-01',d),{sales:200,guests:20},'t');
let ms=ledgerMonths();
ck('months are summarised', ms.length===2&&ms[0].month==='2026-05');
ck('...counting the days with sales', ms[0].withSales===31&&ms[1].withSales===12);
ck('days in month is right for May', daysInMonth('2026-05')===31);
ck('...and February in a leap year', daysInMonth('2024-02')===29);
view='history'; render(); let h=__store['app'].innerHTML;
ck('the history screen lists the months', /2026-05/.test(h)&&/2026-06/.test(h));
ck('...shows the span on record', /43 day\(s\) on record/.test(h), (h.match(/\d+ day\(s\) on record/)||[])[0]||'');
ck('a full month is marked safe to compare', /Full month/.test(h));
ck('a partial month refuses comparison and says why',
   /Totals for this month would be understated/.test(h));
ck('...naming how many days are missing', /Missing 18 day\(s\)/.test(h), (h.match(/Missing \d+ day/)||[])[0]||'');
ck('the window can be moved from here', /shiftWindow\(-1\)/.test(h));
ck('no NaN', !/NaN/.test(h));
ck('history survives a save and reload', (saveNow(),DATA.ledger={days:{},purchases:[]},load(),
   ledgerDates().length===43), String(ledgerDates().length));
console.log(FL.length?('\n'+FL.length+' FAILED: '+FL.join(' | ')):'\nDAY LEDGER: ALL PASS');
