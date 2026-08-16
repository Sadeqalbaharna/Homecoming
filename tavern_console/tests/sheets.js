let F=[];const ck=(n,c,d='')=>{c?console.log('  PASS  '+n):(console.log('  FAIL  '+n+'  '+d),F.push(n))};
SESSION={username:'owner',role:'owner'};WHO='owner';DATA.firstRunDone=true;
DATA.ingredients=[
 {code:'001',name:'Chicken Breast',category:'Meat',price:4,recipeUnit:'g-wt',ruPerPu:1000,purchaseUnit:'KG',yield:1},
 {code:'002',name:'Olive Oil',category:'Condiments',price:5,recipeUnit:'ml-fl',ruPerPu:1000,purchaseUnit:'LTR',yield:1},
 {code:'003',name:'Salt',category:'Grocery',price:1,recipeUnit:'g-wt',ruPerPu:1000,purchaseUnit:'KG',yield:1}];
DATA.menu=[
 {id:'D001',name:'Grilled Chicken',group:'Mains',menuPrice:6,weeklySales:50,dept:'kitchen',
  lines:[{ref:'001_Chicken Breast',qty:200},{ref:'003_Salt',qty:2}]},
 {id:'D002',name:'New Dish',group:'Mains',menuPrice:5,weeklySales:10,dept:'kitchen',lines:[]}];
rebuildIX();rebuildBX();
const fid1=_fid(DATA.menu[0]), fid2=_fid(DATA.menu[1]);

