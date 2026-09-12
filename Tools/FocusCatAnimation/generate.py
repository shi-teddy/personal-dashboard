"""Bake only the approved workcat-v3 animation into portable native drawing data."""
from pathlib import Path
import hashlib,json,math
import numpy as np
import approved_renderer as r
ROOT=Path(__file__).resolve().parents[2]
def frame(data,dy=0):
 return dict(points=np.round(data['points'].flatten(),5).tolist(),tail=np.round(data.get('tail',np.empty((0,2))).flatten(),5).tolist(),tailWidth=round(float(data.get('tail_width',0)),5),tailSeam=round(float(data.get('tail_seam',0)),5),offsetY=round(float(dy),5))
def clip(duration,fn,loop=False):
 count=round(duration*60)+(0 if loop else 1)
 return dict(duration=duration,loop=loop,frames=[fn(i/60) for i in range(count)])
def state_frame(t,origin):
 p,xy,_,_=r.state(t);return frame(p,xy[1]-origin[1])
def gait(t):
 cycles=t/.6;p=r.walk(cycles);bob=1.7*(1-math.cos(4*math.pi*cycles))
 p['points'][:80,1]+=bob*np.clip((p['points'][:80,1]-78)/24,0,1)
 return frame(p,-bob)
clips={
 'sleep':clip(2.4,lambda t:frame(r.rest(1,.16*math.sin(t*math.pi*2/2.4))),True),
 'wake':clip(1.4,lambda t:frame(r.rest(1-r.ease(t/1.4)))),
 'walk':clip(.6,gait,True),
 'reach':clip(1.6,lambda t:state_frame(min(r.HOLD_END-1e-8,r.ARRIVE+t),r.DEST)),
 'recover':clip(.95,lambda t:state_frame(min(r.RETURN_START-1e-8,r.HOLD_END+t),r.DEST)),
 'settle':clip(1.4,lambda t:state_frame(r.TURN_END+t,r.HOME)),
}
# A short departure sequence preserves the GIF's first step after waking.
def depart(t):
 p=r.walk(t/.6);p['points']=r.mix(r.BASE,p['points'],r.ease(t/.18))
 bob=1.7*(1-math.cos(4*math.pi*t/.6))*r.ease(t/.18)
 p['points'][:80,1]+=bob*np.clip((p['points'][:80,1]-78)/24,0,1)
 return frame(p,-bob)
clips['depart']=clip(.18,depart)
ref=ROOT/'output/workcat-v3/workcat_final.gif'
result=dict(version=3,source='workcat-v3/workcat_final.gif',sourceSHA256=hashlib.sha256(ref.read_bytes()).hexdigest(),fps=60,canvasWidth=190,canvasHeight=154,paddingX=18,paddingY=36,pawX=float(r.TIP[0]),pawY=float(r.TIP[1]-28),distancePerLoop=float(np.linalg.norm(r.DEST-r.HOME)/14),closeTime=1.3,clips=clips)
out=ROOT/'PersonalDashboard/Resources/ApprovedCatAnimation.json';out.write_text(json.dumps(result,separators=(',',':'))+'\n')
print(out, sum(len(c['frames']) for c in clips.values()),'frames;',out.stat().st_size,'bytes')
