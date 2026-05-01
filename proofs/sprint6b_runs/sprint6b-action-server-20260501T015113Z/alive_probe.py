import urllib.request
with urllib.request.urlopen("http://127.0.0.1:30000/alive", timeout=3) as resp:
    print(resp.status, resp.read().decode())
