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
    float mist = u.weather>1.5 ? (.05+.26*u.intensity)*smoothstep(.2,.9,fog) : .014*u.intensity*fog;
    mist *= .5+.5*smoothstep(.25,1.0,uv.y);
    float3 tint=u.weather>.5 ? float3(.74,.81,.85) : float3(.53,.65,.71);
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
        float speed=mix(380.0,1680.0,depth)*(0.8+u.intensity*.4);
        float gust=sin(t*.43)*.65+sin(t*.91+1.4)*.35;
        float slope=.025+u.wind*(.28+gust*.12);
        float travel=t*speed;
        p.y=fmod(r1*(u.size.y+180)+travel,u.size.y+180)-90;
        p.x=fmod(r2*(u.size.x+400)+travel*slope+sin(t*.35)*u.wind*20,u.size.x+400)-200;
        extent=float2(mix(.45,1.45,depth),mix(6.0,27.0,depth)*(0.65+r3*.7));
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
        float width=exp(-in.uv.x*in.uv.x*3.8);
        float tail=pow(max(0.0,1.0-abs(in.uv.y)),.55);
        alpha=width*tail*mix(.12,.52,in.depth)*(.65+in.seed*.55);
        tint=mix(float3(.62,.75,.82),float3(.89,.95,1),in.depth);
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
    float cold=u.weather>.5 && u.weather<1.5 ? 1.0 : .13;
    float corners=1-smoothstep(.0,.12+grain*.05,edge);
    float frost=corners*cold*(.075+.17*u.intensity)*(.55+grain*.45);
    float blur=(u.hasPhoto>.5 ? (.30+frost*15) : 0.0);
    if (blur>.01) {
        float2 px=blur/u.size;
        float4 soft=(scene.sample(s,uv+float2(px.x,px.y))+scene.sample(s,uv-float2(px.x,px.y))+
                     scene.sample(s,uv+float2(-px.x,px.y))+scene.sample(s,uv+float2(px.x,-px.y)))*.25;
        color=mix(color,soft,.5+frost);
    }
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
    constexpr sampler s(coord::normalized, address::clamp_to_edge, filter::linear);
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
    if (in.kind>1.5) {
        // Short, scattered satellite drops at contact, never a flashing full ring.
        float r=length(q), a=atan2(q.y,q.x);
        float dots=pow(max(0.0,sin(a*7+in.seed*19)),16.0);
        float alpha=exp(-pow((r-.67)*24,2.0))*dots*fade*.65;
        return float4(float3(.82,.91,.98)*alpha,alpha);
    }
    if (in.kind>.5) {
        float mask=(1-smoothstep(.25,1.0,abs(q.x)))*(1-smoothstep(.72,1.0,abs(q.y)))*fade;
        float2 right=float2(in.axis.y,-in.axis.x);
        float2 offset=right*q.x*in.extent.x*1.5/u.size;
        float4 wet=scene.sample(s,in.screenUV+offset)*mask*(u.hasPhoto>.5 ? .58 : .12);
        float glint=exp(-pow((q.x+.48)*9,2.0))*mask*.055;
        return overTint(wet,float3(.78,.88,.93),glint);
    }
    // Convex, slightly pear-shaped lenses with a bright rim and a shaded underside.
    q.x*=1.0-.13*q.y;
    float r=length(q);
    float mask=(1-smoothstep(.83,1.0,r))*fade;
    if (mask<.001) return float4(0);
    float2 normal=q/sqrt(max(.13,1-dot(q,q)*.8));
    float2 offset=(-q*4.6+normal*.35)*in.extent/u.size;
    float4 lens=scene.sample(s,in.screenUV+offset);
    float rim=exp(-pow((r-.83)*15,2.0));
    float light=max(0.0,dot(normalize(float2(-.55,-.83)),q/max(.001,r)));
    float shadow=max(0.0,dot(normalize(float2(.35,.94)),q/max(.001,r)));
    float spot=exp(-dot((q-float2(-.28,-.43))*float2(15,22),(q-float2(-.28,-.43))*float2(15,22)));
    if (u.hasPhoto>.5) {
        lens.rgb*=1.0-rim*shadow*.27;
        lens*=mask;
    } else {
        lens*=mask*.18;
        lens=overTint(lens,float3(.06,.10,.12),rim*shadow*mask*.12);
    }
    float shine=(rim*(.035+light*.32)+spot*.48)*mask;
    return overTint(lens,float3(.90,.96,1.0),shine);
}
