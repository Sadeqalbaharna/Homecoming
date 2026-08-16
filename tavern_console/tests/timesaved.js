let FT=[];const ck=(n,c,d='')=>{c?console.log('  PASS  '+n):(console.log('  FAIL  '+n+'  '+d),FT.push(n))};
SESSION={username:'owner',role:'owner'};WHO='owner';SETUP_DISMISSED=true;DATA.firstRunDone=true;

// ═══ THE ESTIMATE ═══
DATA.menu=[];DATA.ingredients=[];DATA.ledger={days:{},purchases:[]};
DATA.week={days:['a','b','c','d','e','f','g'],salesByDay:[0,0,0,0,0,0,0],guests:[0,0,0,0,0,0,0],employees:[],purchases:[]};
rebuildIX();
ck('an empty book saved no time', timeSaved().mins===0);

DATA.menu=Array.from({length:100},(_,i)=>({id:'m'+i,name:'D'+i,menuPrice:5,weeklySales:i<60?3:0,dept:'kitchen',lines:[]}));
DATA.ingredients=Array.from({length:200},(_,i)=>({id:'i'+i,code:''+i,name:'X'+i,price:2,recipeUnit:'kg',ruPerPu:1,pu:'kg',yield:1}));
for(let d=0;d<90;d++)DATA.ledger.days['2026-05-'+String((d%28)+1).padStart(2,'0')+'x'+d]={date:'2026-05-01',sales:100};
DATA.ledger.purchases=Array.from({length:24},(_,i)=>({id:'P'+i,supplier:'S'+(i%6),date:'2026-07-0'+((i%9)+1),amount:50}));
DATA.week.employees=[{name:'A',rate:2,hours:[8,0,0,0,0,0,0]},{name:'B',rate:2,hours:[8,0,0,0,0,0,0]}];
rebuildIX();
const t=timeSaved();
ck('a full book estimates real time', t.mins>0);
ck('...counting menu items', t.parts.some(p=>/menu items read/.test(p.label)&&p.n===100));
ck('...ingredients priced', t.parts.some(p=>/ingredients priced/.test(p.label)&&p.n===200));
ck('...invoices by distinct supplier+date', t.parts.some(p=>/invoices read/.test(p.label)));
ck('...and staff hours', t.parts.some(p=>/staff hours/.test(p.label)&&p.n===2));
// 100*0.5 + 200*1.5 + invoices*3 + 90*0.4 + 60*0.25 + 2*1.5 = 50+300+..+36+15+3
ck('the total is the sum of the parts', t.mins===Math.round(t.parts.reduce((s,p)=>s+p.mins,0)));
ck('...shown as hours when large', /hr/.test(t.label), t.label);
ck('it never invents time for records that are not there',
   (DATA.ingredients=[],rebuildIX(),!timeSaved().parts.some(p=>/ingredients/.test(p.label))));

// small amounts read as minutes
DATA.menu=[{id:'m',name:'X',menuPrice:5,weeklySales:0,dept:'kitchen',lines:[]}];
DATA.ingredients=[];DATA.ledger={days:{},purchases:[]};rebuildIX();
ck('a tiny amount reads in minutes', /min/.test(timeSaved().label));

// ═══ IT SHOWS ON THE REPORT ═══
DATA.menu=Array.from({length:50},(_,i)=>({id:'m'+i,name:'D'+i,menuPrice:5,weeklySales:2,dept:'kitchen',lines:[]}));
DATA.ingredients=Array.from({length:80},(_,i)=>({id:'i'+i,code:''+i,name:'X'+i,price:2,recipeUnit:'kg',ruPerPu:1,pu:'kg',yield:1}));
DATA.rates={vat:0,service:0,levy:0};rebuildIX();
DATA.setup={name:'Sadeq',done:true,started:true,skipped:{}};
view='unlocked';render();
const h=__store['app'].innerHTML;
ck('the report shows a Typing saved metric', /Typing saved/.test(h));
ck('...with an approximate figure', /~\d/.test(h));
ck('the report explains it', /The console did the data entry/.test(h));
ck('...framed as an estimate, not a boast', /floor rather than a boast/.test(h));
ck('no NaN', !/NaN/.test(h));

// celebration shows it too
DATA.setup={name:'S',done:false,started:true,skipped:{}};
celebrateStep('menu',{trust:0,count:''});
view='today';render();
ck('the celebration mentions the time saved', /manual entry the console has now done/.test(__store['app'].innerHTML));

// the invoices step teases ongoing time saved
ck('the invoices step teases time saved by scanning',
   SETUP_STEPS.find(s=>s.id==='invoices').examples.some(e=>/minutes? per invoice/.test(e)));
console.log(FT.length?('\n'+FT.length+' FAILED: '+FT.join(' | ')):'\nTIME SAVED: ALL PASS');
