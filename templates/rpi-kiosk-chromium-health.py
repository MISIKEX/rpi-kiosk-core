#!/usr/bin/env python3
import base64
import json
import os
import socket
import struct
import sys
import urllib.parse
import urllib.request

PORT = int(sys.argv[1]) if len(sys.argv) > 1 else 9222
HTTP_TIMEOUT = 3
WS_TIMEOUT = 5


def recv_exact(sock, size):
    data = bytearray()
    while len(data) < size:
        chunk = sock.recv(size - len(data))
        if not chunk:
            raise RuntimeError("WebSocket kapcsolat megszakadt")
        data.extend(chunk)
    return bytes(data)


def send_frame(sock, payload, opcode=0x1):
    payload = payload if isinstance(payload, bytes) else payload.encode("utf-8")
    mask = os.urandom(4)
    length = len(payload)
    header = bytearray([0x80 | opcode])
    if length < 126:
        header.append(0x80 | length)
    elif length < 65536:
        header.append(0x80 | 126)
        header.extend(struct.pack("!H", length))
    else:
        header.append(0x80 | 127)
        header.extend(struct.pack("!Q", length))
    header.extend(mask)
    masked = bytes(b ^ mask[i % 4] for i, b in enumerate(payload))
    sock.sendall(bytes(header) + masked)


def recv_frame(sock):
    first, second = recv_exact(sock, 2)
    opcode = first & 0x0F
    length = second & 0x7F
    if length == 126:
        length = struct.unpack("!H", recv_exact(sock, 2))[0]
    elif length == 127:
        length = struct.unpack("!Q", recv_exact(sock, 8))[0]
    masked = bool(second & 0x80)
    mask = recv_exact(sock, 4) if masked else b""
    payload = recv_exact(sock, length)
    if masked:
        payload = bytes(b ^ mask[i % 4] for i, b in enumerate(payload))
    return opcode, payload


def websocket_runtime_check(ws_url):
    parsed = urllib.parse.urlparse(ws_url)
    host = parsed.hostname or "127.0.0.1"
    port = parsed.port or 80
    path = parsed.path or "/"
    if parsed.query:
        path += "?" + parsed.query

    sock = socket.create_connection((host, port), timeout=WS_TIMEOUT)
    sock.settimeout(WS_TIMEOUT)
    try:
        key = base64.b64encode(os.urandom(16)).decode("ascii")
        request = (
            f"GET {path} HTTP/1.1\r\n"
            f"Host: {host}:{port}\r\n"
            "Upgrade: websocket\r\n"
            "Connection: Upgrade\r\n"
            f"Sec-WebSocket-Key: {key}\r\n"
            "Sec-WebSocket-Version: 13\r\n"
            "\r\n"
        )
        sock.sendall(request.encode("ascii"))
        response = bytearray()
        while b"\r\n\r\n" not in response:
            chunk = sock.recv(4096)
            if not chunk:
                raise RuntimeError("Nincs WebSocket handshake válasz")
            response.extend(chunk)
            if len(response) > 32768:
                raise RuntimeError("Túl nagy WebSocket handshake válasz")
        if b" 101 " not in response.split(b"\r\n", 1)[0]:
            raise RuntimeError("A DevTools WebSocket handshake sikertelen")

        command = {
            "id": 1,
            "method": "Runtime.evaluate",
            "params": {
                "expression": "JSON.stringify({readyState:document.readyState,href:location.href,now:Date.now()})",
                "returnByValue": True,
            },
        }
        send_frame(sock, json.dumps(command, separators=(",", ":")))

        while True:
            opcode, payload = recv_frame(sock)
            if opcode == 0x8:
                raise RuntimeError("A DevTools WebSocket bezárult")
            if opcode == 0x9:
                send_frame(sock, payload, opcode=0xA)
                continue
            if opcode != 0x1:
                continue
            message = json.loads(payload.decode("utf-8"))
            if message.get("id") != 1:
                continue
            if "error" in message:
                raise RuntimeError(str(message["error"]))
            result = message.get("result", {})
            if result.get("exceptionDetails"):
                raise RuntimeError("JavaScript végrehajtási hiba")
            value = result.get("result", {}).get("value")
            if not value:
                raise RuntimeError("A renderer nem adott értelmezhető választ")
            page_state = json.loads(value)
            if not page_state.get("href"):
                raise RuntimeError("A renderer URL-je üres")
            print(page_state.get("href", ""))
            return
    finally:
        sock.close()


def main():
    with urllib.request.urlopen(
        f"http://127.0.0.1:{PORT}/json/list", timeout=HTTP_TIMEOUT
    ) as response:
        targets = json.load(response)
    pages = [
        target
        for target in targets
        if target.get("type") == "page" and target.get("webSocketDebuggerUrl")
    ]
    if not pages:
        raise RuntimeError("Nincs elérhető Chromium page target")
    last_error = None
    for target in pages:
        try:
            websocket_runtime_check(target["webSocketDebuggerUrl"])
            return 0
        except Exception as exc:
            last_error = exc
    raise RuntimeError(str(last_error or "A Chromium renderer nem válaszol"))


if __name__ == "__main__":
    try:
        sys.exit(main())
    except Exception as exc:
        print(f"Chromium health check sikertelen: {exc}", file=sys.stderr)
        sys.exit(1)
