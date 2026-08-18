import json, math, zlib
from pathlib import Path
from collections import defaultdict
import numpy as np
import pandas as pd
from sklearn.preprocessing import StandardScaler
from sklearn.linear_model import Ridge, LogisticRegression
from sklearn.ensemble import HistGradientBoostingRegressor
from sklearn.metrics import ndcg_score

DATA=Path('uci_full'); OUT=Path('diag_out'); OUT.mkdir(exist_ok=True)
r=pd.read_csv(DATA/'rating_final.csv').rename(columns={'userID':'user_id','placeID':'place_id','rating':'relevance'})
p=pd.read_csv(DATA/'geoplaces2.csv', na_values=['?'])
up=pd.read_csv(DATA/'userprofile.csv', na_values=['?'])
uc=pd.read_csv(DATA/'usercuisine.csv')
pc=pd.read_csv(DATA/'chefmozcuisine.csv')
r['stars']=1+2*r.relevance.astype(float)
price_map={'low':1.0,'medium':2.0,'high':3.0}
p['price_num']=p.price.astype(str).str.lower().map(price_map).fillna(2.0)
up['budget_num']=up.budget.astype(str).str.lower().map(price_map).fillna(2.0)
user_prof=up.set_index('userID').to_dict('index')
user_cuis=uc.groupby('userID').Rcuisine.apply(lambda x:set(map(str,x))).to_dict()
place_cuis=pc.groupby('placeID').Rcuisine.apply(lambda x:set(map(str,x))).to_dict()
place_prof=p.set_index('placeID').to_dict('index')

def hav(a,b,c,d):
    if not all(pd.notna(x) for x in [a,b,c,d]): return 100.0
    a,b,c,d=map(float,[a,b,c,d]); p1,p2=math.radians(a),math.radians(c); dp=math.radians(c-a); dl=math.radians(d-b)
    z=math.sin(dp/2)**2+math.cos(p1)*math.cos(p2)*math.sin(dl/2)**2
    return 6371.0088*2*math.asin(math.sqrt(min(1,z)))

def context(uid,pid):
    u=user_prof.get(uid,{}); q=place_prof.get(pid,{})
    U=user_cuis.get(uid,set()); P=place_cuis.get(pid,set())
    cm=float(len(U&P)/max(1,len(U))) if U else 0.0
    price=float(q.get('price_num',2.0)); budget=float(u.get('budget_num',2.0))
    dist=math.log1p(max(hav(u.get('latitude',np.nan),u.get('longitude',np.nan),q.get('latitude',np.nan),q.get('longitude',np.nan)),0))
    pname=' '.join(P).lower(); cafe=float('cafe' in pname or 'coffee' in pname or 'cafeteria' in pname)
    return price,budget,cm,dist,cafe

def split(seed):
    tr=[]; te=[]
    for uid,g in r.groupby('user_id',sort=True):
        g=g.copy().reset_index(drop=True); rng=np.random.default_rng((seed+zlib.crc32(uid.encode()))&0xffffffff); g=g.iloc[rng.permutation(len(g))]
        if len(g)>=6: te.append(g.iloc[:2]); tr.append(g.iloc[2:])
        else: tr.append(g)
    return pd.concat(tr,ignore_index=True),pd.concat(te,ignore_index=True)

def aggs(hist):
    gm=float(hist.stars.mean()); ug={}; ig={}
    for uid,g in hist.groupby('user_id'):
        x=g.stars.to_numpy(float); ug[uid]=(float(x.mean()),len(x))
    for pid,g in hist.groupby('place_id'):
        x=g.stars.to_numpy(float); ig[int(pid)]=(float(x.mean()),len(x),float(x.std(ddof=1)) if len(x)>1 else 0.)
    return gm,ug,ig

def features(frame,hist,loo=False):
    gm,ug,ig=aggs(hist); byu={u:g for u,g in hist.groupby('user_id')}; byi={int(i):g for i,g in hist.groupby('place_id')}; out=[]
    for row in frame.itertuples(index=False):
        uid=row.user_id; pid=int(row.place_id)
        if loo:
            gu=byu[uid]; gu=gu[gu.place_id!=pid]; gi=byi[pid]; gi=gi[gi.user_id!=uid]
            ux=gu.stars.to_numpy(float); ix=gi.stars.to_numpy(float)
            um=float(ux.mean()) if len(ux) else gm; ucx=len(ux); im=float(ix.mean()) if len(ix) else gm; ic=len(ix); istd=float(ix.std(ddof=1)) if len(ix)>1 else 0.
        else:
            um,ucx=ug.get(uid,(gm,0)); im,ic,istd=ig.get(pid,(gm,0,0.))
        price,budget,cm,dist,cafe=context(uid,pid)
        out.append({'user_id':uid,'place_id':pid,'relevance':int(row.relevance),'item_mean':im,'log_item_count':math.log1p(ic),'item_std':istd,'price':price,'user_mean':um,'log_user_count':math.log1p(ucx),'budget':budget,'price_match':max(0.,1-abs(price-budget)/2),'cuisine_match':cm,'distance_log1p':dist,'is_cafe':cafe})
    return pd.DataFrame(out)

