import numpy as np
from scipy.optimize import least_squares
from scipy.sparse import coo_matrix

def solve(circles,cap):
 """Minimal world correction, not per-frame closest-angle branch selection."""
 sets=[];ds=[];bounds=[];prev=None;links=[];cost=None
 for C,r,u,v,E,W,l2,f in circles:
  A=np.dot((W-C)/l2,f);B=-r/l2*np.dot(u,f);D=-r/l2*np.dot(v,f);M=np.hypot(B,D);delta=np.arctan2(D,B);minimum=np.arccos(np.clip(A+M,-1,1));alpha=np.arccos(np.clip((np.cos(max(cap,minimum+1e-6))-A)/max(M,1e-12),-1,1))
  candidates=np.r_[np.arange(-np.pi,np.pi, np.deg2rad(2)),delta-alpha,delta+alpha,delta,0.];dot=A+B*np.cos(candidates)+D*np.sin(candidates);keep=dot>=np.cos(max(cap,minimum+1e-6))-1e-8;candidates=candidates[keep];d=C+r*(u[None,:]*np.cos(candidates)[:,None]+v[None,:]*np.sin(candidates)[:,None])-E
  current=np.sum(d*d,axis=1)
  if prev is not None:
   change=50*np.sum((d[:,None,:]-prev[None,:,:])**2,axis=2)+cost[None,:];prior=np.argmin(change,axis=1);current+=change[np.arange(len(d)),prior];links.append(prior)
  sets.append(candidates);ds.append(d);bounds.append((delta,alpha));cost=current;prev=d
 ids=[int(np.argmin(cost))]
 for l in links[::-1]:ids.append(int(l[ids[-1]]))
 ids=ids[::-1];x=np.array([s[i]for s,i in zip(sets,ids)]);low=[];high=[]
 for t,(delta,alpha)in zip(x,bounds):
  delta+=round((t-delta)/(2*np.pi))*2*np.pi;low.append(delta-alpha+1e-9);high.append(delta+alpha-1e-9)
 low=np.array(low);high=np.array(high);high=np.maximum(high,low+1e-10);x=np.clip(x,low+1e-11,high-1e-11);n=len(x)
 def delta_deriv(theta):
  dd=[];jac=[]
  for t,(C,r,u,v,E,*_)in zip(theta,circles):dd.append(C+r*(u*np.cos(t)+v*np.sin(t))-E);jac.append(r*(-u*np.sin(t)+v*np.cos(t)))
  return np.array(dd),np.array(jac)
 def fun(theta):
  d,_=delta_deriv(theta);return np.r_[d.ravel(),np.sqrt(50)*np.diff(d,axis=0).ravel()]
 def jac(theta):
  _,j=delta_deriv(theta);rr=[];cc=[];vv=[]
  for i in range(n):
   for k in range(3):rr.append(i*3+k);cc.append(i);vv.append(j[i,k])
  for i in range(n-1):
   for k in range(3):
    rr.extend([n*3+i*3+k]*2);cc.extend([i,i+1]);vv.extend([-np.sqrt(50)*j[i,k],np.sqrt(50)*j[i+1,k]])
  return coo_matrix((vv,(rr,cc)),shape=(n*3+(n-1)*3,n)).tocsr()
 result=least_squares(fun,x,jac=jac,bounds=(low,high),ftol=1e-9,xtol=1e-9,gtol=1e-9,max_nfev=120)
 return result.x,{'optimization_success':bool(result.success),'cost':float(result.cost),'evaluations':result.nfev,'method':'global dynamic feasible-circle path followed by continuous world-delta least-squares; minimal source-relative elbow displacement plus continuity'}
