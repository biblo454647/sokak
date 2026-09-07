#include <metal_stdlib>
using namespace metal;

struct Uniforms {
    float2 size;
    float time;
    float weather;
    float intensity;
    float wind;
    float dimming;
    float hasPhoto;
    float2 photoSize;
    float gentle;
    float glass;
    float focus;
    float padding0, padding1, padding2;
};
struct VertexOut {
    float4 position [[position]];
    float2 uv;
    float depth;
    float seed;
};
float hash(float p) { return fract(sin(p * 127.1 + 311.7) * 43758.5453); }
float2 corner(uint vid) {
    const float2 corners[6] = {float2(-1,-1),float2(1,-1),float2(-1,1),float2(-1,1),float2(1,-1),float2(1,1)};
    return corners[vid];
}
vertex VertexOut backgroundVertex(uint vid [[vertex_id]]) {
    VertexOut o; float2 p = corner(vid);
    o.position = float4(p.x, -p.y, 0, 1); o.uv = p * .5 + .5; o.depth = 0; o.seed = 0;
    return o;
}
float noise(float2 p) {
    float2 i=floor(p), f=fract(p); f=f*f*(3.0-2.0*f);
    return mix(mix(hash(i.x+i.y*57), hash(i.x+1+i.y*57),f.x),mix(hash(i.x+(i.y+1)*57),hash(i.x+1+(i.y+1)*57),f.x),f.y);
}
fragment float4 backgroundFragment(VertexOut in [[stage_in]], constant Uniforms &u [[buffer(0)]], texture2d<float> photo [[texture(0)]]) {
    constexpr sampler s(coord::normalized, address::clamp_to_edge, filter::linear);
    float2 uv=in.uv;
    float4 color=float4(0);
    if (u.hasPhoto > .5) {
        float screenAspect=u.size.x/u.size.y, imageAspect=u.photoSize.x/u.photoSize.y;
        float2 scale=screenAspect>imageAspect ? float2(1,imageAspect/screenAspect) : float2(screenAspect/imageAspect,1);
        color=photo.sample(s,(uv-.5)*scale+.5);
        float vignette=1.0-.16*smoothstep(.18,.8,length(uv-.5));
        color.rgb *= (1.0-u.dimming)*vignette;
        color.a=1;
    } else {
        color=float4(0,0,0,u.dimming*.4);
    }
    float drift=u.time*(.018+u.wind*.055);
    float fog=noise(uv*float2(3.2,2.0)+float2(drift,-drift*.2))*.65 + noise(uv*7.0-float2(drift*.6,0))*.35;
    float mist = u.weather>1.5 ? (.05+.26*u.intensity)*smoothstep(.2,.9,fog) : 0.0;
    mist *= .5+.5*smoothstep(.25,1.0,uv.y);
    float3 tint=float3(.74,.81,.85);
    color.rgb=color.rgb*(1-mist)+tint*mist;
    color.a=color.a+(1-color.a)*mist;
    return color;
}

