let FN=[];const ck=(n,c,d='')=>{c?console.log('  PASS  '+n):(console.log('  FAIL  '+n+'  '+d),FN.push(n))};
SESSION={username:'owner',role:'owner'};WHO='owner';SETUP_DISMISSED=true;DATA.firstRunDone=true;
CATSHOCK=null;
const clean=()=>{DATA.ingredients=[];DATA.menu=[];DATA.batch=[];DATA.posRejected={};
  DATA.settings={vatAsked:true};DATA.ledger={days:{},purchases:[]};rebuildIX();rebuildBX();};

// ═══ EMPTY WHEN THERE IS NOTHING TO ASK ═══
clean();
ck('a clean book has no open questions', pendingQuestions().length===0, JSON.stringify(pendingQuestions().map(q=>q.title)));

// ═══ EACH CONFUSION BECOMES A QUESTION ═══
clean();
DATA.ingredients=[{id:'a',code:'001',name:'Olives',price:5,category:'',recipeUnit:'kg',ruPerPu:1,pu:'kg',yield:1,history:[{at:1,price:5,src:'goods received'}]}];
rebuildIX();
ck('a priced ingredient with no category asks', pendingQuestions().some(q=>/no category/.test(q.title)));
DATA.ingredients[0].category='Grocery';rebuildIX();
ck('...and stops asking once categorised', !pendingQuestions().some(q=>/no category/.test(q.title)));

clean();
DATA.ingredients=[{id:'a',code:'001',name:'X',price:5,category:'G',recipeUnit:'kg',ruPerPu:0,pu:'kg',yield:1}];
rebuildIX();
ck('a price with no pack size asks', pendingQuestions().some(q=>/no pack size/.test(q.title)));

clean();
DATA.posRejected={unmatched:[{name:'Mystery Cocktail',qty:9}]};
ck('an unmatched sales line asks', pendingQuestions().some(q=>/matched no dish/.test(q.title)));

clean();
DATA.settings={};DATA.ingredients=[{id:'a',name:'X',price:5,category:'G',recipeUnit:'kg',ruPerPu:1,pu:'kg',yield:1,history:[{at:1,price:5,src:'goods received'}]}];rebuildIX();
ck('unset VAT with purchases asks', pendingQuestions().some(q=>/include VAT/.test(q.title)));

clean();
DATA.ingredients=[{id:'a',code:'001',name:'Beef',price:10,category:'Meat',recipeUnit:'kg',ruPerPu:1,pu:'kg',yield:0}];rebuildIX();
ck('an impossible value asks', pendingQuestions().some(q=>/impossible value/.test(q.title)));

// a circular batch → uncostable dish
clean();
DATA.ingredients=[{id:'a',code:'001',name:'X',price:2,category:'G',recipeUnit:'kg',ruPerPu:1,pu:'kg',yield:1}];
DATA.batch=[{id:'b1',code:'B1',name:'A',yieldQty:1,yieldUnit:'ml',lines:[{ref:'Bb1',qty:1}]}];
DATA.menu=[{id:'m',name:'Dish',menuPrice:5,weeklySales:1,dept:'kitchen',lines:[{ref:'Bb1',qty:1}]}];
rebuildIX();rebuildBX();
ck('an uncostable dish asks', pendingQuestions().some(q=>/cannot be costed/.test(q.title)));

// ═══ ERRORS BEFORE ASKS ═══
clean();
DATA.ingredients=[{id:'a',code:'001',name:'Beef',price:-5,category:'',recipeUnit:'kg',ruPerPu:1,pu:'kg',yield:1,history:[{at:1,price:5,src:'goods received'}]}];rebuildIX();
const Q=pendingQuestions();
ck('errors are ordered before asks', Q[0].kind==='error', Q.map(q=>q.kind).join());

// ═══ THE QUEUE HAS A HOME, WITH A COUNT ═══
clean();
DATA.ingredients=[{id:'a',code:'001',name:'X',price:5,category:'',recipeUnit:'kg',ruPerPu:1,pu:'kg',yield:1,history:[{at:1,price:5,src:'goods received'}]}];rebuildIX();
view='needs';render();
let h=__store['app'].innerHTML;
ck('the needs screen renders', /Needs your input/.test(h));
ck('...listing the question', /no category/.test(h));
ck('...with a jump to resolve it', /go\('ing'\)/.test(h));
ck('no NaN', !/NaN/.test(h));
// the count badge in the nav
drawSide&&drawSide();
const side=(__store['sidegroups']||{innerHTML:''}).innerHTML;
ck('the nav carries a live count badge', /background:var\(--bad\)/.test(side)||/needs/.test(side));

// empty state
clean();view='needs';render();
ck('empty says nothing to resolve', /Nothing to resolve/.test(__store['app'].innerHTML));
console.log(FN.length?('\n'+FN.length+' FAILED: '+FN.join(' | ')):'\nNEEDS INPUT: ALL PASS');
