#!/usr/bin/env python3
"""Drive greetd-bridge.py against mock-greetd.py and assert the event stream."""

import json
import os
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
BRIDGE = os.path.join(HERE, "greetd-bridge.py")
MOCK = os.path.join(HERE, "mock-greetd.py")

failures = []


def check(label, got, want):
    ok = got == want
    print("%-48s %s" % (label, "ok" if ok else "FAIL (got %r, want %r)" % (got, want)))
    if not ok:
        failures.append(label)


class Session:
    """A mock greetd plus a bridge wired to it."""

    def __init__(self, user="tester", password="hunter2", interactive=False,
                 howdy=False, howdy_fail=False, delay=0.0):
        self.gap = tempfile.mkdtemp(prefix="mock-greetd-")
        self.sock = os.path.join(self.gap, "greetd.sock")
        self.log = os.path.join(self.gap, "start.log")
        self.trace = os.path.join(self.gap, "requests.log")
        mock_args = [sys.executable, MOCK, "--socket", self.sock, "--user", user,
                     "--password", password, "--log", self.log, "--trace", self.trace]
        if interactive:
            mock_args.append("--interactive")
        if howdy:
            mock_args.append("--howdy")
        if howdy_fail:
            mock_args.append("--howdy-fail")
        if delay:
            mock_args += ["--delay", str(delay)]
        self.mock = subprocess.Popen(mock_args, stdout=subprocess.PIPE, text=True)
        self.mock.stdout.readline()  # "ready"
        self.bridge = None
        self.spawn_bridge()

    def spawn_bridge(self):
        env = dict(os.environ, GREETD_SOCK=self.sock, USER="greeter")
        self.bridge = subprocess.Popen([sys.executable, "-u", BRIDGE], stdin=subprocess.PIPE,
                                       stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                                       text=True, env=env)
        self.readline()  # "ready"

    def respawn_bridge(self):
        """Drop the helper the way Greetd.qml's restartHelper does.

        The greetd socket dies with it, and greetd does not read that as a
        cancel: whatever was being configured stays configured.
        """
        self.bridge.kill()
        self.bridge.wait()
        self.spawn_bridge()

    def readline(self):
        line = self.bridge.stdout.readline()
        if not line:
            raise SystemExit("bridge exited: %s" % self.bridge.stderr.read())
        return json.loads(line)

    def send(self, **request):
        self.bridge.stdin.write(json.dumps(request) + "\n")
        self.bridge.stdin.flush()

    def ask(self, **request):
        self.send(**request)
        return self.readline()

    def requests(self):
        try:
            with open(self.trace) as handle:
                return handle.read().split()
        except OSError:
            return []

    def started_cmd(self):
        try:
            with open(self.log) as handle:
                return json.loads(handle.read().split(" ", 1)[1])["cmd"]
        except (OSError, IndexError, ValueError):
            return None

    def close(self):
        for proc in (self.bridge, self.mock):
            proc.kill()
            proc.wait()


def case_wrong_password():
    session = Session()
    try:
        # The password never travels with create_session (greetd has no field for
        # it), so a login is always: ask, then answer the prompt.
        event = session.ask(op="auth", username="tester")
        check("passwordless auth -> secret prompt", event.get("kind"), "secret")
        event = session.ask(op="respond", response="nope")
        check("wrong password -> auth_fail", event.get("event"), "auth_fail")
        check("wrong password -> auth_error kind", event.get("kind"), "auth_error")
        session.send(op="quit")
    finally:
        session.close()


def case_happy_path():
    session = Session()
    try:
        event = session.ask(op="auth", username="tester")
        check("passwordless auth -> secret prompt", event.get("kind"), "secret")
        event = session.ask(op="respond", response="hunter2")
        check("right password -> auth_ok", event.get("event"), "auth_ok")
        event = session.ask(op="start", cmd=["niri-session"], env=["XDG_SESSION_TYPE=wayland"])
        check("start_session -> started", event.get("event"), "started")
        check("start_session carries the session cmd", session.started_cmd(), ["niri-session"])
        session.send(op="quit")
    finally:
        session.close()


def case_retry_after_failure():
    """A failed attempt leaves greetd holding that session under configuration."""
    session = Session()
    try:
        session.ask(op="auth", username="tester")
        session.ask(op="respond", response="wrong")
        event = session.ask(op="auth", username="tester")
        check("retry after a failure -> secret prompt", event.get("kind"), "secret")
        event = session.ask(op="respond", response="hunter2")
        check("retry after a failure -> auth_ok", event.get("event"), "auth_ok")
        session.send(op="quit")
    finally:
        session.close()


