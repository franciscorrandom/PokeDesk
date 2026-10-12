const clamp=v=>Math.min(1,Math.max(0,Number.isFinite(v)?v:0));
const smooth=v=>{const x=clamp(v);return x*x*x*(x*(x*6-15)+10);};
const ramp=(t,a,b)=>smooth((t-a)/(b-a));
export const durations={release:2.35,recall:1.85};
export function summonFrame(phase,time) {
  const t=Math.min(durations[phase],Math.max(0,Number.isFinite(time)?time:0)),r=ramp;
  return phase==='release'?{
    petAmount:r(t,.78,1.56),petOpacity:r(t,.78,.96),whiten:(1-r(t,1.40,1.96))*r(t,.65,.82),
    lidOpen:r(t,.38,.78)*(1-r(t,1.68,2.02)),ballOpacity:1-r(t,2.02,2.35),ballLift:.45*(1-r(t,0,.38))+.055*Math.sin(Math.PI*r(t,.38,.63)),
    glow:r(t,.55,.83)*(1-r(t,1.35,1.98)),beam:r(t,.72,.88)*(1-r(t,1.36,1.66)),sparks:r(t,.78,1.03)*(1-r(t,1.56,2.14))
  }:{
    petAmount:1-r(t,.60,1.26),petOpacity:1-r(t,1.13,1.28),whiten:r(t,.38,.69)*(1-r(t,1.25,1.50)),
    lidOpen:r(t,.23,.56)*(1-r(t,1.28,1.57)),ballOpacity:1-r(t,1.58,1.85),ballLift:.34*(1-r(t,0,.32))-.16*r(t,1.58,1.85),
    glow:r(t,.37,.67)*(1-r(t,1.24,1.55)),beam:r(t,.44,.65)*(1-r(t,1.17,1.33)),sparks:r(t,.40,.70)*(1-r(t,1.23,1.54))
  };
}