vertex VertexOut particleVertex(uint vid [[vertex_id]], uint iid [[instance_id]], constant Uniforms &u [[buffer(0)]]) {
    VertexOut o;
    float seed=float(iid)+17.0;
    float depth=pow(hash(seed+4.2),1.55);
    float r1=hash(seed+21), r2=hash(seed+7.7), r3=hash(seed+33.3);
    float2 c=corner(vid);
    float t=u.time*(u.gentle>.5 ? .65 : 1.0);
    float2 p, extent;
    if (u.weather < .5) {
        // A new position, depth and shape at each off-screen birth. There is no
        // wrapping sheet of identical streaks and no synchronised gust cycle.
        float duration=mix(7.0,18.0,r1);
        float life=t/duration+r2;
        float generation=floor(life), phase=fract(life);
        float birth=seed+generation*73.71;
        depth=pow(hash(birth+5),1.6);
        r3=hash(birth+27);
        float gust=noise(float2(t*.045,seed*.007));
        float slope=(hash(birth+12)-.5)*.045+u.wind*(.08+gust*.13);
        p.y=phase*(u.size.y+160)-80;
        p.x=hash(birth+44)*(u.size.x+320)-160+phase*u.size.y*slope;
        // Density, width and contrast all respond to intensity; speed stays calm.
        extent=float2(mix(.95,2.3,depth)*mix(.8,1.25,u.intensity),
                      mix(3.2,10.5,depth)*(.7+r3*.5)*mix(.9,1.15,u.intensity));
        p += float2(c.x*extent.x+c.y*extent.y*slope,c.y*extent.y);
    } else {
        float speed=mix(13.0,122.0,depth)*(0.65+r3*.6);
        float travel=t*speed;
        p.y=fmod(r1*(u.size.y+100)+travel+sin(t*.7+r3*16)*depth*14,u.size.y+100)-50;
        float sway=sin(t*(.32+r1*.5)+r2*6.28)*(15+depth*52)+sin(t*.23+r3*11)*(12+u.wind*30);
        float gust=sin(t*.38)*u.wind*55*(.3+depth);
        p.x=fmod(r2*(u.size.x+240)+t*(5+u.wind*96)*(0.3+depth)+sway+gust+240,u.size.x+240)-120;
        float radius=mix(.6,3.7,pow(depth,1.8))+smoothstep(.88,1.0,depth)*8;
        extent=float2(radius*(.8+r1*.5),radius);
        p+=c*extent;
    }
    o.position=float4(p.x/u.size.x*2-1,1-p.y/u.size.y*2,0,1);
    o.uv=c; o.depth=depth; o.seed=r3;
    return o;
}
fragment float4 particleFragment(VertexOut in [[stage_in]], constant Uniforms &u [[buffer(0)]]) {
    float alpha;
    float3 tint;
    if (u.weather<.5) {
        float soft=exp(-dot(in.uv*float2(1.45,1.1),in.uv*float2(1.45,1.1)));
        soft*=1-smoothstep(.7,1.0,max(abs(in.uv.x),abs(in.uv.y)));
        alpha=soft*mix(.10,.40,in.depth)*(.7+in.seed*.3)*mix(.65,1.2,u.intensity);
        tint=float3(.84,.86,.87);
    } else {
        float d=length(in.uv);
        float near=smoothstep(.84,1.0,in.depth);
        float core=mix(1-smoothstep(.18,.95,d),exp(-d*d*4.5)*(1-smoothstep(.75,1.0,d)),near);
        alpha=core*mix(mix(.26,.86,in.depth),.27,near);
        alpha*=.88+.12*sin(u.time*(.9+in.seed)+in.seed*40);
        tint=float3(.91,.95,1.0);
    }
    return float4(tint*alpha,alpha);
}

// Only the app's own weather/photograph pass is sampled. No desktop pixels are read.
fragment float4 paneFragment(VertexOut in [[stage_in]], constant Uniforms &u [[buffer(0)]], texture2d<float> scene [[texture(0)]]) {
    constexpr sampler s(coord::normalized, address::clamp_to_edge, filter::linear);
    float2 uv=in.uv;
    float4 color=scene.sample(s,uv);
    if (u.glass < .5) return color;
    float edge=min(min(uv.x,1-uv.x),min(uv.y,1-uv.y));
    float grain=noise(uv*u.size/17.0)*.65+noise(uv*u.size/4.0)*.35;
    float cold=u.weather>.5 && u.weather<1.5 ? 1.0 : 0.0;
    float corners=1-smoothstep(.0,.12+grain*.05,edge);
    float frost=corners*cold*(.075+.17*u.intensity)*(.55+grain*.45);
    // A bounded soft focus keeps photograph details and original colours visible.
    // Droplets below still sample the sharp exterior, like little convex lenses.
    float3 ice=float3(.77,.85,.89);
    color=float4(color.rgb*(1-frost)+ice*frost,color.a+(1-color.a)*frost);
    return color;
}

