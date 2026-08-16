let F=[];const ck=(n,c,d='')=>{c?console.log('  PASS  '+n):(console.log('  FAIL  '+n+'  '+d),F.push(n))};
const app=()=>__store['app'].innerHTML;
SESSION={username:'owner',role:'owner'}; DATA.firstRunDone=true;
// The guided flow now returns on every launch while steps are outstanding,
// so a suite testing the ordinary app has to say it has been dismissed.
SETUP_DISMISSED=true;
// The guided flow owns view 'today' until it is finished.
DATA.setup={name:'x',done:true,skipped:{},started:true};

// reproduce your state: a menu imported from the PDF, no ingredients at all
DATA.ingredients=[]; DATA.menu=[
  {id:'1',name:'Bowl of Nuts',menuPrice:3.5,group:'To Share',weeklySales:0,lines:[],dept:'kitchen'},
  {id:'2',name:'Grilled Cheese',menuPrice:6,group:'Sandwiches',weeklySales:0,lines:[],dept:'kitchen'},
  {id:'3',name:'The BFG',menuPrice:9.5,group:'Sandwiches',weeklySales:0,lines:[],dept:'kitchen'}];
const t=taskState();
const mp=t.find(x=>x.id==='menu-price'), ip=t.find(x=>x.id==='ing-price');
ck('menu prices read as complete', mp.complete, `${mp.done}/${mp.total}`);
ck('...and the label says what you SELL', /what you SELL/.test(mp.label), mp.label);
ck('ingredient prices read as not started', !ip.complete);
ck('with no ingredients at all it asks for ingredients, not prices',
   /Add your ingredients/.test(ip.label), ip.label);
// now give him ingredients, which is when the two prices can be confused
DATA.ingredients=[{id:'a',name:'Cashews',price:0,ruPerPu:1},{id:'b',name:'Salt',price:2,ruPerPu:1}];
const t2=taskState(), mp2=t2.find(x=>x.id==='menu-price'), ip2=t2.find(x=>x.id==='ing-price');
ck('...and once they exist, the label says what you BUY', /what you BUY/.test(ip2.label), ip2.label);
ck('...and the two can no longer be confused',
   mp2.label!==ip2.label&&/SELL/.test(mp2.label)&&/BUY/.test(ip2.label));
ck('ingredient prices count only the unpriced', ip2.done===1&&ip2.total===2, `${ip2.done}/${ip2.total}`);
ck('Which? on ingredient price names Cashews only',
   taskOffenders('ing-price').join()==='Cashews', taskOffenders('ing-price').join());
ck('the instruction spells out the difference',
   /purchase costs|pay suppliers/.test(stepAction(ip)), stepAction(ip));

// Which? names the records
DATA.menu.push({id:'4',name:'Mystery Dish',menuPrice:0,group:'',weeklySales:0,lines:[],dept:'kitchen'});
const off=taskOffenders('menu-price');
ck('Which? finds the unpriced item', off.length===1&&off[0]==='Mystery Dish', off.join());
ck('...and none of the priced ones', !off.includes('Bowl of Nuts'));
ck('recipes: every item is missing one', taskOffenders('menu-recipe').length===4);
ck('sales mix: every item is missing one', taskOffenders('sales-mix').length===4);
view='today'; render();
ck('the Which? button appears on incomplete tasks', /toggleTaskShow/.test(app()));
toggleTaskShow('menu-price'); render();
ck('...and names the record when clicked', /Mystery Dish/.test(app()));
ck('...with a count', /<b>1<\/b> still missing this/.test(app()));
toggleTaskShow('menu-price'); render();
ck('clicking again hides it', !/still missing this/.test(app()));
ck('no NaN', !/NaN/.test(app()));
console.log(F.length?('\n'+F.length+' FAILED: '+F.join(' | ')):'\nWHICH RECORDS: ALL PASS');
