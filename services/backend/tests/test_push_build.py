"""Build configuration is optional and never accepts server credentials."""
import importlib.util
import json
from pathlib import Path
import subprocess
import sys
import xml.etree.ElementTree as ET
import pytest

ROOT = Path(__file__).resolve().parents[3]
HELPER = ROOT / 'scripts/prepare_push_build.py'
spec = importlib.util.spec_from_file_location('push_build', HELPER)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
CLIENT = {'PUSH_ENABLED': True, 'FIREBASE_PROJECT_ID': 'sendoh-test',
          'FIREBASE_MESSAGING_SENDER_ID': '123456',
          'FIREBASE_ANDROID_APP_ID': '1:123456:android:abcdef',
          'FIREBASE_ANDROID_API_KEY': 'public-client-key'}


def test_public_config_validation():
    assert module.prepare('') == {'PUSH_ENABLED': False}
    assert module.prepare(json.dumps(CLIENT)) == CLIENT
    with pytest.raises(ValueError):
        module.prepare(json.dumps({**CLIENT, 'private_key': 'never-embed-this'}))
    with pytest.raises(ValueError):
        module.prepare(json.dumps({**CLIENT, 'FIREBASE_MESSAGING_SENDER_ID': '999'}))


def test_native_firebase_options_created_and_removed_safely(tmp_path):
    android = tmp_path / 'android'
    manifest = android / 'app/src/main/AndroidManifest.xml'
    manifest.parent.mkdir(parents=True)
    manifest.write_text('<manifest/>')
    config = tmp_path / 'client.json'
    config.write_text(json.dumps(CLIENT))
    output = tmp_path / 'defines.json'
    command = [sys.executable, str(HELPER), '--output', str(output),
               '--config', str(config), '--android-root', str(android)]
    for _ in range(2):
        subprocess.run(command, check=True, capture_output=True)
    resources = android / 'app/src/main/res/values/sendoh_firebase.xml'
    options = {s.attrib['name']: s.text for s in ET.parse(resources).getroot()}
    assert options['google_app_id'] == CLIENT['FIREBASE_ANDROID_APP_ID']
    assert options['gcm_defaultSenderId'] == CLIENT['FIREBASE_MESSAGING_SENDER_ID']
    config.write_text('{"PUSH_ENABLED":false}')
    subprocess.run(command, check=True, capture_output=True)
    assert not resources.exists()
    assert json.loads(output.read_text()) == {'PUSH_ENABLED': False}
    resources.write_text('<resources><!-- Custom project configuration --></resources>')
    before = resources.read_bytes()
    result = subprocess.run(command, capture_output=True)
    assert result.returncode != 0 and resources.read_bytes() == before
