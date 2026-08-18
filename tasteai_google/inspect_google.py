import json, os
from collections import Counter
from pathlib import Path
p=Path('google_restaurants/filter_all_t.json')
print('bytes',p.stat().st_size)
with p.open('r',encoding='utf-8') as f:
    data=json.load(f)
print('type',type(data).__name__,'len',len(data))
if isinstance(data,dict):
    print('top_keys',list(data)[:30])
    rows=next((v for v in data.values() if isinstance(v,list)),[])
else:
    rows=data
print('rows',len(rows))
for x in rows[:3]:
    print('SAMPLE',json.dumps(x,ensure_ascii=False)[:3000])
print('keys',Counter(k for x in rows[:1000] if isinstance(x,dict) for k in x.keys()))
users=Counter(str(x.get('user_id')) for x in rows if isinstance(x,dict))
items=Counter(str(x.get('business_id')) for x in rows if isinstance(x,dict))
ratings=Counter(x.get('rating') for x in rows if isinstance(x,dict))
print('users',len(users),'items',len(items),'ratings',ratings)
print('user_count_dist',Counter(users.values()).most_common(20))
print('users>=2',sum(v>=2 for v in users.values()),'users>=5',sum(v>=5 for v in users.values()),'users>=10',sum(v>=10 for v in users.values()))
print('items>=5',sum(v>=5 for v in items.values()),'items>=10',sum(v>=10 for v in items.values()))
