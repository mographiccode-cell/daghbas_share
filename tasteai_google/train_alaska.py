import gzip,json,math,re
from pathlib import Path
from collections import Counter
import numpy as np, pandas as pd
from sklearn.preprocessing import StandardScaler
from sklearn.linear_model import Ridge,LogisticRegression
from sklearn.ensemble import HistGradientBoostingRegressor
from sklearn.neural_network import MLPRegressor
from sklearn.metrics import mean_squared_error,mean_absolute_error,accuracy_score,balanced_accuracy_score,roc_auc_score,average_precision_score,ndcg_score
DATA=Path('google_alaska'); OUT=Path('alaska_out'); OUT.mkdir(exist_ok=True)
def read_jsonl_gz(path):
    with gzip.open(path,'rt',encoding='utf-8') as f:
        for line in f:
            try: yield json.loads(line)
            except: pass
def norm_cat(s):
    s=re.sub(r'[^a-z0-9 ]+',' ',str(s).lower()); return ' '.join(s.split())
REST_TOKENS=['restaurant','cafe','coffee shop','bakery','bistro','diner','pizza','pizzeria','barbecue','bbq','grill','steakhouse','sushi','ramen','noodle','burger','sandwich','breakfast','brunch','seafood','dessert','ice cream','tea house','taco','brewery','pub','food court','fast food','chicken','mexican','italian','chinese','japanese','thai','indian','mediterranean','middle eastern','vietnamese','korean','american restaurant','asian restaurant']
meta={}; cat_counter=Counter()
for x in read_jsonl_gz(DATA/'meta-Alaska.json.gz'):
    cats=[norm_cat(c) for c in (x.get('category') or [])]
    if any(any(t in c for t in REST_TOKENS) for c in cats):
        gid=str(x.get('gmap_id')); price=x.get('price')
        pnum=float(len(price)) if isinstance(price,str) and price.startswith('$') else np.nan
        meta[gid]={'cats':cats,'price':pnum,'lat':x.get('latitude'),'lon':x.get('longitude')}; cat_counter.update(cats)
print('restaurant_meta',len(meta),'top_categories',cat_counter.most_common(30))
rows=[]
for x in read_jsonl_gz(DATA/'review-Alaska_10.json.gz'):
    gid=str(x.get('gmap_id'))
    if gid not in meta: continue
    try: rating=float(x.get('rating'))
    except: continue
    rows.append((str(x.get('user_id')),gid,rating,int(x.get('time') or 0)))
df=pd.DataFrame(rows,columns=['user_id','item_id','rating','time']).drop_duplicates(['user_id','item_id'],keep='last')
print('restaurant_reviews_raw',len(df),'users',df.user_id.nunique(),'items',df.item_id.nunique(),'rating_dist',df.rating.value_counts().sort_index().to_dict())
def kcore(d,k=5):
    d=d.copy(); changed=True
    while changed:
        n=len(d); uc=d.user_id.value_counts(); ic=d.item_id.value_counts(); d=d[d.user_id.isin(uc[uc>=k].index)&d.item_id.isin(ic[ic>=k].index)]
        changed=len(d)!=n
    return d.reset_index(drop=True)
df=kcore(df,5); uc=df.user_id.value_counts(); df=df[df.user_id.isin(uc[uc>=6].index)].copy(); df=kcore(df,5); uc=df.user_id.value_counts(); df=df[df.user_id.isin(uc[uc>=6].index)].copy().reset_index(drop=True)
print('after_core',len(df),'users',df.user_id.nunique(),'items',df.item_id.nunique(),'user_mean',df.groupby('user_id').size().mean(),'item_mean',df.groupby('item_id').size().mean())
parts={'train':[],'val':[],'test':[]}
for uid,g in df.sort_values('time').groupby('user_id'):
    g=g.sort_values('time')
    if len(g)<6: continue
    parts['test'].append(g.iloc[-2:]); parts['val'].append(g.iloc[-3:-2]); parts['train'].append(g.iloc[:-3])
