import {config} from './config.js';
let session=null;
export const configured=()=>!!(config.supabaseUrl&&config.supabaseKey);
export const getSession=()=>session;
export async function request(path,{method='GET',body,token=session?.access_token}={}){if(!configured())throw Error('Cloud connection has not been configured yet.');const r=await fetch(config.supabaseUrl+path,{method,headers:{apikey:config.supabaseKey,'Content-Type':'application/json',...(token?{Authorization:'Bearer '+token}:{})},body:body===undefined?undefined:JSON.stringify(body)});const data=await r.json().catch(()=>({}));if(!r.ok)throw Error(data.msg||data.message||data.error_description||data.error||'Cloud request failed.');return data;}
export async function signIn(email,password){session=await request('/auth/v1/token?grant_type=password',{method:'POST',body:{email,password},token:null});session.expires_at=Date.now()+session.expires_in*1000;sessionStorage.setItem('coinplan-session',JSON.stringify(session));return session;}
export async function restore(){try{session=JSON.parse(sessionStorage.getItem('coinplan-session'));if(session){await refresh();await request('/auth/v1/user');}return session;}catch{signOut();return null;}}
export async function refresh(){if(!session)throw Error('Sign in first.');if(Date.now()>=session.expires_at-60000){session=await request('/auth/v1/token?grant_type=refresh_token',{method:'POST',body:{refresh_token:session.refresh_token},token:null});session.expires_at=Date.now()+session.expires_in*1000;sessionStorage.setItem('coinplan-session',JSON.stringify(session));}}
export function signOut(){session=null;sessionStorage.removeItem('coinplan-session');}
export async function loadCloud(){await refresh();return request('/rest/v1/coinplan_state?select=payload,revision');}
export async function saveCloud(payload,revision){await refresh();return request('/rest/v1/rpc/coinplan_save_state',{method:'POST',body:{p_payload:payload,p_revision:revision}});}
export async function bank(action,body={}){await refresh();return request('/functions/v1/'+config.bankFunction,{method:'POST',body:{action,...body}});}
