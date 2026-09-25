import React, { useEffect, useMemo, useState } from 'react'
import { api } from './api.js'
import { translations } from './i18n.js'

const NAV = [['dashboard','◫'],['scanner','⌕'],['approvals','✓'],['policies','⚙'],['audit','≡'],['integration','⇄']]

function Badge({value,t}) {
  const tone = ['allow','approved'].includes(value) ? 'ok' : ['block','rejected','critical','high'].includes(value) ? 'danger' : ['approval','pending','medium'].includes(value) ? 'warn' : 'neutral'
  return <span className={'badge '+tone}>{t[value] || value}</span>
}

function Auth({lang,setLang,onAuth}) {
  const t=translations[lang], [mode,setMode]=useState('login'), [form,setForm]=useState({name:'',email:'',password:''}), [error,setError]=useState('')
  async function submit(e){e.preventDefault();setError('');try{const path='/api/auth/'+(mode==='login'?'login':'signup');const body=mode==='login'?{email:form.email,password:form.password}:{...form,language:lang};const d=await api(path,{method:'POST',body});onAuth(d.access_token,d.user)}catch(e){setError(e.message)}}
  return <div className="auth-shell"><button className="lang floating" onClick={()=>setLang(lang==='en'?'ar':'en')}>{t.language}</button><div className="auth-card"><div className="brand-mark">AG</div><h1>{t.appName}</h1><p>{t.tagline}</p><form onSubmit={submit}>{mode==='signup'&&<label>{t.name}<input required value={form.name} onChange={e=>setForm({...form,name:e.target.value})}/></label>}<label>{t.email}<input type="email" required value={form.email} onChange={e=>setForm({...form,email:e.target.value})}/></label><label>{t.password}<input type="password" minLength="8" required value={form.password} onChange={e=>setForm({...form,password:e.target.value})}/></label>{error&&<div className="alert danger-bg">{error}</div>}<button className="primary full">{mode==='login'?t.login:t.signup}</button></form><button className="link" onClick={()=>setMode(mode==='login'?'signup':'login')}>{mode==='login'?t.noAccount:t.haveAccount}</button></div></div>
}

function Dashboard({token,t}) {
  const [data,setData]=useState(null); const load=()=>api('/api/dashboard',{token}).then(setData); useEffect(()=>{load()},[])
  async function exportCsv(){const base=import.meta.env.VITE_API_URL||'http://127.0.0.1:8000';const r=await fetch(base+'/api/reports/security.csv',{headers:{Authorization:'Bearer '+token}});const b=await r.blob();const u=URL.createObjectURL(b),a=document.createElement('a');a.href=u;a.download='ai-agent-security-report.csv';a.click();URL.revokeObjectURL(u)}
  if(!data)return <div>{t.loading}</div>; const cards=[[t.totalScans,data.total_scans],[t.blocked,data.blocked],[t.allowed,data.allowed],[t.waiting,data.pending_approvals],[t.critical,data.critical]]
  return <><div className="page-head"><div><h2>{t.dashboard}</h2><p>{t.accountSecurity}</p></div><div className="actions"><button className="secondary" onClick={exportCsv}>{t.exportReport}</button><button className="secondary" onClick={load}>{t.refresh}</button></div></div><div className="stats">{cards.map(([k,v])=><div className="stat" key={k}><span>{k}</span><strong>{v}</strong></div>)}</div><section className="panel"><h3>{t.recentActivity}</h3><table><thead><tr><th>{t.source}</th><th>{t.decision}</th><th>{t.risk}</th><th>{t.threat}</th><th>{t.date}</th></tr></thead><tbody>{data.recent.map(x=><tr key={x.id}><td>{x.source_type}</td><td><Badge value={x.decision} t={t}/></td><td>{x.risk_score}/100</td><td><Badge value={x.threat_level} t={t}/></td><td>{new Date(x.created_at).toLocaleString()}</td></tr>)}</tbody></table></section></>
}

