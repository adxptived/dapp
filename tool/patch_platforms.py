"""Доводит сгенерированные `flutter create` платформенные файлы под приложение.

Запускается в CI после `flutter create .` (он создаёт только недостающие файлы), поэтому шаблон всегда
соответствует версии Flutter, а наши правки накладываются поверх: подпись релиза одним ключом
(обновления ставятся поверх), desugaring для уведомлений, разрешения, имя и иконка.
"""
import pathlib
import re
import shutil
import sys

root = pathlib.Path(__file__).resolve().parent.parent
app = root / "android" / "app"


def patch_gradle() -> None:
    path = app / "build.gradle.kts"
    s = path.read_text()
    if "dapp-release.jks" not in s:
        signing = '''
    signingConfigs {
        create("release") {
            storeFile = file(System.getenv("DAPP_KEYSTORE") ?: "../../signing/dapp-release.jks")
            storePassword = System.getenv("DAPP_KEYSTORE_PASSWORD") ?: "dappParty2026"
            keyAlias = System.getenv("DAPP_KEY_ALIAS") ?: "dapp"
            keyPassword = System.getenv("DAPP_KEY_PASSWORD") ?: "dappParty2026"
        }
    }

    buildTypes {'''
        s = s.replace("\n    buildTypes {", signing, 1)
        s = s.replace('signingConfig = signingConfigs.getByName("debug")', 'signingConfig = signingConfigs.getByName("release")')
    if "isCoreLibraryDesugaringEnabled" not in s:
        s = re.sub(r"compileOptions \{", "compileOptions {\n        isCoreLibraryDesugaringEnabled = true", s, count=1)
        s += '\ndependencies {\n    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.5")\n}\n'
    path.write_text(s)
    print(s)


def patch_manifest() -> None:
    path = app / "src" / "main" / "AndroidManifest.xml"
    s = path.read_text()
    perms = [
        "android.permission.INTERNET",
        "android.permission.ACCESS_NETWORK_STATE",
        "android.permission.POST_NOTIFICATIONS",
        "android.permission.REQUEST_INSTALL_PACKAGES",
        "android.permission.RECEIVE_BOOT_COMPLETED",
        "android.permission.WAKE_LOCK",
    ]
    block = "".join(f'    <uses-permission android:name="{p}"/>\n' for p in perms if p not in s)
    s = s.replace('<manifest xmlns:android="http://schemas.android.com/apk/res/android">',
                  '<manifest xmlns:android="http://schemas.android.com/apk/res/android">\n' + block, 1)
    s = re.sub(r'android:label="[^"]*"', 'android:label="Dota Manager"', s, count=1)
    path.write_text(s)


def dark_launch() -> None:
    """Тёмный фон заставки вместо белой вспышки при запуске."""
    res = app / "src" / "main" / "res"
    (res / "values").mkdir(parents=True, exist_ok=True)
    (res / "values" / "dapp_colors.xml").write_text(
        '<?xml version="1.0" encoding="utf-8"?>\n<resources>\n    <color name="dapp_bg">#FF110F16</color>\n</resources>\n')
    for f in res.glob("drawable*/launch_background.xml"):
        t = f.read_text()
        t = t.replace("@android:color/white", "@color/dapp_bg").replace("?android:colorBackground", "@color/dapp_bg")
        f.write_text(t)
    for f in res.glob("values*/styles.xml"):
        t = f.read_text()
        t = t.replace('<item name="android:windowBackground">?android:colorBackground</item>',
                      '<item name="android:windowBackground">@color/dapp_bg</item>')
        f.write_text(t)


def copy_icons() -> None:
    src = root / "assets" / "icon"
    for d in src.glob("mipmap-*"):
        dst = app / "src" / "main" / "res" / d.name
        dst.mkdir(parents=True, exist_ok=True)
        shutil.copy(d / "ic_launcher.png", dst / "ic_launcher.png")


def patch_ios() -> None:
    plist = root / "ios" / "Runner" / "Info.plist"
    if not plist.exists():
        return
    s = plist.read_text()
    s = re.sub(r"(<key>CFBundleDisplayName</key>\s*<string>)[^<]*(</string>)", r"\1Dota Manager\2", s)
    plist.write_text(s)
    icon_dir = root / "ios" / "Runner" / "Assets.xcassets" / "AppIcon.appiconset"
    if icon_dir.exists():
        try:
            from PIL import Image  # noqa: F401
        except Exception:
            return
        from PIL import Image
        base = Image.open(root / "assets" / "icon" / "icon.png").convert("RGB")
        for f in icon_dir.glob("*.png"):
            w, h = Image.open(f).size
            base.resize((w, h), Image.LANCZOS).save(f)


if __name__ == "__main__":
    if (app / "build.gradle.kts").exists():
        patch_gradle()
        patch_manifest()
        copy_icons()
        dark_launch()
    patch_ios()
    sys.exit(0)
