#!/usr/bin/env python3
"""Bind an isolated local fixture server and publish its kernel-selected port."""

import argparse
from functools import partial
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path


class QuietFixtureHandler(SimpleHTTPRequestHandler):
    def log_message(self, format, *args):
        print(format % args, flush=True)

    def do_GET(self):
        # A permanent redirect to a different path, so the browser can be
        # checked against the case a real site creates: the address a
        # bookmark holds is not the address the icon ends up filed under.
        if self.path.startswith("/redirect-to-fixture"):
            self.send_response(301)
            self.send_header("Location", "/index.html")
            self.end_headers()
            return
        super().do_GET()


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--directory", required=True)
    parser.add_argument("--port-file", required=True)
    args = parser.parse_args()

    handler = partial(QuietFixtureHandler, directory=args.directory)
    server = ThreadingHTTPServer(("127.0.0.1", 0), handler)
    port_file = Path(args.port_file)
    port_file.write_text(str(server.server_address[1]), encoding="utf-8")
    server.serve_forever()


if __name__ == "__main__":
    main()
