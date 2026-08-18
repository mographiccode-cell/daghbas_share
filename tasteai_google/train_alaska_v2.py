import gzip,json,math,re
from pathlib import Path
from collections import Counter
import numpy as np, pandas as pd
from sklearn.preprocessing import StandardScaler
from sklearn.linear_model import Ridge,LogisticRegression
from sklearn.metrics import ndcg_score,mean_squared_error,mean_absolute_error
try:
    from lightgbm import LGBMRanker
    HAVE_LGB=True
except Exception:
    HAVE_LGB=False
DATA=Path('google_alaska'); OUT=Path('alaska_v2_out'); OUT.mkdir(exist_ok=True)
def readgz(path):
    with gzip.open(path,'rt',encoding='utf-8') as f:
        for l in f:
            try: yield json.loads(l)
            except: pass
def norm(s): return ' '.join(re.sub(r'[^a-z0-9 ]+',' ',str(s).lower()).split())
TOK=['restaurant','cafe','coffee shop','bakery','bistro','diner','pizza','pizzeria','barbecue','bbq','grill','steakhouse','sushi','ramen','noodle','burger','sandwich','breakfast','brunch','seafood','dessert','ice cream','tea house','taco','brewery','pub','food court','fast food','chicken','mexican','italian','chinese','japanese','thai','indian','mediterranean','middle eastern','vietnamese','korean','american restaurant','asian restaurant']
STOP={'restaurant','restaurants','shop','food','takeout','delivery','store','service','services','and','the','cafe','bar','grill'}
def terms(cats):
    z=set(cats)
    for c in cats:
        for w in c.split():
            if len(w)>=3 and w not in STOP: z.add(w)
    return z
meta={}
for x in readgz(DATA/'meta-Alaska.json.gz'):
    cats=[norm(c) for c in (x.get('category') or [])]
    if any(any(t in c for t in TOK) for c in cats):
        price=x.get('price'); p=float(len(price)) if isinstance(price,str) and price.startswith('$') else np.nan
        meta[str(x.get('gmap_id'))]={'cats':cats,'terms':terms(cats),'price':p,'lat':x.get('latitude'),'lon':x.get('longitude')}
rows=[]
for x in readgz(DATA/'review-Alaska_10.json.gz'):
    iid=str(x.get('gmap_id'))
    if iid not in meta: continue
    try: rr=float(x['rating'])
    except: continue
    rows.append((str(x['user_id']),iid,rr,int(x.get('time') or 0)))
df=pd.DataFrame(rows,columns=['user','item','rating','time']).drop_duplicates(['user','item'],keep='last')
def kcore(d,k=5):
    d=d.copy()
    while True:
        n=len(d); uc=d.user.value_counts(); ic=d.item.value_counts(); d=d[d.user.isin(uc[uc>=k].index)&d.item.isin(ic[ic>=k].index)]
        if len(d)==n:return d.reset_index(drop=True)
df=kcore(df,5);uc=df.user.value_counts();df=df[df.user.isin(uc[uc>=6].index)];df=kcore(df,5);uc=df.user.value_counts();df=df[df.user.isin(uc[uc>=6].index)].reset_index(drop=True)
trL=[];vaL=[];teL=[]
for u,g in df.sort_values('time').groupby('user'):
    g=g.sort_values('time')
    if len(g)>=6:trL.append(g.iloc[:-3]);vaL.append(g.iloc[-3:-2]);teL.append(g.iloc[-2:])
tr=pd.concat(trL).reset_index(drop=True);va=pd.concat(vaL).reset_index(drop=True);te=pd.concat(teL).reset_index(drop=True);GM=float(tr.rating.mean())
item_agg=tr.groupby('item').rating.agg(['sum','count','mean','std']).fillna(0);user_agg=tr.groupby('user').rating.agg(['sum','count','mean']).fillna(0);u_pos=tr.assign(pos=(tr.rating>=4).astype(int)).groupby('user').pos.agg(['sum','count'])
u_profile={}
for u,g in tr.groupby('user'):
    tc=Counter();ps=[];coords=[]
    for row in g.itertuples(index=False):
        m=meta[row.item]
        if row.rating>=4:
            w=max(.2,row.rating-2.5)
            for t in m['terms']:tc[t]+=w
            if not np.isnan(m['price']):ps.append(m['price'])
            try:
                la=float(m['lat']);lo=float(m['lon'])
                if math.isfinite(la) and math.isfinite(lo):coords.append((la,lo))
            except:pass
    u_profile[u]={'terms':tc,'price_sum':sum(ps),'price_n':len(ps),'lat_sum':sum(x for x,_ in coords),'lon_sum':sum(y for _,y in coords),'coord_n':len(coords)}
