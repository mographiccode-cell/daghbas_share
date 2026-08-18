import json, math, os, random
from pathlib import Path
from collections import defaultdict, Counter
import numpy as np
import pandas as pd
from sklearn.preprocessing import StandardScaler
from sklearn.linear_model import Ridge, LogisticRegression
from sklearn.ensemble import HistGradientBoostingRegressor, RandomForestRegressor
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
    vals=[a,b,c,d]
    if not all(pd.notna(x) for x in vals): return 100.0
    a,b,c,d=map(float,vals); p1,p2=math.radians(a),math.radians(c); dp=math.radians(c-a); dl=math.radians(d-b)
    z=math.sin(dp/2)**2+math.cos(p1)*math.cos(p2)*math.sin(dl/2)**2
    return 6371.0088*2*math.asin(math.sqrt(min(1,z)))

def static_context(uid,pid):
    u=user_prof.get(uid,{}); q=place_prof.get(pid,{})
    U=user_cuis.get(uid,set()); P=place_cuis.get(pid,set())
    cuisine=float(len(U&P)/max(1,len(U))) if U else 0.0
    price=float(q.get('price_num',2.0)); budget=float(u.get('budget_num',2.0))
    dist=hav(u.get('latitude',np.nan),u.get('longitude',np.nan),q.get('latitude',np.nan),q.get('longitude',np.nan))
    name=' '.join(P).lower()
    return price, budget, cuisine, math.log1p(max(dist,0)), float('cafe' in name or 'coffee' in name or 'cafeteria' in name)

def aggregates(hist):
    gm=float(hist.stars.mean()); ug={}; ig={}
    for uid,g in hist.groupby('user_id'):
        x=g.stars.to_numpy(float); ug[uid]=(float(x.mean()),len(x),float(x.std(ddof=1)) if len(x)>1 else 0.)
    for pid,g in hist.groupby('place_id'):
        x=g.stars.to_numpy(float); ig[int(pid)]=(float(x.mean()),len(x),float(x.std(ddof=1)) if len(x)>1 else 0.)
    return gm,ug,ig

def frame_features(frame,hist,loo=False):
    gm,ug,ig=aggregates(hist); out=[]
    # exact LOO aggregates for train rows; tiny dataset so clarity > micro-optimization
    byu={u:g for u,g in hist.groupby('user_id')}; byi={int(i):g for i,g in hist.groupby('place_id')}
    for row in frame.itertuples(index=False):
        uid=row.user_id; pid=int(row.place_id)
        if loo:
            gu=byu[uid]; gu=gu[gu.place_id!=pid]
            gi=byi[pid]; gi=gi[gi.user_id!=uid]
            ux=gu.stars.to_numpy(float); ix=gi.stars.to_numpy(float)
            um=float(ux.mean()) if len(ux) else gm; ucx=len(ux)
            im=float(ix.mean()) if len(ix) else gm; ic=len(ix); istd=float(ix.std(ddof=1)) if len(ix)>1 else 0.
        else:
            um,ucx,_=ug.get(uid,(gm,0,0)); im,ic,istd=ig.get(pid,(gm,0,0))
        price,budget,cm,dist,cafe=static_context(uid,pid)
        out.append({'user_id':uid,'place_id':pid,'relevance':int(row.relevance),
          'item_mean':im,'log_item_count':math.log1p(ic),'item_std':istd,
          'price':price,'user_mean':um,'log_user_count':math.log1p(ucx),
          'budget':budget,'price_match':max(0.,1-abs(price-budget)/2),
          'cuisine_match':cm,'distance_log1p':dist,'is_cafe':cafe})
    return pd.DataFrame(out)

BASIC=['item_mean','log_item_count','item_std','price','user_mean','log_user_count']
CONTEXT=BASIC+['budget','price_match','cuisine_match','distance_log1p','is_cafe']

