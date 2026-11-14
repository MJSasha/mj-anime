from pathlib import Path
import re,json,os
import numpy as np
p=Path(os.environ['UPSCALER_TEST_OUTPUT'])
models=Path(os.environ['UPSCALER_MODELS'])
rgba=np.frombuffer((p/'small.rgba').read_bytes(),np.uint8).reshape(18,32,4).astype(np.float32)/255
h,w=rgba.shape[:2]
def bilinear(a,ow,oh):
 yy=np.clip((np.arange(oh)+.5)*a.shape[0]/oh-.5,0,a.shape[0]-1);xx=np.clip((np.arange(ow)+.5)*a.shape[1]/ow-.5,0,a.shape[1]-1)
 y=np.floor(yy).astype(int);x=np.floor(xx).astype(int);dy=(yy-y)[:,None,None];dx=(xx-x)[None,:,None]
 y1=np.minimum(y+1,a.shape[0]-1);x1=np.minimum(x+1,a.shape[1]-1)
 return (a[y[:,None],x[None,:]]*(1-dx)+a[y[:,None],x1[None,:]]*dx)*(1-dy)+(a[y1[:,None],x[None,:]]*(1-dx)+a[y1[:,None],x1[None,:]]*dx)*dy
stats={}
for model in ['S','M']:
 blocks=re.split(r'(?=//!DESC)',(models/f'Anime4K_Upscale_CNN_x2_{model}.glsl').read_text())[1:];values={'MAIN':rgba}
 for i,b in enumerate(blocks[:-1]):
  refs={}
  for line in b.splitlines():
   if line.startswith('#define '):
    name=re.search(r'#define (\w+)',line).group(1)
    source=re.search(r'(\w+)_tex(?:Off)?\(',line).group(1)
    a=values[source]
    if 'max(-' in line:a=np.maximum(-a,0)
    elif 'max(' in line:a=np.maximum(a,0)
    refs[name]=a
  result=np.zeros((h,w,4),np.float32)
  for coeff,name,offset in re.findall(r'mat4\(([^)]+)\)\s*\*\s*(\w+)(\([^;]*\))?;',b):
   mat=np.array([float(n.strip()) for n in coeff.split(',')],np.float32).reshape(4,4,order='F')
   a=refs[name]
   if offset:
    ox,oy=[int(float(n)) for n in re.findall(r'-?\d+\.\d+',offset)]
    a=np.pad(a,((1,1),(1,1),(0,0)),mode='edge')[1+oy:1+oy+h,1+ox:1+ox+w]
   result+=np.einsum('ij,hwj->hwi',mat,a)
  bias=re.findall(r'result\s*\+=\s*vec4\(([^)]+)\)',b)
  assert len(bias)==1
  result+=np.array([float(n.strip()) for n in bias[0].split(',')],np.float32)
  # Android stores signed CNN activations in FP16; never clamp to RGBA8.
  values[re.search(r'^//!SAVE (\w+)',b,re.M).group(1)]=result.astype(np.float16).astype(np.float32)
 features=values['conv2d_last_tf'];detail=np.empty((h*2,w*2))
 for yy in range(2):
  for xx in range(2):detail[yy::2,xx::2]=features[:,:,yy*2+xx]
 reference=np.clip(bilinear(rgba,w*2,h*2)[:,:,:3]+detail[:,:,None],0,1)
 reference=np.round(reference*255).astype(np.uint8)
 gpu=np.frombuffer((p/f'small-cnn_{model.lower()}.rgba').read_bytes(),np.uint8).reshape(h*2,w*2,4)
 delta=np.abs(reference.astype(float)-gpu[:,:,:3])
 assert gpu[:,:,3].min()==255,'Output alpha changed'
 assert delta.mean()<1 and delta.max()<=5,(model,delta.mean(),delta.max())
 stats[model]={'gpu_passes':len(blocks),'mean_channel_error_vs_original_weights':float(delta.mean()),'maximum_channel_error_8bit':float(delta.max())}
print(json.dumps(stats,indent=2));(p/'validation.json').write_text(json.dumps(stats,indent=2))
