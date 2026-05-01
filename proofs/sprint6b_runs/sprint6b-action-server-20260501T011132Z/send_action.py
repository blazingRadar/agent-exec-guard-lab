import json
import sys
import urllib.request

command = sys.argv[1]
payload = {
    "action": {
        "action": "run",
        "args": {
            "command": command,
            "is_input": False,
            "blocking": False,
            "is_static": False,
        },
    }
}
req = urllib.request.Request(
    "http://127.0.0.1:30000/execute_action",
    data=json.dumps(payload).encode(),
    headers={"Content-Type": "application/json"},
    method="POST",
)
with urllib.request.urlopen(req, timeout=45) as resp:
    sys.stdout.write(resp.read().decode())
