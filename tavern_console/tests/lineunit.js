let FL=[];const ck=(n,c,d='')=>{c?console.log('  PASS  '+n):(console.log('  FAIL  '+n+'  '+d),FL.push(n))};
SESSION={username:'owner',role:'owner'};WHO='owner';SETUP_DISMISSED=true;DATA.firstRunDone=true;
DATA.ingredients=[
 {id:'a',code:'001',name:'Chicken',price:6,recipeUnit:'g-wt',ruPerPu:1000,pu:'KG',yield:1},
 {id:'b',code:'002',name:'Cream',price:4,recipeUnit:'ml-fl',ruPerPu:1000,pu:'LTR',yield:1}];
DATA.batch=[{id:'s',code:'B1',name:'Sauce',yieldQty:1000,yieldUnit:'ml',lines:[{ref:'002_Cream',qty:500}]}];
DATA.menu=[{id:'m',name:'Dish',menuPrice:8,weeklySales:1,dept:'kitchen',
  lines:[{ref:'001_Chicken',qty:180},{ref:'',qty:0}]}];
rebuildIX();rebuildBX();
openM=0;view='menu';render();
const h=__store['app'].innerHTML;

ck('a picked ingredient shows its unit beside the quantity',
   /class="mini"[^>]*>g-wt<\/b>/.test(h), (h.match(/min-width:26px[^>]*>[^<]*/)||[])[0]||'');
ck('...and the quantity value is present', /value="180"/.test(h));
ck('an unpicked line disables the quantity', /disabled placeholder="pick first"/.test(h));
ck('...so a number cannot be typed with no unit', !/value=""[^>]*onchange="setQty[^>]*>[^d]/.test(h)||/disabled/.test(h));
ck('the qty field spells out the unit in its tooltip', /Quantity in g-wt/.test(h));
ck('Enter still adds the next line', /Enter adds the next line/.test(h));
ck('no NaN', !/NaN/.test(h));

// batch recipes: the line unit is the batch yield unit
DATA.menu=[{id:'m2',name:'Pasta',menuPrice:9,weeklySales:1,dept:'kitchen',lines:[{ref:'Bs',qty:50}]}];
rebuildBX();openM=0;render();
const h2=__store['app'].innerHTML;
ck('a batch line shows the batch yield unit', /ml<\/b>/.test(h2), (h2.match(/min-width:26px[^>]*>[^<]*/)||[])[0]||'');

// unitOf itself is correct
ck('unitOf reads an ingredient recipe unit', unitOf('001_Chicken')==='g-wt');
ck('...and a batch yield unit', unitOf('Bs')==='ml');
ck('...and nothing for an empty ref', unitOf('')==='');
console.log(FL.length?('\n'+FL.length+' FAILED: '+FL.join(' | ')):'\nLINE UNITS: ALL PASS');
