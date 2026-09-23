#version 300 es
precision highp float;
// Port of viewer/src/cushion.ts. Executed only to rebuild a cached quarter,
// never for each backdrop frame. Analytic derivatives of the same surface.
layout(location=0) in vec3 parameter; // rho, cos(theta), sin(theta)
uniform vec4 profile;
uniform vec2 coefficients[96];
out vec4 profileData;

void main() {
    float rho=parameter.x;
    if (rho<=0.0) {
        gl_Position=vec4(-1,-1,0,1);
        profileData=vec4(0,0,1,1);
        return;
    }
    vec2 n=normalize(parameter.yz), tangent=vec2(-n.y,n.x);
    vec2 halfSize=profile.xy;
    float radius=profile.z;
    float t=min(halfSize.x/max(n.x,1e-15),halfSize.y/max(n.y,1e-15));
    if(t*n.x>halfSize.x-radius && t*n.y>halfSize.y-radius) {
        vec2 corner=halfSize-radius;
        float cross=n.x*corner.y-n.y*corner.x;
        t=dot(n,corner)+sqrt(max(0.0,radius*radius-cross*cross));
    }
    vec2 boundary=t*n;
    vec2 q=boundary-halfSize+radius, outside=max(q,vec2(0));
    vec2 outward=length(outside)>1e-7 ? normalize(outside)
        : (q.x>q.y?vec2(1,0):vec2(0,1));
    vec2 boundaryT=t*(tangent-n*dot(outward,tangent)/max(dot(outward,n),1e-9));
    vec2 cs=n, cs2=vec2(n.x*n.x-n.y*n.y,2.0*n.x*n.y);
    vec2 p=vec2(0), pr=vec2(0), pt=vec2(0), sum=vec2(0), sumT=vec2(0);
    float power=1.0, r2=rho*rho;
    for(int i=0;i<96;i++) {
        float order=float(2*i+1);
        vec2 value=coefficients[i]*cs;
        vec2 derivative=order*coefficients[i]*vec2(-cs.y,cs.x);
        p+=rho*power*value;
        pr+=order*power*value;
        pt+=rho*power*derivative;
        sum+=value; sumT+=derivative;
        power*=r2;
        cs=vec2(cs.x*cs2.x-cs.y*cs2.y,cs.y*cs2.x+cs.x*cs2.y);
    }
    p+=rho*power*(boundary-sum);
    pr+=193.0*power*(boundary-sum);
    pt+=rho*power*(boundaryT-sumT);
    // Cache the smooth squared-height potential and its half-gradient, not
    // unit normals: bilinear interpolation then stays faithful at tight rims.
    float determinant=max(pr.x*pt.y-pr.y*pt.x,1e-12);
    profileData=vec4(rho*vec2(pt.y,-pt.x)/determinant,1.0,max(0.0,1.0-r2));
    gl_Position=vec4(p/halfSize*2.0-1.0,0,1);
}
