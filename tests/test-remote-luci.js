// LuCI 家长设备列表模拟 DOM：显示每个设备，并只传入白名单设备标识进行单台撤销。
'use strict';
const assert=require('assert');
const fs=require('fs');
const source=fs.readFileSync('htdocs/luci-static/resources/view/tvguard/remote.js','utf8');
function E(tag,attrs,children){
    const obj={tag,attrs:attrs||{},children:[],style:{},disabled:false,textContent:'',href:'',removeAttribute(k){delete this[k]},
        appendChild(item){this.children.push(item)},
        replaceChildren(...items){this.children=items}};
    if(children!==undefined)obj.children=Array.isArray(children)?children:[children];
    return obj;
}
const devices=[
 {id:'0123456789abcdef',name:'iPhone Chrome',paired_at:1795000000,expires:0},
 {id:'fedcba9876543210',name:'iPad Browser',paired_at:0,expires:0}
];
let state={enabled:true,listener:true,lan_enabled:true,lan_url:'http://192.168.101.99:18765/',paired:2,devices};
const calls=[];
const exec={exec:async(path,args)=>{
    calls.push({path,args});
    if(path.includes('-manage')){
        if(args[0]==='rename-device'){
            assert.strictEqual(args.length,3);
            assert(/^[0-9a-f]{16}$/.test(args[1]));
            state={...state,devices:state.devices.map(d=>d.id===args[1]?{...d,label:args[2]}:d)};
        }
        if(args[0]==='revoke-device'){
            assert.strictEqual(args.length,2);
            assert(/^[0-9a-f]{16}$/.test(args[1]));
            state={...state,devices:state.devices.filter(d=>d.id!==args[1]),paired:1};
        }
        return {code:0,stdout:'撤销成功',stderr:''};
    }
    return {code:0,stdout:JSON.stringify(state),stderr:''};
}};
const notices=[];
const ui={addNotification:(_,element,level)=>notices.push({element,level})};
const view={extend:x=>x};
const window={confirm:()=>true};
const page=new Function('view','fs','ui','E','window',source)(view,exec,ui,E,window);
const dom=page.render(state);
function gather(root,pred,result=[]){
    if(root&&typeof root==='object'){
        if(pred(root))result.push(root);
        for(const c of root.children||[])gather(c,pred,result);
    }
    return result;
}
function texts(root){
    return gather(root,x=>typeof x==='object').flatMap(x=>[
        ...(typeof x.textContent==='string'?[x.textContent]:[]),
        ...(x.children||[]).filter(c=>typeof c==='string')]);
}
(async()=>{
    assert(texts(dom).some(x=>x.includes('长期有效')));
    assert(texts(dom).some(x=>x.includes('iPhone Chrome')));
    assert(texts(dom).some(x=>x.includes('0123456789abcdef')));
    const editors=gather(dom,x=>x.tag==='button'&&texts(x).includes('修改名称'));
    assert.strictEqual(editors.length,2);
    await editors[0].attrs.click();
    const input=gather(dom,x=>x.tag==='input'&&x.attrs['aria-label']==='自定义设备名称')[0];
    assert(input,'device name editor missing');
    input.value='妙妙的 iPhone';
    const save=gather(dom,x=>x.tag==='button'&&texts(x).includes('保存名称'))[0];
    await save.attrs.click();
    assert(calls.some(c=>c.path==='/usr/libexec/tvguard-remote-manage'&&
        c.args.length===3&&c.args[0]==='rename-device'&&c.args[1]==='0123456789abcdef'&&
        c.args[2]==='妙妙的 iPhone'));
    assert(texts(dom).some(x=>x.includes('妙妙的 iPhone')));
    assert(texts(dom).some(x=>x.includes('iPhone Chrome')));
    const controls=gather(dom,x=>x.tag==='button'&&texts(x).includes('撤销此设备'));
    assert.strictEqual(controls.length,2);
    await controls[0].attrs.click();
    assert(calls.some(c=>c.path==='/usr/libexec/tvguard-remote-manage'&&
        c.args.length===2&&c.args[0]==='revoke-device'&&c.args[1]==='0123456789abcdef'));
    assert(texts(dom).some(x=>x.includes('iPad Browser')));
    assert(!texts(dom).some(x=>x.includes('0123456789abcdef')));
    const after=gather(dom,x=>x.tag==='button'&&texts(x).includes('撤销此设备'));
    assert.strictEqual(after.length,1);
    console.log('PASS: LuCI rename and per-device revocation use allowlisted RPC, preserving other sessions');
})().catch(e=>{console.error(e);process.exitCode=1});