def case_new_bridge_after_abandoned_face():
    """The helper is dropped mid-face-scan, the way restartHelper does it.

    greetd does not cancel on disconnect, so the abandoned conversation is still
    under configuration when the fresh helper asks for a new one: without the
    bridge's cancel-before-create the greeting would answer "a session is
    already being configured" and tty1 could never log in again on that boot.
    """
    session = Session(howdy_fail=True)
    try:
        event = session.ask(op="auth", username="tester")
        check("face scan -> info message", event.get("kind"), "info")
        session.respawn_bridge()
        event = session.ask(op="auth", username="tester")
        check("fresh helper after an abandoned face -> face message", event.get("kind"), "info")
        event = session.ask(op="respond")
        check("fresh helper after an abandoned face -> secret prompt", event.get("kind"), "secret")
        event = session.ask(op="respond", response="hunter2")
        check("fresh helper after an abandoned face -> auth_ok", event.get("event"), "auth_ok")
        session.send(op="quit")
    finally:
        session.close()


def case_cancel_before_create():
    """The cancel has to go out ahead of the next create_session."""
    session = Session()
    try:
        session.ask(op="auth", username="tester")
        session.ask(op="respond", response="wrong")
        session.ask(op="auth", username="tester")
        check("cancels the stale conversation first",
              session.requests()[-2:], ["cancel_session", "create_session"])
        session.send(op="quit")
    finally:
        session.close()


def case_interactive_secret():
    session = Session(interactive=True)
    try:
        event = session.ask(op="auth", username="tester")
        check("passwordless auth -> auth_message", event.get("event"), "auth_message")
        check("auth_message type secret", event.get("kind"), "secret")
        event = session.ask(op="respond", response="wrong")
        check("wrong response -> auth_fail", event.get("event"), "auth_fail")
        session.ask(op="auth", username="tester")
        event = session.ask(op="respond", response="hunter2")
        check("right response -> auth_ok", event.get("event"), "auth_ok")
        session.send(op="quit")
    finally:
        session.close()


def case_howdy_match():
    session = Session(howdy=True)
    try:
        event = session.ask(op="auth", username="tester")
        check("passwordless auth -> face message", event.get("event"), "auth_message")
        check("face message is info", event.get("kind"), "info")
        event = session.ask(op="respond")
        check("howdy matched -> auth_ok", event.get("event"), "auth_ok")
        event = session.ask(op="start", cmd=["niri-session"])
        check("howdy session starts", event.get("event"), "started")
        session.send(op="quit")
    finally:
        session.close()


def case_howdy_miss_then_password():
    session = Session(howdy_fail=True)
    try:
        session.ask(op="auth", username="tester")
        event = session.ask(op="respond")
        check("face missed -> secret prompt", event.get("event"), "auth_message")
        check("secret prompt is secret", event.get("kind"), "secret")
        event = session.ask(op="respond", response="hunter2")
        check("password after missed face -> auth_ok", event.get("event"), "auth_ok")
        session.send(op="quit")
    finally:
        session.close()


def case_unknown_user():
    session = Session()
    try:
        event = session.ask(op="auth", username="nobody")
        check("unknown user -> auth_fail", event.get("event"), "auth_fail")
        session.send(op="quit")
    finally:
        session.close()


def case_epoch_echo():
    """Events carry the attempt's epoch, so the UI can drop a stale attempt."""
    session = Session()
    try:
        event = session.ask(op="auth", username="tester", epoch=7)
        check("secret prompt echoes the epoch", event.get("epoch"), 7)
        event = session.ask(op="respond", response="nope", epoch=7)
        check("auth_fail echoes the epoch", event.get("epoch"), 7)
        session.ask(op="auth", username="tester", epoch=8)
        event = session.ask(op="respond", response="hunter2", epoch=8)
        check("auth_ok echoes the epoch", event.get("epoch"), 8)
        session.send(op="quit")
    finally:
        session.close()


def case_cancel():
    session = Session()
    try:
        event = session.ask(op="cancel")
        check("cancel_session -> cancelled", event.get("event"), "cancelled")
        event = session.ask(op="auth", username="tester")
        check("auth after cancel -> secret prompt", event.get("kind"), "secret")
        event = session.ask(op="respond", response="hunter2")
        check("auth after cancel -> auth_ok", event.get("event"), "auth_ok")
        session.send(op="quit")
    finally:
        session.close()


def case_bad_socket():
    env = dict(os.environ, GREETD_SOCK="/nonexistent/greetd.sock")
    bridge = subprocess.Popen([sys.executable, "-u", BRIDGE], stdin=subprocess.PIPE,
                              stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                              text=True, env=env)
    first = json.loads(bridge.stdout.readline())
    check("no GREETD_SOCK socket -> ready anyway", first.get("event"), "ready")
    bridge.stdin.write(json.dumps({"op": "auth", "username": "t", "password": "p"}) + "\n")
    bridge.stdin.flush()
    event = json.loads(bridge.stdout.readline())
    check("unreachable socket -> error, not a crash", event.get("event"), "error")
    bridge.kill()
    bridge.wait()


def main():
    for case in (case_wrong_password, case_happy_path, case_retry_after_failure,
                 case_new_bridge_after_abandoned_face, case_cancel_before_create,
                 case_interactive_secret, case_howdy_match, case_howdy_miss_then_password,
                 case_unknown_user, case_epoch_echo, case_cancel, case_bad_socket):
        print("-- %s" % case.__name__)
        case()
    print()
    print("FAILURES: %s" % (", ".join(failures) if failures else "none"))
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
