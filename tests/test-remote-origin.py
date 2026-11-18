#!/usr/bin/env python3
"""对真实 CGI 中的 same_origin() 用 sh 执行边界测试，模拟 uhttpd 只转发标准头。"""
import os
import re
import subprocess
from pathlib import Path

root = Path(__file__).resolve().parent.parent
src = (root / "root/usr/share/tvguard-remote/www/cgi-bin/tvg").read_text()
match = re.search(r"(?ms)^same_origin\(\) \{\n.*?^\}", src)
assert match, "same_origin function not found"
func = match.group(0)
cases = [
    ("LAN Safari POST with Origin", True, "192.168.101.1", "192.168.101.1:18765", "http://192.168.101.1:18765", ""),
    ("LAN Safari POST without Origin with Referer", True, "192.168.101.1", "192.168.101.1:18765", "", "http://192.168.101.1:18765/"),
    ("LAN with both absent must fail", False, "192.168.101.1", "192.168.101.1:18765", "", ""),
    ("Wrong Origin cannot fall back to Referer", False, "192.168.101.1", "192.168.101.1:18765", "http://evil.invalid", "http://192.168.101.1:18765/"),
    ("Forged Referer prefix rejected", False, "192.168.101.1", "192.168.101.1:18765", "", "http://192.168.101.1:18765.evil.invalid/"),
    ("Cross-site null Origin rejected", False, "192.168.101.1", "192.168.101.1:18765", "null", "http://192.168.101.1:18765/"),
    ("DNS rebinding LAN Host rejected", False, "192.168.101.1", "evil.invalid:18765", "http://evil.invalid:18765", ""),
    ("LAN Host missing rejected", False, "192.168.101.1", "", "http://192.168.101.1:18765", ""),
    ("LAN HTTPS not automatically allowed via arbitrary Host", False, "192.168.101.1", "tv.example.com", "https://tv.example.com", ""),
    ("Tunnel HTTPS Origin allowed", True, "127.0.0.1", "tv.example.com", "https://tv.example.com", ""),
    ("Tunnel HTTPS Referer fallback", True, "127.0.0.1", "tv.example.com", "", "https://tv.example.com/"),
    ("Tunnel cross-site Origin rejected", False, "127.0.0.1", "tv.example.com", "https://other.example.com", ""),
    ("Unexpected interface rejected", False, "198.51.100.25", "tv.example.com", "https://tv.example.com", ""),
]
for label, allowed, bind, host, origin, referer in cases:
    env = os.environ.copy()
    env.update(SERVER_ADDR=bind, HTTP_HOST=host, HTTP_ORIGIN=origin, HTTP_REFERER=referer)
    env.pop("HTTP_X_TVGUARD_ACTION", None)
    ret = subprocess.run(["/bin/sh", "-c", func + "\nsame_origin"], env=env, capture_output=True, text=True)
    if (ret.returncode == 0) != allowed:
        raise AssertionError(f"{label}: expected {allowed} got {ret.returncode}: {ret.stderr}")
assert 'secure=\'\';' not in src
assert 'secure=\'\';' not in func
assert 'HTTP_X_FORWARDED_PROTO' not in src
assert "secure='; Secure'" in src
print(f"PASS: {len(cases)} same-origin/CSRF/Host tests with no custom CGI header")
