import urllib.request
for url in ['http://127.0.0.1:30000/alive','http://0.0.0.0:30000/alive','http://localhost:30000/alive']:
    try:
        with urllib.request.urlopen(url, timeout=3) as r:
            print(url, r.status, r.read()[:80])
    except Exception as e:
        print(url, type(e).__name__, e)