tr=pd.concat(parts['train']).reset_index(drop=True); va=pd.concat(parts['val']).reset_index(drop=True); te=pd.concat(parts['test']).reset_index(drop=True)
print('split',len(tr),len(va),len(te),'users',te.user_id.nunique())
global_mean=float(tr.rating.mean()); item_stats=tr.groupby('item_id').rating.agg(['mean','count','std']).fillna(0).to_dict('index'); user_groups={u:g for u,g in tr.groupby('user_id')}
def safe_float(x):
    try:
        x=float(x); return x if math.isfinite(x) else np.nan
    except:return np.nan
def hav(lat1,lon1,lat2,lon2):
    vals=list(map(safe_float,[lat1,lon1,lat2,lon2]));
    if any(np.isnan(v) for v in vals): return np.nan
    lat1,lon1,lat2,lon2=vals; p1,p2=math.radians(lat1),math.radians(lat2); dp=math.radians(lat2-lat1); dl=math.radians(lon2-lon1); a=math.sin(dp/2)**2+math.cos(p1)*math.cos(p2)*math.sin(dl/2)**2
    return 6371.0088*2*math.asin(math.sqrt(min(1,a)))
def user_profile(g):
    mean=float(g.rating.mean()); count=len(g); pos=float((g.rating>=4).mean()); c=Counter(); prices=[]; lats=[]; lons=[]
    for row in g.itertuples(index=False):
        m=meta[row.item_id]; weight=max(0.2,row.rating-2.5)
        if row.rating>=4:
            for cat in m['cats']: c[cat]+=weight
            if not np.isnan(m['price']): prices.append(m['price'])
            if not np.isnan(safe_float(m['lat'])) and not np.isnan(safe_float(m['lon'])): lats.append(float(m['lat'])); lons.append(float(m['lon']))
    tot=sum(c.values()) or 1.0
    return {'mean':mean,'count':count,'pos':pos,'cats':{k:v/tot for k,v in c.items()},'price':float(np.mean(prices)) if prices else 2.0,'lat':float(np.mean(lats)) if lats else np.nan,'lon':float(np.mean(lons)) if lons else np.nan}
users={u:user_profile(g) for u,g in user_groups.items()}
def feat(d):
    out=[]
    for row in d.itertuples(index=False):
        u=users.get(row.user_id,{'mean':global_mean,'count':0,'pos':0.75,'cats':{},'price':2.0,'lat':np.nan,'lon':np.nan}); it=item_stats.get(row.item_id,{'mean':global_mean,'count':0,'std':0}); m=meta[row.item_id]
        im=float(it['mean']); ic=int(it['count']); istd=float(it.get('std') or 0); bayes=(ic*im+10*global_mean)/(ic+10); cm=max([u['cats'].get(c,0.0) for c in m['cats']] or [0.0]); p=m['price']; p_known=float(not np.isnan(p)); pval=2.0 if np.isnan(p) else float(p); pm=max(0.0,1.0-abs(pval-u['price'])/3.0) if p_known else 0.5; dist=hav(u['lat'],u['lon'],m['lat'],m['lon']); dist_known=float(not np.isnan(dist)); dlog=math.log1p(dist) if dist_known else math.log1p(25.0)
        out.append([im,math.log1p(ic),istd,bayes,u['mean'],math.log1p(u['count']),u['pos'],pval,p_known,u['price'],pm,cm,dlog,dist_known,len(m['cats']),im-u['mean']])
    return np.asarray(out,float)
