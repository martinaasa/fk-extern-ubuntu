import configparser
from pathlib import Path
import stat
import subprocess
import tempfile
import unittest


INSTALLER = Path(__file__).resolve().parents[1] / 'scripts/install-fkextern.sh'
EXPECTED = {
    'MouseSendsControlV': 'False',
    'WCAGModeKeyCombination': '',
    'TransparentKeyPassthrough': 'Remote',
    'UseCtrlAltEnd': 'True',
    'KeyPassthroughEscapeChar': 'Pause',
    'KeyPassthroughEscapeShift': 'Alt+Ctrl+Shift',
    'RelativeMouseOnChar': 'Pause',
    'RelativeMouseOnShift': 'Alt+Shift',
    'RelativeMouseOffChar': 'Pause',
    'RelativeMouseOffShift': 'Alt+Shift',
}
EXPECTED.update({f'Hotkey{i}Char': '(none)' for i in range(1, 13)})


class CitrixUserInputTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='fkextern-citrix-test-')
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.config = self.root / 'user-config/wfclient.ini'
        self.template = self.root / 'wfclient.template'
        self.template.write_bytes(b'; template\n[WFClient]\nVersion = 2\nKeyboardLayout = Automatic\n')
        self.log = self.root / 'install.log'

    def configure(self, dry_run=False):
        return subprocess.run(
            [
                'bash', '-c', '''
source "$1"
LOG_FILE="$2"
DRY_RUN="$3"
if [[ "$DRY_RUN" == 1 ]]; then
  python3() { return 99; }
fi
configure_citrix_user_input "$4" "$5"
''',
                'citrix-test', str(INSTALLER), str(self.log),
                '1' if dry_run else '0', str(self.config), str(self.template),
            ],
            capture_output=True, text=True, check=True,
        )

    def write_config(self, data):
        self.config.parent.mkdir(parents=True, exist_ok=True)
        self.config.write_bytes(data)
        self.config.chmod(0o640)

    def check_settings(self):
        parser = configparser.ConfigParser(interpolation=None)
        parser.read_string(self.config.read_text())
        section = next(s for s in parser.sections() if s.lower() == 'wfclient')
        for key, value in EXPECTED.items():
            self.assertEqual(parser[section][key], value, key)
        return parser[section], parser

    def backups(self):
        return list(self.config.parent.glob('wfclient.ini.bak.*'))

    def test_existing_settings_are_preserved_and_backed_up(self):
        before = (
            b'; keep comment\n[WFClient]\nVersion = 2\n'
            b'KeyboardEventMode = Automatic\nHotkey1Shift=Alt+Shift\n'
            b'Hotkey4Char=F4\nWCAGModeKeyCombination=Ctrl+Shift+T\n'
            b'TransparentKeyPassthrough=FullScreenOnly\n'
            b'RelativeMouse=3\nRelativeMouseMap=7\nUseLocalIM=True\n'
            b'[Other]\nHotkey4Char=F8\nWCAGModeKeyCombination=Keep\n'
        )
        self.write_config(before)
        self.configure()
        wfclient, parser = self.check_settings()
        self.assertEqual(wfclient['KeyboardEventMode'], 'Automatic')
        self.assertEqual(wfclient['Hotkey1Shift'], 'Alt+Shift')
        self.assertEqual(wfclient['RelativeMouse'], '3')
        self.assertEqual(wfclient['RelativeMouseMap'], '7')
        self.assertEqual(wfclient['UseLocalIM'], 'True')
        self.assertEqual(parser['Other']['Hotkey4Char'], 'F8')
        self.assertEqual(parser['Other']['WCAGModeKeyCombination'], 'Keep')
        self.assertIn(b'; keep comment\n', self.config.read_bytes())
        self.assertEqual(len(self.backups()), 1)
        self.assertEqual(self.backups()[0].read_bytes(), before)
        self.assertEqual(stat.S_IMODE(self.config.stat().st_mode), 0o640)
        self.assertEqual(stat.S_IMODE(self.backups()[0].stat().st_mode), 0o640)

    def test_new_config_uses_template_and_private_permissions(self):
        before = self.template.read_bytes()
        self.configure()
        wfclient, _ = self.check_settings()
        self.assertEqual(wfclient['KeyboardLayout'], 'Automatic')
        self.assertEqual(self.template.read_bytes(), before)
        self.assertEqual(stat.S_IMODE(self.config.stat().st_mode), 0o600)
        self.assertEqual(stat.S_IMODE(self.config.parent.stat().st_mode), 0o700)
        self.assertEqual(self.backups(), [])

    def test_repeated_run_preserves_mtime_and_backup_count(self):
        self.write_config(b'[WFClient]\nVersion=2\n')
        self.configure()
        before = self.config.read_bytes()
        mtime = self.config.stat().st_mtime_ns
        backups = self.backups()
        self.configure()
        self.assertEqual(self.config.read_bytes(), before)
        self.assertEqual(self.config.stat().st_mtime_ns, mtime)
        self.assertEqual(self.backups(), backups)

    def test_already_configured_file_keeps_formatting(self):
        before = b'[wfclient]\n; keep formatting\n' + b''.join(
            f'  {key.lower()} = {value}  \n'.encode()
            for key, value in EXPECTED.items()
        )
        self.write_config(before)
        mtime = self.config.stat().st_mtime_ns
        self.configure()
        self.assertEqual(self.config.read_bytes(), before)
        self.assertEqual(self.config.stat().st_mtime_ns, mtime)
        self.assertEqual(self.backups(), [])

    def test_crlf_and_duplicate_target_keys(self):
        self.write_config(
            b'[WFClient]\r\nHotkey4Char=F4\r\nHotkey4Char=F8\r\n'
            b'WCAGModeKeyCombination=T\r\nwcagmodekeycombination=X\r\n'
            b'Keep = yes\r\n[Other]\r\nHotkey4Char=F9\r\n'
        )
        self.configure()
        wfclient, parser = self.check_settings()
        self.assertEqual(wfclient['Keep'], 'yes')
        self.assertEqual(parser['Other']['Hotkey4Char'], 'F9')
        data = self.config.read_bytes()
        self.assertEqual(data.count(b'\n'), data.count(b'\r\n'))

    def test_missing_section_and_missing_final_newline(self):
        for before in [b'[Other]\nKeep=yes', b'[WFClient]',
                       b'[WFClient]\nWCAGModeKeyCombination=Old']:
            with self.subTest(before=before):
                self.write_config(before)
                self.configure()
                self.check_settings()

    def test_dry_run_lists_all_changes_without_writing_config(self):
        result = self.configure(dry_run=True)
        self.assertFalse(self.config.parent.exists())
        for key, value in EXPECTED.items():
            self.assertIn(f'{key}={value}', result.stdout)
        before = b'[WFClient]\nWCAGModeKeyCombination=Old\n'
        self.write_config(before)
        self.configure(dry_run=True)
        self.assertEqual(self.config.read_bytes(), before)
        self.assertEqual(self.backups(), [])

    def test_missing_template_fails_without_creating_config(self):
        self.template.unlink()
        with self.assertRaises(subprocess.CalledProcessError):
            self.configure()
        self.assertFalse(self.config.parent.exists())


if __name__ == '__main__':
    unittest.main()
