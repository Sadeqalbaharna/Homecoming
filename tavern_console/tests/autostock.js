let F=[];const ck=(n,c,d='')=>{c?console.log('  PASS  '+n):(console.log('  FAIL  '+n+'  '+d),F.push(n))};
SESSION={username:'owner',role:'owner'};WHO='owner';DATA.firstRunDone=true;

// One-tap "Add to inventory" from a scan: clean lines flow straight in, the
// ambiguous (no pack size) line stays behind in the recovery panel.
DATA.ingredients=[]; DATA.menu=[];
STAGE={kind:'purchases',headers:['Supplier','Item','Qty','Unit','Total'],
  rows:[['Gulf Foods','OLIVE OIL 5L',1,18,18],
        ['Gulf Foods','FLOUR 25KG',1,12,12],
        ['Gulf Foods','MISC KITCHEN',1,9,9]],   // no pack size — must wait
  map:{supplier:0,item:1,qty:2,unit:3,total:4},headerRow:-1};

const before=DATA.ingredients.length;
stockFromScan();

ck('two clean lines flow straight to inventory', DATA.ingredients.length===before+2,
   'now '+DATA.ingredients.length);
ck('...the proposal records what was applied', !!(CATPROP&&CATPROP.applied&&CATPROP.applied.added===2),
   JSON.stringify(CATPROP&&CATPROP.applied));
ck('the no-pack line is NOT added — it waits in recovery',
   CATPROP.skipped.some(s=>/MISC/.test(s.desc||'')));
ck('...and is absent from inventory', !DATA.ingredients.some(i=>/misc/i.test(i.name)));
ck('the flow lands on the catalogue view', view==='catalogue');

// Rescue then re-stock: give the held line a pack size and it comes in too.
STAGE.fix={2:{pack:'1 ea'}};
stockFromScan();
ck('rescued line is added on the next pass', DATA.ingredients.some(i=>/misc/i.test(i.name)));

// Idempotent: re-running does not duplicate the clean ingredients.
const n=DATA.ingredients.length;
stockFromScan();
ck('re-stocking the same scan never duplicates', DATA.ingredients.length===n,
   'was '+n+' now '+DATA.ingredients.length);
