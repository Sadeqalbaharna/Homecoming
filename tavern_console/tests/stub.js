const store={};
const mkEl=()=>({innerHTML:'',textContent:'',value:'',style:{},classList:{
  add(){},remove(){},toggle(){},contains(){return false}},
  appendChild(){},addEventListener(){},focus(){},click(){},setAttribute(){},
  querySelector:()=>mkEl(),querySelectorAll:()=>[]});
global.window={addEventListener(){},scrollTo(){},matchMedia:()=>({matches:false,addListener(){}})};
global.document={
  getElementById:id=>(store[id]=store[id]||mkEl()),
  querySelector:()=>mkEl(), querySelectorAll:()=>[],
  createElement:()=>mkEl(), addEventListener(){},
  body:{classList:{add(){},remove(){},toggle(){},contains(){return false}}},
  documentElement:mkEl()
};
const ls={};
global.localStorage={getItem:k=>k in ls?ls[k]:null,setItem:(k,v)=>{ls[k]=String(v)},
  removeItem:k=>{delete ls[k]}};
global.__alerts=[];
global.alert=m=>{global.__alerts=(global.__alerts||[]).concat(m)};
global.confirm=()=>true; global.prompt=()=>null;
global.crypto={subtle:{digest:async()=>new ArrayBuffer(32)}};
global.FileReader=function(){}; global.Blob=function(){}; global.URL={createObjectURL:()=>''};
global.__store=store;
