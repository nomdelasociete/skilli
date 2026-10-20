(()=>{

const vs='attribute vec2 p;varying vec2 uv;void main(){uv=p*.5+.5;gl_Position=vec4(p,0.,1.);}';
const fs=`precision highp float;varying vec2 uv;uniform float t;uniform float mode;uniform float refract;uniform float intensity;
float blob(vec2 p,vec2 c,float r){return exp(-dot(p-c,p-c)*r);}
void main(){vec2 p=uv;float time=t*.38;if(refract>.5){p+=vec2(.10*sin(uv.y*9.+.3),.10*cos(uv.x*6.-.8));}vec3 col;
if(mode<.5){float a=blob(p,vec2(.64+.22*sin(time),.70+.18*cos(time*.8)),5.3+.7*sin(time*.65));float b=blob(p,vec2(.16+.13*cos(time*.75),.18+.18*sin(time*.9)),7.);col=mix(vec3(.015,.09,.13),vec3(.06,.58,.55),a);col+=vec3(.12,.25,.31)*b;float h=blob(p,vec2(.75+.18*sin(time*.85+.7),.86+.12*cos(time*.7)),16.);col+=vec3(.25,.34,.22)*h;}
else if(mode<1.5){float w=sin(p.x*4.+time)+sin(p.y*3.-time*.8);float f=.5+.5*sin(5.*p.x-3.*p.y+w+time*.35);col=mix(vec3(.015,.035,.18),vec3(.04,.3,.72),smoothstep(.0,.8,f));float band=exp(-pow((p.y-.45-.17*sin(p.x*5.+time))*5.,2.));col=mix(col,vec3(.06,.85,.75),band*.7);col+=vec3(.16,.05,.3)*blob(p,vec2(.1,.8),9.);}
else{float w=sin(p.x*6.+time)+cos(p.y*5.-time*.8);col=mix(vec3(.19,.39,.52),vec3(.75,.88,.83),smoothstep(-1.5,1.5,w));col=mix(col,vec3(.56,.43,.72),blob(p,vec2(.85,.7),9.)*.7);float caustic=pow(.5+.5*sin(10.*p.y+4.*p.x+w*1.2+time),12.);col+=vec3(.22,.24,.22)*caustic*.6;}
float grain=fract(sin(dot(gl_FragCoord.xy,vec2(12.9898,78.233)))*43758.5453)-.5;gl_FragColor=vec4(col*intensity+grain*.008,1.);}`;

function mountHalo(hero,stage){
const reduced=matchMedia('(prefers-reduced-motion: reduce)');let visible=true,id=0,last=0,time=3;const resources=[];
function fail(){cancelAnimationFrame(id);stage.classList.remove('shader-ready');hero.classList.remove('halo-ready');}
try{for(const canvas of hero.querySelectorAll('canvas')){const gl=canvas.getContext('webgl',{alpha:false,antialias:false});if(!gl)throw Error('WebGL unavailable');const shaders=[];function compile(type,src){const s=gl.createShader(type);gl.shaderSource(s,src);gl.compileShader(s);if(!gl.getShaderParameter(s,gl.COMPILE_STATUS))throw Error('Shader compile failed');shaders.push(s);return s}const program=gl.createProgram();gl.attachShader(program,compile(gl.VERTEX_SHADER,vs));gl.attachShader(program,compile(gl.FRAGMENT_SHADER,fs));gl.linkProgram(program);if(!gl.getProgramParameter(program,gl.LINK_STATUS))throw Error('Shader link failed');gl.useProgram(program);const buffer=gl.createBuffer();gl.bindBuffer(gl.ARRAY_BUFFER,buffer);gl.bufferData(gl.ARRAY_BUFFER,new Float32Array([-1,-1,1,-1,-1,1,-1,1,1,-1,1,1]),gl.STATIC_DRAW);const p=gl.getAttribLocation(program,'p');gl.enableVertexAttribArray(p);gl.vertexAttribPointer(p,2,gl.FLOAT,false,0,0);gl.uniform1f(gl.getUniformLocation(program,'mode'),0);gl.uniform1f(gl.getUniformLocation(program,'intensity'),hero.classList.contains('freedom')?.38:1);gl.uniform1f(gl.getUniformLocation(program,'refract'),canvas.classList.contains('halo-refraction')?1:0);const t=gl.getUniformLocation(program,'t');resources.push({gl,program,buffer,shaders,draw(){const d=Math.min(devicePixelRatio,2),w=Math.round(canvas.clientWidth*d),h=Math.round(canvas.clientHeight*d);if(canvas.width!==w||canvas.height!==h){canvas.width=w;canvas.height=h;gl.viewport(0,0,w,h)}gl.uniform1f(t,time);gl.drawArrays(gl.TRIANGLES,0,6)}});canvas.addEventListener('webglcontextlost',e=>{e.preventDefault();fail()});}stage.classList.add('shader-ready');hero.classList.add('halo-ready');}catch{fail();return}
function draw(){resources.forEach(r=>r.draw())}function tick(now){time+=Math.min((now-last)/1000,.05);last=now;draw();id=requestAnimationFrame(tick)}
function sync(){cancelAnimationFrame(id);const paused=reduced.matches;draw();if(!paused&&visible&&!document.hidden){last=performance.now();id=requestAnimationFrame(tick)}}
reduced.addEventListener('change',sync);document.addEventListener('visibilitychange',sync);const observer=new IntersectionObserver(entries=>{visible=entries[0].isIntersecting;sync()});observer.observe(hero);const resize=new ResizeObserver(()=>draw());resize.observe(stage);window.addEventListener('pagehide',()=>{cancelAnimationFrame(id);observer.disconnect();resize.disconnect();for(const r of resources){r.shaders.forEach(s=>r.gl.deleteShader(s));r.gl.deleteBuffer(r.buffer);r.gl.deleteProgram(r.program)}});sync();
}
const originalStage=document.querySelector('.brand-stage');
if(originalStage)mountHalo(document.querySelector('.opening'),originalStage);
const freedom=document.querySelector('.freedom');
if(freedom)mountHalo(freedom,freedom);
})();
