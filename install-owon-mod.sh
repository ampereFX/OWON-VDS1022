#!/bin/bash

set -euo pipefail
pushd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null

APP_ID='owon-mod'
APP_NAME='OWON-Mod'
APP_FULLNAME='OWON-Mod Oscilloscope'
APP_VENDOR='Local custom build of OWON VDS1022'
APP_SUMMARY='Custom OWON VDS1022 app bundle built from the current repository state'
APP_VERSION=$(<./version.txt)
APP_ARCH=$(uname -m)
APP_DIR="/Applications/${APP_NAME}.app"
RES_DIR="${APP_DIR}/Contents/Resources"

write() {
    echo -e "$(</dev/stdin)" > "$1"
    [ -z "${2:-}" ] || chmod "$2" "$1"
}

raise() {
    printf "Error: %s\n\n" "$1" >&2
    exit 1
}

echo "==========================================================="
echo " Install ${APP_NAME} ${APP_VERSION}"
echo " Source: $(pwd)"
echo " Target: ${APP_DIR}"
echo "==========================================================="

echo "Check environment ..."

[ "${EUID}" -eq 0 ] || raise "This script requires elevated privileges. Run it with sudo."
[ -d /Applications ] || raise "Folder /Applications missing."
[ -d "lib/mac/${APP_ARCH}" ] || raise "Architecture not supported: ${APP_ARCH}"

echo "Locate Java Runtime ..."

JAVA_HOME=$(/usr/libexec/java_home 2>/dev/null || true)
[ -d "${JAVA_HOME}" ] || raise "Java not installed."
echo "${JAVA_HOME}"

echo "Build ${APP_DIR} ..."

rm -rf "${APP_DIR}"
mkdir -p "${APP_DIR}/Contents"/{MacOS,Resources}
mkdir -p "${RES_DIR}"/{api,doc,fwr,ico,lib}

cp version.txt            "${RES_DIR}/"
cp ico/icon.icns          "${RES_DIR}/"
cp -R api/python          "${RES_DIR}/api/"
cp -R doc/.               "${RES_DIR}/doc/"
cp fwr/*.bin              "${RES_DIR}/fwr/"
cp ico/*.png ico/*.svg ico/*.ico "${RES_DIR}/ico/"
cp lib/*.jar              "${RES_DIR}/lib/"
cp "lib/mac/${APP_ARCH}"/*.dylib "${RES_DIR}/lib/"

write "${APP_DIR}/Contents/MacOS/launch" +x <<EOF
#!/bin/bash
set -euo pipefail
cd '${RES_DIR}'
/usr/libexec/java_home --exec java \\
  --enable-native-access=ALL-UNNAMED \\
  -Xdock:name='${APP_NAME}' \\
  -Xdock:icon='${RES_DIR}/icon.icns' \\
  -cp 'lib/*' \\
  com.owon.vds.tiny.Main
EOF

write "${APP_DIR}/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
    <dict>
        <key>CFBundleIdentifier</key>             <string>${APP_ID}</string>
        <key>CFBundleDisplayName</key>            <string>${APP_NAME}</string>
        <key>CFBundleName</key>                   <string>${APP_NAME}</string>
        <key>CFBundleGetInfoString</key>          <string>${APP_SUMMARY}</string>
        <key>CFBundleVersion</key>                <string>${APP_VERSION}</string>
        <key>CFBundleShortVersionString</key>     <string>${APP_VERSION}</string>
        <key>CFBundleExecutable</key>             <string>launch</string>
        <key>CFBundleIconFile</key>               <string>icon.icns</string>
        <key>CFBundleDevelopmentRegion</key>      <string>English</string>
        <key>CFBundleInfoDictionaryVersion</key>  <string>6.0</string>
        <key>CFBundlePackageType</key>            <string>APPL</string>
        <key>CSResourcesFileMapped</key>          <true/>
        <key>LSRequiresCarbon</key>               <true/>
        <key>NSHumanReadableCopyright</key>       <string>${APP_VENDOR}</string>
        <key>NSPrincipalClass</key>               <string>NSApplication</string>
        <key>NSHighResolutionCapable</key>        <true/>
    </dict>
</plist>
EOF

touch "${APP_DIR}"

printf "\nSUCCESS: %s installed.\n" "${APP_DIR}"
