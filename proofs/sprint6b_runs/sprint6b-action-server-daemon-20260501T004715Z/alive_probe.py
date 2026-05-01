import urllib.request
try:
    with urllib.request.urlopen('http://127.0.0.1:30000/alive', timeout=3) as r:
        print(r.status, r.read()[:80])
except Exception as e:
    print(type(e).__name__, e)