function Scanner({token,t,lang}) {
  const [form,setForm]=useState({source_type:'prompt',source_text:'',tool_name:''}),[result,setResult]=useState(null),[error,setError]=useState(''),[loading,setLoading]=useState(false)
  async function run(e){e.preventDefault();setLoading(true);setError('');try{setResult(await api('/api/scans',{method:'POST',token,body:form}))}catch(e){setError(e.message)}finally{setLoading(false)}}
  return <><div className="page-head"><div><h2>{t.scanTitle}</h2><p>{t.scanHelp}</p></div></div><div className="split"><form className="panel" onSubmit={run}><label>{t.sourceType}<select value={form.source_type} onChange={e=>setForm({...form,source_type:e.target.value})}><option value="prompt">{t.prompt}</option><option value="tool">{t.tool}</option><option value="content">{t.content}</option></select></label>{form.source_type==='tool'&&<label>{t.toolName}<input value={form.tool_name} onChange={e=>setForm({...form,tool_name:e.target.value})} placeholder="Bash / apply_patch / MCP tool"/></label>}<label>{t.text}<textarea rows="12" required value={form.source_text} onChange={e=>setForm({...form,source_text:e.target.value})} placeholder="Ignore previous instructions..."/></label>{error&&<div className="alert danger-bg">{error}</div>}<button className="primary">{loading?t.loading:t.analyze}</button></form><div className="panel result-panel">{result?<><div className="risk-ring" style={{'--risk':result.risk_score}}><strong>{result.risk_score}</strong><span>/100</span></div><div className="result-meta"><Badge value={result.decision} t={t}/><Badge value={result.threat_level} t={t}/></div><h3>{t.findings}</h3>{result.findings.length?result.findings.map((f,i)=><div className="finding" key={f.id+'-'+i}><div><b>{lang==='ar'?(f.title_ar||f.title):f.title}</b><small>{f.category+' · '+f.id}</small></div><Badge value={f.severity} t={t}/><p>{lang==='ar'?(f.recommendation_ar||f.recommendation):f.recommendation}</p></div>):<p>{t.noFindings}</p>}</>:<div className="empty">{t.findings}</div>}</div></div></>
}

