#!/bin/bash

VERSION="1.0.2"
PACKAGE_NAME="manzh-${VERSION}"

# 创建打包目录
mkdir -p "dist/${PACKAGE_NAME}"

# 复制文件
cp manzh.sh "dist/${PACKAGE_NAME}/"
cp translate_man.sh "dist/${PACKAGE_NAME}/"
cp translate.py "dist/${PACKAGE_NAME}/"
cp config_manager.sh "dist/${PACKAGE_NAME}/"
cp clean.sh "dist/${PACKAGE_NAME}/"
cp install.sh "dist/${PACKAGE_NAME}/"
cp README.md "dist/${PACKAGE_NAME}/"
cp LICENSE "dist/${PACKAGE_NAME}/"
cp config.json "dist/${PACKAGE_NAME}/config.json.example"

# 创建发布包
cd dist
tar czf "${PACKAGE_NAME}.tar.gz" "${PACKAGE_NAME}"
zip -r "${PACKAGE_NAME}.zip" "${PACKAGE_NAME}"

echo "打包完成！"
echo "发布包位置："
echo "- dist/${PACKAGE_NAME}.tar.gz"
echo "- dist/${PACKAGE_NAME}.zip" 