const {test}=require('node:test');
const assert=require('node:assert/strict');
const fs=require('node:fs');
const path=require('node:path');
const Module=require('node:module');
const ts=require('typescript');
const {NextRequest}=require('next/server');
const source=path.resolve(__dirname,'../app/api/guest/route.ts');
const compiled=ts.transpileModule(fs.readFileSync(source,'utf8'),{compilerOptions:{module:ts.ModuleKind.CommonJS,target:ts.ScriptTarget.ES2022}}).outputText;
const moduleUnderTest=new Module(source,module);
moduleUnderTest.paths=Module._nodeModulePaths(path.dirname(source));
moduleUnderTest._compile(compiled,source);
const {POST}=moduleUnderTest.exports;

test('guest proxy enforces origin, session and action boundaries and hides tokens',async()=>{
 const originalFetch=global.fetch;
 const originalBase=process.env.API_INTERNAL_URL;
 process.env.API_INTERNAL_URL='https://backend.example';
 let calls=[];
 global.fetch=async(url,options)=>{calls.push({url,options});return Response.json({access_token:'private-access',refresh_token:'private-refresh',expires_in:3600,user:{display_name:'Guest'}});};
 function request(body,origin='https://sendoh.example',cookie=''){
  return new NextRequest('https://sendoh.example/api/guest',{method:'POST',headers:{Origin:origin,'Content-Type':'application/json',...(cookie?{Cookie:cookie}:{})},body:JSON.stringify(body)});
 }
 try {
  assert.equal((await POST(request({action:'code'},'https://attacker.example'))).status,403);
  assert.equal((await POST(request({action:'context',token:'collection'}))).status,401);
  assert.equal(calls.length,0);
  const response=await POST(request({action:'verify',phone:'+237690123456',code:'123456',challenge_id:'challenge'}));
  const value=await response.json();
  assert.deepEqual(value,{user:{display_name:'Guest'}});
  assert.match(response.headers.get('set-cookie'),/HttpOnly/i);
  assert.match(response.headers.get('set-cookie'),/Secure/i);
  assert.match(response.headers.get('set-cookie'),/SameSite=strict/i);
  assert.equal(calls[0].options.headers.Authorization,undefined);
  await POST(request({action:'context',token:'a/b'},undefined,'sendoh_guest_session=private-access'));
  assert.equal(calls[1].url,'https://backend.example/api/v1/me/guest-collections/a%2Fb');
  assert.equal(calls[1].options.headers.Authorization,'Bearer private-access');
  assert.equal((await POST(request({action:'admin'},undefined,'sendoh_guest_session=private-access'))).status,400);
  assert.equal(calls.length,2);
  const logout=await POST(request({action:'logout'},undefined,'sendoh_guest_session=private-access'));
  assert.match(logout.headers.get('set-cookie'),/Expires=Thu, 01 Jan 1970/i);
 }finally{global.fetch=originalFetch;if(originalBase===undefined)delete process.env.API_INTERNAL_URL;else process.env.API_INTERNAL_URL=originalBase;}
});