function Approvals({token,t}) {
  const [data,setData]=useState([]); const load=()=>api('/api/approvals',{token}).then(setData); useEffect(()=>{load();const id=setInterval(load,4000);return()=>clearInterval(id)},[])
  async function act(id,a){await api('/api/approvals/'+id+'/'+a,{method:'POST',token});load()}
  return <><div className="page-head"><h2>{t.approvals}</h2><button className="secondary" onClick={load}>{t.refresh}</button></div><div className="cards-list">{data.length?data.map(a=><div className="panel approval-card" key={a.id}><div><Badge value={a.status} t={t}/><h3>#{a.id} · {a.scan?.tool_name||a.scan?.source_type}</h3><p>{t.risk}: {a.scan?.risk_score}/100</p></div>{a.status==='pending'&&<div className="actions"><button className="primary" onClick={()=>act(a.id,'approve')}>{t.approve}</button><button className="danger-btn" onClick={()=>act(a.id,'reject')}>{t.reject}</button></div>}</div>):<div className="panel empty">{t.noApprovals}</div>}</div></>
}

function Policies({token,t}) {
  const [p,setP]=useState(null),[msg,setMsg]=useState(''); useEffect(()=>{api('/api/policies',{token}).then(setP)},[]); if(!p)return <div>{t.loading}</div>
  const toggle=c=>setP({...p,enabled_categories:p.enabled_categories.includes(c)?p.enabled_categories.filter(x=>x!==c):[...p.enabled_categories,c]})
  async function save(){await api('/api/policies',{method:'PUT',token,body:{approval_threshold:Number(p.approval_threshold),block_threshold:Number(p.block_threshold),llm_enabled:p.llm_enabled,require_approval_for_sensitive_files:p.require_approval_for_sensitive_files,enabled_categories:p.enabled_categories}});setMsg('✓')}
  return <><div className="page-head"><h2>{t.policies}</h2></div><div className="panel settings"><label>{t.approvalThreshold}<input type="number" min="1" max="99" value={p.approval_threshold} onChange={e=>setP({...p,approval_threshold:e.target.value})}/></label><label>{t.blockThreshold}<input type="number" min="2" max="100" value={p.block_threshold} onChange={e=>setP({...p,block_threshold:e.target.value})}/></label><label className="toggle"><input type="checkbox" checked={p.llm_enabled} onChange={e=>setP({...p,llm_enabled:e.target.checked})}/>{t.llmEnabled}</label><label className="toggle"><input type="checkbox" checked={p.require_approval_for_sensitive_files} onChange={e=>setP({...p,require_approval_for_sensitive_files:e.target.checked})}/>{t.sensitiveApproval}</label><h3>{t.categories}</h3><div className="chips">{p.available_categories.map(c=><button type="button" className={p.enabled_categories.includes(c)?'chip active':'chip'} onClick={()=>toggle(c)} key={c}>{c}</button>)}</div><button className="primary" onClick={save}>{t.save} {msg}</button></div></>
}

function Audit({token,t}) {const [data,setData]=useState([]),[filter,setFilter]=useState('');const load=()=>api('/api/audit'+(filter?'?event_type='+encodeURIComponent(filter):''),{token}).then(setData);useEffect(()=>{load()},[filter]);const eventTypes=['','auth.signup','auth.login','scan.completed','policy.updated','approval.approved','approval.rejected','integration.token_regenerated','report.exported'];return <><div className="page-head"><h2>{t.audit}</h2><div className="actions"><select aria-label={t.filter} value={filter} onChange={e=>setFilter(e.target.value)}><option value="">{t.allEvents}</option>{eventTypes.filter(Boolean).map(x=><option value={x} key={x}>{x}</option>)}</select><button className="secondary" onClick={load}>{t.refresh}</button></div></div><section className="panel"><table><thead><tr><th>{t.event}</th><th>{t.details}</th><th>{t.date}</th></tr></thead><tbody>{data.map(x=><tr key={x.id}><td>{x.event_type}</td><td><code>{JSON.stringify(x.details)}</code></td><td>{new Date(x.created_at).toLocaleString()}</td></tr>)}</tbody></table></section></>}

function Integration({token,t}) {
  const [status,setStatus]=useState(null),[newToken,setNewToken]=useState(''); const load=()=>api('/api/integrations/status',{token}).then(setStatus);useEffect(()=>{load()},[])
  async function generate(){const d=await api('/api/integrations/token/regenerate',{method:'POST',token});setNewToken(d.token);load()}
  return <><div className="page-head"><div><h2>{t.integrationTitle}</h2><p>{t.integrationText}</p></div></div><div className="split"><div className="panel"><h3>Status</h3>{status&&<><p>{t.codexStatus}: <b>{status.codex_token_configured?t.yes:t.no}</b></p><p>{t.ollamaStatus}: <b>{status.ollama_enabled?t.yes:t.no}</b></p></>}<button className="primary" onClick={generate}>{t.generateToken}</button>{newToken&&<div className="token-box"><code>{newToken}</code><button onClick={()=>navigator.clipboard.writeText(newToken)}>{t.copy}</button><p>{t.tokenWarning}</p></div>}</div><div className="panel"><h3>{t.hookConfig}</h3><pre>{'AGENT_GUARD_URL=http://127.0.0.1:8000
AGENT_GUARD_TOKEN=ag_...

# Copy codex/hooks into .codex/hooks
# Register hooks.json in trusted Codex configuration'}</pre></div></div></>
}

export default function App(){
  const [lang,setLang]=useState(localStorage.getItem('lang')||'en'),[token,setToken]=useState(localStorage.getItem('token')||''),[user,setUser]=useState(null),[page,setPage]=useState('dashboard');const t=useMemo(()=>translations[lang],[lang])
  useEffect(()=>{document.documentElement.lang=lang;document.documentElement.dir=lang==='ar'?'rtl':'ltr';localStorage.setItem('lang',lang)},[lang]);useEffect(()=>{if(token)api('/api/auth/me',{token}).then(setUser).catch(()=>{localStorage.removeItem('token');setToken('')})},[token])
  const onAuth=(tok,u)=>{localStorage.setItem('token',tok);setToken(tok);setUser(u)}, logout=()=>{localStorage.removeItem('token');setToken('');setUser(null)}
  if(!token)return <Auth lang={lang} setLang={setLang} onAuth={onAuth}/>
  const pages={dashboard:<Dashboard token={token} t={t}/>,scanner:<Scanner token={token} t={t} lang={lang}/>,approvals:<Approvals token={token} t={t}/>,policies:<Policies token={token} t={t}/>,audit:<Audit token={token} t={t}/>,integration:<Integration token={token} t={t}/>}
  return <div className="app-shell"><aside><div className="brand"><div className="brand-mark small">AG</div><div><b>{t.appName}</b><small>{t.tagline}</small></div></div><nav>{NAV.map(([id,icon])=><button key={id} className={page===id?'active':''} onClick={()=>setPage(id)}><span>{icon}</span>{t[id]}</button>)}</nav><div className="aside-foot"><div className="user"><b>{user?.name}</b><small>{user?.email}</small></div><button className="secondary full" onClick={()=>setLang(lang==='en'?'ar':'en')}>{t.language}</button><button className="link full" onClick={logout}>{t.signOut}</button></div></aside><main>{pages[page]}</main></div>
}