FEATURES=['item_mean','log_item_count','item_std','bayes_item_mean','user_mean','log_user_count','user_positive_rate','price','price_known','user_price_pref','price_match','category_match','distance_log1p','distance_known','category_count','item_user_mean_gap']
Xtr=feat(tr); Xv=feat(va); Xte=feat(te); ytr=tr.rating.to_numpy(float); yte=te.rating.to_numpy(float); sc=StandardScaler().fit(Xtr); Xtrs=sc.transform(Xtr); Xtes=sc.transform(Xte)
models={'baseline_item_mean':None,'ridge':Ridge(alpha=10).fit(Xtrs,ytr),'hist_gb':HistGradientBoostingRegressor(max_depth=5,learning_rate=.05,max_iter=250,l2_regularization=3,random_state=42).fit(Xtr,ytr),'mlp':MLPRegressor(hidden_layer_sizes=(32,16),activation='relu',alpha=.01,learning_rate_init=.001,max_iter=180,early_stopping=True,validation_fraction=.12,n_iter_no_change=15,random_state=42).fit(Xtrs,ytr)}
log=LogisticRegression(max_iter=2000,C=.5,class_weight='balanced').fit(Xtrs,(ytr>=4).astype(int)); models['logistic_preference']=log
def pred(name):
    if name=='baseline_item_mean': return Xte[:,0]
    if name=='ridge': return models[name].predict(Xtes)
    if name=='hist_gb': return models[name].predict(Xte)
    if name=='mlp': return models[name].predict(Xtes)
    return 1+4*models[name].predict_proba(Xtes)[:,1]
def metrics(scores):
    scores=np.asarray(scores,float); predstar=np.clip(np.rint(scores),1,5); truepos=(yte>=4).astype(int); probs=np.clip((scores-1)/4,0,1); binpred=(probs>=0.5).astype(int)
    m={'rmse':float(mean_squared_error(yte,scores)**.5),'mae':float(mean_absolute_error(yte,scores)),'exact_star_accuracy':float(accuracy_score(yte,predstar)),'within_1_star_accuracy':float(np.mean(np.abs(yte-predstar)<=1)),'preference_accuracy':float(accuracy_score(truepos,binpred)),'preference_balanced_accuracy':float(balanced_accuracy_score(truepos,binpred))}
    try:m['preference_roc_auc']=float(roc_auc_score(truepos,probs));m['preference_pr_auc']=float(average_precision_score(truepos,probs))
    except:pass
    nd=[];best=[];pair=[];ties=0; tmp=te[['user_id','rating']].copy();tmp['score']=scores
    for _,g in tmp.groupby('user_id'):
        yy=g.rating.to_numpy(float);ss=g.score.to_numpy(float)
        if yy.max()==yy.min():ties+=1;continue
        nd.append(float(ndcg_score([yy],[ss],k=2)));best.append(float(yy[np.argmax(ss)]==yy.max()));pair.append(float((ss[0]-ss[1])*(yy[0]-yy[1])>0))
    m.update({'ndcg_at_2_non_tie':float(np.mean(nd)) if nd else None,'best_choice_at_1':float(np.mean(best)) if best else None,'pairwise_accuracy':float(np.mean(pair)) if pair else None,'non_tie_users':len(nd),'tie_users':ties});return m
results={name:metrics(pred(name)) for name in models}; majority=int(np.mean(ytr>=4)>=.5);results['majority_preference']={'preference_accuracy':float(np.mean((yte>=4)==majority)),'preference_balanced_accuracy':0.5}
print('RESULTS',json.dumps(results,indent=2)); summary={'source':'UCSD Google Local 2021 Alaska 10-core; restaurant/cafe filtered','raw_restaurant_reviews':len(rows),'core_rows':len(df),'core_users':int(df.user_id.nunique()),'core_items':int(df.item_id.nunique()),'train':len(tr),'val':len(va),'test':len(te),'rating_distribution':{str(k):int(v) for k,v in df.rating.value_counts().sort_index().items()},'features':FEATURES,'results':results};(OUT/'metrics.json').write_text(json.dumps(summary,indent=2));pd.DataFrame(results).T.to_csv(OUT/'metrics.csv')
mlp=models['mlp']; export={'format':'tasteai_mlp_regressor_v2','features':FEATURES,'mean':sc.mean_.tolist(),'scale':sc.scale_.tolist(),'layers':[]}
for W,b in zip(mlp.coefs_,mlp.intercepts_): export['layers'].append({'weights':W.tolist(),'bias':b.tolist(),'activation':'relu' if len(export['layers'])<len(mlp.coefs_)-1 else 'linear'})
(OUT/'tasteai_alaska_mlp.json').write_text(json.dumps(export,separators=(',',':')))
