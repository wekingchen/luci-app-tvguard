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
        var lanLink=E('a',{'target':'_blank','rel':'noopener noreferrer','style':'display:none;overflow-wrap:anywhere'},'');
        var deviceList=E('div',{'style':'margin-top:12px'},'读取设备列表中…');
        var codeHint=E('p',{'class':'description'},
            '配对码仅显示本次生成的值，5 分钟后失效，每个配对码最多使用一次。');
        var busy=false,buttons=[],deviceButtons=[];
        function lock(v){busy=v;buttons.concat(deviceButtons).forEach(function(b){b.disabled=v;});}
        function deviceTime(epoch){
            var n=Number(epoch);
            return n>0 ? new Date(n*1000).toLocaleString('zh-CN') : '旧版配对，时间未记录';
        }
        function renderDevices(devices){
            deviceButtons=[];
            deviceList.replaceChildren();
            if(!Array.isArray(devices)||!devices.length){
                deviceList.appendChild(E('p',{'class':'description'},'尚无已授权的家长设备'));
                return;
            }
            devices.forEach(function(d){
                var id=String(d.id||'');
                if(!/^[0-9a-f]{16}$/.test(id))return;
                var deviceName=String(d.name||'浏览器');
                var detail='设备标识 '+id+' · '+deviceTime(d.paired_at)+' · '+
                    (Number(d.expires)===0?'长期授权（除非撤销）':'到期：'+deviceTime(d.expires));
                var cancel=button('撤销此设备',function(){
                    return run('revoke-device','确定撤销 '+deviceName+'（'+id+'）的家长遥控授权吗？',[id]);
                },'cbi-button-negative');
                cancel.disabled=busy;
                deviceButtons.push(cancel);
                deviceList.appendChild(E('div',{'style':'display:flex;align-items:center;justify-content:space-between;gap:12px;flex-wrap:wrap;padding:10px 0;border-bottom:1px solid rgba(127,127,127,.16)'},[
                    E('div',{},[
                        E('strong',{},deviceName),
                        E('div',{'class':'description','style':'overflow-wrap:anywhere;margin-top:4px'},detail)
                    ]),
                    cancel
                ]));
            });
        }
        function notice(msg,level){ui.addNotification(null,E('p',{},msg),level||'info');}
        function renderState(s){
            if(!s){state.textContent='状态读取失败，请检查 RPCD 权限';return;}
            renderDevices(s.devices);
            state.textContent='服务：'+(s.enabled?'已启用':'已关闭')+
                ' · 本机 HTTP：'+(s.listener?'可连接':'未监听')+
                ' · 已配对设备：'+s.paired+
                ' · 本机地址：127.0.0.1:18765' +
                ' · 局域网 HTTP：' + (s.lan_enabled ? '已启用' : '未启用');
            if(s.lan_enabled && /^http:\/\/(10\.\d+\.\d+\.\d+|192\.168\.\d+\.\d+|172\.(1[6-9]|2\d|3[01])\.\d+\.\d+):18765\/$/.test(s.lan_url || '')){
                lanLink.href=s.lan_url;
                lanLink.textContent='打开家长遥控器：'+s.lan_url;
                lanLink.style.display='';
            }else{
                lanLink.textContent='';
                lanLink.removeAttribute('href');
                lanLink.style.display='none';
            }
        }
        function refresh(){
            return exec(READ,['status']).then(function(s){renderState(JSON.parse(s));})
                .catch(function(err){notice('读取状态失败：'+String(err),'error');});
        }
        function run(name,confirmation,args) {
            if(busy)return;
            if(confirmation&&!window.confirm(confirmation))return;
            lock(true);
            return exec(MANAGE,[name].concat(args||[])).then(function(result){
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
        var enableLan=button('启用家中 HTTP 直连',function(){
            return run('enable-lan','局域网 HTTP 不加密，配对会话 Cookie 可被同网段攻击者截获。只建议用于可信的家庭 Wi-Fi，确认启用吗？');
        });
        var disableLan=button('关闭局域网入口',function(){return run('disable-lan');},'cbi-button-negative');
        var pair=button('生成 5 分钟配对码',function(){return run('pair');});
        var revoke=button('撤销全部设备',function(){
            return run('revoke-all','确定让所有已经配对的家长设备重新配对吗？');
        },'cbi-button-negative');
        var update=button('刷新状态',refresh);
        buttons=[enable,disable,enableLan,disableLan,pair,revoke,update];
        renderState(initial);
        return E('div',{'style':'max-width:930px;margin:0 auto'},[
            E('h2',{},'TV Guard · 家长遥控'),
            E('p',{'class':'description'},
                '这个面板负责独立家长遥控器的启停与配对管理；只调用现有 TVGuard 模式和奖励指令，不允许管理路由器。'),
            E('section',{'class':'cbi-section'},[
                E('h3',{},'专用服务状态'),state,
                E('div',{'style':'margin-top:8px'},lanLink),
                E('div',{'style':'margin-top:13px'},[enable,disable,update]),
                E('p',{'class':'description'},
                    '默认仅监听本机 127.0.0.1:18765。开启家中 HTTP 直连后会同时监听 br-lan 的私有 IPv4，iPhone 即可通过本地地址访问；不改变 LuCI 和公网防火墙。')
            ]),
            E('section',{'class':'cbi-section'},[
                E('h3',{},'家中 Wi-Fi · HTTP 直连'),
                E('p',{'class':'description'},
                    '不配置 HTTPS 证书，单独监听 br-lan 的私有 IPv4:18765，不绑定全部网卡。仅限可信家庭局域网，仍需配对授权。'),
                E('div',{},[enableLan,disableLan]),
                E('p',{'class':'description'},
                    'HTTP 是明文传输，无法防御同网段抓包或中间人攻击。请避免在公共 Wi-Fi 上访问本地地址；出门使用 Cloudflare HTTPS + Access，不能直接把 LuCI 发布出去。')
            ]),
            E('section',{'class':'cbi-section'},[
                E('h3',{},'家长设备配对'),
                E('p',{'class':'description'},
                    '在独立遥控页面输入 5 分钟一次性配对码。设备授权长期有效，直到你主动撤销；最多 4 台。浏览器清除 Cookie、使用无痕模式或系统清理网站数据时，仍需重新配对。'),
                pair,E('div',{'style':'padding:12px;border-radius:9px;border:1px solid rgba(127,127,127,.35);margin-top:10px'},code),
                codeHint,
                E('h4',{'style':'margin-top:22px'},'已授权的家长设备'),
                deviceList,
                E('div',{'style':'margin-top:14px'},revoke)
            ]),
            E('p',{'class':'description'},
                '注意：绝对不要在 Cloudflare Tunnel 中配置指向 LuCI 管理页面的公网路由。未来独立公网路由只允许指向 127.0.0.1:18765，并且应先配置 Cloudflare Access 家长身份策略。')
        ]);
    }
});
