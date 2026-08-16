let FA=[];const ck=(n,c,d='')=>{c?console.log('  PASS  '+n):(console.log('  FAIL  '+n+'  '+d),FA.push(n))};
SESSION={username:'owner',role:'owner'};WHO='owner';DATA.firstRunDone=true;
DATA.ai={provider:'anthropic',key:'sk-test',enabled:true,calls:0,ledger:[],auth:[],limits:null};
DATA.venueInfo={city:'Adliya',region:'Capital',country:'bh',cuisine:'gastropub'};
DATA.menu=[{id:'m1',name:'Chicken Plate',menuPrice:6,weeklySales:50,dept:'kitchen',lines:[]}];
DATA.ingredients=[{id:'a',code:'001',name:'Chicken Breast',price:5,recipeUnit:'kg',ruPerPu:1,pu:'kg',yield:1,history:[]}];
DATA.market=[]; rebuildIX();rebuildBX();

(async()=>{
// ═══ THE LINE, ENFORCED IN THE REQUEST ═══
let sent=null;
const reply=(content,extra)=>({ok:true,status:200,json:async()=>Object.assign(
  {content,stop_reason:'end_turn',usage:{server_tool_use:{web_search_requests:2}}},extra||{})});
globalThis.fetch=async(u,o)=>{ sent=JSON.parse(o.body);
  return reply([{type:'web_search_tool_result',tool_use_id:'t',content:[
      {type:'web_search_result',url:'https://cafea.bh/menu',title:'Cafe A',page_age:'2026-06-01'}]},
    {type:'text',text:'Found some. {"venues":[{"venue":"Cafe A","area":"Adliya",'+
      '"source":"https://cafea.bh/menu","asOf":"2026-06-01","items":['+
      '{"name":"Chicken Plate","price":6.5,"currency":"BHD","category":"Mains"}]}]}',
     citations:[{url:'https://cafea.bh/menu',title:'Cafe A',cited_text:'Chicken Plate 6.500'}]}]);
};
await researchMenus();
ck('the request carries the web search tool', sent.tools&&sent.tools[0].name==='web_search');
ck('EVERY aggregator is blocked in the request itself',
   BLOCKED_SOURCES.every(d=>sent.tools[0].blocked_domains.includes(d)));
ck('...including Talabat and Jahez, which matter here',
   sent.tools[0].blocked_domains.includes('talabat.com')&&sent.tools[0].blocked_domains.includes('jahez.net'));
ck('allowed_domains is not also set — the API rejects both', !sent.tools[0].allowed_domains);
ck('search is localised to the venue', sent.tools[0].user_location.city==='Adliya');
ck('...with an uppercase ISO country code', sent.tools[0].user_location.country==='BH',
   sent.tools[0].user_location.country);
ck('...and a search cap', sent.tools[0].max_uses>0);
ck('the prompt names the dishes to compare', /Chicken Plate/.test(sent.messages[0].content));
// The two-stage prompt replaced the "empty answer is correct" line with
// stronger constraints, so assert those instead of the old wording.
ck('...and forbids estimating a price', /Never estimate a price/.test(sent.messages[0].content));
ck('...and forbids carrying one from another branch',
   /never carry a price over from another branch/.test(sent.messages[0].content));
ck('...and only counts prices actually seen',
   /Only list a dish if you saw a real price/.test(sent.messages[0].content));

// ═══ WHAT COMES BACK ═══
ck('venues are parsed', RESEARCH.result.length===1&&RESEARCH.result[0].venue==='Cafe A');
ck('the source url is kept', RESEARCH.result[0].source==='https://cafea.bh/menu');
ck('citations are collected', RESEARCH.sources.some(s=>s.url==='https://cafea.bh/menu'));
ck('searches are counted', RESEARCH.searches===2);
ck('nothing is written before you accept', DATA.market.length===0);
acceptResearch();
ck('accepting writes the set', DATA.market.length===1);
ck('...marked as researched, not uploaded', DATA.market[0].researched===true);
ck('...keeping the source', DATA.market[0].source==='https://cafea.bh/menu');
ck('...and the page date', DATA.market[0].asOf==='2026-06-01');
ck('...and it feeds the SAME comparability scoring', marketCompare().rows.length===1);

// ═══ THE GOVERNOR APPLIES ═══
DATA.ai.ledger=[]; DATA.ai.limits={perRun:1,perDay:1,lifetime:1000};
DATA.ai.ledger=[{at:Date.now()}];
let err=null; try{ await aiResearch('s','p',3); }catch(e){ err=e.message; }
ck('a spend halt stops research too', /Daily limit reached/.test(err||''), String(err));
DATA.ai.limits=null; DATA.ai.ledger=[];

// ═══ A PAUSED TURN MUST BE CONTINUED, NOT READ AS EMPTY ═══
let calls=0;
globalThis.fetch=async(u,o)=>{ calls++; sent=JSON.parse(o.body);
  if(calls===1) return reply([{type:'text',text:'searching…'}],{stop_reason:'pause_turn'});
  return reply([{type:'text',text:'{"venues":[]}'}]);
};
const r2=await aiResearch('s','p',3);
ck('a paused turn is continued', calls===2, String(calls));
ck('...by sending the assistant message back unchanged',
   sent.messages.length===2&&sent.messages[1].role==='assistant');
ck('...and the final answer is used', /venues/.test(r2.text));

// ═══ ERRORS SAY SOMETHING USEFUL ═══
globalThis.fetch=async()=>({ok:false,status:400,text:async()=>'web search is not enabled for this organization'});
err=null; try{ await aiResearch('s','p',3); }catch(e){ err=e.message; }
ck('a disabled-search account is explained, not just "400"', /Claude Console/.test(err||''), String(err));
globalThis.fetch=async()=>({ok:false,status:401,text:async()=>''});
err=null; try{ await aiResearch('s','p',3); }catch(e){ err=e.message; }
ck('a bad key says so', /key was rejected/.test(err||''));
globalThis.fetch=async()=>reply([{type:'web_search_tool_result',tool_use_id:'t',
  content:{type:'web_search_tool_result_error',error_code:'max_uses_exceeded'}}]);
err=null; try{ await aiResearch('s','p',3); }catch(e){ err=e.message; }
ck('a search error inside a 200 response is caught', /max_uses_exceeded/.test(err||''), String(err));

// ═══ OPENAI CANNOT DO THIS, AND SAYS SO ═══
DATA.ai.provider='openai';
err=null; try{ await aiResearch('s','p',3); }catch(e){ err=e.message; }
ck('the OpenAI path refuses rather than failing oddly', /Switch provider to Claude/.test(err||''));
DATA.ai.provider='anthropic';

// ═══ NO LOCATION, NO SEARCH ═══
DATA.venueInfo={}; DATA.market=[];
let alerted='';globalThis.alert=m=>alerted=m;
await researchMenus();
ck('it refuses to search with no location', /city and country/.test(alerted), alerted);

// ═══ UI ═══
DATA.venueInfo={city:'Adliya',country:'BH'}; RESEARCH=null; STAGE=null; INVBATCH=null;
view='market'; render(); const h=__store['app'].innerHTML;
ck('the search buttons exist', /researchMenus\(\)/.test(h)&&/researchSupplyPrices\(\)/.test(h));
ck('the location fields exist', /setVenueInfo\('city'/.test(h));
ck('it explains why a page cannot search by itself', /cannot read another website/.test(h));
ck('it says searches cost money', /paid call/.test(h));
ck('it states the aggregator exclusion on screen', /Aggregator sites are excluded/.test(h));
ck('no NaN', !/NaN/.test(h));
console.log(FA.length?('\n'+FA.length+' FAILED: '+FA.join(' | ')):'\nRESEARCH: ALL PASS');

// The search+fetch tests continue INSIDE this same async block, deliberately:
// two async IIFEs both assigning globalThis.fetch race each other, and the
// second stub replaced the first while it was still in flight. That produced
// seven failures in unrelated assertions that looked exactly like regressions.
// ═══ SEARCH + FETCH: FINDING THE MENU PDF ═══
{
 let G=[];const ck2=(n,c,d='')=>{c?console.log('  PASS  '+n):(console.log('  FAIL  '+n+'  '+d),G.push(n))};
 SESSION={username:'owner',role:'owner'};WHO='owner';DATA.firstRunDone=true;
 DATA.ai={provider:'anthropic',key:'k',enabled:true,calls:0,ledger:[],auth:[],limits:null};
 DATA.venueInfo={city:'Adliya',country:'BH'};
 DATA.menu=[{id:'m1',name:'Chicken Plate',menuPrice:6,weeklySales:9,dept:'kitchen',lines:[]}];
 DATA.market=[]; RESEARCH=null;
 let sent=null;
 globalThis.fetch=async(u,o)=>{ sent=JSON.parse(o.body); return {ok:true,status:200,json:async()=>({
   stop_reason:'end_turn',
   usage:{server_tool_use:{web_search_requests:3,web_fetch_requests:2}},
   content:[
     {type:'web_search_tool_result',tool_use_id:'s1',content:[
       {type:'web_search_result',url:'https://www.instagram.com/cafeb/',title:'Cafe B'}]},
     {type:'web_fetch_tool_result',tool_use_id:'f1',content:{type:'web_fetch_result',
       url:'https://cafea.bh/menu.pdf',retrieved_at:'2026-07-21T10:00:00Z',
       content:{type:'document',title:'Menu',source:{type:'base64',media_type:'application/pdf',data:'JVBER'}}}},
     {type:'web_fetch_tool_result',tool_use_id:'f2',content:{type:'web_fetch_tool_result_error',
       error_code:'url_not_accessible'}},
     {type:'text',text:'{"venues":['+
       '{"venue":"Cafe A","area":"Adliya","site":"https://cafea.bh","source":"https://cafea.bh/menu.pdf",'+
       '"asOf":"2026-07","menuFound":true,"items":[{"name":"Chicken Plate","price":6.5,"currency":"BHD"}]},'+
       '{"venue":"Cafe B","area":"Adliya","instagram":"https://www.instagram.com/cafeb/",'+
       '"menuFound":false,"whyNot":"menu only on Instagram as images","items":[]}]}'}]})};
 };
 await researchMenus();

 ck2('the fetch tool is sent alongside search',
     sent.tools.some(t=>t.name==='web_fetch'), (sent.tools||[]).map(t=>t.name).join());
 ck2('...with citations on', sent.tools.find(t=>t.name==='web_fetch').citations.enabled===true);
 ck2('...and aggregators blocked there too',
     sent.tools.find(t=>t.name==='web_fetch').blocked_domains.includes('talabat.com'));
 ck2('...and a content cap so one huge PDF cannot eat the budget',
     sent.tools.find(t=>t.name==='web_fetch').max_content_tokens>0);
 ck2('the prompt runs two stages', /STAGE 1/.test(sent.messages[0].content)&&/STAGE 2/.test(sent.messages[0].content));
 ck2('...using social as a directory, not a price source',
     /as a DIRECTORY/.test(sent.messages[0].content));
 ck2('...and says those pages cannot be read', /rendered with JavaScript/.test(sent.messages[0].content));
 ck2('...and asks for venues even with no prices',
     /INCLUDE A VENUE EVEN IF YOU COULD NOT GET ITS PRICES/.test(sent.messages[0].content));
 ck2('...and forbids carrying a price from another branch',
     /never carry a price over from another branch/.test(sent.messages[0].content));

 ck2('a PDF that was opened is recorded as a PDF',
     RESEARCH.fetched.some(f=>f.pdf&&/menu\.pdf$/.test(f.url)));
 ck2('a failed fetch is kept as information, not a crash',
     RESEARCH.fetchFails.length===1&&RESEARCH.fetchFails[0].code==='url_not_accessible');
 ck2('fetches are counted', RESEARCH.fetches===2);
 ck2('the priced venue is ticked by default', RESEARCH.accept[0]===true);
 ck2('the unpriced one is NOT ticked', RESEARCH.accept[1]===false);

 view='market'; STAGE=null; INVBATCH=null; render();
 const h=__store['app'].innerHTML;
 ck2('the header separates found from priced', /2 venue\(s\) · 1 with prices/.test(h));
 ck2('the PDF is marked as read', /PDF read/.test(h));
 ck2('the venue with no prices is still listed', /Cafe B/.test(h));
 ck2('...with the reason', /menu only on Instagram as images/.test(h));
 ck2('...and a link to go look', /instagram\.com\/cafeb/.test(h));
 ck2('...framed as a competitor list worth having', /competitor list/.test(h));
 ck2('failed fetches are reported', /could not be opened/.test(h));
 ck2('the screen states what cannot be read and why', /built in JavaScript/.test(h));
 ck2('no NaN', !/NaN/.test(h));

 acceptResearch();
 ck2('only the priced venue is written', DATA.market.length===1&&DATA.market[0].name==='Cafe A');
 ck2('JS-only hosts are recognisable to the code',
     isJsOnly('https://www.instagram.com/x')&&isJsOnly('https://google.com/maps/place/y')
     &&!isJsOnly('https://cafea.bh/menu.pdf'));
 console.log(G.length?('\n'+G.length+' FETCH FAILED: '+G.join(' | ')):'SEARCH+FETCH: ALL PASS');
}
})();