def hav(a,b,c,d):
    try:a,b,c,d=map(float,[a,b,c,d])
    except:return np.nan
    if not all(map(math.isfinite,[a,b,c,d])):return np.nan
    p1,p2=math.radians(a),math.radians(c);dp=math.radians(c-a);dl=math.radians(d-b);z=math.sin(dp/2)**2+math.cos(p1)*math.cos(p2)*math.sin(dl/2)**2
    return 6371.0088*2*math.asin(math.sqrt(min(1,z)))
FEATURES=['item_mean','log_item_count','item_std','bayes_item_mean','user_mean','log_user_count','user_positive_rate','price','price_known','user_price_pref','price_match','category_match','distance_log1p','distance_known','category_count','item_user_gap']
def build(d,loo=False):
    X=[]
    for row in d.itertuples(index=False):
        ia=item_agg.loc[row.item] if row.item in item_agg.index else None;ua=user_agg.loc[row.user] if row.user in user_agg.index else None
        if ia is None:isum=0.;ic=0;im=GM;istd=0.
        else:
            isum=float(ia['sum']);ic=int(ia['count']);istd=float(ia['std'] or 0)
            if loo:ic2=ic-1;im=(isum-row.rating)/ic2 if ic2>0 else GM;ic=ic2
            else:im=float(ia['mean'])
        if ua is None:usum=0.;uc=0;um=GM
        else:
            usum=float(ua['sum']);uc=int(ua['count'])
            if loo:uc2=uc-1;um=(usum-row.rating)/uc2 if uc2>0 else GM;uc=uc2
            else:um=float(ua['mean'])
        if loo:pos_sum=int(u_pos.loc[row.user,'sum'])-int(row.rating>=4);pos_n=max(1,int(u_pos.loc[row.user,'count'])-1)
        else:pos_sum=int(u_pos.loc[row.user,'sum']);pos_n=max(1,int(u_pos.loc[row.user,'count']))
        upr=u_profile.get(row.user,{'terms':Counter(),'price_sum':0,'price_n':0,'lat_sum':0,'lon_sum':0,'coord_n':0});tc=upr['terms'].copy();ps=upr['price_sum'];pn=upr['price_n'];las=upr['lat_sum'];los=upr['lon_sum'];cn=upr['coord_n'];m=meta[row.item]
        if loo and row.rating>=4:
            w=max(.2,row.rating-2.5)
            for t in m['terms']:
                tc[t]-=w
                if tc[t]<=1e-9:del tc[t]
            if not np.isnan(m['price']):ps-=m['price'];pn=max(0,pn-1)
            try:
                la=float(m['lat']);lo=float(m['lon'])
                if math.isfinite(la) and math.isfinite(lo):las-=la;los-=lo;cn=max(0,cn-1)
            except:pass
        total=sum(tc.values()) or 1.;cm=max([tc.get(t,0.)/total for t in m['terms']] or [0.]);up=ps/pn if pn else 2.;p=m['price'];pk=float(not np.isnan(p));pv=float(p) if pk else 2.;pm=max(0.,1-abs(pv-up)/3) if pk else .5;ula=las/cn if cn else np.nan;ulo=los/cn if cn else np.nan;dist=hav(ula,ulo,m['lat'],m['lon']);dk=float(not np.isnan(dist));dlog=math.log1p(dist) if dk else math.log1p(25.);bay=(ic*im+15*GM)/(ic+15)
        X.append([im,math.log1p(ic),istd,bay,um,math.log1p(uc),pos_sum/pos_n,pv,pk,up,pm,cm,dlog,dk,len(m['cats']),im-um])
    return np.asarray(X,float)
Xtr=build(tr,True);Xv=build(va,False);Xte=build(te,False);ytr=tr.rating.to_numpy(float);yv=va.rating.to_numpy(float);yte=te.rating.to_numpy(float);sc=StandardScaler().fit(Xtr);A=sc.transform(Xtr);Av=sc.transform(Xv);At=sc.transform(Xte)
ridge=Ridge(alpha=20).fit(A,ytr);resid_ridge=Ridge(alpha=50).fit(A[:,4:],ytr-Xtr[:,0]);pairs=[];labs=[];rng=np.random.default_rng(42)
for u,idx in tr.groupby('user').groups.items():
    ids=np.array(list(idx));ids=rng.choice(ids,14,replace=False) if len(ids)>14 else ids
    for ii in range(len(ids)):
        for jj in range(ii+1,len(ids)):
            a,b=ids[ii],ids[jj]
            if ytr[a]==ytr[b]:continue
            d=A[a]-A[b];lab=int(ytr[a]>ytr[b]);pairs.extend([d,-d]);labs.extend([lab,1-lab])
