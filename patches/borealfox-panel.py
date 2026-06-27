#!/usr/bin/env python3
import os
import sys
import glob
import json
import re
import subprocess
import socket
import time
import shutil
from http.server import HTTPServer, BaseHTTPRequestHandler
import webbrowser

PORT = 8080

def find_profile_dir():
    bases = [os.path.expanduser("~/.mozilla/firefox"), os.path.expanduser("~/.config/mozilla/firefox")]
    for base in bases:
        if os.path.isdir(base):
            matches = glob.glob(os.path.join(base, "*.default-release"))
            if matches: return matches[0]
            matches = glob.glob(os.path.join(base, "*.default"))
            if matches: return matches[0]
    return None

PROFILE_DIR = find_profile_dir()
if not PROFILE_DIR:
    print("could not find firefox profile directory.")
    sys.exit(1)

USER_JS_PATH = os.path.join(PROFILE_DIR, "user.js")
CHROME_CSS_PATH = os.path.join(PROFILE_DIR, "chrome", "userChrome.css")
HTML_PATH = os.path.join(os.path.dirname(os.path.abspath(__file__)), "borealfox.html")

def kill_existing_server():
    """Kill any process already listening on PORT."""
    try:
        result = subprocess.run(
            ["fuser", f"{PORT}/tcp"],
            capture_output=True, text=True
        )
        pids = result.stdout.strip().split()
        for pid in pids:
            pid = pid.strip()
            if pid:
                try:
                    os.kill(int(pid), 9)
                except (ProcessLookupError, ValueError):
                    pass
        if pids:
            time.sleep(0.5)
    except FileNotFoundError:
        try:
            result = subprocess.run(
                ["ss", "-tlnp", f"sport = :{PORT}"],
                capture_output=True, text=True
            )
            for line in result.stdout.splitlines():
                if f":{PORT}" in line and "pid=" in line:
                    pid = re.search(r'pid=(\d+)', line)
                    if pid:
                        try:
                            os.kill(int(pid.group(1)), 9)
                        except ProcessLookupError:
                            pass
            time.sleep(0.5)
        except Exception:
            pass

def read_prefs():
    prefs = {}
    if not os.path.exists(USER_JS_PATH):
        return prefs
    with open(USER_JS_PATH, "r") as f:
        for line in f:
            match = re.match(r'^\s*user_pref\("([^"]+)",\s*(true|false|-?\d+|"[^"]*")\);', line)
            if match:
                key, val = match.groups()
                if val == "true": val = True
                elif val == "false": val = False
                elif re.match(r'^-?\d+$', val): val = int(val)
                elif val.startswith('"'): val = val.strip('"')
                prefs[key] = val
    return prefs

def write_pref(key, val):
    lines = []
    if os.path.exists(USER_JS_PATH):
        with open(USER_JS_PATH, "r") as f:
            lines = f.readlines()
    updated = False
    if isinstance(val, bool):
        val_str = "true" if val else "false"
    elif isinstance(val, int):
        val_str = str(val)
    else:
        val_str = f'"{val}"'
    for i, line in enumerate(lines):
        if re.match(rf'^\s*user_pref\("{re.escape(key)}"', line):
            lines[i] = f'user_pref("{key}", {val_str});\n'
            updated = True
            break
    if not updated:
        lines.append(f'user_pref("{key}", {val_str});\n')
    with open(USER_JS_PATH, "w") as f:
        f.writelines(lines)

TAB_COLOR_DECL = re.compile(r'(--tab-line-color:\s*)(#[0-9a-fA-F]{3,8})')

def get_tab_color():
    if not os.path.exists(CHROME_CSS_PATH):
        return "#0a84ff"
    with open(CHROME_CSS_PATH, "r") as f:
        content = f.read()
    match = TAB_COLOR_DECL.search(content)
    return match.group(2) if match else "#0a84ff"

def set_tab_color(color):
    if not os.path.exists(CHROME_CSS_PATH):
        return
    with open(CHROME_CSS_PATH, "r") as f:
        content = f.read()
    if TAB_COLOR_DECL.search(content):
        content = TAB_COLOR_DECL.sub(f'--tab-line-color: {color}', content)
    else:
        content = content.replace(':root {', ':root {\n  --tab-line-color: ' + color + ';', 1)
    with open(CHROME_CSS_PATH, "w") as f:
        f.write(content)

def restart_firefox():
    subprocess.run(["pkill", "-f", "firefox"])
    time.sleep(1)
    subprocess.Popen(["firefox", f"http://localhost:{PORT}"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

class BorealfoxHandler(BaseHTTPRequestHandler):
    def log_message(self, format, *args):
        pass

    def do_GET(self):
        if self.path == '/':
            self.send_response(200)
            self.send_header('Content-type', 'text/html')
            self.end_headers()
            with open(HTML_PATH, "rb") as f:
                self.wfile.write(f.read())
        elif self.path == '/api/settings':
            self.send_response(200)
            self.send_header('Content-type', 'application/json')
            self.end_headers()
            self.wfile.write(json.dumps(read_prefs()).encode())
        elif self.path == '/api/chrome':
            self.send_response(200)
            self.send_header('Content-type', 'application/json')
            self.end_headers()
            prefs = read_prefs()
            data = {
                "enabled": prefs.get("toolkit.legacyUserProfileCustomizations.stylesheets", False),
                "tab_color": get_tab_color()
            }
            self.wfile.write(json.dumps(data).encode())
        else:
            self.send_response(404)
            self.end_headers()

    def do_POST(self):
        content_length = int(self.headers.get('Content-Length', 0))
        body = self.rfile.read(content_length)

        if self.path == '/api/settings':
            data = json.loads(body.decode())
            write_pref(data["pref"], data["value"])
            self.send_response(200)
            self.send_header('Content-type', 'application/json')
            self.end_headers()
            self.wfile.write(b'{"status":"ok"}')

        elif self.path == '/api/chrome':
            data = json.loads(body.decode())
            if "enabled" in data:
                write_pref("toolkit.legacyUserProfileCustomizations.stylesheets", data["enabled"])
            if "tab_color" in data:
                set_tab_color(data["tab_color"])
            self.send_response(200)
            self.send_header('Content-type', 'application/json')
            self.end_headers()
            self.wfile.write(b'{"status":"ok"}')

        elif self.path == '/api/restart':
            self.send_response(200)
            self.send_header('Content-type', 'application/json')
            self.end_headers()
            self.wfile.write(b'{"status":"restarting"}')
            restart_firefox()

        elif self.path == '/api/panic':
            self.send_response(200)
            self.send_header('Content-type', 'application/json')
            self.end_headers()
            self.wfile.write(b'{"status":"panicking"}')
            
            subprocess.run(["pkill", "-f", "firefox"])
            time.sleep(1)
            
            keep = ["user.js", "chrome", "extensions"]
            for item in glob.glob(os.path.join(PROFILE_DIR, "*")):
                if os.path.basename(item) not in keep:
                    if os.path.isdir(item):
                        shutil.rmtree(item, ignore_errors=True)
                    else:
                        try: os.remove(item)
                        except: pass
            
            subprocess.Popen(["firefox", f"http://localhost:{PORT}"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

        else:
            self.send_response(404)
            self.end_headers()

if __name__ == '__main__':
    kill_existing_server()
    HTTPServer.allow_reuse_address = True
    server = HTTPServer(('127.0.0.1', PORT), BorealfoxHandler)
    print(f"borealfox panel running on http://127.0.0.1:{PORT}")
    webbrowser.open(f"http://127.0.0.1:{PORT}")
    server.serve_forever()
