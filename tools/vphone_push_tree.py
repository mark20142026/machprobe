#!/usr/bin/env python3
"""Mirror a local directory tree into the running vphone guest (resumable).

  python3 tools/vphone_push_tree.py LOCAL_DIR GUEST_DIR [--bundle-id ID] [--workers N]

GUEST_DIR is an absolute guest path, or (with --bundle-id) relative to the
app's data container (apps.info data_path), e.g. Documents/stkdata/data.

How it works: one files.list per guest directory (walked in parallel; a
missing directory is treated as empty), files whose size already matches are
skipped, the rest go up with PUT /v1/files/content (which creates parent
directories) on a few keep-alive connections with retries; empty local
directories are created with files.mkdir.  Re-running is safe: partial
uploads have the wrong size and are simply sent again.  Finally the guest
tree is listed again and its file count / byte total must equal the local
tree's (extra guest files count as a mismatch; --prune removes them first).
Exit status: 0 ok, 1 verify mismatch, 2 upload failures.  Stdlib only; the
bearer token is read from build/vm-api-token and never printed."""
import argparse, http.client, json, os, posixpath, sys, threading, time, urllib.parse
from concurrent.futures import ThreadPoolExecutor, as_completed
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
TOKEN = (ROOT / 'build/vm-api-token').read_text().strip()
_port = ROOT / 'build/vm-api-port'
PORT = int(_port.read_text().strip()) if _port.exists() else 18765
HOST = '127.0.0.1'
_tls = threading.local()


class ApiError(RuntimeError):
    def __init__(self, msg, status=None):
        super().__init__(msg)
        self.status = status


def _conn():
    c = getattr(_tls, 'conn', None)
    if c is None:
        c = _tls.conn = http.client.HTTPConnection(HOST, PORT, timeout=300)
    return c


def _request(method, path, body, ctype):
    """One request on this thread's keep-alive connection; reconnect once if the
    server closed it.  Returns (status, bytes)."""
    headers = {'Authorization': 'Bearer ' + TOKEN, 'Content-Type': ctype}
    for attempt in (0, 1):
        c = _conn()
        try:
            c.request(method, path, body=body, headers=headers)
            r = c.getresponse()
            return r.status, r.read()
        except (http.client.HTTPException, OSError):
            c.close()
            _tls.conn = None
            if attempt:
                raise
    raise AssertionError


def rpc(method, params):
    status, data = _request('POST', '/v1/rpc', json.dumps({'method': method, 'params': params}).encode(),
                            'application/json')
    try:
        reply = json.loads(data)
    except ValueError:
        raise ApiError(f'{method}: HTTP {status}, non-JSON reply', status)
    if status != 200 or 'error' in reply or 'result' not in reply:
        raise ApiError(f'{method}: HTTP {status} {reply.get("error", "")}', status)
    return reply['result']


def put_file(local, remote, size):
    with open(local, 'rb') as f:
        data = f.read()  # largest STK file is a few tens of MB
    status, body = _request('PUT', '/v1/files/content?path=' + urllib.parse.quote(remote, safe='/'), data,
                            'application/octet-stream')
    try:
        reply = json.loads(body)
    except ValueError:
        reply = {}
    if status != 200 or 'result' not in reply:
        raise ApiError(f'PUT {remote}: HTTP {status} {reply.get("error", "")}', status)
    if reply['result'].get('size') != size:
        raise ApiError(f'PUT {remote}: guest size {reply["result"].get("size")} != {size}')


def with_retry(fn, tries=5):
    for i in range(tries):
        try:
            return fn()
        except (ApiError, OSError, http.client.HTTPException) as e:
            # 4xx other than a missing dir will not get better by retrying much, but a few tries are cheap
            if i == tries - 1:
                raise
            time.sleep(0.5 * 2 ** i)


def list_guest_dir(path):
    """-> (files {name: size}, subdirs [name]); a missing directory lists as empty (the API answers 400)."""
    def call():
        try:
            return rpc('files.list', {'path': path})
        except ApiError as e:
            if e.status == 400:
                return None
            raise
    res = with_retry(call, tries=3)
    if res is None:
        return {}, []
    files, dirs = {}, []
    for e in res.get('entries', []):
        if e.get('is_directory'):
            dirs.append(e['name'])
        else:
            files[e['name']] = e.get('size')
    return files, dirs


def walk_guest(root, workers):
    """Parallel BFS of the guest tree. -> {dirpath: ({name:size}, [subdirs])}"""
    out = {}
    with ThreadPoolExecutor(workers) as ex:
        pending = {ex.submit(list_guest_dir, root): root}
        while pending:
            for fut in as_completed(list(pending)):
                d = pending.pop(fut)
                files, dirs = fut.result()
                out[d] = (files, dirs)
                for sub in dirs:
                    p = posixpath.join(d, sub)
                    pending[ex.submit(list_guest_dir, p)] = p
                break
    return out


def scan_local(local):
    files, dirs = [], []
    for dp, dn, fn in os.walk(local):
        rel = os.path.relpath(dp, local)
        rel = '' if rel == '.' else rel.replace(os.sep, '/')
        dirs.append(rel)
        for n in fn:
            p = os.path.join(dp, n)
            files.append((p, (rel + '/' + n) if rel else n, os.path.getsize(p)))
    return files, dirs


def fmt(n):
    return f'{n / 2 ** 20:.1f} MiB'


