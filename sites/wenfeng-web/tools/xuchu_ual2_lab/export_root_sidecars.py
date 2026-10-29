from lab_context import OUTPUT, TOOLS, SOURCE, TARGET, MANIFEST
from pathlib import Path
import sys,json,hashlib
import numpy as np
sys.path.insert(0,str(TOOLS))
from prepare_polearms import Sampler
B=OUTPUT;m=Sampler(B/'xuchu-ual2-family-recoveries.glb');hip=m.names['mixamorig:Hips'];out={"status":"TMP SOURCE ROOT SIDECAR / NOT APPLIED TO CONTROLLER",'model_sha256':hashlib.sha256(m.path.read_bytes()).hexdigest(),'model_world_scale':2.15,'coordinate_space':'GLB Hips local translation in model rig units. Source full authored XYZ; not rebased to arena or controller. Apply model/global basis and scale once when extracting XZ. Keep Hips Y. Target actor collision/root movement not included.','clips':{}}
for alias in ['XuUAL2RegularTwistRig','XuUAL2RegularARecoveryRaw','XuUAL2RegularBRecoveryRaw','XuUAL2RegularARecoveryTwistRig','XuUAL2RegularBRecoveryTwistRig']:
 dur=m.duration(alias);times=np.linspace(0,dur,round(dur*120)+1);vals=np.array([m.pose(alias,float(t))[1][hip][0]for t in times]);delta=vals-vals[0];out['clips'][alias]={'duration':dur,'sample_hz':120,'time_seconds':times.tolist(),'hips_local_translation_xyz_rig':vals.tolist(),'hips_delta_from_clip_start_xyz_rig':delta.tolist(),'start_xyz_rig':vals[0].tolist(),'end_xyz_rig':vals[-1].tolist(),'xz_path_length_m_if_scale2_15':float(np.linalg.norm(np.diff(vals[:,[0,2]],axis=0),axis=1).sum()*2.15)}
path=B/'family-root-motion-120hz.json';path.write_text(json.dumps(out,indent=2));print(path,[(k,v['xz_path_length_m_if_scale2_15'])for k,v in out['clips'].items()])
