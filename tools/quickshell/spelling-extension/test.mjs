// Exercise the actual extension in a private headless Chrome profile.
// The debugging flag is only used to load the extension into this test profile.
import assert from 'node:assert/strict';
import {spawn} from 'node:child_process';
import {mkdtemp, mkdir, readFile, writeFile, rm} from 'node:fs/promises';
import {createServer} from 'node:http';
import path from 'node:path';
const extension = process.env.SPELLING_EXTENSION;
assert.ok(extension, 'Set SPELLING_EXTENSION to the packaged extension directory');
const expectedID = 'lkehjbmnpkpjchfanhgipcgokeknepkn';
const directory = await mkdtemp('/tmp/qwen-extension-test-');
const profile = path.join(directory, 'profile');
const delay = ms => new Promise(resolve => setTimeout(resolve, ms));
let browser, assistant, reports = [], stderr = '', socket, realHost = false, expectedCorrections = 0;
if (process.env.SPELLING_ASSISTANT) {
 assistant = spawn(process.env.SPELLING_ASSISTANT, ['--stdio'], {env:{...process.env,XDG_RUNTIME_DIR:directory,XDG_STATE_HOME:directory},detached:true,stdio:['pipe','pipe','ignore']});
 let buffer='';assistant.stdout.on('data',chunk=>{buffer+=chunk;let i;while((i=buffer.indexOf('\n'))>=0){try{const item=JSON.parse(buffer.slice(0,i));if(item.event==='correctionChanged')reports.push(item.data)}catch{}buffer=buffer.slice(i+1)}});
}
async function until(check, label, timeout = 15000) {
  const deadline = Date.now() + timeout;
  while (Date.now() < deadline) { try { const value = await check(); if (value) return value; } catch {} await delay(50); }
  throw Error('Timeout: ' + label + '\n' + stderr.slice(-1200));
}
const server = createServer((request, response) => {
  response.setHeader('Content-Type', 'text/html; charset=utf-8');
  response.end(`<!doctype html><meta charset="utf-8"><form id="form">
    <textarea id="field" autofocus>Les fille 😂</textarea><input id="other" value="Autre champ">
    <input id="password" type="password" value="synthetic-test-password">
    <div id="rich" contenteditable><p><b>Les fille</b> sont là.</p><p>Deuxième ligne 🙂</p></div>
    </form><script>
      window.submissions=0;window.changes=0;window.keys=[];
      document.querySelector('form').onsubmit=e=>{e.preventDefault();submissions++};
      document.querySelector('#field').addEventListener('input',()=>changes++);
      document.addEventListener('keydown',e=>keys.push({key:e.key,ctrl:e.ctrlKey,alt:e.altKey,trusted:e.isTrusted}),true);
    </script>`);
});
await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
try {
  await mkdir(path.join(profile, 'NativeMessagingHosts'), {recursive: true});
  const host = path.join(directory, 'host.cjs');
  await writeFile(host, `#!${process.execPath}\nconst fs=require('node:fs');let data=Buffer.alloc(0);process.stdin.on('data',chunk=>{
    data=Buffer.concat([data,chunk]);if(data.length<4||data.length<4+data.readUInt32LE(0))return;
    const req=JSON.parse(data.subarray(4,4+data.readUInt32LE(0)));process.stdin.pause();
    fs.appendFileSync(${JSON.stringify(path.join(directory,'requests.log'))},JSON.stringify({action:req.action,provider:req.provider,id:req.reportId,status:req.status})+'\\n');
    const base=${JSON.stringify(path.join(directory,'review-'))}+encodeURIComponent(req.reportId);
    const decision=()=>fs.existsSync(base)?fs.readFileSync(base,'utf8'):'';
    function reply(result){const payload=Buffer.from(JSON.stringify({ok:true,result}));const size=Buffer.alloc(4);size.writeUInt32LE(payload.length);process.stdout.write(Buffer.concat([size,payload]),()=>process.exit(0));}
    if(req.action==='status'){reply({});return;}
    if(req.action==='decide'){
      if(!decision()&&(req.status==='reject'||fs.existsSync(base+'.ready')))fs.writeFileSync(base,req.status);
      reply({decision:decision()});return;
    }
    if(req.action==='wait'){const poll=setInterval(()=>{if(decision()){clearInterval(poll);reply({decision:decision()});}},10);return;}
    const at=req.text.indexOf('fille'),start=Array.from(req.text.slice(0,at)).length;
    const edits=at<0?[]:[{start,end:start+5,replacement:'filles'}];
    const text=at<0?req.text:req.text.slice(0,at)+'filles'+req.text.slice(at+5);
    setTimeout(()=>{fs.writeFileSync(base+'.ready','1');reply({text,edits,skipped:0,reportId:req.reportId,cancelled:decision()==='reject'})},req.text.includes('attends')?700:20);
  });`, {mode: 0o700});
  await writeFile(path.join(profile, 'NativeMessagingHosts/com.quickshell.spelling.json'), JSON.stringify({
    name:'com.quickshell.spelling', description:'Isolated correction test', path:host, type:'stdio', allowed_origins:[`chrome-extension://${expectedID}/`]
  }));
  browser = spawn('google-chrome-stable', ['--headless=new', '--disable-gpu', '--no-first-run', '--no-default-browser-check',
    '--disable-background-networking', '--disable-component-update', '--disable-sync', '--user-data-dir='+profile,
    '--remote-debugging-port=0', '--enable-unsafe-extension-debugging', 'about:blank'], {env:{...process.env,XDG_RUNTIME_DIR:directory},detached:true,stdio:['ignore','pipe','pipe']});
  for(const stream of [browser.stdout,browser.stderr]) stream.on('data',data=>{stderr=(stderr+data).slice(-4000)});
  const port=await until(async()=>Number((await readFile(path.join(profile,'DevToolsActivePort'),'utf8')).split('\n')[0]),'browser');
  const version=await(await fetch(`http://127.0.0.1:${port}/json/version`)).json();
  socket=new WebSocket(version.webSocketDebuggerUrl);
  await new Promise((resolve,reject)=>{socket.addEventListener('open',resolve,{once:true});socket.addEventListener('error',reject,{once:true})});
  let serial=0;const pending=new Map();
  socket.addEventListener('message',event=>{const message=JSON.parse(event.data);pending.get(message.id)?.(message)});
  function call(method,params={},sessionId) {
    const id=++serial;
    return new Promise((resolve,reject)=>{
      const timer=setTimeout(()=>{pending.delete(id);reject(Error('CDP timeout: '+method))},15000);
      pending.set(id,message=>{clearTimeout(timer);pending.delete(id);if(message.error)reject(Error(JSON.stringify(message.error)));else resolve(message.result)});
      socket.send(JSON.stringify({id,method,params,sessionId}));
    });
  }
  const installed=await call('Extensions.loadUnpacked',{path:extension});
  assert.equal(installed.id,expectedID);
  const {targetId}=await call('Target.createTarget',{url:`http://127.0.0.1:${server.address().port}/`});
  const {sessionId}=await call('Target.attachToTarget',{targetId,flatten:true});
  const evaluate=async expression=>{
    const response=await call('Runtime.evaluate',{expression,returnByValue:true,awaitPromise:true},sessionId);
    if(response.exceptionDetails)throw Error(JSON.stringify(response.exceptionDetails));
    return response.result.value;
  };
  await call('Page.bringToFront',{},sessionId);
  await until(()=>evaluate('!!document.querySelector("#field")'),'page');await delay(300);
  async function shortcut(undo=false, provider='qwen') {
    if(!undo)++expectedCorrections;
    const params={key:'Tab',code:'Tab',windowsVirtualKeyCode:9,modifiers:(undo?8:0)+(provider==='openai'?1:3)};
    await call('Input.dispatchKeyEvent',{...params,type:'keyDown'},sessionId);
    await call('Input.dispatchKeyEvent',{...params,type:'keyUp'},sessionId);
  }
  async function reviewKey(key) {
    const params={key,code:key,windowsVirtualKeyCode:key==='Enter'?13:27};
    await call('Input.dispatchKeyEvent',{...params,type:'keyDown'},sessionId);
    await call('Input.dispatchKeyEvent',{...params,type:'keyUp'},sessionId);
  }
  async function ready() {
    if(realHost) { await until(()=>reports.at(-1)?.state==='ready','real preview',75000);return; }
    await until(async()=>{
      const log=(await readFile(path.join(directory,'requests.log'),'utf8')).trim().split('\n').map(line=>JSON.parse(line));
      const corrections=log.filter(r=>r.action==='correct');
      if(corrections.length<expectedCorrections)return false;
      const id=corrections.at(-1)?.id;
      return id&&log.some(r=>r.id===id&&r.action==='wait');
    },'preview ready');
  }
  async function accept() {await ready();await reviewKey('Enter');}
  const text=()=>evaluate('document.querySelector("#field").value');
  await evaluate('document.querySelector("#field").focus()');
  await shortcut();await ready();assert.equal(await text(),'Les fille 😂','Preview must not change the field');
  await reviewKey('Enter');
  await until(async()=>await text()==='Les filles 😂','keyboard correction');
  assert.equal(await evaluate('window.submissions'),0);
  assert.equal(await evaluate('window.changes'),1);
  await shortcut(true);await until(async()=>await text()==='Les fille 😂','undo');

  await evaluate(String.raw`{const field=document.querySelector('#field');field.value='Début : les fille\nfin 🙂';field.focus();field.setSelectionRange(8,17)}`);
  await shortcut();await accept();await until(async()=>await text()==='Début : les filles\nfin 🙂','selection only');
  await shortcut(true);assert.equal(await text(),'Début : les fille\nfin 🙂');

  await evaluate("{const field=document.querySelector('#field');field.value='Les fille';field.focus()}");
  await shortcut(false,'openai');await accept();await until(async()=>await text()==='Les filles','GPT shortcut');
  const routed=(await readFile(path.join(directory,'requests.log'),'utf8')).trim().split('\n').map(line=>JSON.parse(line));
  assert.ok(routed.some(r=>r.action==='correct'&&r.provider==='openai'));assert.ok(routed.some(r=>r.action==='correct'&&r.provider==='qwen'));
  assert.equal(await evaluate('!!document.querySelector("[role=status]")'),false);
  await evaluate('document.querySelector("#rich").focus()');
  await shortcut();await accept();
  await until(()=>evaluate('document.querySelector("#rich").innerHTML.includes("<b>Les filles</b>")'),'rich formatting');
  assert.equal(await evaluate('document.querySelector("#rich").innerHTML'),'<p><b>Les filles</b> sont là.</p><p>Deuxième ligne 🙂</p>');
  await shortcut(true);assert.equal(await evaluate('document.querySelector("#rich").innerHTML'),'<p><b>Les fille</b> sont là.</p><p>Deuxième ligne 🙂</p>');

  await evaluate("{const field=document.querySelector('#field');field.value='Les fille';field.focus()}");
  await shortcut();await ready();await reviewKey('Escape');await delay(120);
  assert.equal(await text(),'Les fille','Escape must preserve the source');
  await evaluate("{const field=document.querySelector('#field');field.value='attends les fille';field.focus()}");
  await shortcut();await delay(100);await reviewKey('Enter');await reviewKey('Escape');await delay(850);
  assert.equal(await text(),'attends les fille','Escape during generation must cancel late results');
  // A click on the Quickshell preview may leave this window unfocused.
  await evaluate("{const field=document.querySelector('#field');field.value='Les fille';field.focus()}");
  await shortcut();await ready();
  const requests=(await readFile(path.join(directory,'requests.log'),'utf8')).trim().split('\n').map(line=>JSON.parse(line));
  const reviewID=requests.filter(r=>r.action==='correct').at(-1).id;
  const otherPage=await call('Target.createTarget',{url:'about:blank'});
  const otherSession=await call('Target.attachToTarget',{targetId:otherPage.targetId,flatten:true});
  await call('Page.bringToFront',{},otherSession.sessionId);
  await writeFile(path.join(directory,'review-'+reviewID),'accept');
  await until(async()=>await text()==='Les filles','acceptance from the panel while the browser field is unfocused');
  await call('Target.closeTarget',{targetId:otherPage.targetId});
  await call('Page.bringToFront',{},sessionId);
  assert.equal(await evaluate('window.submissions'),0);
  await evaluate(`{const field=document.querySelector('#field');field.value='attends les fille';field.focus()}`);
  await shortcut();
  await evaluate(`{const field=document.querySelector('#field');field.value='Mon nouveau texte';field.dispatchEvent(new InputEvent('input',{bubbles:true}))}`);
  await delay(950);assert.equal(await text(),'Mon nouveau texte');
  await evaluate(`{const field=document.querySelector('#field');field.value='attends les fille';field.focus()}`);
  await shortcut();await evaluate('document.querySelector("#other").focus();document.querySelector("#field").focus()');
  await delay(950);assert.equal(await text(),'attends les fille');
  await evaluate('document.querySelector("#password").focus()');await shortcut();await delay(150);
  assert.equal(await evaluate('document.querySelector("#password").value'),'synthetic-test-password');
  console.log('PASS: Chrome preview, Enter/Escape, cancellation during generation, approval while unfocused, Unicode selection, exact undo, preserved HTML, changed-source cancellation and no form submission.');

  if(process.env.SPELLING_REAL_HOST) {
    const manifest=JSON.parse(await readFile(path.join(profile,'NativeMessagingHosts/com.quickshell.spelling.json'),'utf8'));
    manifest.path=process.env.SPELLING_REAL_HOST;realHost=true;
    await writeFile(path.join(profile,'NativeMessagingHosts/com.quickshell.spelling.json'),JSON.stringify(manifest));
    await evaluate(`{const field=document.querySelector('#field');field.value='Les fille sont aller au cinema 😂';field.focus()}`);
    await shortcut();await accept();await until(async()=>await text()==='Les filles sont allées au cinéma 😂','local Qwen correction',45000);
    await shortcut(true);assert.equal(await text(),'Les fille sont aller au cinema 😂');
    await until(()=>reports.some(r=>r.state==='undone'),'panel report');
    assert.ok(reports.some(r=>r.provider==='qwen'&&r.html?.includes('color:#ed8796')));
    if(process.env.SPELLING_TEST_GPT==='1'){
      await evaluate("{const field=document.querySelector('#field');field.value='Les fille';field.focus()}");
      await shortcut(false,'openai');await accept();await until(async()=>await text()==='Les filles','real GPT correction',75000);
      await until(()=>reports.some(r=>r.provider==='openai'&&r.state==='applied'),'GPT panel report');
    }
    console.log('PASS: real native bridge, provider correction and panel report, followed by exact undo.');
  }
} finally {
  socket?.close();server.close();
  if(assistant?.pid){assistant.stdin.end();try{process.kill(-assistant.pid,'SIGTERM')}catch{}await delay(300);try{process.kill(-assistant.pid,'SIGKILL')}catch{}}
  if(browser?.pid){try{process.kill(-browser.pid,'SIGTERM')}catch{}await delay(300);try{process.kill(-browser.pid,'SIGKILL')}catch{}}
  await rm(directory,{recursive:true,force:true,maxRetries:10,retryDelay:100});
}
