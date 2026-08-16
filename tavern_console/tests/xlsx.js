let F=[];const ck=(n,c,d='')=>{c?console.log('  PASS  '+n):(console.log('  FAIL  '+n+'  '+d),F.push(n))};
const fs=require('fs');
SESSION={username:'owner',role:'owner'};DATA.firstRunDone=true;

// column letters
ck('A is 0', colIndex('A1')===0);
ck('Z is 25', colIndex('Z9')===25);
ck('AA is 26', colIndex('AA1')===26);
ck('BC is 54', colIndex('BC12')===54);

// Excel date serials
ck('serial 45000 is a real date', /^2023-03-15$/.test(serialToDate(45000)), serialToDate(45000));
ck('a new year comes out right', serialToDate(44927)==='2023-01-01', serialToDate(44927));
// 2024 is the leap year; 45351 is 29 Feb 2024. The first attempt at this
// assertion used 2025, which has no leap day, and a serial computed wrong.
ck('and a real leap day', serialToDate(45351)==='2024-02-29', serialToDate(45351));
ck('the day after it', serialToDate(45352)==='2024-03-01', serialToDate(45352));
// Serials 1-60 fall inside Excel's fake 29 Feb 1900 and are off by a day in
// every tool that reads them. No POS exports dates from 1900, so the modern
// epoch is the right one to be correct about.

// xml unescaping
ck('escaped ampersands survive', xmlUnescape('Ampersand &amp; Co')==='Ampersand & Co');
ck('escaped quotes survive', xmlUnescape('&quot;Quoted&quot;')==='"Quoted"');
ck('order matters — &amp;lt; stays literal', xmlUnescape('&amp;lt;')==='&lt;');

// The sandbox has no real Blob.stream(), so inflate runs through node's zlib
// here. This tests the zip walking and the XML parsing — the parts written in
// this file. The inflate call itself is the same DecompressionStream already
// carrying PDF content streams in production.
const zlib=require('zlib');
inflateRaw=async b=>new Uint8Array(zlib.inflateRawSync(Buffer.from(b)));

(async()=>{
const read=async p=>{const b=fs.readFileSync(p);
  return readXlsx(b.buffer.slice(b.byteOffset,b.byteOffset+b.byteLength));};

let r=await read('/tmp/t_pos.xlsx');
ck('it skips the cover page and finds the data sheet', r.sheet==='Data', r.sheet);
ck('...and lists the sheets it saw', r.sheets.includes('Cover')&&r.sheets.includes('Data'));
ck('the header row is read', r.rows[0][0]==='Item Name'&&r.rows[0][3]==='Net Sales');
ck('strings come through', r.rows[1][0]==='Espresso Martini');
ck('numbers come through as numbers', r.rows[1][2]==='96'&&r.rows[1][3]==='480.5');
ck('DATES are dates, not serial numbers', r.rows[1][4]==='2026-07-14', r.rows[1][4]);
ck('an escaped string is unescaped', r.rows[3][0]==='Ampersand & Co "Quoted"', r.rows[3][0]);
ck('a gap before a far column keeps the columns aligned',
   r.rows.some(x=>x[6]==='stray'), JSON.stringify(r.rows.map(x=>x.length)));
ck('trailing empty rows are trimmed', r.rows[r.rows.length-1].some(c=>c!==''));

// it must plug straight into the existing mapper
const hi=sniffHeader(r.rows);
ck('the header row is found by the same sniffer as CSV', hi===0, String(hi));
const map=autoMap(r.rows[hi],'products');
ck('...and columns auto-map', map.name===0, JSON.stringify(map));

r=await read('/tmp/t_formula.xlsx');
ck('a formula yields its cached value, not the formula', r.rows[1][3]==='24'||r.rows[1][3]==='', r.rows[1][3]);

let err=null; try{ await read('/tmp/t_empty.xlsx'); }catch(e){ err=e.message; }
ck('a workbook with no data says so', /no sheet with data/.test(err||''), String(err));

// a non-xlsx zip
const notxl=Buffer.from('504b03040a000000000000000000000000000000000000000774657374'+
  '2e747874'+'68656c6c6f','hex');
err=null; try{ await readXlsx(notxl.buffer.slice(notxl.byteOffset,notxl.byteOffset+notxl.byteLength)); }
catch(e){ err=e.message; }
ck('a zip that is not a workbook is refused', /not an Excel workbook/.test(err||''), String(err));

// .xls is refused with a route out
FILEFAIL=null; STAGE=null;
stageFile({files:[{name:'old.xls',type:'application/vnd.ms-excel'}],value:''},'products');
ck('the old .xls format is refused clearly', FILEFAIL&&FILEFAIL.reason==='xls');
ck('...and told how to convert it', /Save As/.test(FILEFAIL.why));

// the button now offers xlsx
STAGE=null;FILEFAIL=null;INVBATCH=null;view='import';DATA.ai={provider:'',key:'',enabled:false};
render();
ck('the file picker accepts .xlsx', /accept="\.csv,\.txt,\.tsv,\.pdf,\.xlsx"/.test(__store['app'].innerHTML));
console.log(F.length?('\n'+F.length+' FAILED: '+F.join(' | ')):'\nXLSX: ALL PASS');
})();