P=np.asarray(pairs,float);L=np.asarray(labs,int)
if len(P)>300000:sel=rng.choice(len(P),300000,replace=False);P=P[sel];L=L[sel]
pair=LogisticRegression(max_iter=1500,C=.2).fit(P,L);pair_w=pair.coef_[0];lgb=None
if HAVE_LGB:
    order=np.argsort(tr.user.to_numpy());Xs=Xtr[order];ys=(ytr[order]-1).astype(int);us=tr.user.to_numpy()[order];group=pd.Series(us).groupby(us,sort=False).size().to_numpy();lgb=LGBMRanker(objective='lambdarank',metric='ndcg',n_estimators=250,learning_rate=.03,num_leaves=15,max_depth=5,min_child_samples=40,reg_lambda=5,verbosity=-1,random_state=42,label_gain=[0,1,3,7,15]);lgb.fit(Xs,ys,group=group)
def rankmet(frame,scores):
    tmp=frame[['user','rating']].copy();tmp['s']=scores;nd=[];best=[];pa=[];ties=0
    for _,g in tmp.groupby('user'):
        y=g.rating.to_numpy(float);s=g.s.to_numpy(float)
        if y.max()==y.min():ties+=1;continue
        nd.append(ndcg_score([y],[s],k=2));best.append(float(y[np.argmax(s)]==y.max()));pa.append(float((s[0]-s[1])*(y[0]-y[1])>0))
    return {'ndcg':float(np.mean(nd)),'best':float(np.mean(best)),'pair':float(np.mean(pa)),'nontie':len(nd),'ties':ties}
def ratingmet(y,s):return {'rmse':float(mean_squared_error(y,s)**.5),'mae':float(mean_absolute_error(y,s)),'within1':float(np.mean(np.abs(y-np.clip(np.rint(s),1,5))<=1))}
V={'baseline':Xv[:,0],'ridge':ridge.predict(Av),'residual':Xv[:,0]+resid_ridge.predict(Av[:,4:]),'pairwise':Av@pair_w};T={'baseline':Xte[:,0],'ridge':ridge.predict(At),'residual':Xte[:,0]+resid_ridge.predict(At[:,4:]),'pairwise':At@pair_w}
if lgb is not None:V['lambdarank']=lgb.predict(Xv);T['lambdarank']=lgb.predict(Xte)
for name in list(V):
    if name=='baseline':continue
    best_tuple=None
    for alpha in np.linspace(0,1.5,31):
        q=V[name]
        if name in ('pairwise','lambdarank'):q=(q-q.mean())/(q.std()+1e-8)*Xv[:,0].std()+Xv[:,0].mean()
        blend=(1-alpha)*Xv[:,0]+alpha*q;m=rankmet(va,blend);key=(m['best'],m['ndcg'])
        if best_tuple is None or key>best_tuple[0]:best_tuple=(key,float(alpha),m)
    alpha=best_tuple[1];q=T[name]
    if name in ('pairwise','lambdarank'):q=(q-V[name].mean())/(V[name].std()+1e-8)*Xv[:,0].std()+Xv[:,0].mean()
    T[name+'_blend']=(1-alpha)*Xte[:,0]+alpha*q;print('TUNED',name,'alpha',alpha,'val',best_tuple[2])
res={name:{**rankmet(te,s),**ratingmet(yte,s)} for name,s in T.items()};print(json.dumps(res,indent=2));summary={'dataset':{'rows':len(df),'users':int(df.user.nunique()),'items':int(df.item.nunique()),'train':len(tr),'val':len(va),'test':len(te)},'features':FEATURES,'results':res};(OUT/'metrics_v2.json').write_text(json.dumps(summary,indent=2));pd.DataFrame(res).T.to_csv(OUT/'metrics_v2.csv');mobile={'format':'tasteai_linear_ranker_v2','features':FEATURES,'scaler_mean':sc.mean_.tolist(),'scaler_scale':sc.scale_.tolist(),'ridge_coef':ridge.coef_.tolist(),'ridge_intercept':float(ridge.intercept_),'pairwise_standardized_coef':pair_w.tolist(),'global_mean':GM};(OUT/'tasteai_linear_ranker_v2.json').write_text(json.dumps(mobile,separators=(',',':')))
