from pathlib import Path
import json,math,sys
import numpy as np
import cv2
from PIL import Image,ImageDraw
ROOT=Path(__file__).resolve().parent
A=np.array(json.loads((ROOT/'registered-contours.json').read_text())).reshape(75,220,2)
FPS=60;W,H=1074,850;CREAM=(227,224,211);INK=(22,22,20);SEAM=(199,196,183)
BASE=A[4].copy();STAND=A[0].copy()
def ease(t):
 t=np.clip(t,0,1);return t*t*t*(t*(t*6-15)+10)
def mix(a,b,t):return np.asarray(a)*(1-t)+np.asarray(b)*t
def cubic(a,b,c,d,n=30,endpoint=False):
 t=np.linspace(0,1,n,endpoint=endpoint)[:,None];u=1-t
 return u**3*a+3*u*u*t*b+3*u*t*t*c+t**3*d
def rotation(a):return np.array([[math.cos(a),-math.sin(a)],[math.sin(a),math.cos(a)]])
def resample(p,n):
 q=np.vstack([p,p[0]]);u=np.r_[0,np.cumsum(np.linalg.norm(np.diff(q,axis=0),axis=1))];t=np.linspace(0,u[-1],n,endpoint=False)
 return np.c_[np.interp(t,u,q[:,0]),np.interp(t,u,q[:,1])]
def stroke_shape(line,width,reference):
 # Rounded stroke outlines, registered to the original face marks.
 tangent=np.gradient(line,axis=0);tangent/=np.linalg.norm(tangent,axis=1)[:,None];normal=np.c_[-tangent[:,1],tangent[:,0]]
 p=np.vstack([line+normal*width/2,(line-normal*width/2)[::-1]])
 p=resample(p,len(reference));opts=[np.roll(q,j,axis=0) for q in [p,p[::-1]] for j in range(len(p))]
 return min(opts,key=lambda q:np.sum((q-reference)**2))
def ink(p,**kwargs):return {'points':p,**kwargs}

