let FQ=[];const ck=(n,c,d='')=>{c?console.log('  PASS  '+n):(console.log('  FAIL  '+n+'  '+d),FQ.push(n))};
SESSION={username:'owner',role:'owner'};WHO='owner';SETUP_DISMISSED=true;DATA.firstRunDone=true;
CELEBRATE=null;STAGE=null;CATPROP=null;CATSHOCK=null;PALETTE=null;TOASTS=[];
global.setTimeout=(fn)=>0;   // no real timers in the harness

// ═══ NUMBERS AS PEOPLE TYPE THEM ═══
// The bug that started this: parseFloat("1,250") is 1, not NaN.
ck('parseFloat gets a thousands separator WRONG', parseFloat('1,250')===1);
ck('num() gets it right', num('1,250')===1250, String(num('1,250')));
ck('...and a bigger one', num('1,250,500')===1250500);
ck('a plain decimal still works', num('4.5')===4.5);
ck('a currency prefix is stripped', num('BD 4.50')===4.5, String(num('BD 4.50')));
ck('...and a suffix', num('4.50 BHD')===4.5);
ck('...and a symbol', num('$1,299.99')===1299.99);
ck('European decimals work', num('1.250,75')===1250.75, String(num('1.250,75')));
ck('a lone European decimal comma works', num('4,50')===4.5, String(num('4,50')));
ck('...but 1,250 is still thousands', num('1,250')===1250);
ck('accounting negatives work', num('(35.50)')===-35.5, String(num('(35.50)')));
ck('spaces as separators work', num('1 250')===1250);
ck('a number passes through', num(42)===42);
ck('nothing is null, not zero', num('')===null&&num(null)===null&&num(undefined)===null);
ck('...and so is junk', num('abc')===null, String(num('abc')));
ck('zero is zero, not null', num('0')===0);
ck('a negative is negative', num('-7.5')===-7.5);

// ═══ TOASTS ═══
TOASTS=[];
toast('12 rows imported');
ck('a toast appears', TOASTS.length===1&&/12 rows/.test(TOASTS[0].msg));
ck('...without blocking anything', (__alerts||[]).length===0);
toast('undoable',{action:'undo()',actionLabel:'Undo'});
ck('a toast can carry an action', TOASTS[1].action==='undo()');
ck('...and it lives longer than a plain one', TOASTS[1].ms>TOASTS[0].ms);
for(let i=0;i<6;i++)toast('n'+i);
ck('they do not stack up forever', TOASTS.length<=4, String(TOASTS.length));
const id=TOASTS[0].id; dismissToast(id);
ck('a toast can be dismissed', !TOASTS.some(t=>t.id===id));
drawToasts();
ck('they render', /class="toast/.test((__store['toasts']||{innerHTML:''}).innerHTML));
TOASTS=[];toast('bad thing',{kind:'bad'});drawToasts();
ck('...with a kind', /toast bad/.test(__store['toasts'].innerHTML));

// an import now toasts instead of blocking
TOASTS=[];global.__alerts=[];
DATA.menu=[];DATA.ingredients=[];rebuildIX();
STAGE={kind:'products',headers:['Item','Price'],rows:[['A','5']],map:{name:0,price:1},headerRow:0};
stageApply();
ck('an import reports with a toast, not a dialog', TOASTS.length===1&&(__alerts||[]).length===0,
   'alerts:'+(__alerts||[]).length);
ck('...offering Undo right there', TOASTS[0].action==='undo()');

// ═══ COMMAND PALETTE ═══
DATA.menu=[{id:'m',name:'Espresso Martini',menuPrice:6,weeklySales:1,dept:'bar',lines:[]}];
DATA.ingredients=[{id:'i',code:'042',name:'Cashew Nuts',price:8,recipeUnit:'kg',ruPerPu:1,pu:'kg',yield:1}];
rebuildIX();
let hits=paletteHits('');
ck('with no query it lists screens', hits.length>0&&hits.every(h=>h.kind==='screen'));
hits=paletteHits('labour');
ck('a screen is findable by name', hits.some(h=>/Labour/i.test(h.label)));
hits=paletteHits('espresso');
ck('a dish is findable', hits.some(h=>h.kind==='dish'&&/Espresso/.test(h.label)));
hits=paletteHits('cashew');
ck('an ingredient is findable', hits.some(h=>h.kind==='ing'));
hits=paletteHits('042');
ck('...and by its code', hits.some(h=>h.kind==='ing'&&/Cashew/.test(h.label)));
ck('one letter does not search the whole book', !paletteHits('e').some(h=>h.kind!=='screen'));
// The comparison screen is gated until a priced menu exists — clear it so
// the gate is closed, which is the state where it must not be offered.
const _savedMenu=DATA.menu; DATA.menu=[];
ck('a gated screen is not offered', !paletteHits('compare').some(h=>/Compare with others/.test(h.label)),
   paletteHits('compare').map(h=>h.label).join());
DATA.menu=_savedMenu;
ck('results are capped', paletteHits('').length<=12);
openPalette();
ck('it opens', !!PALETTE);
drawPalette();
ck('...and renders', /palwrap/.test((__store['palette']||{innerHTML:''}).innerHTML));
ck('...with a hint about Enter and Esc', /Esc closes/.test(__store['palette'].innerHTML));
closePalette();
ck('...and closes', PALETTE===null&&__store['palette'].innerHTML==='');

// ═══ DUPLICATE A DISH ═══
DATA.menu=[{id:'m1',name:'Burger',menuPrice:6,weeklySales:50,posCode:'B1',dept:'kitchen',
  lines:[{ref:'042_Cashew Nuts',qty:10}]},
  {id:'m2',name:'Salad',menuPrice:4,weeklySales:5,dept:'kitchen',lines:[]}];
TOASTS=[];UNDO.length=0;
dupMenu(0);
ck('a dish duplicates', DATA.menu.length===3);
ck('...right next to the original', DATA.menu[1].name==='Burger (copy)');
ck('...with the recipe', DATA.menu[1].lines.length===1);
ck('...but not the POS code', DATA.menu[1].posCode==='');
ck('...nor the sales, which belong to the original', DATA.menu[1].weeklySales===0);
ck('...with its own id', DATA.menu[1].id!==DATA.menu[0].id);
ck('...and it is undoable from the toast', TOASTS[0].action==='undo()');
undo();
ck('undo removes the copy', DATA.menu.length===2);

// ═══ COPY A RECIPE ═══
TOASTS=[];
copyRecipeFrom(1,'Burger');
ck('a recipe copies across', DATA.menu[1].lines.length===1);
ck('...as a real copy, not a shared reference',
   (DATA.menu[1].lines[0].qty=99, DATA.menu[0].lines[0].qty===10));
TOASTS=[];
copyRecipeFrom(1,'Nonexistent');
ck('an unknown dish says so', /No dish called/.test(TOASTS[0].msg));
ck('...as a bad toast', TOASTS[0].kind==='bad');
TOASTS=[];
DATA.menu.push({id:'m3',name:'Empty',menuPrice:1,weeklySales:0,dept:'kitchen',lines:[]});
copyRecipeFrom(1,'Empty');
ck('a dish with no recipe says so', /has no recipe to copy/.test(TOASTS[0].msg));

// ═══ STICKY HEADERS ═══
const html=require('fs').readFileSync(process.env.TC,'utf-8');
ck('table headers stick when scrolling', /thead th\{position:sticky/.test(html));
console.log(FQ.length?('\n'+FQ.length+' FAILED: '+FQ.join(' | ')):'\nQUALITY OF LIFE: ALL PASS');
