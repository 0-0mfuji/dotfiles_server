"""Exercise dev routing with fake SSH, browsers and host lifecycle helpers."""
import os
import fcntl
import select
import termios
import time
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

REPO = Path(__file__).resolve().parents[1]


class LauncherTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        for folder in ('macos/bin', 'scripts', 'config', 'bin', 'home'):
            (self.root / folder).mkdir(parents=True)
        for path in ('macos/bin/dev', 'macos/bin/secretary', 'scripts/lib.sh', 'scripts/secretary-launch'):
            shutil.copy2(REPO / path, self.root / path)
        with (self.root / 'scripts/lib.sh').open('a') as out:
            out.write('\nensure_tunnel() { echo "$3"; }\n')
        (self.root / 'config/projects.conf').write_text(
            'secretary secretary-dev /srv/secretary/documents secretary-dev - git - - secretary\n'
            'lang lang-dev /src/lang lang-dev -\n'
            'os/sota os-dev /src/sota os-dev -\n'
            'os/boot os-dev /src/boot os-dev -\n')
        self.log = self.root / 'calls'
        self.env = {**os.environ, 'HOME': str(self.root / 'home'), 'DEV_SERVER_HOST': 'dev-server',
                    'DEV_LOCAL_ENV': str(self.root / 'absent'), 'CALL_LOG': str(self.log),
                    'DEV_AGENT_CHECK': 'on', 'PATH': str(self.root / 'bin') + ':' + os.environ['PATH']}
        self.env.pop('DEV_PROJECTS_CONF', None)
        for name in ('server-status', 'server-wake', 'remote-start', 'agent-login', 'open-web', 'open-preview', 'show-mobile-qr', 'open-project', 'project-clone'):
            self.executable('scripts/' + name, '#!/bin/bash\necho "' + name + ' $*" >> "$CALL_LOG"\n')
        self.executable('bin/open', '#!/bin/bash\necho "open $*" >> "$CALL_LOG"\n')
        self.executable('bin/ssh', '''#!/bin/bash
echo "ssh $*" >> "$CALL_LOG"
case "$*" in
  *readiness*) printf 'model\tready\tOllama Cloud\nnotes\tready\tSilverBullet\ngmail\tpending\tGmail OAuth\n' ;;
  *server_token*) echo "${TEST_NANOMUSE_TOKEN:-fixture-token}" ;;
  *curl*) echo 200 ;;
esac
''')

    def executable(self, path, source):
        target = self.root / path
        target.write_text(source)
        target.chmod(0o755)

    def run_dev(self, *args):
        return subprocess.run(['bash', str(self.root / 'macos/bin/dev'), *args], env=self.env, capture_output=True, text=True)

    def calls(self):
        return self.log.read_text() if self.log.exists() else ''

    def test_default_secretary_prompts_and_opens_nanomuse_without_development_tools(self):
        result = self.run_dev('secretary')
        self.assertEqual(result.returncode, 0, result.stderr)
        calls = self.calls()
        self.assertIn('remote-start dev-server secretary-dev', calls)
        self.assertIn('readiness', calls)
        self.assertIn('Gmail OAuth: 未設定・停止中', result.stderr)
        self.assertIn('open http://127.0.0.1:8787/#token=fixture-token', calls)
        self.assertNotIn(':8300/', calls)
        self.assertNotIn(':9119/', calls)
        for forbidden in ('agent-login', 'open-project', 'project-clone', 'open-web'):
            self.assertNotIn(forbidden, calls)
        self.assertNotIn(' setup ', calls)  # non-interactive runs never launch setup

    def interactive_dev(self, args, answer):
        master, slave = os.openpty()
        def controlling_terminal():
            os.setsid()
            fcntl.ioctl(slave, termios.TIOCSCTTY, 0)
        proc = subprocess.Popen(['bash', str(self.root / 'macos/bin/dev'), *args],
                                env=self.env, stdin=slave, stdout=slave, stderr=slave,
                                preexec_fn=controlling_terminal, pass_fds=(slave,))
        os.close(slave)
        output = b''
        answered = False
        try:
            deadline = time.monotonic() + 15
            while time.monotonic() < deadline:
                readable, _, _ = select.select([master], [], [], .1)
                if readable:
                    try:
                        data = os.read(master, 65536)
                    except OSError:
                        break
                    if not data:
                        break
                    output += data
                    if not answered and '設定しますか?'.encode() in output:
                        os.write(master, answer.encode() + b'\n')
                        answered = True
                elif proc.poll() is not None:
                    break
            self.assertEqual(proc.wait(timeout=2), 0, output.decode(errors='replace'))
            return output.decode(errors='replace'), answered
        finally:
            if proc.poll() is None:
                proc.kill()
                proc.wait()
            os.close(master)

    def test_interactive_skip_and_force_login(self):
        output, answered = self.interactive_dev(['secretary'], 's')
        self.assertTrue(answered, output)
        skip = self.root / 'home/.config/dev/skip-secretary/secretary-dev/gmail'
        self.assertTrue(skip.exists())
        output, answered = self.interactive_dev(['secretary'], '')
        self.assertFalse(answered, output)
        output, answered = self.interactive_dev(['--login', 'secretary'], '')
        self.assertTrue(answered, output)

    def test_interactive_setup_has_owned_oauth_tunnel(self):
        output, answered = self.interactive_dev(['secretary'], 'y')
        self.assertTrue(answered, output)
        calls = self.calls()
        self.assertIn('-L 8765:127.0.0.1:8765', calls)
        self.assertIn('ControlPath=none', calls)
        self.assertIn('SECRETARY_OAUTH_TUNNEL=1', calls)
        self.assertIn("setup 'gmail'", calls)
        self.assertFalse((self.root / 'home/.config/dev/skip-secretary/secretary-dev/gmail').exists())

    def test_no_login_skips_readiness(self):
        result = self.run_dev('--no-login', 'secretary')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertNotIn('readiness', self.calls())
        self.assertEqual(self.calls().count('open http'), 1)

    def test_web_selects_only_nanomuse(self):
        result = self.run_dev('--web', 'secretary')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertNotIn(':8300/', self.calls())
        self.assertIn(':8787/', self.calls())

    def test_nanomuse_uses_authenticated_trial_and_preserves_default(self):
        result = self.run_dev('--nanomuse', 'secretary')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('open http://127.0.0.1:8787/#token=fixture-token', self.calls())
        self.assertNotIn(':9119/', self.calls())
        self.assertNotIn(':8300/', self.calls())
        self.assertNotIn('fixture-token', result.stdout + result.stderr)
        self.assertIn('systemctl start secretary-nanomuse.service', self.calls())
        self.assertNotIn('systemctl restart secretary-nanomuse.service', self.calls())

    def test_nanomuse_rejects_invalid_token_without_opening_browser(self):
        self.env['TEST_NANOMUSE_TOKEN'] = 'invalid token value'
        result = self.run_dev('--nanomuse', 'secretary')
        self.assertNotEqual(result.returncode, 0)
        self.assertNotIn('open http', self.calls())
        self.assertNotIn('invalid token value', result.stdout + result.stderr)

    def test_backend_flags_reject_other_targets_and_conflicts_before_wake(self):
        for args in (('--nanomuse', 'lang'), ('--hermes', 'lang'),
                     ('--nanomuse', '--hermes', 'secretary')):
            self.assertEqual(self.run_dev(*args).returncode, 2)
            self.assertEqual(self.calls(), '')

    def test_secretary_nanomuse_alias(self):
        result = subprocess.run(['bash', str(self.root / 'macos/bin/secretary'), 'nanomuse'],
                                env=self.env, capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn(':8787/#token=', self.calls())

    def test_hermes_is_explicit_and_started_on_request(self):
        result = self.run_dev('--hermes', 'secretary')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn(':9119/', self.calls())
        self.assertIn('systemctl start secretary-hermes.service', self.calls())
        self.assertNotIn(':8787/', self.calls())

    def test_chat_and_model_setup_open_nanomuse(self):
        for args in (('chat',), ('setup', 'model')):
            result = subprocess.run(['bash', str(self.root / 'macos/bin/secretary'), *args],
                                    env=self.env, capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stderr)
        self.assertNotIn("/usr/local/bin/secretary 'chat'", self.calls())
        self.assertIn(':8787/', self.calls())

    def test_preview_selects_only_notes(self):
        result = self.run_dev('--preview', 'secretary')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn(':8300/', self.calls())
        self.assertNotIn(':9119/', self.calls())

    def test_unsupported_flags_rejected_before_wake(self):
        for flag in ('--zed',):
            result = self.run_dev(flag, 'secretary')
            self.assertEqual(result.returncode, 2, result.stderr)
            self.assertEqual(self.calls(), '')

    def test_mobile_displays_secretary_qr_without_browser_or_setup(self):
        result = self.run_dev('--mobile', 'secretary')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('/opt/secretary/nanomuse-mobile.py', self.calls())
        self.assertNotIn('open http', self.calls())
        self.assertNotIn('readiness', self.calls())
        self.assertNotIn('cat /home/secretary/.nanomuse/server_token', self.calls())

    def test_existing_targets_keep_development_workflow(self):
        for args in (('lang',), ('os', 'sota'), ('os',)):
            result = self.run_dev(*args)
            self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('agent-login lang-dev', self.calls())
        self.assertIn('open-project os-dev /src/sota', self.calls())

    def test_unknown_target_rejected(self):
        result = self.run_dev('unknown')
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.calls(), '')

    def test_secretary_alias_resolves_symlink_and_delegates(self):
        alias = self.root / 'bin/secretary'
        alias.symlink_to(self.root / 'macos/bin/secretary')
        result = subprocess.run([str(alias)], env=self.env, capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.calls().count('open http'), 1)

    def test_provision_dispatches_secretary_before_development_tools(self):
        (self.root / 'provision').mkdir()
        (self.root / 'secretary').mkdir()
        shutil.copy2(REPO / 'dotfile_infra/provision/run', self.root / 'provision/run')
        self.executable('secretary/provision', '#!/bin/bash\necho "secretary-provision $*" >> "$CALL_LOG"\n')
        self.executable('bin/incus', '#!/bin/bash\necho "incus $*" >> "$CALL_LOG"\n')
        result = subprocess.run(['bash', str(self.root / 'provision/run'), 'secretary-dev'], env=self.env, capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('secretary-provision secretary-dev', self.calls())
        self.assertNotIn('incus', self.calls())


if __name__ == '__main__':
    unittest.main()