def main():
    ap = argparse.ArgumentParser(description=__doc__.split('\n\n')[0], formatter_class=argparse.RawTextHelpFormatter)
    ap.add_argument('local_dir')
    ap.add_argument('guest_dir')
    ap.add_argument('--bundle-id', help='GUEST_DIR is relative to this app\'s data container')
    ap.add_argument('--workers', type=int, default=6)
    ap.add_argument('--prune', action='store_true', help='delete guest files/dirs that are not in the local tree')
    ap.add_argument('--no-verify', action='store_true')
    a = ap.parse_args()

    local = os.path.abspath(a.local_dir)
    if not os.path.isdir(local):
        sys.exit(f'not a directory: {local}')
    guest = a.guest_dir
    if a.bundle_id:
        base = rpc('apps.info', {'bundle_id': a.bundle_id}).get('data_path')
        if not base:
            sys.exit(f'apps.info for {a.bundle_id} has no data_path')
        guest = posixpath.join(base, guest.lstrip('/'))
    elif not guest.startswith('/'):
        sys.exit('GUEST_DIR must be absolute unless --bundle-id is given')
    guest = guest.rstrip('/') or '/'

    t0 = time.monotonic()
    lfiles, ldirs = scan_local(local)
    ltotal = sum(s for _, _, s in lfiles)
    print(f'local : {len(lfiles)} files, {fmt(ltotal)}, {len(ldirs)} dirs  ({local})')
    print(f'guest : {guest}')

    gtree = walk_guest(guest, a.workers)
    gfiles = {}
    for d, (files, _) in gtree.items():
        rel = posixpath.relpath(d, guest)
        for n, s in files.items():
            gfiles[n if rel == '.' else rel + '/' + n] = s
    print(f'listed {len(gtree)} guest dirs in {time.monotonic() - t0:.1f}s: {len(gfiles)} files present')

    if a.prune:
        lset = {r for _, r, _ in lfiles}
        extra = [r for r in gfiles if r not in lset]
        for r in extra:
            with_retry(lambda: rpc('files.remove', {'path': posixpath.join(guest, r)}))
            del gfiles[r]
        if extra:
            print(f'pruned {len(extra)} extra guest files')

    todo = [(p, r, s) for p, r, s in lfiles if gfiles.get(r) != s]
    skipped = len(lfiles) - len(todo)
    todo_bytes = sum(s for _, _, s in todo)
    print(f'plan  : upload {len(todo)} files ({fmt(todo_bytes)}), skip {skipped} unchanged')

    # directories that hold no local files (nothing else would create them)
    have_files = set()
    for _, r, _ in lfiles:
        d = posixpath.dirname(r)
        while d:
            have_files.add(d)
            d = posixpath.dirname(d)
    for d in ldirs:
        full = guest if d == '' else posixpath.join(guest, d)
        if d not in have_files and (full not in gtree):
            with_retry(lambda: rpc('files.mkdir', {'path': full}))
    if not lfiles and guest not in gtree:
        with_retry(lambda: rpc('files.mkdir', {'path': guest}))

    done_files = done_bytes = 0
    failures = []
    lock = threading.Lock()
    t1 = time.monotonic()
    last = [t1]

    def work(item):
        p, r, s = item
        with_retry(lambda: put_file(p, posixpath.join(guest, r), s))
        return s

    def progress(force=False):
        now = time.monotonic()
        if force or now - last[0] >= 3:
            last[0] = now
            el = max(now - t1, 1e-6)
            print(f'  {done_files + len(failures)}/{len(todo)} files, {fmt(done_bytes)}/{fmt(todo_bytes)}, '
                  f'{done_bytes / 2 ** 20 / el:.1f} MiB/s, {el:.0f}s', flush=True)

    if todo:
        # biggest first keeps workers busy to the end
        todo.sort(key=lambda t: -t[2])
        with ThreadPoolExecutor(a.workers) as ex:
            futs = {ex.submit(work, it): it for it in todo}
            for fut in as_completed(futs):
                try:
                    s = fut.result()
                    done_files += 1
                    done_bytes += s
                except Exception as e:
                    failures.append((futs[fut][1], str(e)))
                progress()
    up_time = time.monotonic() - t1

    status = 0
    for r, e in failures[:20]:
        print(f'FAILED {r}: {e}', file=sys.stderr)
    if failures:
        print(f'{len(failures)} uploads failed; re-run to resume', file=sys.stderr)
        status = 2

    if not a.no_verify:
        vtree = walk_guest(guest, a.workers)
        gcount = sum(len(f) for f, _ in vtree.values())
        gbytes = sum(s for f, _ in vtree.values() for s in f.values())
        ok = gcount == len(lfiles) and gbytes == ltotal
        print(f'verify: guest {gcount} files, {gbytes} bytes; local {len(lfiles)} files, {ltotal} bytes -> '
              f'{"OK" if ok else "MISMATCH"}')
        if not ok and status == 0:
            status = 1

    tot = time.monotonic() - t0
    rate = done_bytes / 2 ** 20 / up_time if up_time > 0 and done_bytes else 0
    print(f'summary: uploaded {done_files} files ({fmt(done_bytes)}) in {up_time:.1f}s = {rate:.1f} MiB/s, '
          f'{done_files / up_time if up_time > 0 else 0:.0f} files/s; skipped {skipped}; failed {len(failures)}; '
          f'total {tot:.1f}s')
    return status


if __name__ == '__main__':
    sys.exit(main())
