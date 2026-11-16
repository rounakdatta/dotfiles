"""shelve: put EPUBs on the bookshelf at books.taptappers.club, for the iPad.

    shelve                 every EPUB in ~/Downloads
    shelve a.epub b.epub   just these

A book goes up in 8 MB pieces: Traefik gives one request 60 seconds, and a
big illustrated book would not make it up a home connection in one. Books
taken from ~/Downloads then move to ~/Books, so Downloads only ever holds what
is not on the shelf yet.

The password is the pass entry books.taptappers.club; the server reads the
same value from Bitwarden (bookshelf/password).
"""
import argparse
import base64
import glob
import os
import shutil
import subprocess
import sys
import urllib.error
import urllib.parse
import urllib.request

SHELF = "https://books.taptappers.club"
DOWNLOADS = os.path.expanduser("~/Downloads")
ARCHIVE = os.path.expanduser("~/Books")
CHUNK = 8 << 20


class Refused(Exception):
    """The shelf said no in a way that trying again will not change."""


class _NoRedirects(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, *args, **kwargs):
        return None  # a redirect only ever leads to the login page


_opener = urllib.request.build_opener(_NoRedirects)


def call(method, url, auth, body=None):
    """The HTTP status of one request to the shelf."""
    request = urllib.request.Request(url, data=body, method=method, headers={"Authorization": auth})
    try:
        with _opener.open(request, timeout=120) as response:
            return response.status
    except urllib.error.HTTPError as e:
        return e.code


def password():
    out = subprocess.run(["pass", "show", "books.taptappers.club"], capture_output=True, text=True, check=True)
    return out.stdout.splitlines()[0]


def upload(path, url, auth):
    """Send the book in chunks. A failure starts it over from the first byte."""
    size = os.path.getsize(path)
    name = os.path.basename(path)
    for attempt in range(3):
        try:
            with open(path, "rb") as f:
                offset = 0
                while True:
                    chunk = f.read(CHUNK)
                    final = offset + len(chunk) >= size
                    status = call("PUT", f"{url}?offset={offset}" + ("&final=1" if final else ""), auth, chunk)
                    if status in (400, 401, 413, 422):
                        raise Refused(f"the shelf refused it: {status}")
                    if status not in (201, 204):
                        raise RuntimeError(f"the shelf answered {status}")
                    offset += len(chunk)
                    if size > CHUNK:
                        print(f"\rShelving {name}: {offset * 100 // size}%", end="", flush=True)
                    if final:
                        return
        except (OSError, RuntimeError) as e:
            if attempt == 2:
                raise
            print(f"\n  {e}; starting {name} again", file=sys.stderr)


def archive(path):
    """Move a shelved book out of Downloads, unless ~/Books already has one by that name."""
    os.makedirs(ARCHIVE, exist_ok=True)
    target = os.path.join(ARCHIVE, os.path.basename(path))
    if not os.path.exists(target):
        shutil.move(path, target)


def main(paths):
    books = paths or sorted(glob.glob(os.path.join(DOWNLOADS, "*.epub")))
    if not books:
        print("No EPUBs in ~/Downloads.")
        return 0
    auth = "Basic " + base64.b64encode(f"shelve:{password()}".encode()).decode()
    failed = 0
    for path in books:
        name = os.path.basename(path)
        url = f"{SHELF}/books/{urllib.parse.quote(name)}"
        try:
            status = call("HEAD", url, auth)
            if status == 401:
                sys.exit("The shelf refused the password in pass books.taptappers.club.")
            if status == 200:
                print(f"Already on the shelf: {name}")
            else:
                upload(path, url, auth)
                print(f"\rShelved: {name}" + " " * 12)
        except (Refused, OSError, RuntimeError) as e:
            print(f"\rNot shelved: {name} ({e})", file=sys.stderr)
            failed += 1
            continue
        if os.path.dirname(os.path.abspath(path)) == DOWNLOADS:
            archive(path)
    print(f"On the iPad: {SHELF}")
    return 1 if failed else 0


if __name__ == "__main__":
    parser = argparse.ArgumentParser(prog="shelve", description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("books", nargs="*", help="EPUB files (default: every EPUB in ~/Downloads)")
    sys.exit(main(parser.parse_args().books))
