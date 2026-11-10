from pathlib import Path
import stat
import subprocess
import tempfile
import unittest
import xml.etree.ElementTree as ET


INSTALLER = Path(__file__).resolve().parents[1] / 'scripts/install-fkextern.sh'


class CitrixAuthLoggingTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='fkextern-auth-test-')
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.config = self.root / 'AuthManConfig.xml'
        self.log = self.root / 'install.log'

    def configure(self, dry_run=False):
        return subprocess.run(
            ['bash', '-c', '''
source "$1"
LOG_FILE="$2"
DRY_RUN="$3"
sudo() {
  if [[ "$DRY_RUN" == 1 ]]; then return 99; fi
  "$@"
}
configure_citrix_auth_logging "$4"
''', 'auth-test', str(INSTALLER), str(self.log),
             '1' if dry_run else '0', str(self.config)],
            capture_output=True, text=True, check=True,
        )

    def backups(self):
        return list(self.root.glob('AuthManConfig.xml.bak.*'))

    def test_only_tracing_changes_and_authentication_is_preserved(self):
        before = (
            b'<?xml version="1.0"?>\n<dict>\n<!-- keep comment -->\n'
            b'<key>TracingEnabled</key>\n<value>true</value>\n'
            b'<key>LoggingMode</key><value>normal</value>\n'
            b'<key>PKCS11module</key><value>/example/pkcs11.so</value>\n'
            b'<key>SmartCardRemovalAction</key><value>noaction</value>\n'
            b'<key>AuthManAntiKeyLoggingEnabled</key><value>true</value>\n'
            b'</dict>\n'
        )
        self.config.write_bytes(before)
        self.config.chmod(0o444)
        metadata = self.config.stat()
        self.configure()
        expected = before.replace(b'<value>true</value>', b'<value>false</value>', 1)
        self.assertEqual(self.config.read_bytes(), expected)
        self.assertEqual(len(self.backups()), 1)
        self.assertEqual(self.backups()[0].read_bytes(), before)
        current = self.config.stat()
        self.assertEqual(stat.S_IMODE(current.st_mode), 0o444)
        self.assertEqual((current.st_uid, current.st_gid), (metadata.st_uid, metadata.st_gid))

    def test_already_disabled_is_unchanged(self):
        before = b'<dict>\n<key>TracingEnabled</key>\n<value> false </value>\n</dict>\n'
        self.config.write_bytes(before)
        mtime = self.config.stat().st_mtime_ns
        self.configure()
        self.assertEqual(self.config.read_bytes(), before)
        self.assertEqual(self.config.stat().st_mtime_ns, mtime)
        self.assertEqual(self.backups(), [])

    def test_repeated_run_keeps_backup_count_and_mtime(self):
        self.config.write_bytes(b'<dict><key>TracingEnabled</key><value>true</value></dict>')
        self.configure()
        before = self.config.read_bytes()
        mtime = self.config.stat().st_mtime_ns
        backups = self.backups()
        self.configure()
        self.assertEqual(self.config.read_bytes(), before)
        self.assertEqual(self.config.stat().st_mtime_ns, mtime)
        self.assertEqual(self.backups(), backups)

    def test_missing_flag_is_added(self):
        self.config.write_bytes(b'<dict>\n<key>LoggingMode</key><value>normal</value>\n</dict>\n')
        self.configure()
        children = list(ET.fromstring(self.config.read_bytes()))
        values = {children[i].text: children[i + 1].text
                  for i in range(len(children) - 1) if children[i].tag == 'key'}
        self.assertEqual(values['TracingEnabled'], 'false')
        self.assertEqual(values['LoggingMode'], 'normal')

    def test_crlf_is_preserved(self):
        before = b'<dict>\r\n<key>TracingEnabled</key>\r\n<value>true</value>\r\n</dict>\r\n'
        self.config.write_bytes(before)
        self.configure()
        self.assertEqual(self.config.read_bytes(), before.replace(b'true', b'false'))

    def test_invalid_or_ambiguous_config_is_not_modified(self):
        examples = [
            b'<dict>',
            b'<other><key>TracingEnabled</key><value>true</value></other>',
            b'<dict><key>TracingEnabled</key><value>unknown</value></dict>',
            b'<dict><key>TracingEnabled</key><value>true</value>'
            b'<key>TracingEnabled</key><value>true</value></dict>',
        ]
        for before in examples:
            with self.subTest(before=before):
                self.config.write_bytes(before)
                with self.assertRaises(subprocess.CalledProcessError):
                    self.configure()
                self.assertEqual(self.config.read_bytes(), before)
                self.assertEqual(self.backups(), [])

    def test_dry_run_does_not_require_config_or_sudo(self):
        result = self.configure(dry_run=True)
        self.assertIn('TracingEnabled=false', result.stdout)
        self.assertFalse(self.config.exists())
        self.assertEqual(self.backups(), [])

    def test_missing_config_fails_without_creating_it(self):
        with self.assertRaises(subprocess.CalledProcessError):
            self.configure()
        self.assertFalse(self.config.exists())
        self.assertEqual(self.backups(), [])


if __name__ == '__main__':
    unittest.main()
