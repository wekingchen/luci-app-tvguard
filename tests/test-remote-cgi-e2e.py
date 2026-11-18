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
    generation_file = state / "generation"
    generation = "b2" * 32
    generation_file.write_text(generation + "\n")
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
    script = script.replace("/usr/libexec/tvguard-remote-status", str(status_path))
    script = script.replace("/usr/libexec/tvguardctl", str(ctl_path))
    # 必须执行源代码中真正的 storage_ok 函数，只替换 /proc/mounts 为受控挂载表。
    fake_mounts = work / "mounts"
    fake_mounts.write_text("device /mnt/mmcblk2p4 xfs rw,relatime 0 0\n")
    script = script.replace("/proc/mounts", str(fake_mounts))
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
                   CONTENT_LENGTH=str(len(body)), CONTENT_TYPE="application/x-www-form-urlencoded",
                   HTTP_USER_AGENT="Mozilla/5.0 (iPhone; CPU iPhone OS 27_0) AppleWebKit/605.1 CriOS/143.0")
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

    pair_file.write_text(f"{digest}|{now + 300}|{generation}\n")
    # 真实存储检查必须拒绝只读 XFS，且拒绝时不消耗配对码。
    fake_mounts.write_text("device /mnt/mmcblk2p4 xfs ro,relatime 0 0\n")
    need("503", request("POST", "pair", body=("code="+code).encode()), "storage_unavailable")
    assert pair_file.exists()
    fake_mounts.write_text("device /mnt/mmcblk2p4 xfs rw,relatime 0 0\n")
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
    assert "Path=/cgi-bin/tvg" in pair_headers, "session cookie must not leak to LuCI paths"
    cookie_match = re.search(r"tvguard_auth=([a-f0-9]{64})", pair_headers)
    assert cookie_match, pair_headers
    cookie = "tvguard_auth=" + cookie_match.group(1)
    assert (state / "sessions").exists()
    assert cookie_match.group(1) not in (state / "sessions").read_text(), "明文 Token 被保存在服务端"
    stored = (state / "sessions").read_text().strip().split("|")
    assert stored[1] == "0" and stored[2] == generation, stored
    assert stored[4] == "iPhone Chrome", stored
    assert "Max-Age=31536000" in pair_headers

    need("403", request("POST", "pair", body=("code="+code).encode()), "pair_not_available")
    renewed_header, _ = need("200", request(cookie=cookie), '"mode":"child"')
    assert "Set-Cookie: tvguard_auth=" in renewed_header and "Max-Age=31536000" in renewed_header
    secure_without_referer, _ = need("200", request(cookie=cookie, server="127.0.0.1", host="tv.example.org", origin="", referer=""), '"mode":"child"')
    assert "Secure" in secure_without_referer, secure_without_referer
    revoked_folder = state / "revoked"
    revoked_folder.mkdir()
    revoked_marker = revoked_folder / stored[0]
    revoked_marker.write_text("revoked\n")
    need("401", request(cookie=cookie), "pair_required")
    revoked_marker.unlink()
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
    session_path.write_text(session_data.split("|")[0] + "|" + str(now - 60) + "|" + generation + "\n")
    need("401", request(cookie=cookie), "pair_required")
    session_path.write_text(session_data)
    need("200", request(cookie=cookie), '"mode":"child"')
    session_path.unlink()
    need("401", request(cookie=cookie), "pair_required")

    # 已满四台设备时，一次性码必须仍保留，管理员撤销后可继续使用。
    for idx in range(4):
        token_hash = hashlib.sha256(f"device{idx}".encode()).hexdigest()
        with session_path.open("a") as out:
            out.write(f"{token_hash}|{now+300}|{generation}\n")
    pair_file.write_text(f"{digest}|{now + 300}|{generation}\n")
    need("403", request("POST", "pair", body=("code="+code).encode()), "device_limit")
    assert pair_file.exists(), "device_limit consumed valid pairing code"
    session_path.unlink()

    # 并发领取：两个相同的有效配对请求最多一个成功。
    from concurrent.futures import ThreadPoolExecutor
    with ThreadPoolExecutor(max_workers=2) as pool:
        pair_results = list(pool.map(lambda _: request("POST", "pair", body=("code="+code).encode()), range(2)))
    success_count = sum("Status: 200" in header for header, _ in pair_results)
    assert success_count == 1, pair_results
    assert not pair_file.exists()

    # 撤销后即使旧会话文件被并发写回，也必须因为代际不匹配而拒绝。
    old_record = session_path.read_text()
    generation_file.write_text("c3" * 32 + "\n")
    need("401", request(cookie=cookie), "pair_required")
    generation_file.write_text(generation + "\n")
    session_path.write_text(old_record)

    # 公网 HTTPS Origin 经本机 HTTP 回源时，必须给登录 Cookie 加 Secure。
    pair_file.write_text(f"{digest}|{now + 300}|{generation}\n")
    secure_headers, _ = need("200", request("POST", "pair", host="tv.example.org",
                                         server="127.0.0.1", origin="https://tv.example.org",
                                         body=("code="+code).encode()), '"paired":true')
    assert "Secure" in secure_headers, secure_headers

print("PASS: CGI full-pipeline pair/replay/expiry/cookie/revocation/CSRF/action whitelist/HTTPS proxy")