# The same head geometry is retained for every sleep / wake frame.
def rest(progress,breath=0):
 s=ease(progress);p=BASE.copy();pivot=np.array([106.,46.]);shift=np.array([-3*s,29*s-breath])
 def head(q):return (q-pivot)@rotation(.10*s).T+pivot+shift
 final_head=(BASE[:160]-pivot)@rotation(.10).T+pivot+[-3,29]
 target=BASE.copy()
 target[:25]=cubic(final_head[0],[114,105],[104,105],[92,103],25)
 target[25:45]=cubic(np.array([92,103]),[84,102],[77,103],[70,103],20)
 target[45:65]=cubic(np.array([70,103]),[57,106],[40,106],[31,97],20)
 target[65:80]=cubic(np.array([31,97]),[25,94],[24,88],[25,82],15)
 # One continuous rounded back, with no tail-root spur or second hump.
 target[80:121]=cubic(np.array([25,82]),[17,44],[51,42],final_head[121],41)
 p[:121]=mix(BASE[:121],target[:121],s)
 p[121:160]=head(BASE[121:160]);p[0]=head(BASE[0])
 p[1:9]+=(p[0]-mix(BASE[0],final_head[0],s))*np.linspace(1,0,8)[:,None]
 root_curve=cubic(BASE[80],np.array([27,59]),np.array([28,47]),BASE[108],28)
 p[80:108]=mix(root_curve,target[80:108],s)
 p[107:121,1]-=breath*np.linspace(0,1,14)
 face=BASE[160:].copy();closed=ease((progress-.32)/.50)
 for k in [0,40]:
  ref=BASE[160+k:180+k];c=ref.mean(0)
  line=cubic(c+[-2.15,-.5],c+[-1.55,2.0],c+[1.55,2.0],c+[2.15,-.5],24,True)
  face[k:k+20]=mix(ref,stroke_shape(line,1.25,ref),closed)
 ref=BASE[180:200];c=ref.mean(0)
 line=np.vstack([cubic(c+[-3,-.4],c+[-3,2.25],c+[0,2.25],c+[0,0],16),cubic(c+[0,0],c+[0,2.25],c+[3,2.25],c+[3,-.4],16,True)])
 face[20:40]=mix(ref,stroke_shape(line,1.25,ref),closed)
 p[160:]=head(face)
 # A continuous flexible tail curls around the rump onto the foreground.
 standing=np.array([[31,51],[22,48],[16,43],[15,36],[14,32],[15,29],[15,28]],float)
 tucked=np.array([[31,77],[20,87],[25,99],[39,102],[51,105],[68,102],[62,96]],float)
 def centerline(q):
  raw=np.vstack([cubic(*q[:4],40),cubic(*q[3:],40,True)])
  lens=np.r_[0,np.cumsum(np.linalg.norm(np.diff(raw,axis=0),axis=1))];u=np.linspace(0,lens[-1],81)
  return np.c_[np.interp(u,lens,raw[:,0]),np.interp(u,lens,raw[:,1])]
 tucked[:,1]=77+(tucked[:,1]-77)*.74
 tail0=centerline(standing);tail1=centerline(tucked)
 delta0=np.diff(tail0,axis=0);delta1=np.diff(tail1,axis=0)
 angles0=np.unwrap(np.arctan2(delta0[:,1],delta0[:,0]));angles1=np.unwrap(np.arctan2(delta1[:,1],delta1[:,0]))-2*np.pi
 ts=ease((progress-.02)/.98);angles=mix(angles0,angles1,ts)
 lengths=mix(np.linalg.norm(delta0,axis=1),np.linalg.norm(delta1,axis=1),ts)
 root=mix(tail0[0],tail1[0],s)
 tail=np.vstack([root,root+np.cumsum(np.c_[np.cos(angles),np.sin(angles)]*lengths[:,None],axis=0)])
 # The unwrapping tail brushes the floor instead of passing through it.
 below=tail[:,1]>94
 tail[below,1]=94+4*np.tanh((tail[below,1]-94)/4)
 return ink(p,tail=tail,tail_width=9+2*s,tail_seam=ease((progress-.50)/.45),sleep=s)

# Restore the earlier GIF-based reaching gesture. All intermediate poses
# come from the supplied animation rather than a rotating drawn-on limb.
REACH_FRAMES=A[54:65].copy()
# Register ears and cheek at consistent contour positions. The GIF outlines
# are unchanged, but interpolation no longer slides vertices across the ears.
for _frame in REACH_FRAMES:
 _p=_frame[:160].copy();_q=np.vstack([_p,_p[0]])
 _mins=[i for i in range(110,148) if _p[i,1]<_p[i-1,1] and _p[i,1]<=_p[i+1,1] and _p[i,1]<25]
 _e1,_e2=_mins[:2];_valley=_e1+int(np.argmax(_p[_e1:_e2+1,1]));_tail=88+int(np.argmin(_p[88:103,1]))
 _anchors=[80,_tail,_tail+10,_e1-10,_e1,_valley,_e2,_e2+9,_e2+13,160]
 _counts=[16,12,12,10,5,4,9,4,8];_parts=[]
 for _a,_b,_n in zip(_anchors[:-1],_anchors[1:],_counts):
  _arc=_q[_a:_b+1];_lens=np.r_[0,np.cumsum(np.linalg.norm(np.diff(_arc,axis=0),axis=1))];_u=np.linspace(0,_lens[-1],_n,endpoint=False)
  _parts.append(np.c_[np.interp(_u,_lens,_arc[:,0]),np.interp(_u,_lens,_arc[:,1])])
 _frame[80:160]=np.vstack(_parts)