BASIC=['item_mean','log_item_count','item_std','price','user_mean','log_user_count']
CONTEXT=BASIC+['budget','price_match','cuisine_match','distance_log1p','is_cafe']

def metrics(df,col):
    nd=[]; best=[]; pair=[]; ties=0
    for _,g in df.groupby('user_id'):
        y=g.relevance.to_numpy(float); s=g[col].to_numpy(float)
        if y.max()==y.min(): ties+=1; continue
        nd.append(float(ndcg_score([y],[s],k=2))); best.append(float(y[np.argmax(s)]==y.max())); pair.append(float((s[0]-s[1])*(y[0]-y[1])>0))
    return {'ndcg_at_2':float(np.mean(nd)),'best_choice_at_1':float(np.mean(best)),'pairwise_accuracy':float(np.mean(pair)),'non_tie_users':len(nd),'tie_users':ties}

def pairwise_ranker(tf,feats):
    X=[]; y=[]
    for _,g in tf.groupby('user_id'):
        a=g.reset_index(drop=True)
        for i in range(len(a)):
            for j in range(i+1,len(a)):
                if a.loc[i,'relevance']==a.loc[j,'relevance']: continue
                d=a.loc[i,feats].to_numpy(float)-a.loc[j,feats].to_numpy(float); lab=int(a.loc[i,'relevance']>a.loc[j,'relevance']); X.extend([d,-d]); y.extend([lab,1-lab])
    X=np.vstack(X); y=np.array(y); sc=StandardScaler().fit(X); m=LogisticRegression(max_iter=2000,C=1).fit(sc.transform(X),y); return m.coef_[0]/sc.scale_

seeds=[1,7,19,42,77,99,123,321,777,2026,314159,20260818]
rows=[]
for seed in seeds:
    tr,te=split(seed); tf=features(tr,tr,True); ef=features(te,tr,False)
    for fs,feats in [('basic',BASIC),('context',CONTEXT)]:
        base=ef[['user_id','place_id','relevance']].copy(); base['score']=ef.item_mean; rows.append({'seed':seed,'feature_set':fs,'model':'baseline_item_mean',**metrics(base,'score')})
        X=tf[feats].to_numpy(float); Xt=ef[feats].to_numpy(float); y=tf.relevance.to_numpy(int); sc=StandardScaler().fit(X); Xs=sc.transform(X); Xts=sc.transform(Xt)
        ridge=Ridge(alpha=10).fit(Xs,y); z=base.copy(); z['score']=ridge.predict(Xts); rows.append({'seed':seed,'feature_set':fs,'model':'ridge',**metrics(z,'score')})
        log=LogisticRegression(max_iter=2000,C=.5).fit(Xs,y); pr=log.predict_proba(Xts); z=base.copy(); z['score']=pr@log.classes_.astype(float); rows.append({'seed':seed,'feature_set':fs,'model':'logistic',**metrics(z,'score')})
        h=HistGradientBoostingRegressor(max_depth=3,learning_rate=.05,max_iter=120,l2_regularization=2).fit(X,y); z=base.copy(); z['score']=h.predict(Xt); rows.append({'seed':seed,'feature_set':fs,'model':'hist_gb',**metrics(z,'score')})
        w=pairwise_ranker(tf,feats); z=base.copy(); z['score']=Xt@w; rows.append({'seed':seed,'feature_set':fs,'model':'pairwise_logistic',**metrics(z,'score')})
res=pd.DataFrame(rows); res.to_csv(OUT/'repeated_holdout_metrics.csv',index=False)
summary=res.groupby(['feature_set','model'])[['ndcg_at_2','best_choice_at_1','pairwise_accuracy']].agg(['mean','std']).reset_index(); summary.to_csv(OUT/'repeated_holdout_summary.csv',index=False)
coverage={'rows':len(r),'users':int(r.user_id.nunique()),'places':int(r.place_id.nunique()),'rating_distribution':{str(k):int(v) for k,v in r.relevance.value_counts().sort_index().items()},'ratings_per_user_mean':float(r.groupby('user_id').size().mean()),'ratings_per_place_mean':float(r.groupby('place_id').size().mean()),'user_profiles':len(up),'user_cuisine_rows':len(uc),'place_cuisine_rows':len(pc),'rated_rows_with_user_cuisine':float(r.user_id.isin(user_cuis).mean()),'rated_rows_with_place_cuisine':float(r.place_id.isin(place_cuis).mean())}
(OUT/'dataset_diagnostics.json').write_text(json.dumps(coverage,indent=2))
print(summary.to_string(index=False)); print('\nCOVERAGE',json.dumps(coverage,indent=2))