// ═══ THE PRINTED SHEET ═══
const h=recipeSheetHTML(['D001','D002']);
ck('the form id is printed', h.includes(fid1)&&h.includes(fid2));
ck('...and marked not to be changed', /do not change/.test(h));
ck('corner marks are printed for deskewing', (h.match(/class="reg/g)||[]).length>=3);
ck('ONE PORTION is unmissable', /ONE PORTION/.test(h));
ck('an existing recipe prints its current numbers', /wasv">200/.test(h));
ck('...and asks for a correction, not an author', /cross it out/.test(h));
ck('a dish with no recipe says so plainly', /Nothing is recorded for this dish yet/.test(h));
// the core design claim
ck('there is NOWHERE to write an ingredient name', !/class="write"/.test(h));
ck('blank rows ask for a CODE instead', /Ingredient code/.test(h));
ck('digits get one box each', (h.match(/class="d"/g)||[]).length>20);
ck('units are ticked, not written', /tick"><\/span>g/.test(h));
ck('the pantry is NOT repeated on every dish sheet', !/Ingredients you buy/.test(h));
ck('...and the photo instruction is there', /all four edges/.test(h));
ck('portions is asked for', /makes/.test(h)&&/portion/.test(h));

// ═══ THE WALL SHEET ═══
const p=pantrySheetHTML();
ck('the pantry sheet lists codes', /001/.test(p)&&/Chicken Breast/.test(p));
ck('...grouped by category', /Meat/.test(p)&&/Condiments/.test(p));
ck('...with the recipe unit', /g-wt/.test(p));
ck('...and says why codes beat names', /misread name is not/.test(p));

// ═══ READING ONE BACK ═══
let r=readRecipeSheet({formId:fid1,portions:1,lines:[
  {code:'001',qty:180,corrected:true},{code:'003',qty:2,corrected:false}]});
ck('the form id finds the dish', r.dish&&r.dish.id==='D001');
ck('both lines resolve', r.lines.length===2);
ck('a corrected quantity comes through', r.lines[0].qty===180);
ck('...and it knows what it was', r.lines[0].was===200);
ck('the ingredient name is resolved from the code', r.lines[0].name==='Chicken Breast');
ck('the recipe unit comes from YOUR pantry, not the sheet', r.lines[0].unit==='g-wt');
ck('no problems on a clean sheet', r.problems.length===0, r.problems.join());

// THE ONE THAT MATTERS: a bad code must not be silently corrected
r=readRecipeSheet({formId:fid1,portions:1,lines:[{code:'007',qty:50}]});
ck('an unknown code is NOT matched to a near one', r.lines.length===0);
ck('...it is reported', /Code 007 is not in your pantry/.test(r.problems[0]||''));
ck('...and says nothing was guessed', /Nothing was guessed/.test(r.problems[0]||''));

r=readRecipeSheet({formId:'RS-ZZZZZZ',portions:1,lines:[{code:'001',qty:10}]});
ck('an unmatched form is reported, not applied to a random dish', !r.dish&&r.problems.length===1);
ck('...telling you where the id is', /printed top-right/.test(r.problems[0]));

r=readRecipeSheet({formId:fid1,lines:[{code:'001',qty:0},{code:'',qty:5}]});
ck('a zero quantity is left out', !r.lines.length);
ck('...and both are explained', r.problems.length===2);

// ═══ APPLYING ═══
r=readRecipeSheet({formId:fid2,portions:2,lines:[
  {code:'001',qty:150},{code:'002',qty:10},{code:'003',qty:1}]});
ck('nothing is written by reading', (DATA.menu[1].lines||[]).length===0);
const res=applyRecipeSheet(r);
ck('applying writes the lines', res.ok&&DATA.menu[1].lines.length===3);
ck('...in the ref format the coster expects', /^001_/.test(DATA.menu[1].lines[0].ref), DATA.menu[1].lines[0].ref);
ck('...and the dish now costs', itemCost(DATA.menu[1])>0, String(itemCost(DATA.menu[1])));
ck('portions is recorded when more than one', DATA.menu[1].portions===2);
const before=itemCost(DATA.menu[0]);
applyRecipeSheet(readRecipeSheet({formId:fid1,lines:[{code:'001',qty:180},{code:'003',qty:2}]}));
ck('a correction changes the cost', itemCost(DATA.menu[0])!==before);

// ═══ THE UI ═══
view='sheets'; STAGE=null; INVBATCH=null; render();
const ui=__store['app'].innerHTML;
ck('the wall list can be printed', /printPantry\(\)/.test(ui));
ck('filled sheets can be scanned back', /stageBatch\(this,'recipes'\)/.test(ui));
ck('no NaN', !/NaN/.test(ui));
console.log(F.length?('\n'+F.length+' FAILED: '+F.join(' | ')):'\nRECIPE SHEETS: ALL PASS');

// ═══ THE BUTTON NEXT TO A DISH ═══
(function(){
 let G=[];const ck2=(n,c,d='')=>{c?console.log('  PASS  '+n):(console.log('  FAIL  '+n+'  '+d),G.push(n))};
 SESSION={username:'owner',role:'owner'};WHO='owner';SETUP_DISMISSED=true;DATA.firstRunDone=true;
 DATA.ingredients=[{code:'001',name:'Cashews',category:'Grocery',price:8,recipeUnit:'g-wt',
   ruPerPu:1000,purchaseUnit:'KG',yield:1}];
 DATA.menu=[{id:'D1',name:'Bowl of Nuts',group:'To Share',menuPrice:3.5,weeklySales:12,
   dept:'kitchen',lines:[]},
  {id:'D2',name:'Cashew Bowl',group:'To Share',menuPrice:4,weeklySales:8,dept:'kitchen',
   lines:[{ref:'001_Cashews',qty:60}]}];
 DATA.rates={vat:0.10,service:0.10,levy:0};
 rebuildIX();rebuildBX();

 let printed='';
 global.window.open=()=>({document:{write:s=>{printed+=s},close(){}}});

 // AN UNCOSTED DISH — the case that printed "Food cost 0.0%"
 printed=''; printCard('m',0);
 ck2('an uncosted dish prints the FILL-IN sheet, not an empty card',
     /Ingredient code/.test(printed), printed.slice(0,80));
 ck2('...never claiming a 0% food cost', !/0\.0%/.test(printed));
 ck2('...never showing a total cost of zero', !/0\.000/.test(printed));
 ck2('...with the form id so it can be scanned back', /RS-/.test(printed));
 ck2('...and one box per digit', /class="d"/.test(printed));

 // A COSTED DISH — a proper reference card
 printed=''; printCard('m',1);
 ck2('a costed dish prints a card with its quantities', /60/.test(printed));
 ck2('...showing the ingredient code', /001/.test(printed));
 ck2('...and the real cost', /0\.480/.test(printed), (printed.match(/0\.\d{3}/g)||[]).join());
 ck2('...with a food cost that is not zero', /Food cost/.test(printed)&&!/>0\.0%</.test(printed));
 ck2('...stated as net of tax and service', /net of tax and service/.test(printed));
 ck2('...and it carries the form id too', /RS-/.test(printed));
 ck2('...telling the chef corrections can be photographed', /photograph the page/.test(printed));
 ck2('no NaN on either', !/NaN/.test(printed));

 // A dish with a recipe but no price must not invent a food cost
 DATA.menu[1].menuPrice=0; printed=''; printCard('m',1);
 ck2('a dish with no menu price shows no food cost', !/Food cost/.test(printed));
 ck2('...and says why in the footer', /no menu price/.test(printed));

 // Batch recipes
 DATA.batch=[{id:'B1',code:'B1',name:'Empty Batch',lines:[],yieldQty:0}];
 rebuildBX(); global.__alerts=[];
 printed=''; printCard('b',0);
 ck2('an empty batch says so rather than printing a blank page',
     /nothing to print/.test((__alerts||[]).join()));
 ck2('...and prints nothing', printed==='');
 console.log(G.length?('\n'+G.length+' CARD FAILED: '+G.join(' | ')):'RECIPE CARD: ALL PASS');
})();
