'use strict';
'require view';
'require fs';
'require ui';
var READ='/usr/libexec/tvguard-remote-read';
var MANAGE='/usr/libexec/tvguard-remote-manage';
function exec(path,args) {
    return fs.exec(path,args).then(function(r) {
        if(r.code) throw new Error(String(r.stderr || r.stdout || '操作失败'));
        return String(r.stdout || '').trim();
    });
}
function button(name,fn,style) {
    return E('button',{'class':'btn '+(style || 'cbi-button-action'),
        'type':'button','style':'min-height:38px;margin:4px 8px 4px 0',click:fn},name);
}
return view.extend({
    load:function(){
        return exec(READ,['status']).then(function(s){return JSON.parse(s);})
            .catch(function(){return null;});
    },
    render:function(initial){
        var state=E('div',{},'读取中…');
        var code=E('code',{'style':'overflow-wrap:anywhere;user-select:all'},'尚未生成');
        var codeHint=E('p',{'class':'description'},
            '配对码仅显示本次生成的值，5 分钟后失效，每个配对码最多使用一次。');
        var busy=false,buttons=[];
        function lock(v){busy=v;buttons.forEach(function(b){b.disabled=v;});}
        function notice(msg,level){ui.addNotification(null,E('p',{},msg),level||'info');}
        function renderState(s){
            if(!s){state.textContent='状态读取失败，请检查 RPCD 权限';return;}
            state.textContent='服务：'+(s.enabled?'已启用':'已关闭')+
                ' · 本机 HTTP：'+(s.listener?'可连接':'未监听')+
                ' · 已配对设备：'+s.paired+
                ' · 监听地址：127.0.0.1:18765';
        }
        function refresh(){
            return exec(READ,['status']).then(function(s){renderState(JSON.parse(s));})
                .catch(function(err){notice('读取状态失败：'+String(err),'error');});
        }
        function run(name,confirmation) {
            if(busy)return;
            if(confirmation&&!window.confirm(confirmation))return;
            lock(true);
            return exec(MANAGE,[name]).then(function(result){
                if(name==='pair'){
                    code.textContent=result.replace(/^.*：/,'');
                    notice('一次性配对码已生成，请在可信设备上使用');
                }else{
                    notice(result);
                    if(name==='revoke-all')code.textContent='已撤销';
                }
                return refresh();
            }).catch(function(err){notice('操作失败：'+String(err.message||err),'error');})
            .finally(function(){lock(false);});
        }
        var enable=button('启用本机遥控服务',function(){return run('enable');});
        var disable=button('停止服务',function(){return run('disable');},'cbi-button-negative');
        var pair=button('生成 5 分钟配对码',function(){return run('pair');});
        var revoke=button('撤销全部设备',function(){
            return run('revoke-all','确定让所有已经配对的家长设备重新配对吗？');
        },'cbi-button-negative');
        var update=button('刷新状态',refresh);
        buttons=[enable,disable,pair,revoke,update];
        renderState(initial);
        return E('div',{'style':'max-width:930px;margin:0 auto'},[
            E('h2',{},'TV Guard · 家长遥控'),
            E('p',{'class':'description'},
                '这个面板负责独立家长遥控器的启停与配对管理；只调用现有 TVGuard 模式和奖励指令，不允许管理路由器。'),
            E('section',{'class':'cbi-section'},[
                E('h3',{},'专用服务状态'),state,
                E('div',{'style':'margin-top:13px'},[enable,disable,update]),
                E('p',{'class':'description'},
                    '安全预览：服务默认关闭且只监听 N1 本机 127.0.0.1:18765，不会自动开放局域网端口；目前不能从 iPhone 直接访问这个本机地址。待完成可信 HTTPS 局域网入口及 Cloudflare Access 保护后再开放。')
            ]),
            E('section',{'class':'cbi-section'},[
                E('h3',{},'家长设备配对'),
                E('p',{'class':'description'},
                    '在独立遥控页面输入以下一次性配对码，设备即可建立独立会话。服务端保存哈希而非明文会话令牌；30 天过期，最多支持 4 台设备。'),
                pair,E('div',{'style':'padding:12px;border-radius:9px;border:1px solid rgba(127,127,127,.35);margin-top:10px'},code),
                codeHint,
                revoke
            ]),
            E('p',{'class':'description'},
                '注意：绝对不要在 Cloudflare Tunnel 中配置指向 LuCI 管理页面的公网路由。未来独立公网路由只允许指向 127.0.0.1:18765，并且应先配置 Cloudflare Access 家长身份策略。')
        ]);
    }
});
