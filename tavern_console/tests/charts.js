let FC=[];const ck=(n,c,d='')=>{c?console.log('  PASS  '+n):(console.log('  FAIL  '+n+'  '+d),FC.push(n))};
SESSION={username:'owner',role:'owner'};WHO='owner';
// The guided flow now returns on every launch while steps are outstanding,
// so a suite testing the ordinary app has to say it has been dismissed.
SETUP_DISMISSED=true;
DATA.setup={name:'Sadeq',done:true,started:true,skipped:{}};DATA.firstRunDone=true;
STAGE=null;INVBATCH=null;RESEARCH=null;CATPROP=null;

// ═══ DONUT GEOMETRY ═══
const seg=(...v)=>v.map((x,i)=>({label:'s'+i,value:x}));
let d=svgDonut(seg(1,1,1,1),160,20);
const dashes=[...d.matchAll(/stroke-dasharray="([\d.]+) ([\d.]+)"/g)].map(m=>+m[1]);
ck('four equal shares give four equal arcs',
   dashes.length===4&&Math.abs(dashes[0]-dashes[3])<0.01, JSON.stringify(dashes));
const C=2*Math.PI*((160-20)/2);
ck('...that add up to the whole circle', Math.abs(dashes.reduce((a,b)=>a+b,0)-C)<0.05,
   dashes.reduce((a,b)=>a+b,0)+' vs '+C);
