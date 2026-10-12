"""Direct vphone.sock client: one JSON request per connection, one JSON line back."""
import json,socket
from pathlib import Path
SOCK=str(Path.home()/'.vphone/machines/iphone/vphone.sock')
def send(obj,timeout=120):
    s=socket.socket(socket.AF_UNIX,socket.SOCK_STREAM);s.settimeout(timeout);s.connect(SOCK)
    s.sendall(json.dumps(obj).encode()+b'\n');buf=b''
    while not buf.endswith(b'\n'):
        part=s.recv(1<<20)
        if not part:break
        buf+=part
    s.close();return json.loads(buf)
def rpc(method,params,timeout=120):
    r=send({'t':'rpc','method':method,'params':params},timeout)
    if not r.get('ok'):raise RuntimeError(r.get('error'))
    return r['result']
