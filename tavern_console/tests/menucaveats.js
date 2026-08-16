let FC=[];const ck=(n,c,d='')=>{c?console.log('  PASS  '+n):(console.log('  FAIL  '+n+'  '+d),FC.push(n))};
SESSION={username:'owner',role:'owner'};WHO='owner';SETUP_DISMISSED=true;DATA.firstRunDone=true;
const src=require('fs').readFileSync(process.env.TC,'utf-8');

// ═══ THE PROMPT ASKS FOR THE CAVEATS ═══
ck('the prompt asks for portion size', /"portion":string/.test(src)&&/200g patty/.test(src));
ck('...and what the price includes', /"includes":string/.test(src)&&/with fries/.test(src));
ck('...and a per-item date', /asOf on the ITEM/.test(src));
ck('...forbidding invented portions', /Never invent a portion size/.test(src));

// ═══ CAVEATS SURVIVE INTO STORAGE ═══
DATA.market=[];
addMarketSet('Cafe A','Adliya',[{name:'Beef Burger',price:6,currency:'BHD',category:'Mains',
  portion:'200g patty',includes:'with fries',asOf:'2026-06'}]);
const it=DATA.market[0].items[0];
ck('the portion is stored', it.portion==='200g patty');
ck('the inclusions are stored', it.includes==='with fries');
ck('the item date is stored', it.asOf==='2026-06');
ck('...all length-capped', addMarketSet('X','',[{name:'Y',price:1,portion:'z'.repeat(200)}])||
   DATA.market[DATA.market.length-1].items[0].portion.length<=50);

// ═══ INTO THE COMPARISON ═══
DATA.menu=[{id:'m',name:'Beef Burger',menuPrice:5,weeklySales:9,dept:'kitchen',lines:[]}];
DATA.market=[];
addMarketSet('Cafe A','Adliya',[{name:'Beef Burger',price:6,portion:'200g patty',includes:'with fries',asOf:'2026-06'}]);
addMarketSet('Cafe B','Adliya',[{name:'Beef Burger',price:7,portion:'',includes:'',asOf:''}]);
const C=marketCompare();
const row=C.rows.find(r=>/Beef Burger/i.test(r.dish));
ck('a dish is comparable', !!row);
ck('...carrying each match portion', row.matches.some(m=>m.portion==='200g patty'));
ck('...counting how many portions are known', row.portionsKnown===1, String(row.portionsKnown));

// ═══ THE UI ═══ — caveats live in the per-dish expand now
view='market';STAGE=null;INVBATCH=null;RESEARCH=null;MKT_OPEN=null;render();
let h=__store['app'].innerHTML;
ck('the table warns a cheaper one may be smaller', /may simply be smaller/.test(h));
const bid=marketCompare().rows.find(r=>/Beef Burger/i.test(r.dish)).dishId;
MKT_OPEN=bid; render(); h=__store['app'].innerHTML;
ck('the expanded detail shows the portion', /200g patty/.test(h));
ck('...and the inclusions', /with fries/.test(h));
ck('no NaN', !/NaN/.test(h));

RESEARCH={busy:false,kind:'menus',accept:{0:true},sources:[],searches:1,fetches:0,fetched:[],fetchFails:[],
  result:[{venue:'Cafe C',area:'Adliya',source:'https://c.bh',
    items:[{name:'Wings',price:4,portion:'6 pieces',includes:'sauce extra',asOf:'2026-07'}]}]};
render();
const h2=__store['app'].innerHTML;
ck('the review shows the portion before accepting', /6 pieces/.test(h2));
ck('...the inclusions', /sauce extra/.test(h2));
ck('...and the date', /2026-07/.test(h2));
console.log(FC.length?('\n'+FC.length+' FAILED: '+FC.join(' | ')):'\nMENU CAVEATS: ALL PASS');

// ═══ SINGLE-DISH COMPARISON ═══
(function(){
 let G=[];const ck2=(n,c,d='')=>{c?console.log('  PASS  '+n):(console.log('  FAIL  '+n+'  '+d),G.push(n))};
 SESSION={username:'owner',role:'owner'};WHO='owner';SETUP_DISMISSED=true;DATA.firstRunDone=true;
 DATA.menu=[{id:'D1',name:'Beef Burger',menuPrice:6,weeklySales:9,dept:'kitchen',lines:[]},
            {id:'D2',name:'Wings',menuPrice:4,weeklySales:5,dept:'kitchen',lines:[]}];
 DATA.market=[];
 addMarketSet('Cafe A','Adliya',[{name:'Beef Burger',price:7,portion:'200g',includes:'with fries',asOf:'2026-06'},
                                 {name:'Wings',price:5,portion:'6 pieces'}]);
 addMarketSet('Cafe B','Adliya',[{name:'Beef Burger',price:5}]);
 rebuildIX();rebuildBX();

 // rows now carry the dish id for deep-dive
 const C=marketCompare();
 const burger=C.rows.find(r=>/Burger/.test(r.dish));
 ck2('a comparison row carries the dish id', burger.dishId==='D1', burger.dishId);

 // the band bar renders and pins your price
 const bar=bandBar(burger);
 ck2('the band bar shows where you sit', /you 6\.000/.test(bar));
 ck2('...with the delta vs median', /vs median/.test(bar));
 ck2('...the cheapest and dearest', /cheapest/.test(bar)&&/dearest/.test(bar));
 ck2('no NaN in the band', !/NaN/.test(bar));

 // a single-match dish's band does not pretend to be a market
 addMarketSet('Cafe C','Adliya',[{name:'Solo Dish',price:3}]);
 DATA.menu.push({id:'D3',name:'Solo Dish',menuPrice:3.5,weeklySales:1,dept:'kitchen',lines:[]});
 const solo=marketCompare().rows.find(r=>/Solo/.test(r.dish));
 ck2('a single match is shown', !!solo);
 ck2('...and its band says "one price", not a spread', /the one price seen/.test(bandBar(solo)));

 // expanding a dish shows the full per-competitor detail
 MKT_OPEN='D1'; view='market'; STAGE=null; INVBATCH=null; RESEARCH=null; render();
 const h=__store['app'].innerHTML;
 ck2('clicking a dish expands its detail', /against 2 competitor item/.test(h));
 ck2('...listing each competitor with its portion', /200g/.test(h));
 ck2('...and inclusions', /with fries/.test(h));
 ck2('...and the source venue', /Cafe A/.test(h)&&/Cafe B/.test(h));
 ck2('...with a not-stated marker where a portion is missing', /not stated/.test(h));
 ck2('the band bar is in the detail', /you 6\.000/.test(h));
 ck2('no NaN', !/NaN/.test(h));
 mktToggle('D1');
 ck2('clicking again collapses it', MKT_OPEN===null);

 // the menu item has a Compare button that jumps here
 openM=0; view='menu'; render();
 ck2('the menu item has a Compare button', /compareDish\('D1'\)/.test(__store['app'].innerHTML));
 compareDish('D1');
 ck2('...which opens the comparison with that dish expanded', view==='market'&&MKT_OPEN==='D1');
 console.log(G.length?('\n'+G.length+' DISH COMPARE FAILED: '+G.join(' | ')):'SINGLE-DISH COMPARE: ALL PASS');
})();
