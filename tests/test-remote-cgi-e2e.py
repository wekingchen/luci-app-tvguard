#!/usr/bin/env python3
"""独立 CGI 真实执行测试：不需要 N1、Root 权限或公网。通过临时文件模拟配对、授权和控制。"""
import hashlib
import os
import re
import subprocess
import tempfile
import time
from pathlib import Path

repo = Path(__file__).resolve().parent.parent
original = (repo / "root/usr/share/tvguard-remote/www/cgi-bin/tvg").read_text()

with tempfile.TemporaryDirectory(prefix="tvguard-api-e2e-") as directory:
    work = Path(directory)
    state = work / "state"
    state.mkdir()
    pair_file = work / "pair"
    action_log = work / "actions"
    status_path = work / "status"
    ctl_path = work / "ctl"
    script_path = work / "cgi.sh"
    lock_path = work / "pair.lock"
    now = int(time.time())

    status_path.write_text("#!/bin/sh\nprintf '%s\\n' '{\"mode\":\"child\",\"watch_seconds\":500,\"used_seconds\":500,\"quota_seconds\":3600,\"bonus_seconds\":0,\"remaining_seconds\":3100,\"bonus_undo_available\":0,\"bonus_limit_seconds\":7200,\"enforce\":1,\"blocked\":0,\"agent_activity\":\"private_value\"}'\n")
    ctl_path.write_text(f"#!/bin/sh\nprintf '%s\\n' \"$*\" >> '{action_log}'\n")
    status_path.chmod(0o700)
    ctl_path.chmod(0o700)

    script = original
    script = script.replace("ROOT=/mnt/mmcblk2p4/tvguard-remote", f"ROOT={state}")
    script = script.replace("PAIR=/tmp/tvguard-remote/pair", f"PAIR={pair_file}")
    script = script.replace("/tmp/tvguard-remote/pair.lock", str(lock_path))
    script = script.replace("/usr/libexec/tvguard-status", str(status_path))
    script = script.replace("/usr/libexec/tvguardctl", str(ctl_path))
    script = re.sub(r"(?ms)^storage_ok\(\) \{\n.*?^\}", 'storage_ok() { [ -d "$ROOT" ]; }', script, count=1)
    script = re.sub(r"(?ms)^client_allowed\(\) \{\n.*?^\}", 'client_allowed() { [ "$REMOTE_ADDR" = 127.0.0.1 ]; }', script, count=1)
    script = re.sub(r"(?m)^new_random\(\) \{.*\}$", "new_random() { printf '%064d\\n' 0; }", script, count=1)
    script_path.write_text(script)
    script_path.chmod(0o700)
    assert "random_hex" not in script

    def request(method="GET", action="status", host="192.168.101.2:18765",
                origin="http://192.168.101.2:18765", referer="", cookie="",
                body=b"", remote="127.0.0.1", server="192.168.101.2"):
        env = os.environ.copy()
        env.update(REQUEST_METHOD=method, QUERY_STRING="action=" + action,
                   HTTP_HOST=host, HTTP_ORIGIN=origin, HTTP_REFERER=referer,
                   HTTP_COOKIE=cookie, REMOTE_ADDR=remote, SERVER_ADDR=server,
                   CONTENT_LENGTH=str(len(body)), CONTENT_TYPE="application/x-www-form-urlencoded")
        result = subprocess.run(["/bin/sh", str(script_path)], env=env, input=body,
                                capture_output=True, timeout=5)
        response = result.stdout.decode(errors="replace")
        assert result.returncode == 0, f"{action}: CGI exited {result.returncode} {result.stderr!r}"
        assert "\r\n\r\n" in response, f"missing CGI headers for {action}: {response}"
        headers, payload = response.split("\r\n\r\n", 1)
        assert headers.startswith("Status:"), response
        return headers, payload

    def need(status, result, expected):
        header, payload = result
        assert f"Status: {status}" in header, (expected, header, payload)
        if expected:
            assert expected in payload, (status, expected, payload)
        return header, payload

    # 未配对前不得泄漏状态；错误同源不得跳过认证。
    need("401", request(), "pair_required")
    code = "a1" * 16
    digest = hashlib.sha256(code.encode()).hexdigest()

    pair_file.write_text(f"{digest}|{now + 300}\n")
    need("403", request("POST", "pair", origin="https://evil.invalid", body=("code="+code).encode()), "origin_rejected")
    # 跨域失败不能消耗正确配对码。
    assert pair_file.exists()

    need("403", request("POST", "pair", body=b"code=" + b"f"*32), "pair_code_expired_or_invalid")
    assert pair_file.exists()
    need("400", request("POST", "pair", body=b"code=invalid"), "invalid_pair_code")
    assert pair_file.exists()

    pair_headers, payload = need("200", request("POST", "pair", body=("code="+code).encode()), '"paired":true')
    assert not pair_file.exists(), "成功后没有消耗一次性配对码"
    assert "HttpOnly" in pair_headers and "SameSite=Strict" in pair_headers
    cookie_match = re.search(r"tvguard_auth=([a-f0-9]{64})", pair_headers)
    assert cookie_match, pair_headers
    cookie = "tvguard_auth=" + cookie_match.group(1)
    assert (state / "sessions").exists()
    assert cookie_match.group(1) not in (state / "sessions").read_text(), "明文 Token 被保存在服务端"

    need("401", request("POST", "pair", body=("code="+code).encode()), "pair_not_available")
    need("200", request(cookie=cookie), '"mode":"child"')
    need("403", request("POST", "mode-child", cookie=cookie, origin="https://evil.invalid"), "origin_rejected")
    assert not action_log.exists(), "跨站请求触发了实际控制指令"
    need("405", request("POST", "enforce-on", cookie=cookie), "unsupported_action")
    assert not action_log.exists(), "未授权命令触发了控制指令"

    actions = ["mode-child", "mode-parent", "mode-locked", "bonus-15",
               "bonus-30", "bonus-60", "bonus-undo"]
    for item in actions:
        need("200", request("POST", item, cookie=cookie), '"mode":"child"')
    assert action_log.read_text().splitlines() == [
        "mode child", "mode parent", "mode locked", "bonus 15",
        "bonus 30", "bonus 60", "bonus undo"
    ]

    # Origin 缺失时允许真实同源 Referer；跨站 Origin 必须优先拒绝。
    need("200", request("POST", "bonus-15", cookie=cookie, origin="",
                        referer="http://192.168.101.2:18765/"), '"mode":"child"')
    need("403", request("POST", "bonus-15", cookie=cookie, origin="",
                        referer="http://192.168.101.2:18765.attacker.test/"), "origin_rejected")
    need("403", request("POST", "bonus-15", cookie=cookie, origin="",
                        referer=""), "origin_rejected")

    # 服务端会话到期后失效、删除后立即失效。
    session_path = state / "sessions"
    session_data = session_path.read_text()
    session_path.write_text(session_data.split("|")[0] + "|" + str(now - 60) + "\n")
    need("401", request(cookie=cookie), "pair_required")
    session_path.write_text(session_data)
    need("200", request(cookie=cookie), '"mode":"child"')
    session_path.unlink()
    need("401", request(cookie=cookie), "pair_required")

    # 公网 HTTPS Origin 经本机 HTTP 回源时，必须给登录 Cookie 加 Secure。
    pair_file.write_text(f"{digest}|{now + 300}\n")
    secure_headers, _ = need("200", request("POST", "pair", host="tv.example.org",
                                         server="127.0.0.1", origin="https://tv.example.org",
                                         body=("code="+code).encode()), '"paired":true')
    assert "Secure" in secure_headers, secure_headers

print("PASS: CGI full-pipeline pair/replay/expiry/cookie/revocation/CSRF/action whitelist/HTTPS proxy")
