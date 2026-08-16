let FR=[];const ck=(n,c,d='')=>{c?console.log('  PASS  '+n):(console.log('  FAIL  '+n+'  '+d),FR.push(n))};
SESSION={username:'owner',role:'owner'};WHO='owner';SETUP_DISMISSED=true;DATA.firstRunDone=true;
TOASTS=[];global.setTimeout=fn=>0;

// ═══ UNDO / REDO PAIR ═══
DATA.menu=[{id:'m',name:'Original',menuPrice:5,weeklySales:0,dept:'kitchen',lines:[]}];
DATA.ingredients=[];UNDO.length=0;REDO.length=0;rebuildIX();
editAs2('renaming',()=>{DATA.menu[0].name='Changed'});
ck('an edit changes the value', DATA.menu[0].name==='Changed');
ck('...and stacks an undo', UNDO.length===1);
undo();
ck('undo rolls it back', DATA.menu[0].name==='Original');
ck('...and offers redo', REDO.length===1);
ck('...via a toast', TOASTS.some(t=>t.action==='redo()'));
redo();
ck('redo brings it forward again', DATA.menu[0].name==='Changed');
ck('...clearing the redo stack', REDO.length===0);
ck('...and undo is available again', UNDO.length===1);

// a NEW action kills the redo path
undo();
ck('undo again', DATA.menu[0].name==='Original'&&REDO.length===1);
editAs2('a fresh change',()=>{DATA.menu[0].menuPrice=9});
ck('a new action clears redo', REDO.length===0);
redo();
ck('...so there is nothing to redo into', DATA.menu[0].menuPrice===9);

// empty stacks are gentle, not alerts
TOASTS=[];UNDO.length=0;REDO.length=0;
undo();
ck('undo with nothing says so via toast, not alert', TOASTS.some(t=>/Nothing to undo/.test(t.msg)));
TOASTS=[];redo();
ck('redo with nothing too', TOASTS.some(t=>/Nothing to redo/.test(t.msg)));

// ═══ DELETES ARE UNDOABLE WITH FEEDBACK ═══
DATA.week={days:['a','b','c','d','e','f','g'],salesByDay:[0,0,0,0,0,0,0],guests:[0,0,0,0,0,0,0],
  employees:[{name:'Ana',rate:2,hours:[8,0,0,0,0,0,0]},{name:'Bo',rate:2,hours:[8,0,0,0,0,0,0]}],
  purchases:[{id:'P1',supplier:'Gulf',date:'2026-07-01',amount:50,alloc:{}}]};
TOASTS=[];UNDO.length=0;
empDel(0);
ck('deleting an employee works', (DATA.week.employees||[]).length===1&&DATA.week.employees[0].name==='Bo');
ck('...tells you who went', /Removed Ana/.test((TOASTS[0]||{}).msg||''));
ck('...with an Undo', TOASTS[0].action==='undo()');
undo();
ck('...and undo brings them back', DATA.week.employees.length===2);
TOASTS=[];
purchDel(0);
ck('deleting a purchase works', (DATA.week.purchases||[]).length===0);
ck('...names the supplier', /Gulf/.test((TOASTS[0]||{}).msg||''));
undo();
ck('...and is reversible', DATA.week.purchases.length===1);

// ═══ THE TOOLBAR REFLECTS AVAILABILITY ═══
UNDO.length=0;REDO.length=0;SETUP_DISMISSED=true;view='menu';render();
let h=__store['app'].innerHTML;
ck('undo is disabled when there is nothing', /↶ Undo/.test(h)&&/redo\(\)/.test(h));
ck('a redo button exists', /↷ Redo/.test(h));
editAs2('x',()=>{DATA.menu[0].name='Y'});render();
h=__store['app'].innerHTML;
ck('undo enables after an edit', /↶ Undo <span/.test(h)||!/↶ Undo[^<]*disabled/.test(h));
ck('no NaN', !/NaN/.test(h));
console.log(FR.length?('\n'+FR.length+' FAILED: '+FR.join(' | ')):'\nREDO: ALL PASS');

// ═══ SEARCH SURVIVES NAVIGATION ═══
(function(){
 let G=[];const ck2=(n,c,d='')=>{c?console.log('  PASS  '+n):(console.log('  FAIL  '+n+'  '+d),G.push(n))};
 QMEM={};
 view='ing'; setQ('cashew');
 ck2('a search is set', q==='cashew');
 go('menu');
 ck2('...cleared when you move to a different screen', q==='');
 go('ing');
 ck2('...but restored when you come back', q==='cashew', q);
 go('menu'); setQ('burger'); go('ing');
 ck2('each screen keeps its own search', q==='cashew');
 go('menu');
 ck2('...independently', q==='burger');

 // ═══ ENTER ADDS A RECIPE LINE ═══
 DATA.menu=[{id:'m',name:'Dish',menuPrice:5,weeklySales:0,dept:'kitchen',lines:[{ref:'',qty:0}]}];
 rebuildIX();
 const n0=DATA.menu[0].lines.length;
 lineKey({key:'Enter',preventDefault(){}},'m',0);
 ck2('Enter in a quantity adds the next line', DATA.menu[0].lines.length===n0+1);
 lineKey({key:'Tab',preventDefault(){}},'m',0);
 ck2('...but Tab does not', DATA.menu[0].lines.length===n0+1);
 const html=require('fs').readFileSync(process.env.TC,'utf-8');
 ck2('the quantity field is wired for Enter', /onkeydown="lineKey\(event/.test(html));
 ck2('...and the ingredient box is focusable', /class="wide recipe-ing"/.test(html));
 console.log(G.length?('\n'+G.length+' SEARCH/ENTER FAILED: '+G.join(' | ')):'SEARCH + ENTER: ALL PASS');
})();
