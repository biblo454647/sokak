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
    float padding;
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
        float speed=mix(440.0,1380.0,depth)*(0.8+u.intensity*.4);
        float slope=.018+u.wind*.32+sin(t*.22+r1*6.28)*u.wind*.025;
        float travel=t*speed;
        p.y=fmod(r1*(u.size.y+180)+travel,u.size.y+180)-90;
        p.x=fmod(r2*(u.size.x+400)+travel*slope+sin(t*.35)*u.wind*20,u.size.x+400)-200;
        extent=float2(mix(.55,1.25,depth),mix(8.0,32.0,depth)*(0.8+u.intensity*.4));
        p += float2(c.x*extent.x+c.y*extent.y*slope,c.y*extent.y);
    } else {
        float speed=mix(16.0,105.0,depth)*(0.8+r3*.35);
        float travel=t*speed;
        p.y=fmod(r1*(u.size.y+60)+travel,u.size.y+60)-30;
        float sway=sin(t*(.32+r1*.5)+r2*6.28)*(12+depth*24)+sin(t*.18+r3*11)*18;
        p.x=fmod(r2*(u.size.x+200)+t*(10+u.wind*115)*(0.3+depth)+sway,u.size.x+200)-100;
        float radius=mix(.65,4.8,pow(depth,2.0));
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
        alpha=width*tail*mix(.15,.48,in.depth);
        tint=mix(float3(.62,.75,.82),float3(.89,.95,1),in.depth);
    } else {
        float d=length(in.uv);
        float soft=in.depth>.83 ? .1 : .32;
        alpha=(1-smoothstep(soft,1.0,d))*mix(.30,.85,in.depth);
        alpha*=.83+.17*sin(u.time*(.9+in.seed)+in.seed*40);
        tint=float3(.91,.95,1.0);
    }
    return float4(tint*alpha,alpha);
}
