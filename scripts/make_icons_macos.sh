# NOTE(blackedout): Original source https://stackoverflow.com/questions/646671/how-do-i-set-the-icon-for-my-applications-mac-os-x-app-bundle (2025-11-06)

SCRIPT_DIR=$(dirname "$0")

ASSETS_DIR=$SCRIPT_DIR/../assets/cubyz
TMP_DIR=$SCRIPT_DIR/logo.iconset
ORIGINAL_ICON=$ASSETS_DIR/logo.png

echo $ASSETS_DIR
echo $TMP_DIR
echo $ORIGINAL_ICON

mkdir $TMP_DIR

# Normal screen icons
for SIZE in 16 32 64 128 256 512; do
sips -z $SIZE $SIZE $ORIGINAL_ICON --out $TMP_DIR/icon_${SIZE}x${SIZE}.png ;
done

# Retina display icons
for SIZE in 32 64 256 512; do
sips -z $SIZE $SIZE $ORIGINAL_ICON --out $TMP_DIR/icon_$(expr $SIZE / 2)x$(expr $SIZE / 2)x2.png ;
done

# Make a multi-resolution Icon
iconutil -c icns -o $ASSETS_DIR/logo.icns $TMP_DIR
rm -rf $TMP_DIR #it is useless now