struct GlassSprite {
    float2 center;
    float2 extent;
    float2 axis;
    float age;
    float seed;
    float kind;
    float opacity;
    float2 padding;
};
struct GlassOut {
    float4 position [[position]];
    float2 local;
    float2 screenUV;
    float2 extent;
    float2 axis;
    float age;
    float seed;
    float kind;
    float opacity;
};
vertex GlassOut glassVertex(uint vid [[vertex_id]], uint iid [[instance_id]],
                           constant Uniforms &u [[buffer(0)]], device const GlassSprite *sprites [[buffer(1)]]) {
    GlassSprite d=sprites[iid];
    float2 c=corner(vid), right=float2(d.axis.y,-d.axis.x);
    float2 p=d.center+right*c.x*d.extent.x+d.axis*c.y*d.extent.y;
    GlassOut o;
    o.position=float4(p.x/u.size.x*2-1,1-p.y/u.size.y*2,0,1);
    o.local=c; o.screenUV=p/u.size; o.extent=d.extent; o.axis=d.axis;
    o.age=d.age; o.seed=d.seed; o.kind=d.kind; o.opacity=d.opacity;
    return o;
}
float4 overTint(float4 base, float3 tint, float alpha) {
    return float4(base.rgb*(1-alpha)+tint*alpha,base.a+(1-base.a)*alpha);
}
fragment float4 glassFragment(GlassOut in [[stage_in]], constant Uniforms &u [[buffer(0)]], texture2d<float> scene [[texture(0)]]) {
    constexpr sampler s(coord::normalized, address::clamp_to_edge, filter::linear, mip_filter::linear);
    float2 q=in.local;
    float fade=in.opacity;
    if (in.kind>2.5) {
        // A few flakes catch the pane and slowly melt; most snow remains outside.
        float r=length(q), a=atan2(q.y,q.x)+in.seed*6.28;
        float grain=noise(q*15+in.seed*90);
        float crystal=exp(-r*r*4.2)*(.55+.45*pow(max(0.0,cos(a*6)),6.0));
        float alpha=crystal*(.45+grain*.55)*fade*.7*(1-smoothstep(.75,1.0,r));
        alpha*=smoothstep(0.0,.12,in.age);
        return float4(float3(.88,.94,.98)*alpha,alpha);
    }
    if (in.kind>.5) {
        float mask=(1-smoothstep(.25,1.0,abs(q.x)))*(1-smoothstep(.72,1.0,abs(q.y)))*fade;
        float2 right=float2(in.axis.y,-in.axis.x);
        float2 offset=right*q.x*in.extent.x*1.5/u.size;
        float4 wet=scene.sample(s,in.screenUV+offset)*mask*(u.hasPhoto>.5 ? .12 : .025);
        float glint=exp(-pow((q.x+.48)*9,2.0))*mask*.045;
        return overTint(wet,float3(.78,.88,.93),glint);
    }
    // A pinned water bead: a soft, imperfect contact boundary; inverted exterior;
    // total internal reflection in the upper crescent and a bright lower caustic.
    // Small beads are spherical; only the heavier, sliding ones have a pear shape.
    float weight=smoothstep(3.0,12.0,in.extent.x);
    q.x*=1.0-(.025+weight*.045)*q.y;
    float angle=atan2(q.y,q.x);
    float distortion=(sin(angle*3+in.seed*61)*.011+sin(angle*5-in.seed*37)*.007)*weight;
    float r=length(q)+distortion;
    float aa=max(fwidth(r)*.85,.012);
    float mask=(1-smoothstep(.94-aa,.94+aa,r))*fade;
    if (mask<.001) return float4(0);
    float2 center=in.screenUV-in.local*in.extent/u.size;
    float bend=1.0+pow(clamp(r,0.0,1.0),3.0)*1.8;
    float2 lensUV=center-q*float2(.065,.095)*bend*(.8+in.seed*.35);
    float3 refracted=scene.sample(s,clamp(lensUV,.001,.999)).rgb;
    float3 sky=scene.sample(s,float2(clamp(center.x-q.x*.12,.02,.98),.08+(.9-r)*.08)).rgb;
    float3 ground=scene.sample(s,float2(clamp(center.x+q.x*.08,.02,.98),.82+q.y*.08)).rgb;
    float rim=exp(-pow((r-.865)/.057,2.0));
    float inner=exp(-pow((r-.75)/.12,2.0));
    float upper=1-smoothstep(-.6,.25,q.y);
    float lower=smoothstep(.12,.8,q.y);
    float fresnel=pow(clamp(r/.96,0.0,1.0),6.0);
    float3 optical=mix(refracted,ground*.18,fresnel*.85);
    optical*=1.0-upper*(.46+inner*.4);
    float caustic=exp(-pow((q.y-(.50-.16*q.x*q.x))/.12,2.0))*(1-smoothstep(.38,.85,abs(q.x)));
    optical=mix(optical,sky*.88+float3(.12),caustic*.8);
    float fineRim=exp(-pow((r-.914)/max(.019,aa*.55),2.0));
    float shine=(fineRim*(.10+.60*lower)+rim*lower*.20)*(.75+in.seed*.25);
    float spot=exp(-dot((q-float2(-.32,-.63))*float2(15,24),(q-float2(-.32,-.63))*float2(15,24)))*.24;
    float4 lens;
    if (u.hasPhoto>.5) {
        lens=float4(optical*mask,mask);
        return overTint(lens,clamp(sky*.6+.42,0.0,1.0),(shine+spot)*mask);
    } else {
        // A transparent pane never reads other apps' pixels. Paired dark and
        // bright menisci remain legible over both light and dark desktop content.
        float shadow=(rim*(.24+upper*.42)+inner*upper*.20)*mask;
        lens=float4(float3(.012,.019,.023)*shadow,shadow);
        float light=(shine*.90+caustic*.23+spot)*mask;
        return overTint(lens,float3(.91,.95,.97),light);
    }
}