def rank_metrics(df,score):
    nd=[]; best=[]; pair=[]
    for uid,g in df.groupby('user_id'):
        y=g.relevance.to_numpy(float); s=g[score].to_numpy(float)
        if len(g)<2 or y.max()==y.min(): continue
        nd.append(ndcg_score([y],[s],k=min(3,len(g))))
        best.append(float(y[np.argmax(s)]==y.max()))
        for i in range(len(g)):
            for j in range(i+1,len(g)):
                if y[i]==y[j]: continue
                pair.append(float((s[i]-s[j])*(y[i]-y[j])>0))
    return {'ndcg_at_3':float(np.mean(nd)),'best_choice_at_1':float(np.mean(best)),'pairwise_accuracy':float(np.mean(pair)),'users':len(nd),'pairs':len(pair)}

def fold_ids(seed,k=5):
    fold=np.empty(len(r),int)
    for uid,idx in r.groupby('user_id').groups.items():
        ids=np.array(list(idx)); rng=np.random.default_rng(seed+sum(map(ord,uid))); rng.shuffle(ids)
        for j,ix in enumerate(ids): fold[ix]=j%k
    return fold

def run(seed,feature_set):
    folds=fold_ids(seed); pred=[]
    for f in range(5):
        tr=r[folds!=f].copy(); te=r[folds==f].copy()
        tf=frame_features(tr,tr,loo=True); ef=frame_features(te,tr,loo=False)
        feats=BASIC if feature_set=='basic' else CONTEXT
        X=tf[feats].to_numpy(float); Xt=ef[feats].to_numpy(float); y=tf.relevance.to_numpy(int)
        sc=StandardScaler().fit(X); Xs=sc.transform(X); Xts=sc.transform(Xt)
        models={
          'ridge': Ridge(alpha=10).fit(Xs,y),
          'logistic': LogisticRegression(max_iter=2000,C=.5).fit(Xs,y),
          'hist_gb': HistGradientBoostingRegressor(max_depth=3,learning_rate=.05,max_iter=150,l2_regularization=2).fit(X,y),
          'random_forest': RandomForestRegressor(n_estimators=250,max_depth=6,min_samples_leaf=4,random_state=seed+f,n_jobs=-1).fit(X,y),
        }
        base=ef[['user_id','place_id','relevance']].copy(); base['score']=ef.item_mean; base['model']='baseline_item_mean'; pred.append(base)
        for name,m in models.items():
            z=ef[['user_id','place_id','relevance']].copy()
            if name=='logistic':
                pr=m.predict_proba(Xts); z['score']=pr@m.classes_.astype(float)
            elif name=='ridge': z['score']=m.predict(Xts)
            else: z['score']=m.predict(Xt)
            z['model']=name; pred.append(z)
    allp=pd.concat(pred,ignore_index=True)
    # each row appears once per model
    return [{'seed':seed,'feature_set':feature_set,'model':m,**rank_metrics(g,'score')} for m,g in allp.groupby('model')]

results=[]
for seed in [7,42,99,314159,2026]:
    for fs in ['basic','context']:
        results.extend(run(seed,fs))
res=pd.DataFrame(results)
res.to_csv(OUT/'oof_metrics_all.csv',index=False)
summary=res.groupby(['feature_set','model'])[['ndcg_at_3','best_choice_at_1','pairwise_accuracy']].agg(['mean','std']).reset_index()
summary.to_csv(OUT/'oof_summary.csv',index=False)
# dataset diagnostics
D={
 'rows':len(r),'users':int(r.user_id.nunique()),'places':int(r.place_id.nunique()),
 'rating_distribution':{str(k):int(v) for k,v in r.relevance.value_counts().sort_index().items()},
 'ratings_per_user':r.groupby('user_id').size().describe().to_dict(),
 'ratings_per_place':r.groupby('place_id').size().describe().to_dict(),
 'user_cuisine_rows':len(uc),'place_cuisine_rows':len(pc),'user_profiles':len(up),
 'constant_or_near_constant_context_features':{}
}
(OUT/'dataset_diagnostics.json').write_text(json.dumps(D,indent=2,default=float))
print('\nOOF SUMMARY\n',summary.to_string(index=False))