REACH_DISTANCE=np.r_[0,np.cumsum(np.sqrt(np.mean(np.diff(REACH_FRAMES,axis=0)**2,axis=(1,2))))]
REACH_DISTANCE/=REACH_DISTANCE[-1]
_H=np.diff(REACH_DISTANCE)
_D=np.diff(REACH_FRAMES,axis=0)/_H[:,None,None]
_M=np.zeros_like(REACH_FRAMES);_M[0]=_D[0];_M[-1]=_D[-1]
for _k in range(1,len(REACH_FRAMES)-1):
 _same=_D[_k-1]*_D[_k]>0;_w1=2*_H[_k]+_H[_k-1];_w2=_H[_k]+2*_H[_k-1]
 _den=np.divide(_w1,_D[_k-1],out=np.zeros_like(_D[_k-1]),where=_same)+np.divide(_w2,_D[_k],out=np.zeros_like(_D[_k]),where=_same)
 _M[_k]=np.divide(_w1+_w2,_den,out=np.zeros_like(_den),where=_same)
def REACH_CURVE(value):
 j=min(9,max(0,int(np.searchsorted(REACH_DISTANCE,value,side='right')-1)))
 h=_H[j];u=(value-REACH_DISTANCE[j])/h
 return (2*u**3-3*u*u+1)*REACH_FRAMES[j]+(u**3-2*u*u+u)*h*_M[j]+(-2*u**3+3*u*u)*REACH_FRAMES[j+1]+(u**3-u*u)*h*_M[j+1]
def reaching(amount):
 # Allocate time to actual pose movement, so the paw does not rush through
 # the middle of the lift. Shape-preserving interpolation avoids overshoot.
 return ink(REACH_CURVE(float(ease(amount))))

DURS=np.array([70,70,60]*7)[:20]/1000
LOOP=sum(DURS)
def walk(cycles):
 phase=(cycles%1)*LOOP;j=min(19,int(np.searchsorted(np.cumsum(DURS),phase,side='right')))
 u=(phase-sum(DURS[:j]))/DURS[j]
 return ink(mix(A[j],A[(j+1)%20],u))

HOME=np.array([20.,654.])
raised=reaching(1)['points'][:160];TIP=raised[np.argmax(raised[:,0])]
REACH=np.array([1021.,65.])-TIP
DEST=REACH+np.array([0.,28.])
# 28 support changes over the trip; travel, gait and weight transfer share a clock.
TRAVEL=8.4;CYCLES=14;TAKEOFF=2.5;ARRIVE=TAKEOFF+TRAVEL
LIFT_START=ARRIVE+.25;LIFT_END=LIFT_START+.65;HOLD_END=LIFT_END+.70
LOWER_END=HOLD_END+.65;RETURN_START=LOWER_END+.3;RETURN_END=RETURN_START+TRAVEL
TURN_END=RETURN_END+.3;REST_END=TURN_END+1.4;DURATION=REST_END+2.1

def travel(elapsed,start,end,facing):
 u=np.clip(elapsed/TRAVEL,0,1)
 # Small acceleration windows only at departure and landing.
 ramp=.065
 if u<ramp:v=u*u/(2*ramp)
 elif u>1-ramp:v=1-ramp-(1-u)**2/(2*ramp)
 else:v=u-ramp/2
 v/=1-ramp
 phase=CYCLES*v
 # A small advance on push-off, followed by a planted weight-bearing phase.
 advance=v-.12*math.sin(4*math.pi*phase)/(4*math.pi*CYCLES)
 xy=mix(start,end,advance)
 weight=math.sin(math.pi*min(1,u/.10)/2)**2*math.sin(math.pi*min(1,(1-u)/.10)/2)**2
 bob=1.7*(1-math.cos(4*math.pi*phase))*weight
 xy[1]-=bob
 p=walk(phase)
 # The torso rises over each planted foot, while the toes retain contact.
 contact=np.clip((p['points'][:80,1]-78)/24,0,1)
 p['points'][:80,1]+=bob*contact
 # Starts and ends on the same four-paw stance. No arrival body-pose blend.
 return p,xy,facing