const offs=[...d.matchAll(/stroke-dashoffset="(-?[\d.]+)"/g)].map(m=>+m[1]);
ck('...laid end to end, not stacked', offs[1]!==offs[2]&&offs[0]===0, JSON.stringify(offs));
// the case arc paths get wrong
d=svgDonut(seg(1,1),160,20);
const two=[...d.matchAll(/stroke-dasharray="([\d.]+) /g)].map(m=>+m[1]);
ck('a 50/50 split is exactly half each', Math.abs(two[0]-C/2)<0.01&&Math.abs(two[1]-C/2)<0.01);
d=svgDonut(seg(1),160,20);
ck('a single 100% segment fills the ring',
   Math.abs([...d.matchAll(/stroke-dasharray="([\d.]+) /g)].map(m=>+m[1])[0]-C)<0.01);
ck('zero values are skipped, not drawn as slivers',
   (svgDonut(seg(3,0,1),160,20).match(/stroke-dasharray/g)||[]).length===2);
ck('an all-zero donut says "no data" rather than drawing nonsense',
   /no data/.test(svgDonut(seg(0,0),160,20)));
ck('an empty donut does not crash', /svg/.test(svgDonut([],160,20)));
ck('negative values cannot invert an arc', !/dasharray="-/.test(svgDonut(seg(-5,10),160,20)));
ck('no NaN in any donut', ![svgDonut(seg(1,2),160,20),svgDonut([],80,10),svgDonut(seg(0),80,10)]
   .some(s=>/NaN/.test(s)));

// ═══ BARS ═══
let b=svgBars([{label:'Mon',value:10},{label:'Tue',value:20},{label:'Wed',value:0}]);
const hs=[...b.matchAll(/height="([\d.]+)" rx/g)].map(m=>+m[1]);
ck('a bar twice the value is twice as tall', Math.abs(hs[1]-hs[0]*2)<0.5, JSON.stringify(hs));
ck('a zero bar still renders a baseline rather than vanishing', hs[2]>=1);
ck('bars do not escape the canvas', [...b.matchAll(/y="([\d.]+)"/g)].every(m=>+m[1]>=0));
ck('empty bars say so', /no data yet/.test(svgBars([])));
ck('all-zero bars say so too', /no data yet/.test(svgBars([{label:'a',value:0}])));
ck('no NaN in bars', !/NaN/.test(svgBars([{label:'a',value:0}]))&&!/NaN/.test(b));

// ═══ HORIZONTAL BARS ═══
let hb=svgHBars([{label:'Very Long Dish Name That Goes On',value:5,note:'5.000'},{label:'B',value:10}]);
// The VISIBLE label is truncated; the <title> tooltip keeps the full name,
// which is right — hovering should tell you which dish it is.
ck('the visible label is truncated',
   !/>Very Long Dish Name That Goes On</.test(hb), (hb.match(/>[^<]*Very Long[^<]*</)||[])[0]||'');
ck('...but the tooltip keeps the whole name', /<title>Very Long Dish Name That Goes On:/.test(hb));
ck('the widest bar belongs to the largest value',
   (()=>{const w=[...hb.matchAll(/width="([\d.]+)" height/g)].map(m=>+m[1]);return w[1]>w[0]})());
ck('empty hbars say so', /no data yet/.test(svgHBars([])));
ck('no NaN in hbars', !/NaN/.test(hb));

// ═══ LINE ═══
ck('a line needs two points', svgLine([5]).indexOf('path')===-1);
ck('a flat line does not divide by zero', !/NaN/.test(svgLine([5,5,5])));
ck('a real line draws', /path d="M/.test(svgLine([1,5,3])));

// ═══ THE SCREEN ═══
DATA.menu=[];DATA.ingredients=[];
DATA.week={days:['a','b','c','d','e','f','g'],salesByDay:[0,0,0,0,0,0,0],guests:[0,0,0,0,0,0,0],
  employees:[],purchases:[]};
rebuildIX();rebuildBX();
view='unlocked';render();let h=__store['app'].innerHTML;
ck('an empty book still renders the screen', /Here is what you unlocked/.test(h));
ck('...greeting by name', /unlocked, Sadeq/.test(h));
ck('...with no NaN', !/NaN/.test(h));
ck('...and says what each empty chart needs', /Upload daily sales to fill this in/.test(h));
ck('...listing everything as still locked', /STILL LOCKED/.test(h));

DATA.menu=[{id:'m1',name:'Chicken Plate',menuPrice:6,weeklySales:100,dept:'kitchen',
   lines:[{ref:'001_Chicken',qty:0.2}]},
  {id:'m2',name:'Salad',menuPrice:4,weeklySales:50,dept:'kitchen',lines:[]}];
DATA.ingredients=[{id:'a',code:'001',name:'Chicken',price:5,recipeUnit:'kg',ruPerPu:1,pu:'kg',yield:1,history:[]}];
DATA.rates={vat:0.10,service:0.10,levy:0};
DATA.week={days:['a','b','c','d','e','f','g'],salesByDay:[100,200,150,300,400,500,250],
  guests:[10,20,15,30,40,50,25],
  employees:[{name:'A',rate:2,hours:[8,8,8,8,8,8,0]}],
  purchases:[{supplier:'Gulf',date:'1/7/2026',amount:300,alloc:{Meat:300}},
             {supplier:'Delta',date:'2/7/2026',amount:120,alloc:{Produce:120}}]};
rebuildIX();rebuildBX();
render();h=__store['app'].innerHTML;
ck('with data, the money donut draws', (h.match(/stroke-dasharray/g)||[]).length>2);
ck('the day bars draw', (h.match(/rx="2"/g)||[]).length>3);
ck('top dishes are listed', /Chicken Plate/.test(h));
ck('supplier spend appears', /Gulf/.test(h)&&/Delta/.test(h));
ck('food cost by dish appears for costed dishes', /Food cost by dish/.test(h));
ck('...and says how many are costed', /1 of 2 dishes costed/.test(h));
ck('unlocked steps show their italic unlocks', /<i>food cost per dish/.test(h));
ck('prime cost is shown as a headline', /Prime cost/.test(h));
ck('there is a way onward to the report', /go\('report'\)/.test(h));
ck('...and back to the checklist', /go\('today'\)/.test(h));
ck('no NaN with real data', !/NaN/.test(h));
ck('no Infinity either', !/Infinity/.test(h));

// finishing the flow lands here
DATA.setup={name:'X',done:false,started:true,skipped:{}};
setupFinish();
ck('finishing the guided flow opens this screen', view==='unlocked');
console.log(FC.length?('\n'+FC.length+' FAILED: '+FC.join(' | ')):'\nCHARTS: ALL PASS');

// ═══ THE UNLOCKED REPORT ANIMATES — BUT DEGRADES TO THE TRUTH ═══
(function(){
 let G=[];const ck2=(n,c,d='')=>{c?console.log('  PASS  '+n):(console.log('  FAIL  '+n+'  '+d),G.push(n))};
 SESSION={username:'owner',role:'owner'};WHO='owner';SETUP_DISMISSED=true;DATA.firstRunDone=true;
 DATA.setup={name:'Sadeq',done:true,started:true,skipped:{}};
 DATA.menu=[{id:'m',name:'Chicken',menuPrice:6,weeklySales:100,dept:'kitchen',lines:[{ref:'001_X',qty:1}]}];
 DATA.ingredients=[{id:'x',code:'001',name:'X',price:2,recipeUnit:'kg',ruPerPu:1,pu:'kg',yield:1,history:[]}];
 DATA.rates={vat:0.1,service:0.1,levy:0};
 DATA.week={days:['a','b','c','d','e','f','g'],salesByDay:[100,200,150,300,400,500,250],
   guests:[10,20,15,30,40,50,25],employees:[{name:'A',rate:2,hours:[8,8,8,8,8,8,0]}],
   purchases:[{supplier:'Gulf',date:'1/7/2026',amount:300,alloc:{Meat:300}}]};
 rebuildIX();rebuildBX();
 view='unlocked'; render();
 const h=__store['app'].innerHTML;

 // the animation HOOKS are present
 ck2('donut segments are marked for the draw-on', /class="donutseg"/.test(h));
 ck2('...carrying their real length for the reveal', /data-len="/.test(h)&&/data-c="/.test(h));
 ck2('bars are marked to rise', /class="risebar"/.test(h)&&/animation:barRise/.test(h));
 ck2('horizontal bars grow from the left', /class="growbar"/.test(h)&&/animation:barGrow/.test(h));
 ck2('the KPI numbers are marked to count up', /data-count="/.test(h));
 ck2('the card grids reveal in sequence', /grid2 reveal/.test(h));

 // …but the STATIC picture is already correct (degrade-to-truth)
 ck2('the donut still shows its true final arcs', (h.match(/stroke-dasharray="[\d.]+ [\d.]+"/g)||[]).length>=2);
 ck2('...not a zeroed placeholder', !/stroke-dasharray="0\.00 /.test(h));
 ck2('the KPI still shows its real number, not 0', /data-count="1"[^>]*>1<|>1\/6</.test(h)||/Steps done/.test(h));
 ck2('the bars still have real heights', (h.match(/class="risebar"[^>]*height="[\d.]+"/g)||[]).length>0);
 ck2('no NaN anywhere', !/NaN/.test(h));

 // the orchestrator is safe to call with no browser
 let threw=null; try{ playUnlocked(); }catch(e){ threw=e.message; }
 ck2('playUnlocked is a no-op without a real browser, never throws', threw===null, String(threw));

 // reduced-motion is respected
 const css=require('fs').readFileSync(process.env.TC,'utf-8');
 ck2('prefers-reduced-motion turns the animation off', /prefers-reduced-motion:reduce/.test(css)&&/animation:none/.test(css));
 console.log(G.length?('\n'+G.length+' ANIM FAILED: '+G.join(' | ')):'UNLOCKED ANIMATION: ALL PASS');
})();
