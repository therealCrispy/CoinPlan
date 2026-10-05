const USER='11111111-1111-4111-8111-111111111111';
for(const [key,value] of Object.entries({SUPABASE_URL:'https://test.invalid',SUPABASE_SERVICE_ROLE_KEY:'test-service-only',SUPABASE_ANON_KEY:'test-public',PLAID_CLIENT_ID:'test-client',PLAID_SECRET:'test-plaid-secret',PLAID_ENV:'sandbox',COINPLAN_TOKEN_KEY:btoa(String.fromCharCode(...new Uint8Array(32).fill(1))),COINPLAN_ALLOWED_USER_IDS:USER,COINPLAN_CRON_SECRET:'test-cron-secret',COINPLAN_REDIRECT_URI:'https://example.test/CoinPlan/',COINPLAN_ORIGINS:'https://example.test'}))Deno.env.set(key,value);
const {handle}=await import('../supabase/functions/coinplan-bank/handler.ts');
function assert(value:unknown,message='Assertion failed'){if(!value)throw Error(message);}
const response=(value:unknown,status=200)=>new Response(JSON.stringify(value),{status,headers:{'Content-Type':'application/json'}});
function request(body:unknown,headers:Record<string,string>={Authorization:'Bearer test-user'}){return new Request('https://example.test/function',{method:'POST',headers:{'Content-Type':'application/json',Origin:'https://example.test',...headers},body:JSON.stringify(body)});}
Deno.test('bank API security and exchange/sync integration with mock services',async()=>{
 const original=globalThis.fetch;const calls:{url:string,body:any}[]=[];let authUser=USER,stored:any=null,commit:any=null;
 globalThis.fetch=(async(input:any,init:any={})=>{const url=String(input),body=init.body?JSON.parse(init.body):null;calls.push({url,body});
  if(url.endsWith('/auth/v1/user'))return response({id:authUser});
  if(url.includes('/rest/v1/')){assert(init.headers.Authorization==='Bearer test-service-only');if(url.includes('rpc/coinplan_bank_lease'))return response({...stored,cursor:''});if(url.includes('rpc/coinplan_bank_commit')){commit=body;return response(true);}if(url.includes('coinplan_bank_items')){if(init.method==='POST'){stored=body;return response([stored]);}if(url.includes('select=id,owner&owner'))return response(stored?[{id:stored.id,owner:stored.owner}]:[]);if(url.includes('select=id,owner'))return response([]);return response([]);}if(url.includes('coinplan_bank_accounts'))return response(commit?commit.p_accounts.map((payload:any)=>({payload})):[]);if(url.includes('coinplan_bank_transactions'))return response(commit?commit.p_transactions.map((payload:any)=>({payload})):[]);}
  if(url.includes('sandbox.plaid.com')){assert(body.secret==='test-plaid-secret');if(url.endsWith('/link/token/create'))return response({link_token:'temporary-link'});if(url.endsWith('/item/public_token/exchange'))return response({item_id:'item-test',access_token:'private-bank-token'});if(url.endsWith('/transactions/sync'))return response({added:[{transaction_id:'tx-test',account_id:'a-test',amount:5.25,name:'Coffee',date:'2026-10-04',pending:false,iso_currency_code:'USD',personal_finance_category:{primary:'FOOD_AND_DRINK'}}],modified:[],removed:[],has_more:false,next_cursor:'cursor-done'});if(url.endsWith('/accounts/get'))return response({accounts:[{account_id:'a-test',name:'Checking',type:'depository',balances:{current:100,iso_currency_code:'USD'}}]});}
  throw Error('Unexpected request: '+url);
 }) as typeof fetch;
 try{
  let r=await handle(new Request('https://example.test/function',{method:'POST',body:'{}'}));assert(r.status===401,'Anonymous requests must fail');assert(calls.length===0);
  r=await handle(request({action:'link'},{Origin:'https://evil.test'}));assert(r.status===403);assert(calls.length===0);
  authUser='another-user';r=await handle(request({action:'link'}));assert(r.status===403,'Unapproved user must fail');assert(!calls.some(c=>c.url.includes('plaid.com')));
  authUser=USER;r=await handle(request({action:'scheduled'},{'x-coinplan-cron':'wrong'}));assert(r.status===401);
  r=await handle(request({action:'link'}));assert((await r.json()).link_token==='temporary-link');
  r=await handle(request({action:'exchange',public_token:'public-test',institution:'Test bank'}));assert(r.status===200);assert(stored.owner===USER);assert(!stored.token.includes('private-bank-token'),'Access token must be encrypted');
  r=await handle(request({action:'sync'}));assert(r.status===200);const body=await r.json();assert(body.accounts.length===1&&body.transactions.length===1);assert(body.transactions[0].amount===525);assert(commit.p_cursor==='cursor-done');assert(commit.p_owner===USER);assert(!JSON.stringify(body).includes('private-bank-token'));assert(!JSON.stringify(body).includes('test-service-only'));assert(calls.filter(c=>c.url.includes('coinplan_bank_transactions?')).every(c=>c.url.includes('owner=eq.'+USER)));
 }finally{globalThis.fetch=original;}
});