def state(t):
 f=1;visible=1
 if t<1.1:p=rest(1,.16*math.sin(t*math.pi*2/2.4));xy=HOME
 elif t<TAKEOFF:p=rest(1-ease((t-1.1)/1.4));xy=HOME
 elif t<ARRIVE:
  p,xy,f=travel(t-TAKEOFF,HOME,DEST,1)
  # Complete the initial step from the familiar resting stance.
  if t<TAKEOFF+.18:p['points']=mix(BASE,p['points'],ease((t-TAKEOFF)/.18))
 elif t<LIFT_START:p=ink(mix(STAND,reaching(0)['points'],ease((t-ARRIVE)/.25)));xy=DEST
 elif t<LIFT_END:
  u=(t-LIFT_START)/.65;p=reaching(u);xy=mix(DEST,REACH,ease(u))
 elif t<HOLD_END:p=reaching(1);xy=REACH;visible=1-ease((t-(LIFT_END+.4))/.25)
 elif t<LOWER_END:
  u=(t-HOLD_END)/.65;p=reaching(1-u);xy=mix(REACH,DEST,ease(u));visible=0
 elif t<RETURN_START:
  p=ink(mix(reaching(0)['points'],STAND,ease((t-LOWER_END)/.14)));xy=DEST;f=1 if t<LOWER_END+.15 else -1;visible=0
 elif t<RETURN_END:p,xy,f=travel(t-RETURN_START,DEST,HOME,-1);visible=0
 elif t<TURN_END:p=ink(STAND);xy=HOME;f=-1 if t<RETURN_END+.15 else 1;visible=0
 elif t<REST_END:
  v=(t-TURN_END)/1.4;p=rest(ease(v));xy=HOME;visible=0
  if v<.15:p['points']=mix(STAND,p['points'],ease(v/.15))
 else:p=rest(1,.16*math.sin((t-REST_END)*math.pi*2/2.4));xy=HOME;visible=ease((t-(DURATION-.7))/.55)
 return p,xy,f,visible

def smooth_curve(p,n=5):
 p0=np.roll(p,1,axis=0);p1=p;p2=np.roll(p,-1,axis=0);p3=np.roll(p,-2,axis=0);t=np.linspace(0,1,n,endpoint=False)[None,:,None]
 return (.5*((2*p1[:,None])+(-p0+p2)[:,None]*t+(2*p0-5*p1+4*p2-p3)[:,None]*t*t+(-p0+3*p1-3*p2+p3)[:,None]*t*t*t)).reshape(-1,2)
def sprite(data,facing=1):
 ss=4;ox,oy=18,8;sw,sh=190,126;rgba=np.zeros((sh*ss,sw*ss,4),np.uint8)
 def transform(p):
  q=p.copy();q[:,0]=72+(q[:,0]-72)*facing
  return np.round((q+[ox,oy])*ss).astype('int32')
 def fill(p,col,smooth=True):cv2.fillPoly(rgba,[transform(smooth_curve(p) if smooth else p)],(*col,255),lineType=cv2.LINE_AA)
 def stroke(p,col,width):
  pts=transform(p);cv2.polylines(rgba,[pts],False,(*col,255),max(1,round(width*ss)),cv2.LINE_AA)
  for pt in [pts[0],pts[-1]]:cv2.circle(rgba,tuple(pt),round(width*ss/2),(*col,255),-1,cv2.LINE_AA)
 p=data['points'];fill(p[:160],CREAM)
 if 'arm_line' in data:stroke(data['arm_line'],CREAM,11)
 if 'tail' in data:
  tail=data['tail'];w=data['tail_width'];s=data['tail_seam']
  # The subtle inside edge shows the wrap without a pasted-on outline.
  if s>0:stroke(tail[8:],tuple(int(x) for x in mix(CREAM,SEAM,s)),w+1.5*s)
  stroke(tail,CREAM,w)
 for start in [160,180,200]:fill(p[start:start+20],INK)
 alpha=rgba[:,:,3:4].astype(float)/255;prem=rgba[:,:,:3]*alpha
 alpha=cv2.resize(alpha,(sw,sh),interpolation=cv2.INTER_AREA)[:,:,None];prem=cv2.resize(prem,(sw,sh),interpolation=cv2.INTER_AREA)
 rgb=np.divide(prem,alpha,out=np.zeros_like(prem),where=alpha>0)
 return np.dstack([rgb,alpha*255]).clip(0,255).astype('uint8'),ox,oy

